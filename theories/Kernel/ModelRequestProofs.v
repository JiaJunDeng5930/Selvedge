From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State Observation ContextSelection ReasoningView.
Import ListNotations.
Open Scope string_scope.
Theorem selected_model_request_uses_the_measured_scope : forall id ticket model task scope reserve,
 (0 <? reserve)%N = true ->
 field "history" (Observation.effect_json (RequestModel id ticket model task scope reserve)) =
 Some (JArray (ContextSelection.target_messages (ContextSelection.history_json id (task_history task)) scope)).
Proof. intros; unfold Observation.effect_json; rewrite H; reflexivity. Qed.
Theorem unselected_model_request_uses_portable_context : forall id ticket model task scope,
 field "history" (Observation.effect_json (RequestModel id ticket model task scope 0)) =
 Some (JArray (ContextSelection.portable_messages (ContextSelection.history_json id (task_history task)))).
Proof. intros; reflexivity. Qed.
Theorem model_request_preserves_the_frozen_reserve : forall id ticket model task scope reserve,
 field "output_reserve_tokens" (Observation.effect_json (RequestModel id ticket model task scope reserve)) =
 Some (Numbers.number reserve).
Proof. intros; unfold Observation.effect_json; destruct (0 <? reserve)%N; reflexivity. Qed.
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
