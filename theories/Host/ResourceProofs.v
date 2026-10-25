From Stdlib Require Import String List Bool.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
From Selvedge.Host Require Import LocalResources.
Definition local_observation_only (action : LocalResources.action) :=
 match action with LocalResources.Persist | LocalResources.Classify | LocalResources.Observe | LocalResources.Finish=>True | _=>False end.
Definition local_recovery_phase (phase : LocalResources.phase) :=
 match phase with LocalResources.Classifying _ | LocalResources.Observing _
 | LocalResources.TerminalPersistence _ _ | LocalResources.Complete _ _ | LocalResources.NeedsResolution _=>true | _=>false end.
Theorem local_recovery_step_never_repeats_mutation : forall value event,
 LocalResources.recovering value.(LocalResources.operation) = true ->
 local_recovery_phase value.(LocalResources.current) = true ->
 Forall local_observation_only (LocalResources.actions (LocalResources.step value event)) /\
 local_recovery_phase (LocalResources.current (LocalResources.next_state (LocalResources.step value event))) = true.
Proof.
 intros [intent metadata phase] event recovering safe.
 destruct intent; cbn in recovering; try discriminate;
 destruct phase; cbn in safe; try discriminate;
 destruct event; cbn;
 repeat match goal with
 | owner : option LocalResources.reservation |- _ => destruct owner
 | classification : LocalResources.classification |- _ => destruct classification
 | result : LocalResources.terminal |- _ => destruct result
 | |- context [String.eqb ?left ?right] => destruct (String.eqb left right)
 end; cbn; split; repeat constructor.
Qed.

Inductive local_trace : LocalResources.state -> list LocalResources.action -> LocalResources.state -> Prop :=
 | LocalTraceDone : forall value, local_trace value [] value
 | LocalTraceStep : forall value event tail final,
   local_trace (LocalResources.next_state (LocalResources.step value event)) tail final ->
   local_trace value (LocalResources.actions (LocalResources.step value event) ++ tail) final.
Theorem local_recovery_trace_never_repeats_mutation : forall value actions final,
 local_trace value actions final ->
 LocalResources.recovering value.(LocalResources.operation) = true ->
 local_recovery_phase value.(LocalResources.current) = true ->
 Forall local_observation_only actions.
Proof.
 intros value actions final trace; induction trace; intros recovering safe; [constructor|].
 destruct (local_recovery_step_never_repeats_mutation value event recovering safe) as [head next].
 apply Forall_app; split; [exact head|apply IHtrace; [|exact next]].
 destruct value as [intent metadata phase]; destruct intent; destruct phase; destruct event; cbn in *;
 repeat match goal with
 | owner : option LocalResources.reservation |- _ => destruct owner
 | classification : LocalResources.classification |- _ => destruct classification
 | result : LocalResources.terminal |- _ => destruct result
 | |- context [String.eqb ?left ?right] => destruct (String.eqb left right)
 end; exact recovering.
Qed.

Theorem git_registration_requires_reservation_persisted_ack : forall intent metadata owner,
 LocalResources.step (LocalResources.State intent metadata (LocalResources.ReservationPersistence owner)) LocalResources.Persisted =
 LocalResources.Plan (LocalResources.State intent metadata (LocalResources.Registering owner)) [LocalResources.Register].
Proof. reflexivity. Qed.
Theorem preparation_requires_git_registration_persisted_ack : forall intent metadata owner,
 LocalResources.step (LocalResources.State intent metadata (LocalResources.RegistrationPersistence owner)) LocalResources.Persisted =
 LocalResources.Plan (LocalResources.State intent metadata (LocalResources.Preparing owner)) [LocalResources.Prepare].
Proof. reflexivity. Qed.
Theorem failed_release_receipt_requires_resolution : forall intent metadata owner,
 LocalResources.current (LocalResources.next_state (LocalResources.step
   (LocalResources.State intent metadata (LocalResources.TerminalPersistence owner LocalResources.Released))
   LocalResources.PersistenceFailed)) = LocalResources.NeedsResolution (Some owner).
Proof. reflexivity. Qed.
Theorem failed_ready_receipt_rechecks_ownership_before_rollback : forall metadata owner,
 LocalResources.actions (LocalResources.step
   (LocalResources.State LocalResources.Create metadata (LocalResources.TerminalPersistence owner LocalResources.CheckoutReady))
   LocalResources.PersistenceFailed) = [LocalResources.Classify].
Proof. reflexivity. Qed.
