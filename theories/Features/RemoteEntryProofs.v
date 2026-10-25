From Selvedge.Kernel Require Import CommandHandlers.
From Selvedge.Foundation Require Import RemoteIdentity.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonProofs JsonObjectsProofs.
From Selvedge.Kernel Require Import Domain State Numbers Tasks Packet.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Remote Worktree RemoteProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module G := Selvedge.Generated.Commands.
Module F := Selvedge.Features.Domain.

(** A scoped real control transition: a running first task must become stopped,
    while the independently checked workspace guard remains satisfied. *)
Theorem actual_stop_preserves_workspace_and_stops_task : forall task phase operations value,
 world_tasks value = [task] ->
 task_lifecycle task = Running phase operations ->
 Worktree.control_allowed Tasks.Stop 0 value = true ->
 Packet.execute_domain (G.Cmd_stop (G.Build_stop 0)) None value =
 accept (JObject [("task_id",number 0)])
   (put_task 0 (with_lifecycle (Stopped phase operations) task) value) [].
Proof.
 intros task phase operations value Tasks Running Allowed.
 assert (Executable : Worktree.execution_allowed 0 value = true).
 { unfold Worktree.control_allowed in Allowed.
   apply andb_true_iff in Allowed; exact (proj1 Allowed). }
 cbn [Packet.execute_domain Packet.query Selvedge.Kernel.Queries.answer
   CommandHandlers.query G.handle_stop Selvedge.Generated.Commands.dispatch CommandHandlers.handlers CommandHandlers.require_handler Selvedge.Features.Runtime.or_else
   Selvedge.Features.Work.query Selvedge.Features.Board.query
   Selvedge.Features.TaskGraph.query Worktree.query Remote.query
   Selvedge.Features.Chatgpt.query Selvedge.Features.TitleRuntime.query
   Selvedge.Features.Runtime.guard_command Worktree.guard_command].
 unfold Selvedge.Features.Runtime.guard_command, Worktree.guard_command.
 cbn [G.stop_task_id]. unfold Worktree.execution_guard.
 rewrite Executable, Allowed. cbn [Selvedge.Features.Runtime.or_else].
 cbn [CommandHandlers.execute G.handle_stop Selvedge.Generated.Commands.dispatch CommandHandlers.handlers CommandHandlers.require_handler Selvedge.Features.Runtime.or_else
   Selvedge.Features.Work.command Selvedge.Features.Board.command
   Selvedge.Features.TaskGraph.command Worktree.command
   Remote.command Selvedge.Features.Chatgpt.command Selvedge.Features.Compaction.command
   Selvedge.Features.TitleRuntime.command Selvedge.Kernel.CommandExecution.execute
   Selvedge.Kernel.Tasks.control_command].
 unfold Tasks.control_command, State.find_task. rewrite Tasks. cbn.
 unfold Tasks.control_task, Tasks.control_target. rewrite Running. cbn [Tasks.control_transition].
 unfold Selvedge.Features.Runtime.guard_result, Worktree.guard_result, accept, put_task.
 destruct value; cbn in Tasks; subst.
 destruct task; cbn in Running; subst. cbn -[Json.equal].
 rewrite !JsonProofs.equal_is_reflexive.
 match goal with
 | |- context [Selvedge.Kernel.Workspace.same_resource ?reference ?reference] =>
   destruct reference; cbn [Selvedge.Kernel.Workspace.same_resource];
   rewrite ?N.eqb_refl; reflexivity
 end.
Qed.

Definition stop_first_wire := JObject [("op",JString "stop");("task_id",number 0)].
Definition stop_first_source := JObject [("command",stop_first_wire)].

(** Current control authority has observable force at the extracted executor:
    the task is stopped and the original success is durably retained. Read,
    configure and approve permissions are unnecessary for this operation. *)
Theorem current_control_grant_executes_actual_remote_stop : forall task phase operations value request issued,
 world_tasks value = [task] ->
 task_lifecycle task = Running phase operations ->
 Worktree.control_allowed Tasks.Stop 0 value = true ->
 F.remote_enabled (Remote.registry value) = true ->
 Remote.request_valid request = true ->
 Remote.find_grant (Remote.controller request) (Remote.registry value) = Some issued ->
 Remote.epoch request = F.grant_epoch issued ->
 F.may_control (F.grant_rights issued) = true ->
 find (Remote.key_matches request) (F.remote_receipts (Remote.registry value)) = None ->
 (N.of_nat (List.length (F.remote_receipts (Remote.registry value))) <? 1024) = true ->
 Remote.execute_remote Packet.execute_domain stop_first_source request
   (G.Cmd_stop (G.Build_stop 0)) value =
 (true,true,Decision
   (Remote.store
     (Remote.retain request (success (JObject [("task_id",number 0)])) (Remote.registry value))
     (put_task 0 (with_lifecycle (Stopped phase operations) task) value))
   (success (JObject [("task_id",number 0)])) []).
Proof.
 intros task phase operations value request issued Tasks Running Workspace
   Enabled Valid Granted Epoch Control Fresh Space.
 assert (Permissions : RemoteProofs.granted_permissions Remote.control_rights (F.grant_rights issued)).
 { unfold RemoteProofs.granted_permissions, Remote.control_rights; cbn.
   repeat split; intros; try discriminate; assumption. }
 pose proof (RemoteProofs.current_grant_admits_fresh_remote_request
   Remote.control_rights request (Remote.registry value) issued
   Enabled Valid Granted Epoch Permissions Fresh Space) as Admitted.
 assert (Authorize : Remote.authorize_command true (G.Cmd_stop (G.Build_stop 0))
   request (Remote.registry value) = Remote.Admitted).
 { exact Admitted. }
 assert (Configuration : Remote.configuration_allowed
   (G.Cmd_stop (G.Build_stop 0)) stop_first_source = true) by reflexivity.
 unfold Remote.execute_remote. rewrite Configuration, Authorize.
 cbn [stop_first_source stop_first_wire Remote.observation_command Remote.required_rights].
 assert (Decoded : G.decode stop_first_wire = Some (G.Cmd_stop (G.Build_stop 0))) by reflexivity.
 assert (Field : field "command" stop_first_source = Some stop_first_wire) by reflexivity.
 rewrite Field, Decoded. cbn [G.declared_command]. rewrite Configuration, Authorize.
 assert (Prepared : Remote.prepared_world stop_first_source value = Some value) by reflexivity.
 rewrite Prepared.
 rewrite (actual_stop_preserves_workspace_and_stops_task task phase operations value Tasks Running Workspace).
 reflexivity.
Qed.
