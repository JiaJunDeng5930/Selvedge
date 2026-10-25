From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json Utf8.
From Selvedge.Kernel Require Import ChatgptProtocol.
From Selvedge.Adapters Require Import Common Observation Api Http HttpProofs Audio AudioProofs BrowserAdapters BrowserObservations BrowserAdaptersProofs
  PluginConnections Plugins EvaluatorBudget EvaluatorPolicy Rpc RpcProofs Configuration ConfigurationProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

(** These statements constrain the actual extracted dispatch entry. Both
    successful behavior and admission requirements are stated, so rejecting
    every input cannot satisfy the public contract. *)
Theorem public_http_body_requires_authorization : forall source target value,
  Api.call "http.body" source = success (JObject [("action",JString target);("body",value)]) ->
  Http.authorized source = true.
Proof. intros;apply (http_body_requires_authorization source target value);exact H. Qed.
Theorem public_http_body_requires_local_origin : forall source target value,
  connection_path source = false ->
  Api.call "http.body" source = success (JObject [("action",JString target);("body",value)]) ->
  local_origin_valid source = true.
Proof. intros;apply (http_body_requires_local_origin source target value);assumption. Qed.

Theorem public_admitted_command_body_is_delivered : forall source original value,
  open_valid source = true -> host_valid source = true -> Http.authorized source = true ->
  local_origin_valid source = true ->
  str source "method" = "POST" -> str source "pathname" = "/api/commands" ->
  str source "target" = "command" ->
  starts (str source "content_type") "application/json" = true ->
  as_string (get source "text") = Some original -> TextJson.parse_input_json original = TextJson.InputAccepted value ->
  Api.call "http.body" source = success (JObject [("action",JString "command");("body",value)]).
Proof.
 intros source original value opened host authorization origin method pathname selected mime text parsed.
 assert (local : connection_path source = false).
 { unfold connection_path;rewrite pathname;reflexivity. }
 assert (audio : audio_target source = "").
 { unfold audio_target,audio_kind;rewrite pathname,method;reflexivity. }
 assert (route : selected_route source = Some (Route "POST" "/api/commands" ModelResultDeclarations.Http_command true)).
 { unfold selected_route,matches_route;rewrite method,pathname;reflexivity. }
 assert (target : body_target source = "command").
 { unfold body_target;rewrite audio,route;reflexivity. }
 change (Http.call "http.body" source = success (JObject [("action",JString "command");("body",value)])).
 unfold Http.call;cbn;unfold request_guard,open_host_guard.
 rewrite opened,host,authorization,local,origin;cbn.
 unfold body_stage;rewrite target,selected;cbn.
 rewrite mime;cbn;rewrite text,parsed;reflexivity.
Qed.

Theorem public_transcript_cannot_delegate : forall source result,
  str (get source "value") "type" = "turn.done" ->
  Api.call "audio.event" source = success result -> get result "type" <> JString "delegation".
Proof. intros;apply (transcript_events_cannot_delegate_work source result);assumption. Qed.
Theorem public_voice_session_requires_audio_authority : forall source result,
  Api.call "audio.session_request" source = success result ->
  boolean_field source "authorized" = true /\ str source "source" = "chatgpt_audio".
Proof. intros;apply (accepted_voice_session_requires_audio_authority source result);exact H. Qed.
Theorem public_safe_fragment_is_accepted : forall source,
  raw_valid (get source "raw") = true -> starts (str source "raw") "#" = true ->
  Api.call "browser.link" source = success (get source "raw").
Proof. intros;change (success (link source) = success (get source "raw"));f_equal;now apply safe_fragment_navigation_is_not_rejected. Qed.
Theorem public_link_has_admitted_scheme : forall source target,
  Api.call "browser.link" source = success (JString target) ->
  starts target "#" || allowed_target target = true.
Proof. intros;apply (returned_link_has_an_admitted_scheme source target);now inversion H. Qed.
Theorem public_browser_git_observation_uses_cwd_default : forall cwd,
  Api.call "browser.observation" (JObject [("phase",JString "plan");
    ("observation",JObject [("kind",JString "workspace-git");("primary",JString "")]);("cwd",cwd)]) =
    success (JObject [("kind",JString "workspace-git");("primary",cwd)]).
