From Selvedge.Kernel Require Import TaskConstraints.
From Selvedge.Kernel Require Import TaskChangesProofs.
From Stdlib Require Import String List Bool NArith PeanoNat.
From Selvedge.Foundation Require Import Json JsonProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Dispatch
 TicketedRequest TicketedRequestProofs LifecycleProofs ForkConstructionProofs.
Import ListNotations.
Open Scope string_scope.

Theorem a_manual_fork_selects_children_without_reconfiguring_the_parent :
 forall origin owner count messages options before parent operations selected selection,
 find_task owner before = Some parent ->
 task_lifecycle parent = Running Idle operations ->
 TaskConstraints.fork_count_fits count (contract_max_fork (task_contract parent)) = true ->
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

Theorem an_issued_after_hook_survives_the_final_withdrawal :
 forall before (request : TicketedRequest.Scoped.plan before) original plugin pending result error,
 TicketedRequest.Scoped.intent request =
   TicketedRequest.Scoped.AfterOperation original plugin pending result error ->
 decision_effects (Dispatch.retain_live_effects (TicketedRequest.Scoped.issue request)) =
 [CheckResult (TaskScope.owner (TicketedRequest.Scoped.target request))
   (world_next_ticket before) (operation_id original) plugin (operation_call original) result error].
Proof.
 intros before request original plugin pending result error Intent.
 pose proof (TicketedRequest.Scoped.operation_observed before request) as Admitted.
 rewrite Intent in Admitted; cbn [TicketedRequest.Scoped.admitted_action] in Admitted.
 destruct Admitted as [Owned Stage].
 unfold TicketedRequest.Scoped.operation_at,RequestReceiver.operation_at in Owned.
 apply find_some in Owned as [Member _].
 pose proof (issued_task before request) as Installed.
 unfold TicketedRequest.Scoped.build in Installed; rewrite Intent in Installed; cbn [fst] in Installed.
 pose proof (issued_effects before request) as Effects.
 unfold TicketedRequest.Scoped.build in Effects; rewrite Intent in Effects; cbn [snd] in Effects.
 unfold Dispatch.retain_live_effects; rewrite Effects; cbn [filter].
 assert (Live : Dispatch.live_request (decision_world (TicketedRequest.Scoped.issue request))
   [CheckResult (TaskScope.owner (TicketedRequest.Scoped.target request))
     (world_next_ticket before) (operation_id original) plugin (operation_call original) result error]
   (CheckResult (TaskScope.owner (TicketedRequest.Scoped.target request))
     (world_next_ticket before) (operation_id original) plugin (operation_call original) result error) = true).
 { eapply a_retained_after_hook_survives_the_final_withdrawal.
   - exact Installed.
   - apply TaskChangeProofs.changing_stage_retains_the_selected_operation; exact Member.
   - reflexivity.
   - reflexivity. }
 now rewrite Live.
Qed.
