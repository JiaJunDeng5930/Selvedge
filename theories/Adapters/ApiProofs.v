From Stdlib Require Import String List Bool NArith Lia Sorting.Permutation.
From Selvedge.Foundation Require Import Json Utf8 JsonObjectsProofs Registry.
From Selvedge.Kernel Require Import ChatgptProtocol.
From Selvedge.Adapters Require Import Common Observation Api Http
  PluginConnections Plugins EvaluatorPolicy Rpc RpcProofs Configuration ConfigurationProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

(** These statements constrain the actual extracted dispatch entry. Both
    successful behavior and admission requirements are stated, so rejecting
    every input cannot satisfy the public contract. *)

Theorem public_configured_connection_grants_preserve_authority values :
 exists projected,
 Api.call "plugin.connection_grants" (configuration_json values) = success (JArray projected) /\
 Permutation projected (map (fun value => grant_json (connection_grant value)) (Connections.values values)).
Proof.
 exists (map (fun value => grant_json (connection_grant value)) (Connections.values values)).
 split; [|apply Permutation_refl].
 change (connection_grants (configuration_json values) =
   success (JArray (map (fun value => grant_json (connection_grant value)) (Connections.values values)))).
 unfold connection_grants,configuration_json.
 cbn [Common.get Common.object_fields Json.field Json.lookup String.eqb Ascii.eqb Bool.eqb].
 rewrite map_map. reflexivity.
Qed.

Theorem public_admitted_command_body_is_delivered : forall source original value,
  open_valid source = true -> host_valid source = true -> Http.authorized source = true ->
  local_origin_valid source = true ->
  str source "method" = "POST" -> str source "pathname" = "/api/commands" ->
  str source "target" = "command" ->
  starts (str source "content_type") "application/json" = true ->
  as_string (get source "text") = Some original -> TextJson.parse_input_json original = TextJson.InputAccepted value ->
  let response := Api.call "http.body" source in
  JsonObjects.equivalent response (success (JObject [("action",JString "command");("body",value)])) = true /\
  field "body" (get response "value") = Some value.
Proof.
 intros source original value opened host authorization origin method pathname selected mime text parsed.
 assert (local : connection_path source = false).
 { unfold connection_path;rewrite pathname;reflexivity. }
 assert (audio : audio_target source = "").
 { unfold audio_target,audio_kind;rewrite pathname,method;reflexivity. }
 assert (route : selected_route source = Some (Route "POST" "/api/commands" ModelResultDeclarations.Http_command)).
 { unfold selected_route,matches_route;rewrite method,pathname;reflexivity. }
 assert (target : body_target source = ModelResultDeclarations.http_body_target_named "command").
 { unfold body_target;rewrite audio,route;reflexivity. }
 assert (delivered : Api.call "http.body" source =
   success (JObject [("action",JString "command");("body",value)])).
 { change (Http.call "http.body" source = success (JObject [("action",JString "command");("body",value)])).
   unfold Http.call;cbn;unfold request_guard,open_host_guard.
   rewrite opened,host,authorization,local,origin;cbn.
   unfold body_stage;rewrite target;cbn;rewrite selected;cbn.
   rewrite mime;cbn;rewrite text,parsed;reflexivity. }
 rewrite delivered.
 split; [apply equivalent_is_reflexive|reflexivity].
Qed.

Theorem public_browser_git_observation_uses_cwd_default : forall (cwd : string),
  JsonObjects.equivalent (Api.call "browser.observation" (JObject [("phase",JString "plan");
    ("observation",JObject [("kind",JString "workspace-git");("primary",JString "")]);("cwd",JString cwd)]))
    (success (JObject [("kind",JString "workspace-git");("primary",JString cwd)])) = true.
