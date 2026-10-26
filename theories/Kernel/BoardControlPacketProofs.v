From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonProofs RegistryProofs.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Numbers Domain State Inputs InputDecoder Packet
 CommandHandlers Delivery Observation Notifications Dispatch DeferredCommit
 WorldInvariant WorldInvariantProofs CommitAdmission CreationCommitAuthorization.
From Selvedge.Features Require Import Board BoardProofs Worktree Runtime.
Import ListNotations.
Open Scope string_scope.
Module G := Selvedge.Generated.Commands.
Module F := Selvedge.Features.Domain.

Local Lemma numbered_members_have_their_actual_registry_position :
 forall (A B : Type) (project : N -> A -> B) entries offset member,
 In member (indexed project offset entries) ->
 exists position current,
 registry_at position entries = Some current /\
 member = project (offset + position)%N current.
Proof.
 intros A B project entries; induction entries as [|head rest IH];
   intros offset member Member; [contradiction|].
 cbn [indexed] in Member; destruct Member as [Same|Member].
 - subst member; exists 0%N, head; split; [reflexivity|].
   now rewrite N.add_0_r.
 - destruct (IH (N.succ offset) member Member)
     as [position [current [Found Same]]].
   exists (N.succ position), current; split.
   + rewrite registry_lookup_after_head; exact Found.
   + rewrite Same, N.add_succ_l, N.add_succ_r; reflexivity.
Qed.

(* A business refusal keeps every existing workspace selection, including the
   pending owner whose unchanged binding still has cleanup authority. *)
Local Lemma unchanged_worlds_keep_their_workspace_admission : forall before reply effects,
 Worktree.guard_result before (Decision before reply effects) = Decision before reply effects.
Proof.
 intros before reply effects; unfold Worktree.guard_result; cbn [decision_world].
 match goal with
 | |- (if ?checked then _ else _) = _ => assert (Checked : checked = true)
 end.
 { apply forallb_forall; intros [owner current] Member.
   destruct (numbered_members_have_their_actual_registry_position _ _ _ _ _ _ Member)
     as [position [selected [Found Same]]].
   rewrite N.add_0_l in Same; inversion Same; subst owner selected.
   change (find_task position before = Some current) in Found.
   cbn beta iota zeta delta [fst snd]; rewrite Found, JsonProofs.equal_is_reflexive.
   unfold Workspace.same_resource.
   destruct (settings_resource (task_current_settings current));
     cbn; rewrite ?N.eqb_refl; reflexivity. }
 rewrite Checked; reflexivity.
Qed.

Local Lemma unchanged_commands_have_no_notifications : forall command before reply,
 Notifications.envelope true true (Some (UserCommand command)) before
   (Decision before reply []) = Observation.envelope true (Decision before reply []).
Proof.
 intros command before reply.
 assert (NoTaskEvents : forall owner current,
   find_task owner before = Some current ->
   Notifications.task_events before owner current before = []).
 { intros owner current Found; unfold Notifications.task_events.
   rewrite Found, JsonProofs.equal_is_reflexive, Nat2N.id, skipn_all; reflexivity. }
 assert (Empty : forall events,
   In events (indexed (fun owner current => Notifications.task_events before owner current before)
     0 (world_tasks before)) -> events = []).
 { intros events Member.
   destruct (numbered_members_have_their_actual_registry_position _ _ _ _ _ _ Member)
     as [position [current [Found Same]]].
   rewrite N.add_0_l in Same; rewrite Same; apply NoTaskEvents; exact Found. }
 assert (NoEvents : concat (indexed
   (fun owner current => Notifications.task_events before owner current before)
   0 (world_tasks before)) = []).
 { generalize dependent Empty.
   generalize (indexed (fun owner current => Notifications.task_events before owner current before)
     0 (world_tasks before)).
   intros batches; induction batches as [|events rest IH]; intros Empty; [reflexivity|].
   rewrite (Empty events (or_introl eq_refl)); cbn [concat app].
   apply IH; intros item Member; apply Empty; right; exact Member. }
 assert (NoBatch : Notifications.batch (Some (UserCommand command)) before
   (Decision before reply []) = []).
 { change ((concat (indexed
     (fun owner current => Notifications.task_events before owner current before)
     0 (world_tasks before)) ++ [])%list = []).
   rewrite NoEvents; reflexivity. }
 unfold Notifications.envelope; rewrite NoBatch; reflexivity.
Qed.

