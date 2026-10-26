From Selvedge.Kernel Require Import CommandHandlers.
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
    after opening a side while the parent's workspace is still being created.
    The shared origin policy precedes resource admission: this command is
    TaskExcluded, so Task callers get its exact origin refusal; public callers
    retain the workspace refusal. Both branches preserve the world and effects. *)
Theorem failed_parent_preserves_side_return : forall payload caller value side parent,
 find_task (return_side_conversation_task_id payload) value = Some side ->
 task_side_parent side = Some parent ->
 Worktree.execution_allowed parent value = false ->
 Packet.execute_domain (Cmd_return_side_conversation payload) caller value =
 match caller with
 | Some _ => Decision value CommandHandlers.origin_failure []
 | None => reject "worktree_creation_failed"
   "Worktree creation failed. Archive this task and create a new task to retry; this task cannot execute in the original workspace." value
 end.
Proof.
 intros payload caller value side parent found related failed.
 destruct caller as [context|]; [reflexivity|].
 unfold Packet.execute_domain, Packet.query.
 cbn [CommandHandlers.query CommandHandlers.interpret CommandHandlers.task_origin
   Selvedge.Kernel.Commands.origin_allowed option_map
   Selvedge.Generated.Commands.dispatch CommandHandlers.handlers].
 unfold Selvedge.Features.Runtime.guard_command, Worktree.guard_command.
 rewrite found, related, failed. reflexivity.
Qed.

Local Lemma rejected_command_preserves_tasks_at_packet : forall source command value code reason,
 InputDecoder.decode source = Some (UserCommand command) ->
 Packet.manual_fork source = None ->
 CreationCommit.input (InputDecoder.decode source) = None ->
 Packet.deferred_candidate (InputDecoder.decode source) value = None ->
 Packet.execute_domain command None value = reject code reason value ->
 world_tasks (fst (Packet.packet source value)) = world_tasks value.
Proof.
 intros source command value code reason decoded Manual Creation Deferred refused.
 unfold Packet.packet, Packet.packet_admitted;
 rewrite !InputDecoder.admitted_input_is_its_decoder_result;
 cbv beta zeta; fold (Packet.manual_fork source) (Packet.transition source value).
 destruct (N.leb (N.of_nat (String.length (TextJson.render_json source))) Limits.frame_bytes);
   [|reflexivity].
 rewrite Manual, Creation, Deferred. unfold Packet.transition, Packet.transition_decoded. rewrite decoded.
 destruct (Packet.query command None value) as [reply|] eqn:queried.
 - cbn [Packet.prepare].
   destruct (Packet.admit_with_status false (Some (UserCommand command)) source value
     (Decision value reply [])) as [admitted result] eqn:Outcome.
   cbn [fst].
   assert (World : decision_world result = value).
   { rewrite <- (admit_result_is_the_selected_outcome _ _ _ _ _ _ _ Outcome).
     apply actual_commit_admission_keeps_an_unchanged_world; reflexivity. }
   rewrite World; reflexivity.
 - unfold Packet.execute_command. rewrite refused.
   assert (does_not_schedule : Packet.command_schedules command (reject code reason value) = false)
     by reflexivity.
   rewrite does_not_schedule. cbn beta iota zeta.
   rewrite does_not_schedule. cbn beta iota zeta.
   cbn [Packet.prepare].
   destruct (Packet.admit_with_status true (Some (UserCommand command)) source value
     (reject code reason value)) as [admitted result] eqn:Outcome.
   cbn [fst].
   assert (World : decision_world result = value).
   { rewrite <- (admit_result_is_the_selected_outcome _ _ _ _ _ _ _ Outcome).
     apply actual_commit_admission_keeps_an_unchanged_world; reflexivity. }
   rewrite World; reflexivity.
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
 eapply rejected_command_preserves_tasks_at_packet; [exact decoded| | | |].
   { unfold Packet.manual_fork, Packet.manual_fork_input; rewrite decoded; reflexivity. }
   { rewrite decoded; reflexivity. }
   { rewrite decoded; reflexivity. }
 eapply (failed_parent_preserves_side_return payload None value side parent); eassumption.
Qed.

Theorem failed_setup_refuses_new_input_at_packet : forall source payload value,
 InputDecoder.decode source = Some (UserCommand (Cmd_send payload)) ->
 Worktree.execution_allowed (send_task_id payload) value = false ->
 world_tasks (fst (Packet.packet source value)) = world_tasks value.
Proof.
 intros source payload value Decoded Failed.
 eapply rejected_command_preserves_tasks_at_packet; [exact Decoded| | | |].
   { unfold Packet.manual_fork, Packet.manual_fork_input; rewrite Decoded; reflexivity. }
   { rewrite Decoded; reflexivity. }
   { rewrite Decoded; reflexivity. }
 unfold Packet.execute_domain, Packet.query.
 cbn [CommandHandlers.query CommandHandlers.interpret CommandHandlers.task_origin
   Selvedge.Kernel.Commands.origin_allowed option_map
   Selvedge.Generated.Commands.dispatch CommandHandlers.handlers].
 unfold Selvedge.Features.Runtime.guard_command, Worktree.guard_command, Worktree.execution_guard.
 rewrite Failed; reflexivity.
Qed.