Proof. intros; apply equivalent_is_reflexive. Qed.
Theorem public_browser_directory_observation_marks_empty_path_default :
  JsonObjects.equivalent (Api.call "browser.observation" (JObject [("phase",JString "plan");
    ("observation",JObject [("kind",JString "browse-directories");("path",JString "")])]))
    (success (JObject [("kind",JString "browse-directories");("path",JString "");
      ("default_path",JBool true);("project_root",JNull)])) = true.
Proof. apply equivalent_is_reflexive. Qed.
Theorem public_browser_directory_default_prefers_task_root : forall task_root project_root,
  JsonObjects.equivalent (Api.call "browser.observation" (JObject [("phase",JString "resolve");
    ("plan",JObject [("kind",JString "browse-directories");("path",JString "");
      ("default_path",JBool true);("project_root",project_root)]);
    ("task_environment_present",JBool true);("task_root",task_root)]))
    (success (JObject [("path",task_root);("canonicalize",JBool false)])) = true.
Proof. intros; apply equivalent_is_reflexive. Qed.
Theorem public_browser_directory_default_canonicalizes_project_root : forall project_root,
  JsonObjects.equivalent (Api.call "browser.observation" (JObject [("phase",JString "resolve");
    ("plan",JObject [("kind",JString "browse-directories");("path",JString "");
      ("default_path",JBool true);("project_root",project_root)]);
    ("task_environment_present",JBool false)]))
    (success (JObject [("path",project_root);("canonicalize",JBool true)])) = true.
Proof. intros; apply equivalent_is_reflexive. Qed.
Theorem public_browser_directory_failure_is_returned_as_observation : forall message,
  JsonObjects.equivalent (Api.call "browser.observation" (JObject [("phase",JString "complete");
    ("kind",JString "browse-directories");("ok",JBool false);("error",JString message)]))
    (success (JObject [("ok",JBool false);("error",JString message)])) = true.
Proof. intros; apply equivalent_is_reflexive. Qed.
Theorem public_browser_skill_failure_is_returned_as_observation : forall message,
  JsonObjects.equivalent (Api.call "browser.observation" (JObject [("phase",JString "complete");
    ("kind",JString "skill-catalog");("ok",JBool false);("error",JString message)]))
    (success (JObject [("kind",JString "skill-catalog");("ok",JBool false);("error",JString message)])) = true.
Proof. intros; apply equivalent_is_reflexive. Qed.
Theorem public_exec_injects_authenticated_connection : forall connection args,
  keys args (client_keys Execute) = true ->
  JsonObjects.equivalent
  (Api.call "plugin.command" (JObject [("connection",connection);("body",JObject [("tool",JString "exec");("arguments",args)])]))
  (success (JObject [("op",JString "chatgpt_exec");("connection_id",connection);("project_id",get args "project_id");
    ("request_id",get args "request_id");("arguments",JObject [("command",get args "command");
      ("timeout_ms",default_value (get args "timeout_ms") (number 120000));
      ("max_output_length",default_value (get args "max_output_length") (number 4096))])])) = true.
Proof.
 intros connection args accepted.
 change (JsonObjects.equivalent
   (if keys args (client_keys Execute) then success (command_value connection Execute args)
    else type_error "Invalid ChatGPT tool arguments") (success (command_value connection Execute args)) = true).
 rewrite accepted; apply equivalent_is_reflexive.
Qed.
Theorem public_evaluator_authorizes_only_configured_decision : forall source reply value,
  TextJson.parse_json (str source "text") = Some reply ->
  Api.call "evaluator.decision" source = success value ->
  decision_identity reply (get source "evaluator") = true /\ decision_configured reply (get source "policy") = true.
Proof.
  intros source reply value parsed H.
  change (decision source = success value) in H.
  unfold decision in H; rewrite parsed in H;unfold decision_reply,checked in H.
  destruct (decision_identity reply (get source "evaluator") && decision_configured reply (get source "policy")) eqn:A;[|discriminate].
  now apply andb_true_iff in A.
