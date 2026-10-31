From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json RegistryProofs.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Inputs TaskScope TaskScopeProofs
 TaskChangeProofs HistoryProofs NativeTools Scheduler NativeForkCommit NativeForkSchedulingProofs
 ForkCommit ForkCommitProofs.
From Selvedge.Features Require Import Runtime.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module G := Selvedge.Generated.Commands.

Theorem a_native_fork_transaction_acknowledges_its_delivery :
 forall before (accepted : NativeForkCommit.plan before),
 decision_reply (NativeForkCommit.candidate accepted) = success JNull /\
 decision_effects (NativeForkCommit.candidate accepted) = [ContinueScheduling].
Proof.
 intros before accepted; split; [reflexivity|].
 assert (Empty : match NativeForkCommit.business_result accepted with
   | CommandResult.Accepted change => CommandResult.change_effects change = []
   | CommandResult.Rejected _ => True end).
 { unfold NativeForkCommit.business_result; apply fork_command_has_no_external_effects. }
 unfold NativeForkCommit.candidate, NativeForkCommit.interpret, NativeForkCommit.settle_result.
 destruct (NativeForkCommit.business_result accepted) as [[value next effects]|reason];
   cbn in Empty; try subst effects;
   unfold Scheduler.finish_call;
   cbn [CommandResult.decide CommandResult.resolve CommandResult.accept CommandResult.reject
     CommandResult.change_world CommandResult.change_value CommandResult.change_effects
     decision_world accept reject].
 all: destruct (find_task _ _); reflexivity.
Qed.

Lemma every_native_fork_plan_has_its_actual_final_dispatch_gate :
 forall before (accepted : NativeForkCommit.plan before),
 Scheduler.native_fork_ready (Scheduler.native_fork_owner (NativeForkCommit.planned_step accepted))
   (TaskScope.selected (NativeForkCommit.planned_target accepted)) before =
 Some (NativeForkCommit.planned_step accepted).
Proof.
 intros before accepted.
 destruct (the_selected_native_fork_has_an_observed_ready_owner
   Runtime.can_schedule_task (world_tasks before) before 0 (NativeForkCommit.planned_step accepted)
   (NativeForkCommit.planned_selection before accepted)) as [offset [current [Found [Owner Ready]]]].
 rewrite N.add_0_l in Owner.
 pose proof (TaskScope.observed (NativeForkCommit.planned_target accepted)) as Selected.
 rewrite (NativeForkCommit.planned_owner before accepted) in Selected.
 assert (Observed : find_task (Scheduler.native_fork_owner (NativeForkCommit.planned_step accepted)) before = Some current).
 { unfold find_task; rewrite Owner; exact Found. }
 rewrite Observed in Selected; inversion Selected; subst current; exact Ready.
Qed.

Lemma a_native_fork_request_names_its_selected_owner : forall before (accepted : NativeForkCommit.plan before),
 G.fork_task_id (Scheduler.native_fork_request (NativeForkCommit.planned_step accepted)) =
 Scheduler.native_fork_owner (NativeForkCommit.planned_step accepted).
Proof.
 intros; pose proof (every_native_fork_plan_has_its_actual_final_dispatch_gate before accepted) as Ready.
 destruct (a_ready_native_fork_carries_its_final_dispatch_gate _ _ _ _ Ready) as [_ [_ [_ [_ Owner]]]]; exact Owner.
Qed.

Lemma exhausted_descendant_capacity_refuses_the_actual_native_fork_handler :
 forall request invocation remaining messages before parent,
 Codec.traverse Images.message_content (message_sources request) = Some messages ->
 find_task (G.fork_task_id request) before = Some parent ->
 Tasks.ancestors_fit (G.fork_task_id request :: task_lineage parent)
   (G.fork_child_count request) before = false ->
 CommandExecution.handle_fork_result request
   (Some (Tasks.NativeCall (G.fork_task_id request) invocation remaining)) before =
 CommandResult.Rejected (Tasks.start_refusal Tasks.NativeForkEntry Tasks.DescendantCapacity).
