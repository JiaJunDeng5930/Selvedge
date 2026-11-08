From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Adapters Require Import Common Observation Api Http.
From Selvedge.Interaction Require CardDecisions ObjectDecisions Identity UserCommand Codec.
From Selvedge.Interaction.Experience Require Query Read.
From Selvedge.Generated Require Commands.
From Selvedge.Kernel Require Codec ModelResultDeclarations Numbers Packet State.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Theorem public_interaction_delivers_authenticated_request source original value :
 open_valid source = true -> host_valid source = true -> Http.authorized source = true ->
 local_origin_valid source = true ->
 str source "method" = "POST" -> str source "pathname" = "/api/interaction" ->
 str source "target" = "interaction" ->
 starts (str source "content_type") "application/json" = true ->
 as_string (get source "text") = Some original -> TextJson.parse_input_json original = TextJson.InputAccepted value ->
 Api.call "http.body" source =
  Json.success (JObject [("action", JString "interaction"); ("body", value)]).
Proof.
 intros opened host authorization origin method pathname target mime text parsed.
 assert (local : connection_path source = false).
 { unfold connection_path; rewrite pathname; reflexivity. }
 assert (route : body_target source = ModelResultDeclarations.http_body_target_named "interaction").
 { unfold body_target, audio_target, audio_kind, selected_route, matches_route.
   rewrite method, pathname. reflexivity. }
 change (Http.call "http.body" source =
   Json.success (JObject [("action", JString "interaction"); ("body", value)])).
 unfold Http.call; cbn; unfold request_guard, open_host_guard.
 rewrite opened, host, authorization, local, origin; cbn.
 unfold body_stage; rewrite route; cbn; rewrite target; cbn.
 rewrite mime; cbn; rewrite text, parsed; reflexivity.
Qed.

Theorem public_interaction_shares_business_observations snapshot raw subject :
 Query.decode_request raw = Some (Query.Information subject) ->
 Api.call "http.interaction" (JObject [("request", raw); ("snapshot", snapshot)]) =
 Json.success (match Read.describe snapshot subject with
 | Some value => Http.respond 200 (State.success value)
 | None => Http.rejection 404 "not_found" "The requested subject is unavailable"
 end).
Proof.
 intro decoded.
 change (Api.call "http.interaction" (JObject [("request", raw); ("snapshot", snapshot)]))
  with (Json.success (Http.interaction_response (JObject [("request", raw); ("snapshot", snapshot)]))).
 unfold Http.interaction_response.
 change (get (JObject [("request", raw); ("snapshot", snapshot)]) "request") with raw.
 rewrite decoded. reflexivity.
Qed.

Theorem public_interaction_shares_object_choices snapshot clock raw subject :
 Query.decode_request raw = Some (Query.ObjectChoices subject) ->
 ObjectDecisions.subject_exists snapshot subject = true ->
 Api.call "http.interaction" (JObject [("request", raw); ("snapshot", snapshot); ("now", clock)]) =
 Json.success (Http.respond 200 (State.success (Read.encode_list ObjectDecisions.encode_decision
   (ObjectDecisions.decisions snapshot (Selvedge.Interaction.Codec.natural clock) subject ++
    match subject with
    | Identity.TaskActions task => ObjectDecisions.reading_decisions snapshot task
    | _ => []
    end)%list))).
Proof.
 intros decoded exists_subject.
 change (Api.call "http.interaction" (JObject [("request", raw); ("snapshot", snapshot); ("now", clock)]))
  with (Json.success (Http.interaction_response (JObject [("request", raw); ("snapshot", snapshot); ("now", clock)]))).
 unfold Http.interaction_response.
 change (get (JObject [("request", raw); ("snapshot", snapshot); ("now", clock)]) "request") with raw.
 rewrite decoded.
 cbn [Query.observe].
 change (get (JObject [("request", raw); ("snapshot", snapshot); ("now", clock)]) "snapshot") with snapshot.
 now rewrite exists_subject.
Qed.

Theorem public_interaction_shares_card_choices snapshot raw id :
 Selvedge.Interaction.Codec.text "kind" raw = "card-decisions" ->
 Selvedge.Interaction.Codec.natural_field "id" raw = Some id ->
 Api.call "http.interaction" (JObject [("request", raw); ("snapshot", snapshot)]) =
 Json.success (match CardDecisions.observe snapshot id with
 | Some value => Http.respond 200 (State.success (CardDecisions.encode_opportunity value))
 | None => Http.rejection 404 "not_found" "The requested subject is unavailable"
 end).
Proof.
 intros kind selected.
 change (Api.call "http.interaction" (JObject [("request", raw); ("snapshot", snapshot)]))
  with (Json.success (Http.interaction_response (JObject [("request", raw); ("snapshot", snapshot)]))).
 unfold Http.interaction_response, Query.decode_request.
 change (get (JObject [("request", raw); ("snapshot", snapshot)]) "request") with raw.
 rewrite kind, selected.
 change (get (JObject [("request", raw); ("snapshot", snapshot)]) "snapshot") with snapshot.
 cbn [option_map Query.observe].
 now destruct (CardDecisions.observe snapshot id).
Qed.

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
 | None => True
 end.
Proof.
 intro admitted; unfold Packet.assess; rewrite admitted.
 cbv zeta; split; [reflexivity|].
 set (reply := State.decision_reply _) in *.
 unfold UserCommand.feedback_of, Codec.bool_default.
 destruct (bool_field "ok" reply) as [[]|]; cbn [option_map].
 - destruct (field "result" reply); now cbn.
 - unfold Codec.value_or_null. destruct (field "error" reply); now cbn.
 - exact I.
Qed.