Qed.
Theorem public_evaluator_accepts_configured_decision : forall source reply,
  TextJson.parse_json (str source "text") = Some reply ->
  decision_identity reply (get source "evaluator") = true ->
  decision_configured reply (get source "policy") = true ->
  JsonObjects.equivalent (Api.call "evaluator.decision" source) (success (JObject [
    ("effort",get (get (get reply "answers") "effort") "choice");
    ("generations",lease_number (get (get (get reply "answers") "lease") "choice"))])) = true.
Proof.
 intros source reply parsed identity configured;change (Api.call "evaluator.decision" source) with (decision source).
 unfold decision;rewrite parsed.
 unfold decision_reply,checked;rewrite identity,configured;apply equivalent_is_reflexive.
Qed.
Local Lemma evaluator_calls_preserve_preview_positions : forall history index,
 EvaluatorContext.calls history index =
 map (fun entry => JObject [("history_index",number (fst entry));
   ("call_id",get (snd entry) "call_id");("name",get (snd entry) "name");
   ("arguments",get (snd entry) "arguments")])
 (filter (fun entry => String.eqb (str (snd entry) "role") "function_call")
   (Registry.indexed (fun position item => (position,item)) index history)).
Proof.
 induction history as [|item rest IH]; intros index;
   cbn [EvaluatorContext.calls Registry.indexed List.map List.filter fst snd]; [reflexivity|].
 rewrite N.add_1_r, IH.
 destruct (String.eqb (str item "role") "function_call"); reflexivity.
Qed.

Local Lemma evaluator_outputs_preserve_matching_previews : forall history call index,
 EvaluatorContext.outputs history call index =
 map (fun entry => JObject [("history_index",number (fst entry));
   ("is_error",get (snd entry) "is_error");("text",get (snd entry) "content")])
 (filter (fun entry => String.eqb (str (snd entry) "role") "function_output" &&
   JsonObjects.equivalent (get (snd entry) "call_id") (get call "call_id"))
   (Registry.indexed (fun position item => (position,item)) index history)).
Proof.
 induction history as [|item rest IH]; intros call index;
   cbn [EvaluatorContext.outputs Registry.indexed List.map List.filter fst snd]; [reflexivity|].
 rewrite N.add_1_r, IH.
 destruct (String.eqb (str item "role") "function_output" &&
   JsonObjects.equivalent (get item "call_id") (get call "call_id")); reflexivity.
Qed.

Theorem public_evaluator_request_keeps_calls_and_results : forall history evaluator policy,
 let response := Api.call "evaluator.request" (JObject [
   ("effect",JObject [("history",JArray history)]);("evaluator",evaluator);("policy",policy)]) in
 let state := get (get response "value") "state" in
 let indexed := Registry.indexed (fun position item => (position,item)) 0 history in
 items (get state "recent_tool_calls") =
 map (fun entry => let '(position,call) := entry in
   JObject [("history_index",number position);("call_id",get call "call_id");
     ("name",get call "name");("arguments",get call "arguments");
     ("outputs",JArray (map (fun result =>
       JObject [("history_index",number (fst result));("is_error",get (snd result) "is_error");
         ("text",get (snd result) "content")])
       (filter (fun result => String.eqb (str (snd result) "role") "function_output" &&
         JsonObjects.equivalent (get (snd result) "call_id") (get call "call_id")) indexed)))])
   (filter (fun entry => String.eqb (str (snd entry) "role") "function_call") indexed).
Proof.
 intros history evaluator policy response state indexed.
 assert (Selected : items (get state "recent_tool_calls") =
   EvaluatorContext.pair_calls (EvaluatorContext.calls history 0) history).
 { unfold state,response.
   change (items (get (get (request_value evaluator policy
     (EvaluatorContext.context (JObject [("history",JArray history)]))) "state") "recent_tool_calls") =
     EvaluatorContext.pair_calls (EvaluatorContext.calls history 0) history).
   unfold request_value.
   destruct (String.eqb (str evaluator "provider") "vercel"); [reflexivity|].
   destruct (String.eqb (str evaluator "provider") "openrouter"); reflexivity. }
 rewrite Selected.
 unfold EvaluatorContext.pair_calls,indexed.
 rewrite evaluator_calls_preserve_preview_positions, map_map.
 apply map_ext. intros [position call]. cbn [fst snd].
 rewrite evaluator_outputs_preserve_matching_previews.
 reflexivity.
