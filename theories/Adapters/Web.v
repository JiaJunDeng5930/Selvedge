From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import WebCommon WebResources WebStream WebStore WebHistory WebContinuation.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition invalid_source := "Invalid ChatGPT Web JSON source".
Definition with_stored source handler := match optional_stored source with
 | Some value => handler value
 (* DEFENSE: A persisted SQLite row with a missing or unknown retirement code
    cannot authorize reuse of a request or reset of its continuation. *)
 | None => err invalid_source end.
Definition frame_fields := [required "data" (D.Value Schema.KText);raw "event"].
Definition frame_value := project frame_fields (fun data event => (data,text (missing event))).
Definition stream_fields := [required "pending" (D.Value Schema.KText);required "data" (D.Array (D.Value Schema.KText));
 required "size" safe_natural;required "name" (D.Value Schema.KText);required "after_cr" D.Boolean].
Definition stream_value := project stream_fields (fun pending data size name after_cr =>
 StreamState pending data (proj1_sig size) name after_cr).
Definition http_fields := [required "ok" D.Boolean].
Definition http_value := project http_fields (fun ok => ok).
Definition options effect := let model := String.eqb (member_text effect "kind") "model" in
  success (JObject [("snapshots",JBool model);("receipt",JBool model);("stages",number 2)]).
Definition contract request tools := success (JObject (("model",get (member request "model") "name")::
  (member_subset request ["instructions"] ++ [("tools",JArray tools)]))).
Definition continuation_entry request previous owner store binding contract digest :=
 with_stored (missing previous) (fun previous => WebContinuation.continuation
   (ContinuationInput (history_value request) previous (missing owner)
     (missing store) (missing binding) (missing contract) (missing digest))).
Definition receipt_entry effect response record deferred count hash store binding contract tools :=
 let '(history,model,task) := model_history_value effect in
 WebContinuation.receipt history model task response record deferred count hash store
   (missing binding) (missing contract) (items (missing tools)).

(** The declaration determines each handler's argument types. Invocation decodes
    once and supplies those values; operations cannot reread an unchecked source. *)
Record operation := Operation {
 operation_name : string;
 operation_fields : list (string * bool * D.t);
 operation_run : O.arguments operation_fields json;
 operation_error : string;
 operation_names : Schema.DistinctNames (map (fun field => fst (fst field)) operation_fields)
}.
Definition method name fields handler
 `{Schema.DistinctNames (map (fun field => fst (fst field)) fields)} :=
 Operation name fields handler invalid_source H.
Definition diagnostic_method name fields handler message
 `{Schema.DistinctNames (map (fun field => fst (fst field)) fields)} :=
 Operation name fields handler message H.
