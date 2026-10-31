From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import State Inputs Dispatch.
From Selvedge.Kernel Require Import DeferredCommit.
From Selvedge.Kernel Require Import Delivery Notifications NotificationsProofs.
From Selvedge.Programming Require Import CommitPacket.
Import ListNotations.
Open Scope string_scope.

Definition admitted_decision durable before candidate :=
 snd (DeferredCommit.admit_with_status durable before candidate).

Lemma retaining_live_effects_preserves_the_world : forall candidate,
 decision_world (Dispatch.retain_live_effects candidate) = decision_world candidate.
Proof. intros []; reflexivity. Qed.

Theorem actual_commit_admission_keeps_an_unchanged_world : forall durable before candidate,
 decision_world candidate = before ->
 decision_world (admitted_decision durable before candidate) = before.
Proof.
 intros durable before candidate Unchanged.
 unfold admitted_decision, DeferredCommit.admit_with_status, Delivery.deliver_with_status.
 destruct (Delivery.fits durable _); [|reflexivity].
 exact Unchanged.
Qed.

Theorem actual_commit_admission_keeps_an_empty_effect_list : forall durable before candidate,
 decision_effects candidate = [] ->
 decision_effects (admitted_decision durable before candidate) = [].
Proof.
 intros durable before [next reply effects] Empty; cbn in Empty; subst effects.
 unfold admitted_decision, DeferredCommit.admit_with_status, Delivery.deliver_with_status.
 destruct (Delivery.fits durable _); reflexivity.
Qed.

Lemma a_noncommitting_unchanged_candidate_has_no_effect : forall source before candidate,
 decision_world candidate = before -> decision_effects candidate = [] ->
 fst (CommitPacket.finalize before (DeferredCommit.select false source before candidate)) = before /\
 Json.field "effects" (snd (CommitPacket.finalize before (DeferredCommit.select false source before candidate))) = Some (JArray []) /\
 Json.field "durable" (snd (CommitPacket.finalize before (DeferredCommit.select false source before candidate))) = Some (JBool false).
Proof.
 intros source before candidate Unchanged Empty.
 pose proof (actual_commit_admission_keeps_an_unchanged_world false before candidate Unchanged) as World.
 pose proof (actual_commit_admission_keeps_an_empty_effect_list false before candidate Empty) as Effects.
 unfold admitted_decision in World,Effects.
 unfold DeferredCommit.select,CommitPacket.choose,CommitPacket.finalize.
 destruct (DeferredCommit.admit_with_status false before candidate) as [admitted result].
 cbn [fst snd selected_durable selected_admitted selected_source selected_decision] in *.
 split; [exact World|split].
 - rewrite NotificationsProofs.a_query_has_no_notification_batch.
   unfold Observation.envelope; rewrite Effects; reflexivity.
 - apply NotificationsProofs.notification_envelopes_preserve_the_durability_flag.
Qed.

Theorem a_constructed_candidate_with_its_actual_budget_is_committed : forall source before candidate,
 Dispatch.retain_live_effects candidate = candidate -> Delivery.fits true candidate = true ->
 DeferredCommit.packet source before candidate =
 (with_sequence (N.succ (world_sequence before)) (decision_world candidate),
  Notifications.envelope true true source before candidate).
Proof.
 intros source before candidate Live Budget.
 unfold DeferredCommit.packet, DeferredCommit.select, CommitPacket.choose, DeferredCommit.admit_with_status.
 rewrite Live; unfold Delivery.deliver_with_status; rewrite Budget; reflexivity.
Qed.

Theorem a_business_refusal_commits_its_exact_receipt : forall command before code message,
 Delivery.fits true (reject code message before) = true ->
 DeferredCommit.packet (Some (UserCommand command)) before (reject code message before) =
 (with_sequence (N.succ (world_sequence before)) before,Observation.envelope true (reject code message before)).
Proof.
 intros command before code message Fits.
 rewrite a_constructed_candidate_with_its_actual_budget_is_committed; try reflexivity; try exact Fits.
 unfold reject; rewrite unchanged_commands_have_no_notifications; reflexivity.
Qed.
