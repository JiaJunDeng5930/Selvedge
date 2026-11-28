From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Programming Require CommandResult DecisionComposition TaskChange.
From Selvedge.Kernel Require OperationEvent.
From Selvedge.Foundation Require Import Json RegistryProofs.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Inputs.
From Selvedge.Programming Require Import TaskScope TaskChangeProofs.
From Selvedge.Kernel Require Import HistoryProofs NativeTools Scheduler NativeForkCommit NativeForkSchedulingProofs ForkCommit ForkCommitProofs.
From Selvedge.Features Require Import Runtime.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module G := Selvedge.Generated.Commands.

Lemma monitoring_a_new_child_keeps_fork_effects : forall before (accepted : NativeForkCommit.plan before) change,
 CommandResult.change_effects (NativeForkCommit.monitor_children accepted change) =
 CommandResult.change_effects change.
Proof.
 intros. unfold NativeForkCommit.monitor_children.
 destruct (G.fork_monitor (Scheduler.native_fork_request (NativeForkCommit.planned_step accepted))) as [[]|];
 reflexivity.
Qed.

Lemma settling_a_native_fork_keeps_its_effects owner invocation remaining before outcome :
 decision_effects (NativeForkCommit.settle_result owner invocation remaining before outcome) =
 decision_effects (CommandResult.decide before outcome).
Proof.
 unfold NativeForkCommit.settle_result, Scheduler.finish_call.
 destruct outcome; cbn zeta;
 match goal with |- context [find_task ?id ?value] => destruct (find_task id value) end;
 cbn [DecisionComposition.follow DecisionComposition.run DecisionComposition.transform DecisionComposition.maintain
   DecisionComposition.from_decision DecisionComposition.appended_effects Scheduler.internal_result
   Callbacks.acknowledged accept decision_effects snd];
 now rewrite ?app_nil_r.
Qed.

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
 unfold NativeForkCommit.candidate, NativeForkCommit.interpret.
 cbn [accept decision_effects]. rewrite settling_a_native_fork_keeps_its_effects.
 destruct (NativeForkCommit.business_result accepted) as [change|reason]; [|reflexivity].
 change (CommandResult.change_effects (NativeForkCommit.monitor_children accepted change) ++
   [ContinueScheduling] = [ContinueScheduling]).
 now rewrite monitoring_a_new_child_keeps_fork_effects, Empty.
Qed.

Lemma every_native_fork_plan_has_its_actual_final_dispatch_gate :
 forall before (accepted : NativeForkCommit.plan before),
 Scheduler.native_fork_ready (Scheduler.native_fork_owner (NativeForkCommit.planned_step accepted))
   (TaskScope.selected (NativeForkCommit.planned_target accepted)) before =
 Some (NativeForkCommit.planned_step accepted).
Proof.
 intros before accepted.
 destruct (the_world_native_fork_has_an_observed_ready_owner
   Runtime.can_schedule_task before (NativeForkCommit.planned_step accepted)
   (NativeForkCommit.planned_selection before accepted)) as [current [Found Ready]].
 pose proof (TaskScope.observed (NativeForkCommit.planned_target accepted)) as Selected.
 rewrite (NativeForkCommit.planned_owner before accepted) in Selected.
 rewrite Found in Selected; inversion Selected; subst current; exact Ready.
Qed.

Theorem a_native_fork_uses_its_calling_task : forall request owner invocation remaining before messages,
 Codec.traverse Images.message_content (message_sources request) = Some messages ->
 CommandExecution.handle_fork_result request (Some (Tasks.NativeCall owner invocation remaining)) before =
 Tasks.fork_result (Tasks.AcceptedNativeFork invocation remaining) (settings_origin request)
   owner (G.fork_child_count_admitted request) messages
   (option_map (settings_request_of_values true) (G.fork_settings_admitted request)) before.
Proof.
 intros request owner invocation remaining before messages Parsed.
 unfold CommandExecution.handle_fork_result; cbn zeta.
 match goal with |- match ?parsed with Some _ => _ | None => _ end = _ =>
   change (parsed = Some messages) in Parsed end.
 rewrite Parsed; reflexivity.
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
 cbn [CommandResult.map CommandResult.bind].
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
