From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State Observation ContextSelection ReasoningView.
Import ListNotations.
Open Scope string_scope.
Theorem selected_model_request_uses_the_measured_scope : forall value request,
 (0 <? ModelRequest.reserve request)%N = true ->
 field "history" (Observation.effect_json value (RequestModel request)) =
 Some (JArray (ContextSelection.target_messages
   (ContextSelection.history_json (ModelRequest.owner request) (ModelRequest.history request))
   (ModelRequest.scope request))).
Proof.
 intros value [owner [model [contract profile settings lifecycle original queued lineage parent cursor consumed] Selected]
   ticket callable mode history scope reserve] Positive.
 unfold Observation.effect_json, Observation.effect_fields; cbn in *; rewrite Positive, !map_id; reflexivity.
Qed.
Theorem unselected_model_request_uses_portable_context : forall value request,
 ModelRequest.reserve request = 0%N ->
 field "history" (Observation.effect_json value (RequestModel request)) =
 Some (JArray (ContextSelection.portable_messages
   (ContextSelection.history_json (ModelRequest.owner request) (ModelRequest.history request)))).
Proof.
 intros value [owner [model [contract profile settings lifecycle original queued lineage parent cursor consumed] Selected]
   ticket callable mode history scope reserve] Zero. cbn in Zero; subst reserve; cbn; rewrite map_id; reflexivity.
Qed.
Theorem model_request_preserves_the_frozen_reserve : forall value request,
 field "output_reserve_tokens" (Observation.effect_json value (RequestModel request)) =
 Some (Numbers.number (ModelRequest.reserve request)).
Proof.
 intros; unfold Observation.effect_json, Observation.effect_fields;
 destruct (0 <? ModelRequest.reserve request)%N; reflexivity.
Qed.
Theorem model_request_uses_its_unique_sent_mode : forall value request,
 field "output_mode" (Observation.effect_json value (RequestModel request)) =
 Some (JString (Codec.output_mode_name (ModelRequest.mode request))).
Proof.
 intros value request.
 change (Some (JString (proj1_sig (Codec.output_mode_value (ModelRequest.mode request)))) =
   Some (JString (Codec.output_mode_name (ModelRequest.mode request)))).
 destruct (ModelRequest.mode request); reflexivity.
Qed.
Theorem model_request_uses_its_unique_callable_set : forall value request,
 field "callable" (Observation.effect_json value (RequestModel request)) =
 Some (JArray (map JString (ModelRequest.callable request))).
Proof.
 intros; unfold Observation.effect_json, Observation.effect_fields;
 destruct (0 <? ModelRequest.reserve request)%N; reflexivity.
Qed.
Theorem evaluator_history_obeys_its_transport_budget : forall history,
 ReasoningView.fits (ReasoningView.history history) = true.
Proof.
 intros; unfold ReasoningView.history.
 repeat match goal with |- context [if ?condition then _ else _] =>
   let Checked := fresh "Checked" in destruct condition eqn:Checked end;
 try assumption; vm_compute; reflexivity.
Qed.
(* The statement compares arbitrary payloads at the actual recursive preview
   entry. Arbitrary text is deliberately not interpreted as provider JSON. *)
Theorem encrypted_provider_payload_cannot_affect_public_preview : forall fuel value other rest,
 ReasoningView.public_value (S fuel) (JObject (("encrypted_content",value) :: rest)) =
 ReasoningView.public_value (S fuel) (JObject (("encrypted_content",other) :: rest)).
Proof. intros; reflexivity. Qed.
