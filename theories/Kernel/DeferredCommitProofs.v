From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State Inputs Dispatch DeferredCommit Delivery Notifications
 WorldInvariant WorldInvariantProofs CommitAdmission CommitAdmissionProofs.
Import ListNotations.
Open Scope string_scope.

Definition admitted_decision (durable : bool) (source : option input) (raw : json)
 (before : world) (candidate : decision) :=
 snd (DeferredCommit.admit_with_status durable source raw before candidate).

Lemma admit_is_validation_pipeline : forall durable source raw_source before candidate,
 admitted_decision durable source raw_source before candidate =
 Delivery.deliver durable
   (CommitAdmission.validate durable source raw_source before
     (WorldInvariant.validate before (Dispatch.retain_live_effects candidate))) before.
Proof.
 intros. unfold admitted_decision, DeferredCommit.admit_with_status, Delivery.deliver,
   CommitAdmission.validate, WorldInvariant.validate.
 destruct (WorldInvariant.validate_with_status before (Dispatch.retain_live_effects candidate)) as [valid checked]; cbn [snd].
 destruct (CommitAdmission.validate_with_status durable source raw_source before checked) as [authorized granted]; cbn [snd].
 destruct (Delivery.deliver_with_status durable granted before); reflexivity.
Qed.

Lemma admit_result_is_the_selected_outcome : forall durable source raw_source before candidate admitted result,
 DeferredCommit.admit_with_status durable source raw_source before candidate = (admitted,result) ->
 admitted_decision durable source raw_source before candidate = result.
Proof. intros; unfold admitted_decision; rewrite H; reflexivity. Qed.

Theorem actual_commit_admission_preserves_world_requirements : forall durable source raw_source before candidate,
 world_valid before = true ->
 world_valid (decision_world (admitted_decision durable source raw_source before candidate)) = true.
Proof.
 intros durable source raw_source before candidate Before; rewrite admit_is_validation_pipeline; unfold Delivery.deliver, Delivery.deliver_with_status.
 destruct (Delivery.fits durable _); [|exact Before].
 apply CommitAdmissionProofs.global_admission_preserves_world_validity; [exact Before|].
 apply an_admitted_world_satisfies_the_commit_requirements; exact Before.
Qed.

Theorem actual_commit_refusal_restores_the_world_and_discards_every_effect : forall durable source raw_source before candidate,
 world_valid (decision_world (Dispatch.retain_live_effects candidate)) = false ->
 decision_world (admitted_decision durable source raw_source before candidate) = before /\
 decision_effects (admitted_decision durable source raw_source before candidate) = [].
Proof.
 intros durable source raw_source before candidate Invalid; rewrite admit_is_validation_pipeline; unfold Delivery.deliver, Delivery.deliver_with_status.
 unfold WorldInvariant.validate, WorldInvariant.validate_with_status; rewrite Invalid; cbn [snd].
 unfold CommitAdmission.validate, CommitAdmission.validate_with_status.
 destruct (CommitAdmission.transition_authorized durable source raw_source before
   (reject "invariant_violation" "The candidate violates a world invariant; no state change or effect was committed" before)); cbn [snd];
   destruct (Delivery.fits durable _); split; reflexivity.
Qed.

Lemma retaining_live_effects_preserves_the_world : forall candidate,
 decision_world (Dispatch.retain_live_effects candidate) = decision_world candidate.
Proof. intros []; reflexivity. Qed.

Theorem actual_commit_admission_keeps_an_unchanged_world : forall durable source raw_source before candidate,
 decision_world candidate = before ->
 decision_world (admitted_decision durable source raw_source before candidate) = before.
Proof.
 intros durable source raw_source before candidate Unchanged; rewrite admit_is_validation_pipeline; unfold Delivery.deliver, Delivery.deliver_with_status.
 destruct (Delivery.fits durable _); [|reflexivity].
 unfold CommitAdmission.validate, CommitAdmission.validate_with_status.
 destruct (CommitAdmission.transition_authorized durable source raw_source before
   (WorldInvariant.validate before (Dispatch.retain_live_effects candidate)));
   [|reflexivity].
 unfold WorldInvariant.validate, WorldInvariant.validate_with_status.
 assert (LiveWorld : decision_world (Dispatch.retain_live_effects candidate) = before).
 { rewrite retaining_live_effects_preserves_the_world; exact Unchanged. }
 assert (DecoratedWorld : decision_world (Dispatch.retain_live_effects candidate) = before).
 { exact LiveWorld. }
 destruct (world_valid (decision_world (Dispatch.retain_live_effects candidate)));
   [exact DecoratedWorld|reflexivity].
