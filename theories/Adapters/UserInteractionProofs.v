From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Adapters Require Import Common Observation Api Http.
From Selvedge.Interaction Require UserCommand.
From Selvedge.Generated Require Commands.
From Selvedge.Kernel Require Codec ModelResultDeclarations Numbers Packet State.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Theorem public_browser_command_delivers_unwrapped_payload source original command :
 open_valid source = true -> host_valid source = true -> Http.authorized source = true ->
 local_origin_valid source = true ->
 str source "method" = "POST" -> str source "pathname" = "/api/browser/command" ->
 str source "target" = "browser_command" ->
 starts (str source "content_type") "application/json" = true ->
 as_string (get source "text") = Some original ->
 TextJson.parse_input_json original = TextJson.InputAccepted (JObject [("command", command)]) ->
 Api.call "http.body" source =
 Json.success (JObject [("action", JString "browser_command"); ("body", command)]).
Proof.
 intros opened host authorization origin method pathname target mime text parsed.
 assert (local : connection_path source = false).
 { unfold connection_path; rewrite pathname; reflexivity. }
 assert (route : body_target source = ModelResultDeclarations.http_body_target_named "browser_command").
 { unfold body_target, audio_target, audio_kind, selected_route, matches_route.
   rewrite method, pathname; reflexivity. }
 change (Http.call "http.body" source =
   Json.success (JObject [("action", JString "browser_command"); ("body", command)])).
 unfold Http.call; cbn; unfold request_guard, open_host_guard.
 rewrite opened, host, authorization, local, origin; cbn.
 unfold body_stage; rewrite route; cbn; rewrite target; cbn.
 rewrite mime; cbn; rewrite text, parsed; reflexivity.
Qed.

Theorem public_command_admission_uses_shared_gate command :
 Api.call "http.public_command" (JObject [("command", command)]) =
 (if UserCommand.public_operation_allowed (str command "op")
  then Json.success JNull else type_error "Speech observations require a live upstream session").
Proof. reflexivity. Qed.

Theorem public_reply_status_uses_command_feedback reply :
 Api.call "http.reply_status" (JObject [("reply", reply)]) =
 Json.success (number (if UserCommand.accepted reply then 200 else 400)).
Proof. reflexivity. Qed.

Theorem accepted_command_feedback_retains_the_result value :
 UserCommand.result (State.success value) = Some value /\
 Api.call "http.reply_status" (JObject [("reply", State.success value)]) =
 Json.success (number 200).
Proof. split; reflexivity. Qed.

Theorem refused_command_feedback_retains_the_diagnostic code message :
 UserCommand.refusal (State.failure code message) =
 JObject [("code", JString code); ("message", JString message)] /\
 Api.call "http.reply_status" (JObject [("reply", State.failure code message)]) =
 Json.success (number 400).
Proof. split; reflexivity. Qed.

Theorem public_assessment_reports_the_command_decision source before command :
 Commands.admit (Codec.value_or_null "command" source) = Some command ->
 let reply := State.decision_reply (Packet.execute_domain (Commands.admitted_value command) None before) in
 let report := Packet.assess source before in
 field "sequence" report = Some (Numbers.number (State.world_sequence before)) /\
 match UserCommand.feedback_of reply with
 | Some (UserCommand.Accepted _) =>
   field "admitted" report = Some (JBool true) /\ field "refusal" report = Some JNull
 | Some (UserCommand.Refused diagnostic) =>
   field "admitted" report = Some (JBool false) /\ field "refusal" report = Some diagnostic
 | None =>
   field "admitted" report = Some (JBool false) /\ field "refusal" report = Some JNull
 end.
Proof.
 intro admitted; unfold Packet.assess; rewrite admitted.
 cbv zeta; unfold UserCommand.assessment.
 destruct (UserCommand.feedback_of (State.decision_reply _)); [destruct f|];
  repeat split; reflexivity.
Qed.