Local Lemma unchanged_business_refusals_pass_commit_admission :
 forall durable source raw before code reason,
 WorldInvariant.well_formed before ->
 Delivery.fits durable (reject code reason before) = true ->
 DeferredCommit.admit_with_status durable source raw before (reject code reason before) =
   (true,reject code reason before).
Proof.
 intros durable source raw before code reason Valid Fits.
 pose proof (well_formed_worlds_pass_the_checker before Valid) as World.
 assert (Authorized : CommitAdmission.transition_authorized durable source raw before
   (reject code reason before) = true).
 { unfold CommitAdmission.transition_authorized; cbn [reject decision_world decision_effects].
   rewrite an_unchanged_world_preserves_cross_state_authority by exact Valid; reflexivity. }
 assert (Retained : Dispatch.retain_live_effects (reject code reason before) = reject code reason before)
   by reflexivity.
 unfold DeferredCommit.admit_with_status; rewrite Retained.
 unfold WorldInvariant.validate_with_status; cbn [reject decision_world]; rewrite World.
 unfold CommitAdmission.validate_with_status; rewrite Authorized.
 unfold Delivery.deliver_with_status; rewrite Fits; reflexivity.
Qed.

(* The public archive_card refusal is an admitted durable command. Its exact
   worktree_pending reply comes from the shared control guard, not a later
   invariant_violation rollback. No final admission result is a premise. *)
Theorem pending_worktree_card_archive_returns_its_exact_public_refusal :
 forall source request before card target task now tree,
 Delivery.fits_json source = true ->
 InputDecoder.decode source = Some (UserCommand (G.Cmd_archive_card request)) ->
 WorldInvariant.well_formed before ->
 Board.lookup (G.archive_card_card_id request) before = Some card ->
 Board.clock (G.archive_card_observed_at request) = Some now ->
 G.archive_card_revision request = F.card_revision card ->
 Board.pending card = false ->
 F.card_task card = Some target ->
 find_task target before = Some task ->
 task_busy task = true -> task_archived task = false ->
 Worktree.execution_allowed target before = true ->
 Worktree.lookup target before = Some tree -> Worktree.pending tree = true ->
 Packet.packet source before =
 (with_sequence (N.succ (world_sequence before)) before,
  Observation.envelope true (reject "worktree_pending"
    "Wait for worktree creation or archive the task before changing its execution" before)).
