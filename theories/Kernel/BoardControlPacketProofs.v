From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonProofs RegistryProofs.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Numbers Domain State Inputs InputDecoder Packet
 CommandHandlers Delivery Observation Notifications Dispatch DeferredCommit DeferredCommitProofs
 WorldInvariant WorldInvariantProofs CommitAdmission CreationCommitAuthorization.
From Selvedge.Features Require Import Board BoardProofs Worktree WorktreeProofs Runtime.
Import ListNotations.
Open Scope string_scope.
Module G := Selvedge.Generated.Commands.
Module F := Selvedge.Features.Domain.

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
 unfold Packet.packet, Packet.packet_admitted, Packet.select_admitted.
 rewrite InputDecoder.admitted_input_is_its_decoder_result.
 fold (Delivery.fits_json source); rewrite InputFits,Decoded.
 change (DeferredCommit.packet (Some (UserCommand (G.Cmd_archive_card request))) source before
   (Packet.prepare (Packet.command_schedules (G.Cmd_archive_card request)
     (Packet.execute_command (G.Cmd_archive_card request) None before))
     (Some (UserCommand (G.Cmd_archive_card request)))
     (Packet.execute_command (G.Cmd_archive_card request) None before)) =
   (with_sequence (N.succ (world_sequence before)) before,
    Observation.envelope true (reject "worktree_pending"
      "Wait for worktree creation or archive the task before changing its execution" before))).
 rewrite Executed.
 apply a_business_refusal_commits_its_exact_receipt; [exact Valid|reflexivity].
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