Qed.
Theorem public_unissued_rpc_response_preserves_pending_requests : forall source state,
  Rpc.state_of source = state ->
  is_object (get source "message") = true -> str (get source "message") "jsonrpc" = "2.0" ->
  as_string (get (get source "message") "method") = None ->
  correlate state (get (get source "message") "id") = None ->
  Api.call "rpc.message" source = encode_action (unchanged "ignore" state []).
Proof.
 intros source state decoded shape version method identity.
 change (Rpc.call "rpc.message" source = encode_action (unchanged "ignore" state [])).
 unfold Rpc.call;rewrite decoded;cbn.
 now apply unissued_response_cannot_settle.
Qed.

(** Field presence distinguishes an actual null result from a dropped result. *)
Theorem public_issued_plain_rpc_result_resolves_its_pending_request : forall source state id,
  Rpc.state_of source = state ->
  is_object (get source "message") = true -> str (get source "message") "jsonrpc" = "2.0" ->
  as_string (get (get source "message") "method") = None ->
  correlate state (get (get source "message") "id") = Some id ->
  has (get source "message") "result" = true -> has (get source "message") "error" = false ->
  contains id state.(preparable) = false ->
  field "ok" (Api.call "rpc.message" source) = Some (JBool true) /\
  exists reply,
    field "value" (Api.call "rpc.message" source) = Some reply /\
    field "action" reply = Some (JString "resolve") /\
    field "id" reply = Some (number id) /\
    field "value" reply = Some (get (get source "message") "result") /\
    exists next,
      field "nextId" reply = Some (number next) /\ state.(next_id) <= next /\
    exists remaining,
      field "nextPending" reply = Some (JArray (map number remaining)) /\
      ~ In id remaining /\
      (forall other, other <> id -> (In other remaining <-> In other state.(pending))).
Proof.
 intros source state id decoded shape version method identity result_present error_absent plain_result.
 assert (execution : Api.call "rpc.message" source = encode_action
   (consume "resolve" state id [("value",get (get source "message") "result")])).
 { change (Rpc.call "rpc.message" source = encode_action
     (consume "resolve" state id [("value",get (get source "message") "result")])).
   unfold Rpc.call;rewrite decoded;cbn.
   unfold message;rewrite shape,version;cbn;rewrite method,identity.
   unfold response;rewrite result_present,error_absent;cbn;rewrite plain_result;reflexivity. }
 split; [rewrite execution;reflexivity|].
 exists (get (encode_action (consume "resolve" state id
   [("value",get (get source "message") "result")])) "value").
 split; [rewrite execution;reflexivity|].
 split; [reflexivity|].
 split; [reflexivity|].
 split; [reflexivity|].
 exists state.(next_id). split; [reflexivity|].
 split; [apply N.le_refl|].
 exists (retire id state.(pending)).
 split; [reflexivity|].
 split; [apply consumed_identity_cannot_remain_pending|].
 intros other different;now apply unrelated_pending_identity_is_preserved.
Qed.

Theorem public_issued_media_rpc_result_reserves_before_materialization : forall source state id,
  Rpc.state_of source = state ->
  is_object (get source "message") = true -> str (get source "message") "jsonrpc" = "2.0" ->
  as_string (get (get source "message") "method") = None ->
  correlate state (get (get source "message") "id") = Some id ->
  has (get source "message") "result" = true -> has (get source "message") "error" = false ->
  contains id state.(preparable) = true ->
  Api.call "rpc.message" source = encode_action
    (reserve_materialization state id (get (get source "message") "result")) /\
  ~ In id (action_pending (reserve_materialization state id (get (get source "message") "result"))) /\
  In id (action_materializing (reserve_materialization state id (get (get source "message") "result"))).