Theorem failed_setup_refuses_fork_at_packet : forall source payload value,
 InputDecoder.decode source = Some (UserCommand (Cmd_fork payload)) ->
 Worktree.execution_allowed (fork_task_id payload) value = false ->
 world_tasks (fst (Packet.packet source value)) = world_tasks value.
Proof.
 intros source payload value Decoded Failed.
 assert (Refused : ForkCommit.candidate payload value = Worktree.failed_execution value).
 { unfold ForkCommit.candidate, ForkCommit.propose, Worktree.execution_guard.
   rewrite Failed; unfold ForkCommit.admit_workspace, Worktree.failed_execution.
   cbn [reject decision_world]; rewrite skipn_all; reflexivity. }
 unfold Packet.packet, Packet.packet_admitted;
 rewrite !InputDecoder.admitted_input_is_its_decoder_result;
 destruct (N.leb _ _); [|reflexivity].
 cbv beta zeta; rewrite Decoded; cbn [Packet.manual_fork_input].
 unfold ForkCommit.packet; rewrite Refused; unfold Delivery.deliver_with_status.
 destruct (Delivery.fits _ _); reflexivity.
Qed.

Theorem failed_setup_refuses_steering_at_packet : forall source payload value,
 InputDecoder.decode source = Some (UserCommand (Cmd_steer payload)) ->
 Worktree.execution_allowed (steer_task_id payload) value = false ->
 world_tasks (fst (Packet.packet source value)) = world_tasks value.
Proof.
 intros source payload value Decoded Failed.
 eapply rejected_command_preserves_tasks_at_packet; [exact Decoded| | | |].
   { unfold Packet.manual_fork, Packet.manual_fork_input; rewrite Decoded; reflexivity. }
   { rewrite Decoded; reflexivity. }
   { rewrite Decoded; reflexivity. }
 unfold Packet.execute_domain, Packet.query.
 cbn [CommandHandlers.query CommandHandlers.interpret CommandHandlers.task_origin
   Selvedge.Kernel.Commands.origin_allowed option_map
   Selvedge.Generated.Commands.dispatch CommandHandlers.handlers].
 unfold Selvedge.Features.Runtime.guard_command, Worktree.guard_command, Worktree.execution_guard.
 rewrite Failed; reflexivity.
Qed.

Theorem failed_setup_refuses_side_creation_at_packet : forall source payload value,
 InputDecoder.decode source = Some (UserCommand (Cmd_open_side_conversation payload)) ->
 Worktree.execution_allowed (open_side_conversation_task_id payload) value = false ->
 world_tasks (fst (Packet.packet source value)) = world_tasks value.
Proof.
 intros source payload value Decoded Failed.
 eapply rejected_command_preserves_tasks_at_packet; [exact Decoded| | | |].
   { unfold Packet.manual_fork, Packet.manual_fork_input; rewrite Decoded; reflexivity. }
   { rewrite Decoded; reflexivity. }
   { rewrite Decoded; reflexivity. }
 unfold Packet.execute_domain, Packet.query.
 cbn [CommandHandlers.query CommandHandlers.interpret CommandHandlers.task_origin
   Selvedge.Kernel.Commands.origin_allowed option_map
   Selvedge.Generated.Commands.dispatch CommandHandlers.handlers].
 unfold Selvedge.Features.Runtime.guard_command, Worktree.guard_command, Worktree.execution_guard.
 rewrite Failed; reflexivity.
Qed.

Theorem failed_setup_refuses_execution_changes_at_packet : forall source payload value,
 InputDecoder.decode source = Some (UserCommand (Cmd_configure_task_execution payload)) ->
 Worktree.execution_allowed (configure_task_execution_task_id payload) value = false ->
 world_tasks (fst (Packet.packet source value)) = world_tasks value.
Proof.
 intros source payload value Decoded Failed.
 eapply rejected_command_preserves_tasks_at_packet; [exact Decoded| | | |].
   { unfold Packet.manual_fork, Packet.manual_fork_input; rewrite Decoded; reflexivity. }
   { rewrite Decoded; reflexivity. }
   { rewrite Decoded; reflexivity. }
 unfold Packet.execute_domain, Packet.query.
 cbn [CommandHandlers.query CommandHandlers.interpret CommandHandlers.task_origin
   Selvedge.Kernel.Commands.origin_allowed option_map
   Selvedge.Generated.Commands.dispatch CommandHandlers.handlers].
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
 - eapply rejected_command_preserves_tasks_at_packet; [exact Decoded| | | |].
   { unfold Packet.manual_fork, Packet.manual_fork_input; rewrite Decoded; reflexivity. }
   { rewrite Decoded; reflexivity. }
   { rewrite Decoded; reflexivity. }
   unfold Packet.execute_domain, Packet.query.
   cbn [CommandHandlers.query CommandHandlers.interpret CommandHandlers.task_origin
   Selvedge.Kernel.Commands.origin_allowed option_map
   Selvedge.Generated.Commands.dispatch CommandHandlers.handlers].
   unfold Selvedge.Features.Runtime.guard_command, Worktree.guard_command, Worktree.execution_guard.
   rewrite Available, Found, Pending; reflexivity.
 - eapply failed_setup_refuses_execution_changes_at_packet; eassumption.
Qed.
