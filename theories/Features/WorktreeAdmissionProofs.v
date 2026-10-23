From Stdlib Require Import String List NArith.
From Selvedge.Generated Require Import Commands.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Domain State Codec Packet InputDecoder Inputs Notifications Delivery PacketProofs.
From Selvedge.Features Require Import Worktree Runtime.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

(** Rejection occurs at the real command entry, before a side's history is
    copied or its return cursor advances. A later setup failure is reachable
    after opening a side while the parent's workspace is still being created. *)
Theorem failed_parent_preserves_side_return : forall payload caller value side parent,
 find_task (return_side_conversation_task_id payload) value = Some side ->
 task_side_parent side = Some parent ->
 Worktree.execution_allowed parent value = false ->
 Packet.execute_domain (Cmd_return_side_conversation payload) caller value =
 reject "worktree_creation_failed"
   "Worktree creation failed. Archive this task and create a new task to retry; this task cannot execute in the original workspace." value.
Proof.
 intros payload caller value side parent found related failed.
 unfold Packet.execute_domain, Packet.query.
 cbn [Queries.answer Selvedge.Features.Runtime.query].
 unfold Selvedge.Features.Runtime.guard_command, Worktree.guard_command.
 rewrite found, related, failed. reflexivity.
Qed.

Local Lemma rejected_command_preserves_tasks_at_packet : forall source command value code reason,
 InputDecoder.decode source = Some (UserCommand command) ->
 Packet.execute_domain command None value = reject code reason value ->
 world_tasks (fst (Packet.packet source value)) = world_tasks value.
Proof.
 intros source command value code reason decoded refused. unfold Packet.packet.
 destruct (N.leb (N.of_nat (String.length (TextJson.render_json source))) Limits.frame_bytes);
   [|reflexivity].
 unfold Packet.transition. rewrite decoded.
 destruct (Packet.query command None value) as [reply|] eqn:queried.
 - cbn. rewrite (actual_commit_admission_keeps_an_unchanged_world false _ source value (Decision value reply []) eq_refl).
   reflexivity.
 - unfold Packet.execute_command. rewrite refused.
   assert (does_not_schedule : Packet.command_schedules command (reject code reason value) = false)
     by reflexivity.
   rewrite does_not_schedule. cbn beta iota zeta.
   rewrite does_not_schedule. cbn beta iota zeta.
   cbv [with_sequence set].
   cbn beta iota zeta.
   (* Project state first; reducing the unused observation here is expensive. *)
   cbn [fst].
   rewrite (actual_commit_admission_keeps_an_unchanged_world true _ source value (reject code reason value) eq_refl).
   reflexivity.
Qed.

(** The exported packet entry preserves every task, including the side's history
    and return cursor. Its durable journal sequence may still advance. *)
Theorem failed_parent_preserves_tasks_at_packet : forall source payload value side parent,
 InputDecoder.decode source = Some (UserCommand (Cmd_return_side_conversation payload)) ->
 find_task (return_side_conversation_task_id payload) value = Some side ->
 task_side_parent side = Some parent ->
 Worktree.execution_allowed parent value = false ->
 world_tasks (fst (Packet.packet source value)) = world_tasks value.
Proof.
 intros source payload value side parent decoded found related failed.
 eapply rejected_command_preserves_tasks_at_packet; [exact decoded|].
 eapply failed_parent_preserves_side_return; eassumption.
Qed.

Theorem failed_setup_refuses_new_input_at_packet : forall source payload value,
 InputDecoder.decode source = Some (UserCommand (Cmd_send payload)) ->
 Worktree.execution_allowed (send_task_id payload) value = false ->
 world_tasks (fst (Packet.packet source value)) = world_tasks value.
Proof.
 intros source payload value Decoded Failed.
 eapply rejected_command_preserves_tasks_at_packet; [exact Decoded|].
 unfold Packet.execute_domain, Packet.query.
 cbn [Queries.answer Selvedge.Features.Runtime.query].
 unfold Selvedge.Features.Runtime.guard_command, Worktree.guard_command, Worktree.execution_guard.
 rewrite Failed; reflexivity.
Qed.

Theorem failed_setup_refuses_steering_at_packet : forall source payload value,
 InputDecoder.decode source = Some (UserCommand (Cmd_steer payload)) ->
 Worktree.execution_allowed (steer_task_id payload) value = false ->
 world_tasks (fst (Packet.packet source value)) = world_tasks value.
Proof.
 intros source payload value Decoded Failed.
 eapply rejected_command_preserves_tasks_at_packet; [exact Decoded|].
 unfold Packet.execute_domain, Packet.query.
 cbn [Queries.answer Selvedge.Features.Runtime.query].
 unfold Selvedge.Features.Runtime.guard_command, Worktree.guard_command, Worktree.execution_guard.
 rewrite Failed; reflexivity.
Qed.

Theorem failed_setup_refuses_side_creation_at_packet : forall source payload value,
 InputDecoder.decode source = Some (UserCommand (Cmd_open_side_conversation payload)) ->
 Worktree.execution_allowed (open_side_conversation_task_id payload) value = false ->
 world_tasks (fst (Packet.packet source value)) = world_tasks value.
Proof.
 intros source payload value Decoded Failed.
 eapply rejected_command_preserves_tasks_at_packet; [exact Decoded|].
 unfold Packet.execute_domain, Packet.query.
 cbn [Queries.answer Selvedge.Features.Runtime.query].
 unfold Selvedge.Features.Runtime.guard_command, Worktree.guard_command, Worktree.execution_guard.
 rewrite Failed; reflexivity.
Qed.

Theorem failed_setup_refuses_execution_changes_at_packet : forall source payload value,
 InputDecoder.decode source = Some (UserCommand (Cmd_configure_task_execution payload)) ->
 Worktree.execution_allowed (configure_task_execution_task_id payload) value = false ->
 world_tasks (fst (Packet.packet source value)) = world_tasks value.
Proof.
 intros source payload value Decoded Failed.
 eapply rejected_command_preserves_tasks_at_packet; [exact Decoded|].
 unfold Packet.execute_domain, Packet.query.
 cbn [Queries.answer Selvedge.Features.Runtime.query].
 unfold Selvedge.Features.Runtime.guard_command, Worktree.guard_command, Worktree.execution_guard.
 rewrite Failed; reflexivity.
Qed.

Theorem pending_setup_refuses_execution_changes_at_packet : forall source payload value tree,
 InputDecoder.decode source = Some (UserCommand (Cmd_configure_task_execution payload)) ->
 Worktree.lookup (configure_task_execution_task_id payload) value = Some tree ->
 Worktree.pending tree = true ->
 world_tasks (fst (Packet.packet source value)) = world_tasks value.
Proof.
 intros source payload value tree Decoded Found Pending.
 destruct (Worktree.execution_allowed (configure_task_execution_task_id payload) value) eqn:Available.
 - eapply rejected_command_preserves_tasks_at_packet; [exact Decoded|].
   unfold Packet.execute_domain, Packet.query.
   cbn [Queries.answer Selvedge.Features.Runtime.query].
   unfold Selvedge.Features.Runtime.guard_command, Worktree.guard_command, Worktree.execution_guard.
   rewrite Available, Found, Pending; reflexivity.
 - eapply failed_setup_refuses_execution_changes_at_packet; eassumption.
Qed.