Proof.
 intros source state id decoded shape version method identity result_present error_absent media_result.
 split.
 - change (Rpc.call "rpc.message" source = encode_action
     (reserve_materialization state id (get (get source "message") "result"))).
   unfold Rpc.call;rewrite decoded;cbn.
   unfold message;rewrite shape,version;cbn;rewrite method,identity.
   unfold response;rewrite result_present,error_absent;cbn;rewrite media_result;reflexivity.
 - apply materialization_reserves_and_removes_its_pending_identity.
Qed.

Theorem public_reserved_rpc_materialization_resolves_once : forall source state,
  Rpc.state_of source = state ->
  contains (nat_value (get source "id")) state.(materializing) = true ->
  boolean_field source "ok" = true ->
  Api.call "rpc.prepared" source = encode_action
    (consume "resolve" state (nat_value (get source "id")) [("value",get source "value")]) /\
  ~ In (nat_value (get source "id"))
    (action_materializing (consume "resolve" state (nat_value (get source "id")) [("value",get source "value")])).
Proof.
 intros source state decoded reserved successful. split.
 - change (Rpc.call "rpc.prepared" source = encode_action
     (consume "resolve" state (nat_value (get source "id")) [("value",get source "value")])).
   unfold Rpc.call;rewrite decoded;cbn.
   unfold prepared;rewrite reserved,successful;reflexivity.
 - apply consumed_materialization_cannot_remain_active.
Qed.

Theorem public_rpc_frame_admission_matches_its_byte_budget : forall source,
  field "ok" (Api.call "rpc.frame" source) = Some (JBool true) <->
   num source "bytes" <= num source "frameLimit".
Proof.
 intros source.
 change (field "ok" (Rpc.call "rpc.frame" source) = Some (JBool true) <->
   num source "bytes" <= num source "frameLimit").
 unfold Rpc.call;cbn.
 destruct (num source "bytes" <=? num source "frameLimit") eqn:Budget;cbn.
 - split;[intros _;now apply N.leb_le|intros _;reflexivity].
 - split;[discriminate|intros Bound;apply N.leb_gt in Budget;lia].
Qed.

Theorem public_rpc_write_admission_matches_its_byte_budgets : forall source state,
  Rpc.state_of source = state ->
  (get (get (Api.call "rpc.write" source) "value") "action" = JString "write" <->
   state.(failed) = false /\ state.(closing) = false /\
   num source "bytes" <= num source "frameLimit" /\
   num source "queuedBytes" + num source "bytes" <= 2 * num source "frameLimit").
Proof.
 intros source state decoded.
 change (get (get (Rpc.call "rpc.write" source) "value") "action" = JString "write" <->
   state.(failed) = false /\ state.(closing) = false /\
   num source "bytes" <= num source "frameLimit" /\
   num source "queuedBytes" + num source "bytes" <= 2 * num source "frameLimit").
 unfold Rpc.call;rewrite decoded;cbn -[N.mul];unfold Rpc.write.
 destruct state.(failed);[cbn -[N.mul];split;[discriminate|intros [Impossible _];discriminate]|].
 destruct state.(closing);[cbn -[N.mul];split;[discriminate|intros [_ [Impossible _]];discriminate]|].
 destruct (num source "bytes" <=? num source "frameLimit") eqn:Frame;
   [|cbn -[N.mul];split;[discriminate|intros [_ [_ [Bound _]]];apply N.leb_gt in Frame;lia]].
 destruct (num source "queuedBytes" + num source "bytes" <=? 2 * num source "frameLimit") eqn:Queue;
   [|cbn -[N.mul];split;[discriminate|intros [_ [_ [_ Bound]]];apply N.leb_gt in Queue;lia]].
 cbn -[N.mul]. split;[intros _;repeat split;try reflexivity;now apply N.leb_le|intros _;reflexivity].