Proof.
 intros request invocation remaining messages before parent Parsed Found Capacity.
 change (Tasks.ancestors_fit (@cons N (G.fork_task_id request) (task_lineage parent))
   (TaskConstraints.fork_count_value (G.fork_child_count_admitted request)) before = false) in Capacity.
 unfold CommandExecution.handle_fork_result.
 match goal with |- match ?parsed with Some _ => _ | None => _ end = _ =>
   change (parsed = Some messages) in Parsed end; rewrite Parsed.
 cbn [Tasks.native_owner Tasks.native_invocation Tasks.native_remaining].
 rewrite N.eqb_refl; unfold Tasks.fork_result.
 destruct (TaskScopeProofs.selecting_an_existing_task_retains_its_key _ _ _ Found)
   as [target [Selected [_ Current]]].
 rewrite Selected; cbn beta iota zeta; rewrite Current,Capacity,andb_false_r.
 unfold Tasks.fork_refusal_reason; rewrite Capacity; reflexivity.
Qed.


Theorem a_refused_native_call_records_its_error_and_releases_its_continuation :
 forall before (accepted : NativeForkCommit.plan before) code reason,
 NativeForkCommit.business_result accepted = CommandResult.Rejected (CommandResult.Refusal code reason) ->
 let step := NativeForkCommit.planned_step accepted in
 let original := TaskScope.selected (NativeForkCommit.planned_target accepted) in
 exists settled,
 find_task (Scheduler.native_fork_owner step) (decision_world (NativeForkCommit.candidate accepted)) = Some settled /\
 task_history settled = task_history original ++
   match OperationEvent.after_plugins original with
   | [] => [FunctionOutput (call_id (Scheduler.native_fork_invocation step)) (failure code reason) true]
   | _ => [ToolReceipt (Scheduler.native_fork_owner step) (world_next_ticket before)
       (Scheduler.native_fork_invocation step) (failure code reason) true] end /\
 decision_reply (NativeForkCommit.candidate accepted) = success JNull /\
 decision_effects (NativeForkCommit.candidate accepted) = [ContinueScheduling].
Proof.
 intros before accepted code reason Refused step original.
 pose proof (TaskScope.observed (NativeForkCommit.planned_target accepted)) as Found.
 rewrite (NativeForkCommit.planned_owner before accepted) in Found; fold step original in Found.
 assert (Started : exists current,
   find_task (Scheduler.native_fork_owner step) (NativeForkCommit.started_world accepted) = Some current /\
   task_history current = task_history original /\
   OperationEvent.after_plugins current = OperationEvent.after_plugins original).
 { unfold NativeForkCommit.started_world; fold step.
   eexists; split.
   - unfold step; rewrite <- (NativeForkCommit.planned_owner before accepted).
     exact (a_field_plan_installs_its_exact_interpretation before
       (TaskChange.Plan before (NativeForkCommit.planned_target accepted)
         [TaskChange.ChangePhase (PendingCalls
           (Scheduler.native_fork_remaining (NativeForkCommit.planned_step accepted)))])).
   - split; reflexivity. }
 destruct Started as [current [Started [History Plugins]]].
 unfold NativeForkCommit.candidate, NativeForkCommit.interpret, NativeForkCommit.settle_result.
 fold step; rewrite Refused.
 cbn [CommandResult.decide CommandResult.resolve CommandResult.reject CommandResult.refusal_code
   CommandResult.refusal_message reject decision_world decision_effects].
 unfold Scheduler.finish_call, CommandResult.reject.
 cbn [reject decision_world CommandResult.refusal_code CommandResult.refusal_message]; rewrite Started.
 cbn [DecisionComposition.follow Scheduler.internal_result Callbacks.acknowledged
   accept decision_world decision_effects decision_reply app].
 eexists; split.
 - apply LifecycleProofs.find_put_task with (before:=current).
   destruct (Callbacks.after_plugins current); exact Started.
 - split; [|split; reflexivity].
   rewrite native_results_append_their_completed_observation, History, Plugins.
   reflexivity.
Qed.