Proof. reflexivity. Qed.
Theorem public_browser_directory_observation_marks_empty_path_default :
  Api.call "browser.observation" (JObject [("phase",JString "plan");
    ("observation",JObject [("kind",JString "browse-directories");("path",JString "")])]) =
    success (JObject [("kind",JString "browse-directories");("path",JString "");
      ("default_path",JBool true);("project_root",JNull)]).
Proof. reflexivity. Qed.
Theorem public_browser_directory_default_prefers_task_root : forall task_root project_root,
  Api.call "browser.observation" (JObject [("phase",JString "resolve");
    ("plan",JObject [("kind",JString "browse-directories");("path",JString "");
      ("default_path",JBool true);("project_root",project_root)]);
    ("task_environment_present",JBool true);("task_root",task_root)]) =
    success (JObject [("path",task_root);("canonicalize",JBool false)]).
Proof. reflexivity. Qed.
Theorem public_browser_directory_default_canonicalizes_project_root : forall project_root,
  Api.call "browser.observation" (JObject [("phase",JString "resolve");
    ("plan",JObject [("kind",JString "browse-directories");("path",JString "");
      ("default_path",JBool true);("project_root",project_root)]);
    ("task_environment_present",JBool false)]) =
    success (JObject [("path",project_root);("canonicalize",JBool true)]).
Proof. reflexivity. Qed.
Theorem public_browser_directory_failure_is_returned_as_observation : forall message,
  Api.call "browser.observation" (JObject [("phase",JString "complete");
    ("kind",JString "browse-directories");("ok",JBool false);("error",JString message)]) =
    success (JObject [("ok",JBool false);("error",JString message)]).
Proof. reflexivity. Qed.
Theorem public_browser_skill_failure_is_returned_as_observation : forall message,
  Api.call "browser.observation" (JObject [("phase",JString "complete");
    ("kind",JString "skill-catalog");("ok",JBool false);("error",JString message)]) =
    success (JObject [("kind",JString "skill-catalog");("ok",JBool false);("error",JString message)]).
Proof. reflexivity. Qed.
Theorem public_exec_injects_authenticated_connection : forall connection args,
  keys args (client_keys Execute) = true ->
  Api.call "plugin.command" (JObject [("connection",connection);("body",JObject [("tool",JString "exec");("arguments",args)])]) =
  success (JObject [("op",JString "chatgpt_exec");("connection_id",connection);("project_id",get args "project_id");
    ("request_id",get args "request_id");("arguments",JObject [("command",get args "command");
      ("timeout_ms",default_value (get args "timeout_ms") (number 120000));
      ("max_output_length",default_value (get args "max_output_length") (number 4096))])]).
Proof. intros connection args accepted;change ((if keys args (client_keys Execute) then success (command_value connection Execute args) else type_error "Invalid ChatGPT tool arguments") = success (command_value connection Execute args));now rewrite accepted. Qed.
Theorem public_unrelated_transcript_is_preserved : forall source,
  is_text (get source "pending") = true -> is_text (get source "completed") = true ->
  starts (str source "pending") (str source "completed") = false ->
  starts (str source "completed") (str source "pending") = false ->
  Api.call "audio.transcript_tail" source = success (JString (str source "pending")).
Proof. intros;apply transcript_tail_preserves_unrelated_utterance;assumption. Qed.
Theorem public_evaluator_authorizes_only_configured_decision : forall source reply value,
  str source "mode" <> "parsed" -> get source "reply" = reply ->
  Api.call "evaluator.decision" source = success value ->
  decision_identity reply (get source "evaluator") = true /\ decision_configured reply (get source "policy") = true.
Proof.
  intros source reply value mode parsed H.
  change (decision source = success value) in H.
  unfold decision in H. destruct (String.eqb (str source "mode") "parsed") eqn:E.
  - apply String.eqb_eq in E;contradiction.
  - rewrite parsed in H;unfold decision_reply,checked in H.
    destruct (decision_identity reply (get source "evaluator") && decision_configured reply (get source "policy")) eqn:A;[|discriminate].
    now apply andb_true_iff in A.
Qed.
Theorem public_evaluator_accepts_configured_decision : forall source,
  str source "mode" <> "parsed" ->
  decision_identity (get source "reply") (get source "evaluator") = true ->
  decision_configured (get source "reply") (get source "policy") = true ->
  Api.call "evaluator.decision" source = success (JObject [
    ("effort",get (get (get (get source "reply") "answers") "effort") "choice");
    ("generations",lease_number (get (get (get (get source "reply") "answers") "lease") "choice"))]).