Definition operations := [
 method "web.messages" [required "history" (D.Array D.Any)] WebHistory.messages;
 method "web.tools" [required "effect" D.RawObject] WebHistory.tools;
 method "web.resource" [raw "value";raw "model";raw "body";raw "tools"]
   (fun value model body tools => WebResources.resource (missing value) (missing model) (missing body) (items (missing tools)));
 method "web.failure" [required "record" D.RawObject;raw "code";raw "status"]
   (fun record code status => WebResources.failure_result record (missing code) (missing status));
 method "web.event" [required "frame" (D.OpenObject frame_fields);raw "body";raw "model";raw "tools";raw "index"]
   (fun frame body model tools index => let '(data,name) := frame_value frame in
    WebResources.event false name data (missing body) (missing model) (items (missing tools)) (missing index));
 method "web.store_identify" [required "record" D.RawObject;required "current" D.RawObject;raw "id"]
   (fun record current id => WebStore.store_identify record current (missing id));
 method "web.store_finish" [required "record" D.RawObject;required "current" D.RawObject;required "response" D.RawObject] WebStore.store_finish;
 method "web.store_reject" [required "record" D.RawObject] WebStore.store_reject;
 method "web.store_retire" [] WebStore.store_retire;
 method "web.store_prepare" [raw "record";required "request" (D.OpenObject WebStore.request_fields);raw "previous";required "new_key" (D.Value Schema.KText)]
   (fun record request previous key => with_stored (missing record) (fun record =>
    with_stored (missing previous) (fun previous => WebStore.store_prepare record (WebStore.request_value request) previous key)));
 method "web.retire_existing" [required "rows" (D.Array D.Any);required "records" (D.Array D.Any);required "owner" (D.Value Schema.KText);raw "ticket"] WebStore.retire_existing;
 method "web.continuation" [required "request" (D.OpenObject history_fields);
   raw "previous";raw "owner";raw "store_identity";raw "binding";raw "contract";raw "history_digest"] continuation_entry;
 method "web.receipt" [required "effect" (D.OpenObject model_history_fields);required "resource" D.RawObject;required "record" D.RawObject;
   required "deferred" (D.Array D.Any);required "output_count" positive_natural;required "input_hash" nonempty_text;
   required "store_identity" nonempty_text;raw "binding";raw "contract";raw "tools"] receipt_entry;
 method "web.sse_step" [required "state" (D.OpenObject stream_fields);required "chunk" (D.Value Schema.KText);
   required "eof" D.Boolean;required "maximum" safe_natural]
   (fun state chunk eof maximum => WebStream.sse_step (stream_value state) chunk eof (proj1_sig maximum));
 method "web.http" [required "record" D.RawObject;required "status" safe_natural]
   (fun record status => WebResources.http record (proj1_sig status));
 method "web.commit" [raw "resource"] (fun resource => WebResources.commit (missing resource));
 method "web.request_bounds" [raw "body";raw "deferred";raw "limits"]
   (fun body deferred limits => WebResources.request_bounds (missing body) (missing deferred) (num (missing limits) "frame_bytes"));
 method "web.owner" [required "effect" D.RawObject] WebCommon.owner;
 method "web.headers" [raw "version";raw "content_type"] (fun version content_type => WebStream.headers (missing version) (missing content_type));
 diagnostic_method "web.recovery" (WebStore.recovery_fields ++ [raw "profile";raw "record";raw "binding"])
   (fun action confirm profile record binding => WebStore.recovery (recovery_action_value action) confirm (missing profile) (missing record) (missing binding))
   "Invalid ChatGPT Web recovery action";
 method "web.recovery_result" [raw "action";raw "value";raw "record"]
   (fun action value record => WebStore.recovery_result (missing action) (missing value) (missing record));
 method "web.retained" [required "record" D.RawObject] WebResources.retained;
 method "web.decode" [required "text" (D.Value Schema.KText)] decode_provider_text;
 method "web.settle" [required "resource" D.RawObject;required "deferred" (D.Array D.Any);raw "body";raw "index"]
   (fun resource deferred body index => match D.decode WebContinuation.stage (missing index) with
    | Some index => WebContinuation.settle index resource deferred (missing body)
    | None => err "Unsupported ChatGPT Web output stage; only parts 0 and 1 are defined" end);
 method "web.cancel_owner" [raw "task"] (fun task => WebStore.cancel_owner (missing task));
 method "web.position" [required "effect" (D.OpenObject history_fields)]
   (fun effect => let effect := history_value effect in WebCommon.position effect.(effect_kind) effect.(effect_history));
 method "web.contract" [required "request" D.RawObject;required "tools" (D.Array D.Any)] contract;
 method "web.store_metadata" [required "rows" (D.Array D.Any);required "new_identity" (D.Value Schema.KText);required "created" D.Boolean] WebStore.store_metadata;
 method "web.frame" [required "frame" (D.OpenObject frame_fields)] (fun frame => WebResources.frame (fst (frame_value frame)));
 method "web.event_header" [required "frame" (D.OpenObject frame_fields)]
   (fun frame => let '(data,name) := frame_value frame in WebResources.event true name data JNull JNull [] JNull);
 diagnostic_method "web.recovery_shape" WebStore.recovery_fields (fun _ _ => success JNull) "Invalid ChatGPT Web recovery action";
 method "web.recovery_connection" [raw "profile";raw "record"] (fun profile record => WebStore.recovery_connection (missing profile) (missing record));
 method "web.options" [required "effect" D.RawObject] options;
 method "web.invocation" [required "effect" D.RawObject;required "profile" D.RawObject;required "body" D.RawObject;
   required "owner" (D.Value Schema.KText);required "stage" safe_natural;raw "binding";required "reset" D.Boolean]
   (fun effect profile body owner stage binding reset => WebStore.invocation effect profile body owner (proj1_sig stage) (missing binding) reset);
 method "web.cancellation" [raw "record"] (fun record => WebStore.cancellation (missing record));
 method "web.store_latest" [required "records" (D.Array D.Any);required "owner" (D.Value Schema.KText);raw "ticket"] WebStore.store_latest;
 method "web.exchange_start" [raw "record";raw "body";raw "model";raw "tools"]
   (fun record body model tools => WebStore.exchange_start (missing record) (missing body) (missing model) (items (missing tools)));
 method "web.exchange_result" [raw "resource"] (fun resource => WebStore.exchange_result (missing resource));
 method "web.catch" [raw "record";raw "error"] (fun record error => WebStore.catch (missing record) (missing error));
 method "web.http_json" [required "response" (D.OpenObject http_fields);required "text" (D.Value Schema.KText)]
   (fun response text => WebResources.http_json (http_value response) text);
 diagnostic_method "web.reset_session" [required "rows" (D.Array D.Any);required "records" (D.Array D.Any);required "task_id" safe_natural]
   (fun rows records task => WebStore.reset_session rows records (proj1_sig task)) "Invalid ChatGPT Web reset source"
].
Definition select_operation name := find (fun operation => String.eqb name operation.(operation_name)) operations.
Definition call name source := match select_operation name with
 | None => err ("Unknown Web model operation: " ++ name)
 | Some operation => match O.invoke operation.(operation_fields) operation.(operation_run) source with
   | Some result => result
   (* DEFENSE: Public operations can receive missing or incorrectly typed
      fields; the operation declaration rejects them before interpretation. *)
   | None => err operation.(operation_error) end end.
