From Stdlib Require Import List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import State Inputs CommitPacket Delivery
 WorldInvariant WorldInvariantProofs CommitAdmission CommitAdmissionProofs.

(** This is the common contract of every selected commit route. A business
    refusal may retain the original domain; an accepted failure settlement
    must satisfy the same cross-state authority as any other committed work. *)
Record requirements (raw : json) (before : world) (chosen : selected) : Prop := Requirements {
 selected_world_valid : world_valid before = true ->
   world_valid (decision_world (selected_decision chosen)) = true;
 selected_world_authorized : well_formed before ->
   world_structure (decision_world (selected_decision chosen)) = world_structure before \/
   CommitAdmission.world_evolution (selected_source chosen) raw before
     (decision_world (selected_decision chosen)) = true;
 selected_history_bound : Forall
   (CommitAdmissionProofs.inference_history_bound (decision_world (selected_decision chosen)))
   (decision_effects (selected_decision chosen))
}.

Lemma sequence_preserves_structure : forall value sequence,
 world_structure (with_sequence sequence value) = world_structure value.
Proof. intros []; reflexivity. Qed.
Lemma sequence_preserves_authority : forall source raw before after sequence,
 CommitAdmission.world_evolution source raw before (with_sequence sequence after) =
 CommitAdmission.world_evolution source raw before after.
Proof. intros source raw before []; reflexivity. Qed.
Lemma sequence_preserves_history_binding : forall after sequence request,
 CommitAdmissionProofs.inference_history_bound (with_sequence sequence after) request <->
 CommitAdmissionProofs.inference_history_bound after request.
Proof.
 intros after sequence request; unfold CommitAdmissionProofs.inference_history_bound.
 destruct (CommitAdmissionProofs.inference_snapshot request) as [[owner snapshot]|];
   destruct after; reflexivity.
Qed.

Theorem output_admission_preserves_requirements : forall raw before durable source candidate,
 requirements raw before (Selected durable true source candidate) ->
 requirements raw before (choose durable source (Delivery.deliver_with_status durable candidate before)).
Proof.
 intros raw before durable source candidate Safe; unfold Delivery.deliver_with_status.
 destruct (Delivery.fits durable candidate); [exact Safe|].
 constructor; cbn; [auto|intros; left; reflexivity|constructor].
Qed.

Theorem finalized_world_is_valid : forall raw before chosen,
 requirements raw before chosen -> world_valid before = true ->
 world_valid (fst (finalize before chosen)) = true.
Proof.
 intros raw before chosen Safe Valid; apply finalize_preserves.
 - intros; now rewrite a_journal_cursor_does_not_change_domain_validity.
 - exact (selected_world_valid raw before chosen Safe Valid).
Qed.
Theorem finalized_world_is_authorized : forall raw before chosen,
 requirements raw before chosen -> well_formed before ->
 world_structure (fst (finalize before chosen)) = world_structure before \/
 CommitAdmission.world_evolution (selected_source chosen) raw before
   (fst (finalize before chosen)) = true.
Proof.
 intros raw before chosen Safe Valid; apply finalize_preserves.
 - intros value sequence [Retained|Authorized].
   + left; now rewrite sequence_preserves_structure.
   + right; now rewrite sequence_preserves_authority.
 - exact (selected_world_authorized raw before chosen Safe Valid).
Qed.
Theorem finalized_receipt_binds_its_history : forall raw before chosen,
 requirements raw before chosen ->
 Forall (CommitAdmissionProofs.inference_history_bound (fst (finalize before chosen)))
   (decision_effects (selected_decision chosen)).
Proof.
 intros raw before chosen Safe; apply finalize_preserves.
 - intros value sequence Bound; rewrite Forall_forall in *; intros request Present.
   apply (proj2 (sequence_preserves_history_binding value sequence request)); auto.
 - exact (selected_history_bound raw before chosen Safe).
Qed.
