From Selvedge.Programming Require TaskChange TaskScope.
From Selvedge.Kernel Require Import CommandHandlers.
From Selvedge.Foundation Require Import RemoteIdentity.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State Numbers Tasks Packet.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Remote Worktree RemoteProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module G := Selvedge.Generated.Commands.
Module F := Selvedge.Features.Domain.
Module C := CommandResult.
Definition stop_first_payload : G.stop_payload := G.Admit_stop
 (exist _ (exist _ "stop" (or_introl eq_refl), (exist _ 0 eq_refl, tt)) eq_refl).

Definition stop_first_wire := JObject [("op",JString "stop");("task_id",number 0)].

(** Current control authority has observable force at the extracted executor:
    the task is stopped and the original success is durably retained. Read,
    configure and approve permissions are unnecessary for this operation. *)
Theorem current_control_grant_executes_actual_remote_stop : forall task phase operations value request issued,
 world_tasks value = [task] ->
 task_lifecycle task = Running phase operations ->
 F.remote_enabled (Remote.registry value) = true ->
 RemoteProofs.request_valid request = true ->
 Remote.find_grant (Remote.controller request) (Remote.registry value) = Some issued ->
 Remote.epoch request = F.grant_epoch issued ->
 F.may_control (F.grant_rights issued) = true ->
 find (Remote.key_matches request) (F.remote_receipts (Remote.registry value)) = None ->
 (N.of_nat (List.length (F.remote_receipts (Remote.registry value))) <? 1024) = true ->
 exists reply,
 bool_field "ok" reply = Some true /\
 Remote.execute_remote Packet.execute_domain stop_first_wire JNull request
   (G.Cmd_stop stop_first_payload) value =
 (true,true,Decision
   (Remote.store
     (Remote.retain request reply (Remote.registry value))
     (put_task 0 (with_lifecycle (Stopped phase operations) task) value))
   reply []).
Proof.
 intros task phase operations value request issued Tasks Running
   Enabled Valid Granted Epoch Control Fresh Space.
 eexists; split; cycle 1.
 assert (Permissions : RemoteProofs.granted_permissions Remote.control_rights (F.grant_rights issued)).
 { unfold RemoteProofs.granted_permissions, Remote.control_rights; cbn.
   repeat split; intros; try discriminate; assumption. }
 pose proof (RemoteProofs.current_grant_admits_fresh_remote_request
   Remote.control_rights request (Remote.registry value) issued
   Enabled Valid Granted Epoch Permissions Fresh Space) as Admitted.
 assert (Checked : Remote.check Remote.control_rights (Remote.controller request)
   (Remote.epoch request) (Remote.registry value) = C.Accepted tt).
 { unfold Remote.authorize in Admitted.
   destruct (Remote.check Remote.control_rights (Remote.controller request)
     (Remote.epoch request) (Remote.registry value)) as [[]|reason]; try discriminate; reflexivity. }
 assert (Authorize : Remote.authorize_command (G.Cmd_stop stop_first_payload)
   request (Remote.registry value) = C.Accepted None).
 { exact Admitted. }
 assert (Configuration : Remote.configuration_allowed
   (G.Cmd_stop stop_first_payload) JNull = true) by reflexivity.
 unfold Remote.execute_remote. rewrite Configuration, Authorize.
 cbn [stop_first_wire Remote.observation_command Remote.required_rights].
 assert (Decoded : G.decode stop_first_wire = Some (G.Cmd_stop stop_first_payload)) by reflexivity.
 unfold G.decode in Decoded.
 destruct (G.admit stop_first_wire) as [admitted|] eqn:PreparedAdmitted; [|discriminate].
 change (Some (G.admitted_value admitted) = Some (G.Cmd_stop stop_first_payload)) in Decoded.
 injection Decoded as Projected. rewrite Projected.
 cbn [G.declared_command]. rewrite Configuration.
 cbn [Remote.with_command_rights Remote.required_rights]. rewrite Checked.
 assert (Prepared : Remote.prepared_world JNull value = Some value) by reflexivity.
 rewrite Prepared.
 cbn [Packet.execute_domain Packet.query CommandHandlers.query option_map
   CommandHandlers.interpret CommandHandlers.task_origin Selvedge.Kernel.Commands.origin_allowed
   G.handle_stop Selvedge.Generated.Commands.dispatch CommandHandlers.handlers].
 cbn [CommandHandlers.execute CommandHandlers.interpret CommandHandlers.task_origin option_map
   Selvedge.Kernel.Commands.origin_allowed G.handle_stop
   Selvedge.Generated.Commands.dispatch CommandHandlers.handlers].
 (* The selected reference carries evidence about this exact world. *)
 all: destruct value; cbn in Tasks; subst.
 all: destruct task; cbn in Running; subst.
 all: cbn [Selvedge.Kernel.CommandExecution.handle_stop Tasks.control_command
   TaskScope.select State.find_task registry_at TaskScope.selected TaskScope.owner
   Tasks.control_available Tasks.control_changes
   TaskChange.interpret TaskChange.target TaskChange.changes TaskChange.apply
   TaskChange.apply_edit TaskChange.ChangeStatus Tasks.control_effects].
 all: reflexivity.
Qed.