Qed.

Theorem actual_commit_admission_is_authorized_or_rolled_back : forall durable source raw_source before candidate,
 (decision_world (admitted_decision durable source raw_source before candidate) = before /\
  decision_effects (admitted_decision durable source raw_source before candidate) = []) \/
 (CommitAdmission.transition_authorized durable source raw_source before
    (WorldInvariant.validate before (Dispatch.retain_live_effects candidate)) = true /\
  admitted_decision durable source raw_source before candidate =
    WorldInvariant.validate before (Dispatch.retain_live_effects candidate)).
Proof.
 intros durable source raw_source before candidate.
 rewrite admit_is_validation_pipeline; unfold Delivery.deliver, Delivery.deliver_with_status.
 destruct (Delivery.fits durable
   (CommitAdmission.validate durable source raw_source before
     (WorldInvariant.validate before (Dispatch.retain_live_effects candidate)))) eqn:Fits.
 - destruct (CommitAdmissionProofs.every_global_admission_preserves_or_rolls_back durable source raw_source before
     (WorldInvariant.validate before (Dispatch.retain_live_effects candidate)))
     as [[RolledBackWorld RolledBackEffects] | [Authorized Kept]].
   + left; split; assumption.
   + right; split; [exact Authorized|exact Kept].
 - left; split; reflexivity.
Qed.

Theorem actual_commit_admission_satisfies_global_transition_or_rollback : forall durable source raw_source before candidate,
 (decision_world (admitted_decision durable source raw_source before candidate) = before /\
  decision_effects (admitted_decision durable source raw_source before candidate) = []) \/
 (CommitAdmission.world_evolution source raw_source before
   (decision_world (admitted_decision durable source raw_source before candidate)) = true /\
  CommitAdmission.effect_tickets_fresh (world_next_ticket before)
   (world_next_ticket (decision_world (admitted_decision durable source raw_source before candidate)))
   (decision_effects (admitted_decision durable source raw_source before candidate)) = true /\
  CommitAdmission.effects_authorized source raw_source before
   (decision_world (admitted_decision durable source raw_source before candidate))
   (decision_effects (admitted_decision durable source raw_source before candidate)) = true).
Proof.
 intros durable source raw_source before candidate.
 destruct (actual_commit_admission_is_authorized_or_rolled_back durable source raw_source before candidate)
   as [Rollback | [Authorized Same]].
 - left; exact Rollback.
 - right; rewrite Same.
   exact (CommitAdmissionProofs.an_authorized_transition_has_state_and_effect_authority
     durable source raw_source before
     (WorldInvariant.validate before (Dispatch.retain_live_effects candidate)) Authorized).
Qed.

Theorem actual_admission_binds_every_inference_to_its_exact_history :
 forall durable source raw_source before candidate,
 Forall (CommitAdmissionProofs.inference_history_bound
   (decision_world (admitted_decision durable source raw_source before candidate)))
   (decision_effects (admitted_decision durable source raw_source before candidate)).
Proof.
 intros durable source raw_source before candidate.
 destruct (actual_commit_admission_satisfies_global_transition_or_rollback
   durable source raw_source before candidate)
   as [[Rollback NoEffects] | [Evolution [Fresh Effects]]].
 - rewrite NoEffects; constructor.
 - eapply CommitAdmissionProofs.every_authorized_effect_has_its_inference_history_bound.
   exact Effects.
Qed.

Lemma inference_history_binding_ignores_the_journal_cursor : forall after sequence request,
 CommitAdmissionProofs.inference_history_bound (with_sequence sequence after) request <->
 CommitAdmissionProofs.inference_history_bound after request.
Proof.
 intros after sequence request; unfold CommitAdmissionProofs.inference_history_bound.
 destruct (CommitAdmissionProofs.inference_snapshot request) as [[owner snapshot]|];
   destruct after; reflexivity.
Qed.

Theorem packet_preserves_world_validity : forall source raw before candidate,
 world_valid before = true ->
 world_valid (fst (DeferredCommit.packet source raw before candidate)) = true.