Proof.
 intros source request before card target task now tree InputFits Decoded Valid
   Found Clock Revision NotDrafting Linked Owned Busy NotArchived Executable Resource Pending.
 assert (Refused : Board.handle_archive_card request None before =
   reject "worktree_pending"
     "Wait for worktree creation or archive the task before changing its execution" before).
 { unfold Board.handle_archive_card.
   eapply archive_card_pending_owner_rejected; eassumption. }
 assert (Executed : Packet.execute_command (G.Cmd_archive_card request) None before =
   reject "worktree_pending"
     "Wait for worktree creation or archive the task before changing its execution" before).
 { unfold Packet.execute_command.
   assert (DomainRefused : Packet.execute_domain (G.Cmd_archive_card request) None before =
     reject "worktree_pending"
       "Wait for worktree creation or archive the task before changing its execution" before).
   { cbn [Packet.execute_domain Packet.query CommandHandlers.query option_map
       CommandHandlers.interpret CommandHandlers.task_origin Selvedge.Kernel.Commands.origin_allowed
       G.handle_archive_card G.dispatch CommandHandlers.handlers].
     unfold Runtime.guard_command.
     cbn [Worktree.guard_command Runtime.or_else].
     cbn [CommandHandlers.execute CommandHandlers.interpret CommandHandlers.task_origin option_map
       Selvedge.Kernel.Commands.origin_allowed G.handle_archive_card G.dispatch CommandHandlers.handlers].
     change (Worktree.guard_result before (Board.handle_archive_card request None before) =
       reject "worktree_pending"
         "Wait for worktree creation or archive the task before changing its execution" before).
     rewrite Refused; apply unchanged_worlds_keep_their_workspace_admission. }
   rewrite DomainRefused; reflexivity. }
 assert (Admitted : DeferredCommit.admit_with_status true
   (Some (UserCommand (G.Cmd_archive_card request))) source before
   (reject "worktree_pending"
     "Wait for worktree creation or archive the task before changing its execution" before) =
   (true,reject "worktree_pending"
     "Wait for worktree creation or archive the task before changing its execution" before)).
 { apply unchanged_business_refusals_pass_commit_admission; [exact Valid|reflexivity]. }
 unfold Packet.packet, Packet.packet_admitted.
 rewrite InputDecoder.admitted_input_is_its_decoder_result.
 fold (Delivery.fits_json source); rewrite InputFits, Decoded.
 change ((let result := Packet.execute_command (G.Cmd_archive_card request) None before in
   let '(admitted,result) := DeferredCommit.admit_with_status true
     (Some (UserCommand (G.Cmd_archive_card request))) source before
     (Packet.prepare (Packet.command_schedules (G.Cmd_archive_card request) result)
       (Some (UserCommand (G.Cmd_archive_card request))) result) in
   (with_sequence (N.succ (world_sequence before)) (decision_world result),
    Notifications.envelope true admitted (Some (UserCommand (G.Cmd_archive_card request))) before result)) =
   (with_sequence (N.succ (world_sequence before)) before,
    Observation.envelope true (reject "worktree_pending"
      "Wait for worktree creation or archive the task before changing its execution" before))).
 rewrite Executed.
 change ((let '(admitted,result) := DeferredCommit.admit_with_status true
     (Some (UserCommand (G.Cmd_archive_card request))) source before
     (reject "worktree_pending"
       "Wait for worktree creation or archive the task before changing its execution" before) in
   (with_sequence (N.succ (world_sequence before)) (decision_world result),
    Notifications.envelope true admitted (Some (UserCommand (G.Cmd_archive_card request))) before result)) =
   (with_sequence (N.succ (world_sequence before)) before,
    Observation.envelope true (reject "worktree_pending"
      "Wait for worktree creation or archive the task before changing its execution" before))).
 rewrite Admitted.
 change ((with_sequence (N.succ (world_sequence before)) before,
   Notifications.envelope true true (Some (UserCommand (G.Cmd_archive_card request))) before
     (Decision before (State.failure "worktree_pending"
       "Wait for worktree creation or archive the task before changing its execution") [])) =
   (with_sequence (N.succ (world_sequence before)) before,
    Observation.envelope true (Decision before (State.failure "worktree_pending"
      "Wait for worktree creation or archive the task before changing its execution") []))).
 rewrite unchanged_commands_have_no_notifications; reflexivity.
Qed.

Corollary pending_worktree_card_archive_keeps_card_task_and_resource :
 forall source request before card target task now tree,
 Delivery.fits_json source = true ->
 InputDecoder.decode source = Some (UserCommand (G.Cmd_archive_card request)) ->
 WorldInvariant.well_formed before ->
 Board.lookup (G.archive_card_card_id request) before = Some card ->
 Board.clock (G.archive_card_observed_at request) = Some now ->
 G.archive_card_revision request = F.card_revision card ->
 Board.pending card = false ->
 F.card_task card = Some target ->
 find_task target before = Some task ->
 task_busy task = true -> task_archived task = false ->
 Worktree.execution_allowed target before = true ->
 Worktree.lookup target before = Some tree -> Worktree.pending tree = true ->
 let committed := fst (Packet.packet source before) in
 let receipt := snd (Packet.packet source before) in
 Board.lookup (G.archive_card_card_id request) committed = Some card /\
 find_task target committed = Some task /\
 Worktree.lookup target committed = Some tree /\
 field "reply" receipt = Some (State.failure "worktree_pending"
   "Wait for worktree creation or archive the task before changing its execution") /\
 field "effects" receipt = Some (JArray []).
Proof.
 intros source request before card target task now tree InputFits Decoded Valid
   Found Clock Revision NotDrafting Linked Owned Busy NotArchived Executable Resource Pending.
 rewrite (pending_worktree_card_archive_returns_its_exact_public_refusal
   source request before card target task now tree InputFits Decoded Valid
   Found Clock Revision NotDrafting Linked Owned Busy NotArchived Executable Resource Pending).
 cbn beta iota zeta delta [fst snd].
 change (Board.lookup (G.archive_card_card_id request) before = Some card /\
   find_task target before = Some task /\ Worktree.lookup target before = Some tree /\
   Some (State.failure "worktree_pending"
     "Wait for worktree creation or archive the task before changing its execution") =
   Some (State.failure "worktree_pending"
     "Wait for worktree creation or archive the task before changing its execution") /\
   Some (JArray []) = Some (JArray [])).
 repeat split; assumption || reflexivity.
Qed.
