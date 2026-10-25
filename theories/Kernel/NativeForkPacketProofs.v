From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Inputs InputDecoder Packet
 NativeForkCommit NativeForkCommitProofs NativeForkAuthorizationProofs NativeForkPreservation
 ForkCommitProofs ForkPreservation DeferredCommit Dispatch WorldInvariant WorldInvariantProofs CommitAdmission Delivery Notifications.
From Selvedge.Features Require Import Worktree.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module G := Selvedge.Generated.Commands.

Lemma a_durable_continuation_is_never_withdrawn : forall candidate,
 decision_effects candidate = [ContinueScheduling] -> Dispatch.retain_live_effects candidate = candidate.
Proof. intros [after reply effects] Only; cbn in Only; subst effects; reflexivity. Qed.

Theorem every_authorized_native_fork_has_its_actual_commit_admission :
 forall raw before (accepted : NativeForkCommit.plan before) messages parent selected,
 let step := NativeForkCommit.planned_step accepted in
 let original := TaskScope.selected (NativeForkCommit.planned_target accepted) in
 WorldInvariant.well_formed before ->
 fork_admissible (Tasks.AcceptedNativeFork (Scheduler.native_fork_invocation step) (Scheduler.native_fork_remaining step))
   (settings_origin (Scheduler.native_fork_request step)) (Scheduler.native_fork_owner step)
   (G.fork_child_count (Scheduler.native_fork_request step)) messages (G.fork_settings (Scheduler.native_fork_request step))
   (started_world accepted) parent selected ->
 WorldInvariant.hooks_correspond (Scheduler.native_fork_owner step) original (Scheduler.native_fork_invocation step) [] = true ->
 historical_result_tickets_below (world_next_ticket before) (task_history original) ->
 WorldInvariant.world_valid (decision_world (requested_decision accepted messages parent selected)) = true /\
 CommitAdmission.transition_authorized true (Some Continue) raw before (requested_decision accepted messages parent selected) = true /\
 Dispatch.retain_live_effects (requested_decision accepted messages parent selected) = requested_decision accepted messages parent selected.
Proof.
 intros raw before accepted messages parent selected step original Valid Admissible Hooks Historical.
 split.
 - apply WorldInvariantProofs.well_formed_worlds_pass_the_checker.
   unfold requested_decision; cbn [decision_world].
   apply every_authorized_native_fork_settlement_preserves_every_world_requirement; assumption.
 - pose proof (every_native_fork_settlement_retains_its_actual_cross_state_authority
     (Some Continue) raw before accepted messages parent selected Valid Admissible) as Authority.
   pose proof (each_native_fork_result_has_only_its_durable_continuation before accepted messages parent selected) as Effects.
   split.
   + unfold CommitAdmission.transition_authorized.
     change (CommitAdmission.world_evolution (Some Continue) raw before
       (decision_world (requested_settlement accepted messages parent selected)) = true) in Authority.
     rewrite Effects; cbn [requested_decision decision_world]; rewrite Authority; reflexivity.
   + apply a_durable_continuation_is_never_withdrawn; exact Effects.
Qed.

Theorem every_admissible_exported_native_fork_commits_its_actual_result :
 forall raw before (accepted : NativeForkCommit.plan before) messages parent selected,
 let step := NativeForkCommit.planned_step accepted in
 let original := TaskScope.selected (NativeForkCommit.planned_target accepted) in
 WorldInvariant.well_formed before ->
 InputDecoder.decode raw = Some Continue -> Delivery.fits_json raw = true ->
 NativeForkCommit.resolve Continue before = Some accepted ->
 Codec.traverse Images.parse_content (message_sources (Scheduler.native_fork_request step)) = Some messages ->
 fork_admissible (Tasks.AcceptedNativeFork (Scheduler.native_fork_invocation step) (Scheduler.native_fork_remaining step))
   (settings_origin (Scheduler.native_fork_request step)) (Scheduler.native_fork_owner step)
   (G.fork_child_count (Scheduler.native_fork_request step)) messages (G.fork_settings (Scheduler.native_fork_request step))
   (started_world accepted) parent selected ->
 Worktree.workspace_available (settings_workspace selected) (started_world accepted) &&
   Worktree.binding_available selected (requested_world accepted messages parent selected) = true ->
 WorldInvariant.hooks_correspond (Scheduler.native_fork_owner step) original (Scheduler.native_fork_invocation step) [] = true ->
 historical_result_tickets_below (world_next_ticket before) (task_history original) ->
 Delivery.fits true (requested_decision accepted messages parent selected) = true ->
 Packet.packet raw before =
 (with_sequence (N.succ (world_sequence before)) (decision_world (requested_settlement accepted messages parent selected)),
  Notifications.envelope true true (Some Continue) before (requested_decision accepted messages parent selected)).
Proof.
 intros raw before accepted messages parent selected step original Valid Decoded InputFits Selected Parsed
   Admissible Workspace Hooks Historical OutputFits.
 pose proof (every_admissible_native_fork_plan_constructs_its_actual_settlement before accepted messages parent selected Parsed Admissible Workspace) as Constructed.
 destruct (every_authorized_native_fork_has_its_actual_commit_admission raw before accepted messages parent selected Valid Admissible Hooks Historical)
   as [World [Authority Retained]].
 unfold Packet.packet; fold (Delivery.fits_json raw); rewrite InputFits,Decoded.
 cbn [Packet.manual_fork_input CreationCommit.input Packet.deferred_candidate BoardCommit.input ConnectionCommit.input
   Packet.native_fork_input].
 rewrite Selected; cbn.
 unfold DeferredCommit.packet,DeferredCommit.admit_with_status.
 rewrite Constructed,Retained.
 unfold WorldInvariant.validate_with_status; rewrite World.
 unfold CommitAdmission.validate_with_status; rewrite Authority.
 unfold Delivery.deliver_with_status; rewrite OutputFits; reflexivity.
Qed.
