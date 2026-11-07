From Stdlib Require Import String List Bool PeanoNat.
From Selvedge.Foundation Require Import JsonProofs.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
From Selvedge.Host Require Import LocalResources.
Definition local_recovery_intent value := match value with
 | LocalResources.RecoverCreate | LocalResources.RecoverArchive=>true | _=>false end.
Definition local_observation_only (action : LocalResources.action) :=
 match action with LocalResources.Persist | LocalResources.Classify | LocalResources.Observe
 | LocalResources.Finish=>True | _=>False end.
Definition local_recovery_phase (phase : LocalResources.phase) :=
 match phase with LocalResources.Classifying _ | LocalResources.Observing _
 | LocalResources.TerminalPersistence _ _
 | LocalResources.Complete _ _ | LocalResources.NeedsResolution _=>true | _=>false end.
Theorem local_recovery_step_never_repeats_mutation : forall value event,
 local_recovery_intent value.(LocalResources.operation) = true ->
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
 local_recovery_intent value.(LocalResources.operation) = true ->
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

Theorem admitted_git_registration_matches_its_reservation : forall source,
 LocalResources.git_admitted source = true ->
 get source "root" = get source "canonical_root" /\
 get source "root" = get source "git_top_level" /\
 boolean_field source "git_link_file" = true /\
 get source "backlink" = JString (str source "root" ++ "/.git") /\
 get source "dev" = get (get source "reservation") "dev" /\
 get source "ino" = get (get source "reservation") "ino" /\
 get source "repository_common_dir" = get source "checkout_common_dir".
Proof.
 intros source Admitted. unfold LocalResources.git_admitted in Admitted.
 repeat rewrite andb_true_iff in Admitted.
 repeat split; try (apply equal_reflects_equality; tauto); tauto.
Qed.

Theorem unregistered_release_requires_its_observed_directory : forall source,
 LocalResources.local_classification source = JString "owned_unregistered" ->
 exists entry,
 filter (fun row => boolean_field row "present") (items (get source "entries")) = [entry] /\
 boolean_field entry "directory" = true /\
 get entry "root" = get entry "canonical_root" /\
 get entry "root" = get (get source "reservation") "canonical_root" /\
 get entry "dev" = get (get source "reservation") "dev" /\
 get entry "ino" = get (get source "reservation") "ino" /\
 boolean_field entry "git_link" = false /\
 forall observed, In observed (items (get source "entries")) ->
 forall registration, In registration (items (get observed "registrations")) ->
 registration <> JString ("worktree " ++ str observed "root").
Proof.
 intros source Classified. unfold LocalResources.local_classification in Classified.
 cbn zeta in Classified.
 destruct (is_null (get source "reservation")); [discriminate|].
 destruct (filter (fun entry => boolean_field entry "present") (items (get source "entries")))
   as [|entry rest] eqn:Present.
 - match type of Classified with context [if ?condition then _ else _] => destruct condition end;
     discriminate.
 - destruct rest as [|other rest]; [|discriminate].
   destruct (boolean_field entry "directory" && equal (get entry "root") (get entry "canonical_root") &&
     equal (get entry "dev") (get (get source "reservation") "dev") &&
     equal (get entry "ino") (get (get source "reservation") "ino")) eqn:Owned; [|discriminate].
   destruct (boolean_field entry "git_link") eqn:Link.
   { match type of Classified with context [if ?condition then _ else _] => destruct condition end;
       discriminate. }
   match type of Classified with context [if negb ?condition then _ else _] =>
     destruct condition eqn:Registrations end; cbn in Classified; [|discriminate].
   destruct (equal (get entry "root") (get (get source "reservation") "canonical_root")) eqn:Root; [|discriminate].
   repeat rewrite andb_true_iff in Owned.
   apply Nat.eqb_eq in Registrations. apply length_zero_iff_nil in Registrations.
   exists entry. repeat split; try reflexivity; try assumption;
     try (apply equal_reflects_equality; tauto); try tauto.
   intros observed Member registration Registered Same.
   assert (Found : In observed (filter (fun row => existsb
     (fun value => equal value (JString ("worktree " ++ str row "root")))
     (items (get row "registrations"))) (items (get source "entries")))).
   { apply filter_In. split; [exact Member|].
     apply existsb_exists. exists registration. split; [exact Registered|].
     rewrite Same. apply equal_is_reflexive. }
   rewrite Registrations in Found. contradiction.
Qed.