Qed.

Theorem public_rpc_reservation_matches_available_capacity : forall source state,
  Rpc.state_of source = state ->
  (get (get (Api.call "rpc.request" source) "value") "action" = JString "request" <->
   boolean_field source "aborted" = false /\ state.(failed) = false /\
   N.of_nat (List.length (state.(pending) ++ state.(working))) < Rpc.request_limit /\
   state.(next_id) < 9007199254740991).
Proof.
 intros source state decoded.
 change (get (get (Rpc.call "rpc.request" source) "value") "action" = JString "request" <->
   boolean_field source "aborted" = false /\ state.(failed) = false /\
   N.of_nat (List.length (state.(pending) ++ state.(working))) < Rpc.request_limit /\
   state.(next_id) < 9007199254740991).
 unfold Rpc.call;rewrite decoded;cbn;unfold Rpc.request.
 destruct (boolean_field source "aborted");[cbn;split;[discriminate|intros [Impossible _];discriminate]|].
 destruct state.(failed);[cbn;split;[discriminate|intros [_ [Impossible _]];discriminate]|].
 destruct (N.of_nat (List.length (state.(pending) ++ state.(working))) <? Rpc.request_limit) eqn:Capacity;
   [|cbn;split;[discriminate|intros [_ [_ [Bound _]]];apply N.ltb_ge in Capacity;lia]].
 destruct (state.(next_id) <? 9007199254740991) eqn:Identity;
   [|cbn;split;[discriminate|intros [_ [_ [_ Bound]]];apply N.ltb_ge in Identity;lia]].
 cbn. split;[intros _;repeat split;try reflexivity;now apply N.ltb_lt|intros _;reflexivity].
Qed.

Theorem public_rpc_reservation_returns_a_bounded_pending_set : forall source state,
  Rpc.state_of source = state ->
  get (get (Api.call "rpc.request" source) "value") "action" = JString "request" ->
  N.of_nat (List.length (items (get (get (Api.call "rpc.request" source) "value") "nextPending"))) +
    N.of_nat (List.length state.(working)) <= Rpc.request_limit.
Proof.
 intros source state decoded accepted.
 apply (proj1 (public_rpc_reservation_matches_available_capacity source state decoded)) in accepted.
 destruct accepted as [Aborted [Failed [Capacity Identity]]].
 assert (CapacityValue : (N.of_nat (List.length (state.(pending) ++ state.(working))) <? Rpc.request_limit) = true)
   by now apply N.ltb_lt.
 assert (IdentityValue : (state.(next_id) <? 9007199254740991) = true) by now apply N.ltb_lt.
 assert (Entry : Api.call "rpc.request" source = Rpc.request state source).
 { change (Rpc.call "rpc.request" source = Rpc.request state source).
   unfold Rpc.call;rewrite decoded;reflexivity. }
 rewrite Entry. unfold Rpc.request. rewrite Aborted,Failed,CapacityValue,IdentityValue;cbn.
 rewrite map_length,app_length,Nat2N.inj_add;cbn.
 rewrite app_length,Nat2N.inj_add in Capacity. lia.
Qed.

Theorem public_mcp_media_plan_admits_each_observed_part : forall source result,
  Api.call "plugin.mcp_media_plan" source = success result ->
  Forall (fun pair => mcp_media_part (fst pair) (snd pair) = true) (mcp_media_pairs source).
Proof.
 intros source result H. change (mcp_media_plan source = success result) in H.
 unfold mcp_media_plan in H. destruct (negb (is_object (get source "result"))); [discriminate|].
 destruct (mcp_media_admitted source) eqn:Admitted; [|discriminate].
 unfold mcp_media_admitted in Admitted. apply Forall_forall. intros pair Present.
 apply forallb_forall with (x:=pair) in Admitted; assumption.
Qed.