Proof.
 intros source raw before candidate Valid; unfold DeferredCommit.packet.
 destruct (DeferredCommit.admit_with_status true source raw before candidate)
   as [accepted committed] eqn:Outcome; cbn [fst].
 rewrite a_journal_cursor_does_not_change_domain_validity.
 pose proof (actual_commit_admission_preserves_world_requirements
   true source raw before candidate Valid) as Preserved.
 rewrite (admit_result_is_the_selected_outcome _ _ _ _ _ _ _ Outcome) in Preserved.
 exact Preserved.
Qed.

Theorem packet_advances_sequence : forall source raw before candidate,
 world_sequence (fst (DeferredCommit.packet source raw before candidate)) =
 N.succ (world_sequence before).
Proof.
 intros; unfold DeferredCommit.packet.
 destruct (DeferredCommit.admit_with_status true source raw before candidate)
   as [accepted committed]; reflexivity.
Qed.

Lemma journal_sequence_preserves_world_structure : forall sequence value,
 world_structure (with_sequence sequence value) = world_structure value.
Proof. intros sequence []; reflexivity. Qed.
Lemma journal_sequence_preserves_world_evolution : forall source raw before after sequence,
 CommitAdmission.world_evolution source raw before (with_sequence sequence after) =
 CommitAdmission.world_evolution source raw before after.
Proof. intros source raw before []; reflexivity. Qed.

Theorem packet_preserves_global_state_relation_or_rolls_back : forall source raw before candidate,
 let after := fst (DeferredCommit.packet source raw before candidate) in
 world_structure after = world_structure before \/
 CommitAdmission.world_evolution source raw before after = true.
Proof.
 intros source raw before candidate; unfold DeferredCommit.packet.
 destruct (DeferredCommit.admit_with_status true source raw before candidate)
   as [accepted committed] eqn:Outcome; cbn [fst].
 pose proof (actual_commit_admission_satisfies_global_transition_or_rollback
   true source raw before candidate) as Authority.
 rewrite (admit_result_is_the_selected_outcome _ _ _ _ _ _ _ Outcome) in Authority.
 destruct Authority as [[RolledBack _] | [Evolution _]].
 - left; rewrite journal_sequence_preserves_world_structure, RolledBack; reflexivity.
 - right; rewrite journal_sequence_preserves_world_evolution; exact Evolution.
Qed.

Theorem packet_binds_its_emitted_inference_history : forall source raw before candidate,
 exists admitted committed,
 snd (DeferredCommit.packet source raw before candidate) =
   Notifications.envelope true admitted source before committed /\
 Forall (CommitAdmissionProofs.inference_history_bound
   (fst (DeferredCommit.packet source raw before candidate)))
   (decision_effects committed).
Proof.
 intros source raw before candidate; unfold DeferredCommit.packet.
 destruct (DeferredCommit.admit_with_status true source raw before candidate)
   as [accepted committed] eqn:Outcome; cbn [fst snd].
 exists accepted, committed; split; [reflexivity|].
 pose proof (actual_admission_binds_every_inference_to_its_exact_history
   true source raw before candidate) as Bound.
 rewrite (admit_result_is_the_selected_outcome _ _ _ _ _ _ _ Outcome) in Bound.
 rewrite Forall_forall in *; intros request Present.
 apply (proj2 (inference_history_binding_ignores_the_journal_cursor
   (decision_world committed) (N.succ (world_sequence before)) request)).
 exact (Bound request Present).
Qed.

Theorem a_constructed_candidate_with_its_actual_budget_is_committed : forall source raw before candidate,
 Dispatch.retain_live_effects candidate = candidate ->
 WorldInvariant.world_valid (decision_world candidate) = true ->
 CommitAdmission.transition_authorized true source raw before candidate = true ->
 Delivery.fits true candidate = true ->
 DeferredCommit.packet source raw before candidate =
 (with_sequence (N.succ (world_sequence before)) (decision_world candidate),
  Notifications.envelope true true source before candidate).
Proof.
 intros source raw before candidate Live World Authority Budget.
 unfold DeferredCommit.packet, DeferredCommit.admit_with_status. rewrite Live.
 unfold WorldInvariant.validate_with_status. rewrite World.
 unfold CommitAdmission.validate_with_status. rewrite Authority.
 unfold Delivery.deliver_with_status. rewrite Budget. reflexivity.
Qed.
