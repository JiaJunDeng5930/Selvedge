From Selvedge.Kernel Require Import TaskChangesProofs.
From Stdlib Require Import String List Bool NArith PeanoNat.
From Selvedge.Foundation Require Import Json JsonProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Dispatch
 TicketedRequest TicketedRequestProofs LifecycleProofs ForkConstructionProofs.
Import ListNotations.
Open Scope string_scope.

Lemma task_operations_after_replacement : forall operations task,
 task_operations (with_operations operations task) = operations.
Proof.
 intros operations [contract profile settings lifecycle history queued lineage parent cursor consumed].
 destruct lifecycle; reflexivity.
Qed.

Theorem a_manual_fork_selects_children_without_reconfiguring_the_parent :
 forall origin owner count messages options before parent operations selected selection,
 find_task owner before = Some parent ->
 task_lifecycle parent = Running Idle operations ->
 TaskConstraints.fork_count_valid count (contract_max_fork (task_contract parent)) = true ->
 TaskConstraints.fork_messages_valid count (List.length messages) = true ->
 Tasks.ancestors_fit (owner :: task_lineage parent) count before = true ->
 Tasks.resolve_settings (task_current_profile parent) options
   (Tasks.fork_settings_base origin parent before) before = Some selected ->
 Tasks.admit_fork_selection parent before selected = Some selection ->
 let decision := Tasks.fork_with_caller Tasks.ManualFork origin owner count messages options before in
 bool_default "ok" (decision_reply decision) false = true /\
 exists retained,
   find_task owner (decision_world decision) = Some retained /\
   task_contract retained = task_contract parent /\
   task_current_profile retained = task_current_profile parent /\
   task_current_settings retained = task_current_settings parent /\
   task_operations retained = operations.
Proof.
 intros origin owner count messages options before parent operations selected selection
   Found Running Count Messages Capacity Resolved Fixed.
 rewrite TaskChangesProofs.fork_with_caller_expression; cbv beta zeta; rewrite Found.
 unfold Tasks.fork_parent_ready; rewrite Running.
 cbn [andb]. rewrite Count, Messages, Capacity, Resolved, Fixed.
 unfold allocate_ticket. cbn [andb CommandResult.decide CommandResult.resolve CommandResult.accept
   CommandResult.change_value CommandResult.change_world CommandResult.change_effects
   decision_world decision_reply accept success bool_default field value_or_null].
 split; [reflexivity|]. eexists; split.
 - apply fork_children_preserve_every_existing_task.
   unfold find_task, put_task, with_tasks, with_ticket; cbv [set]; cbn.
   eapply RegistryProofs.registry_replace_selected; exact Found.
 - destruct parent as [contract profile settings lifecycle history queued lineage side cursor consumed].
   cbn in Running; subst lifecycle; repeat split; reflexivity.
Qed.

(* Settlement ownership is independent of the lifecycle that permits new
   execution. The final withdrawal point inspects the retained operation. *)
Theorem a_retained_after_hook_survives_the_final_withdrawal :
 forall owner ticket operation plugin plugins invocation result error value effects task pending,
 find_task owner value = Some task ->
 In pending (task_operations task) ->
 operation_id pending = operation ->
 operation_stage pending = AwaitingAfterHook ticket plugin plugins result error ->
 Dispatch.live_request value effects
   (CheckResult owner ticket operation plugin invocation result error) = true.
Proof.
 intros owner ticket operation plugin plugins invocation result error value effects task pending
   Found Member Owned Waiting.
 unfold Dispatch.live_request; rewrite Found.
 apply existsb_exists. exists pending; split; [exact Member|].
 unfold RequestReceiver.operation_receiver; rewrite Owned, Waiting, !N.eqb_refl; reflexivity.
Qed.

Lemma replacing_an_operation_installs_its_settlement :
 forall original plugin pending result error ticket operations,
 In original operations ->
 In (Operation (operation_id original) (operation_call original)
   (operation_announced original) (AwaitingAfterHook ticket plugin pending result error))
   (TicketedRequest.replace_operation
     (Operation (operation_id original) (operation_call original)
       (operation_announced original) (AwaitingAfterHook ticket plugin pending result error)) operations).
Proof.
 intros original plugin pending result error ticket operations Member.
 unfold TicketedRequest.replace_operation. apply in_map_iff.
 exists original; split; [cbn; rewrite N.eqb_refl; reflexivity|exact Member].
Qed.

Theorem an_issued_after_hook_survives_the_final_withdrawal :
 forall owner original plugin pending result error task before,
 find_task owner before = Some task ->
 In original (task_operations task) ->
 decision_effects (Dispatch.retain_live_effects
   (TicketedRequest.issue owner (TicketedRequest.After original plugin pending result error task) before)) =
 [CheckResult owner (world_next_ticket before) (operation_id original)
   plugin (operation_call original) result error].
Proof.
 intros owner original plugin pending result error task before Found Member.
 unfold Dispatch.retain_live_effects.
 rewrite (proj1 (an_issued_after_hook_keeps_the_operation_and_ticket
   owner original plugin pending result error task before)).
 cbn [filter].
 assert (Installed : find_task owner
   (decision_world (TicketedRequest.issue owner
     (TicketedRequest.After original plugin pending result error task) before)) =
   Some (with_operations (TicketedRequest.replace_operation
     (Operation (operation_id original) (operation_call original) (operation_announced original)
       (AwaitingAfterHook (world_next_ticket before) plugin pending result error))
     (task_operations task)) task)).
 { rewrite (proj2 (an_issued_after_hook_keeps_the_operation_and_ticket
     owner original plugin pending result error task before)).
   apply find_put_task with (before:=task); exact Found. }
 unfold Dispatch.live_request; rewrite Installed.
 assert (Live : existsb (fun operation =>
   N.eqb (operation_id original) (operation_id operation) &&
   match RequestReceiver.operation_receiver RequestReceiver.AfterReceiver operation with
   | Some (expected,_) => N.eqb (world_next_ticket before) expected
   | None => false end)
   (task_operations (with_operations (TicketedRequest.replace_operation
     (Operation (operation_id original) (operation_call original) (operation_announced original)
       (AwaitingAfterHook (world_next_ticket before) plugin pending result error))
     (task_operations task)) task)) = true).
 { rewrite task_operations_after_replacement.
   apply existsb_exists.
   exists (Operation (operation_id original) (operation_call original) (operation_announced original)
     (AwaitingAfterHook (world_next_ticket before) plugin pending result error)).
   split.
   - apply replacing_an_operation_installs_its_settlement; exact Member.
   - cbn; rewrite !N.eqb_refl; reflexivity. }
 rewrite Live; reflexivity.
Qed.
