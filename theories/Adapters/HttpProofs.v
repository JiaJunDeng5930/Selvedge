From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common Observation Http.
Import ListNotations.
Open Scope string_scope.

Theorem http_body_requires_authorization : forall source target value,
  Http.call "http.body" source = success (JObject [("action",JString target);("body",value)]) ->
  authorized source = true.
Proof.
  intros source target value H.
  unfold Http.call in H; cbn in H.
  unfold request_guard, open_host_guard in H.
  destruct (negb (open_valid source)); [discriminate|].
  destruct (negb (host_valid source)); [discriminate|].
  destruct (negb (authorized source)) eqn:authorized.
  - unfold authorization_rejection in H.
    destruct (connection_path source); discriminate.
  - apply negb_false_iff in authorized; exact authorized.
Qed.

Theorem http_body_requires_local_origin : forall source target value,
  connection_path source = false ->
  Http.call "http.body" source = success (JObject [("action",JString target);("body",value)]) ->
  local_origin_valid source = true.
Proof.
  intros source target value local H.
  unfold Http.call in H; cbn in H.
  unfold request_guard, open_host_guard in H.
  destruct (negb (open_valid source)); [discriminate|].
  destruct (negb (host_valid source)); [discriminate|].
  destruct (negb (authorized source)); [unfold authorization_rejection in H;rewrite local in H;discriminate|].
  rewrite local in H.
  destruct (negb (local_origin_valid source)) eqn:origin; [discriminate|].
  apply negb_false_iff in origin; exact origin.
Qed.

Theorem http_body_requires_connection_method_and_origin : forall source target value,
  connection_path source = true ->
  Http.call "http.body" source = success (JObject [("action",JString target);("body",value)]) ->
  str source "method" = "POST" /\ connection_origin_valid source = true.
Proof.
  intros source target value connection H.
  unfold Http.call in H; cbn in H.
  unfold request_guard, open_host_guard in H.
  destruct (negb (open_valid source)); [discriminate|].
  destruct (negb (host_valid source)); [discriminate|].
  destruct (negb (authorized source)); [unfold authorization_rejection in H;rewrite connection in H;discriminate|].
  rewrite connection in H.
  destruct (negb (String.eqb (str source "method") "POST")) eqn:method; [discriminate|].
  destruct (negb (connection_origin_valid source)) eqn:origin; [discriminate|].
  apply negb_false_iff in method. apply String.eqb_eq in method.
  apply negb_false_iff in origin; auto.
Qed.

Theorem http_public_command_rejects_sideband_observations : forall source,
  str (get source "command") "op" = "record_speech_transcript" \/
  str (get source "command") "op" = "accept_speech_delegation" ->
  Http.call "http.public_command" source =
    failure "TypeError" "Speech observations require a live upstream session".
Proof.
  intros source denied.
  unfold Http.call.
  cbn [String.eqb].
  unfold Http.public_command, Http.public_command_allowed.
  destruct denied as [transcript | delegation]; rewrite transcript || rewrite delegation; reflexivity.
Qed.

Theorem http_command_not_submitted_has_its_public_error_code : forall message,
  Http.call "http.error"
    (JObject [("name",JString "CommandNotSubmitted");("message",JString message)]) =
  success (Http.rejection 400 "command_not_submitted" message).
Proof.
  intros message.
  unfold Http.call, Http.request_error_response.
  cbn [String.eqb].
  reflexivity.
Qed.

Theorem http_input_errors_are_bad_requests : forall name message,
  name = "RangeError" \/ name = "SyntaxError" \/ name = "TypeError" ->
  Http.call "http.error"
    (JObject [("name",JString name);("message",JString message)]) =
  success (Http.rejection 400 "request_failed" message).
Proof.
  intros name message [range | [syntax | type_error]]; subst name;
    unfold Http.call, Http.request_error_response; cbn [String.eqb]; reflexivity.
Qed.

Theorem http_other_errors_are_service_unavailable : forall message,
  Http.call "http.error"
    (JObject [("name",JString "Error");("message",JString message)]) =
  success (Http.rejection 503 "request_failed" message).
Proof.
  intros message.
  unfold Http.call, Http.request_error_response.
  cbn [String.eqb].
  reflexivity.
Qed.