Proof.
 intros source mode identity configured;change (decision source = success (JObject [
    ("effort",get (get (get (get source "reply") "answers") "effort") "choice");
    ("generations",lease_number (get (get (get (get source "reply") "answers") "lease") "choice"))]));unfold decision.
 destruct (String.eqb (str source "mode") "parsed") eqn:E;[apply String.eqb_eq in E;contradiction|].
 unfold decision_reply,checked;now rewrite identity,configured.
Qed.
Theorem public_evaluator_nonterminal_retry_preserves_provider_and_bound : forall source result,
  Api.call "evaluator.retry" source = success result -> str result "action" <> "fail" ->
  same_provider source = true /\ bounded_retry source = true.
Proof.
 intros source result H nonterminal;change (retry source = success result) in H;unfold retry in H.
 destruct (String.eqb (str (retry_calculation source) "action") "fail") eqn:terminal.
 - inversion H;subst;apply String.eqb_eq in terminal;contradiction.
 - unfold checked in H;destruct (same_provider source && bounded_retry source) eqn:admission;[|discriminate].
   now apply andb_true_iff in admission.
Qed.

Theorem public_parsed_evaluator_decision_requires_identity_and_configuration : forall source reply value,
  str source "mode" = "parsed" -> TextJson.parse_json (str source "text") = Some reply ->
  Api.call "evaluator.decision" source = success value ->
  decision_identity reply (get source "evaluator") = true /\ decision_configured reply (get source "policy") = true.
Proof.
 intros source reply value mode parsed H;change (decision source = success value) in H.
 unfold decision in H;rewrite mode in H;cbn in H;rewrite parsed in H;unfold decision_reply,checked in H.
 destruct (decision_identity reply (get source "evaluator") && decision_configured reply (get source "policy")) eqn:A;[|discriminate].
 now apply andb_true_iff in A.
Qed.
Theorem public_unissued_rpc_response_preserves_pending_requests : forall source state,
  decode_state source = Some state ->
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
Theorem public_issued_rpc_result_resolves_its_pending_request : forall source state id,
  decode_state source = Some state ->
  is_object (get source "message") = true -> str (get source "message") "jsonrpc" = "2.0" ->
  as_string (get (get source "message") "method") = None ->
  correlate state (get (get source "message") "id") = Some id ->
  has (get source "message") "result" = true -> has (get source "message") "error" = false ->
  field "ok" (Api.call "rpc.message" source) = Some (JBool true) /\
  exists reply,
    field "value" (Api.call "rpc.message" source) = Some reply /\
    field "action" reply = Some (JString "resolve") /\
    field "id" reply = Some (number id) /\
    field "value" reply = Some (get (get source "message") "result") /\
    field "nextId" reply = Some (number state.(next_id)) /\
    exists remaining,
      field "nextPending" reply = Some (JArray (map number remaining)) /\
      ~ In id remaining /\
      (forall other, other <> id -> (In other remaining <-> In other state.(pending))).
Proof.
 intros source state id decoded shape version method identity result_present error_absent.
 assert (execution : Api.call "rpc.message" source = encode_action
   (consume "resolve" state id [("value",get (get source "message") "result")])).
 { change (Rpc.call "rpc.message" source = encode_action
     (consume "resolve" state id [("value",get (get source "message") "result")])).
   unfold Rpc.call;rewrite decoded;cbn.
   unfold message;rewrite shape,version;cbn;rewrite method,identity.
   unfold response;rewrite result_present,error_absent;reflexivity. }
 split; [rewrite execution;reflexivity|].
 exists (get (encode_action (consume "resolve" state id
   [("value",get (get source "message") "result")])) "value").
 split; [rewrite execution;reflexivity|].
 split; [reflexivity|].
 split; [reflexivity|].
 split; [reflexivity|].
 split; [reflexivity|].
 exists (retire id state.(pending)).
 split; [reflexivity|].
 split; [apply consumed_identity_cannot_remain_pending|].
 intros other different;now apply unrelated_pending_identity_is_preserved.
Qed.

Theorem public_compaction_policy_has_ordered_thresholds : forall source result,
  Api.call "config.compaction" source = success result ->
  1 <= nat_value (get result "background_percent") /\
  nat_value (get result "background_percent") < nat_value (get result "blocking_percent") /\
  nat_value (get result "blocking_percent") < 100.
Proof. intros;apply (successful_compaction_has_required_threshold_order Compaction.legal_budget source result);exact H. Qed.
