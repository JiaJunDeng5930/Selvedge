From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json RegistryProofs.
From Selvedge.Kernel Require Import Numbers Domain State Tasks Scheduler Reasoning TicketedRequest ScopedRequestProofs SchedulerChangesProofs.
Import ListNotations.
Open Scope string_scope.

(* Freeze suspends new work while accepted result processing can finish. *)
Theorem frozen_tasks_without_ready_results_do_not_take_scheduler_steps :
 forall execute id task phase operations value,
 task_lifecycle task = Frozen phase operations ->
 Scheduler.ready_settlement operations = None ->
 Scheduler.task_step execute id task value = None.
Proof. intros; unfold Scheduler.task_step; rewrite H, H0; reflexivity. Qed.

(* Stop settles the current turn without issuing another inference request. *)
Theorem stopped_inference_requests_settle_without_effects :
 forall execute id task phase value,
 find_task id value = Some task ->
 task_lifecycle task = Stopped phase [] ->
 (phase = WantsModel \/ phase = ReadyForModel) ->
 exists result, Scheduler.task_step execute id task value = Some result /\
 decision_effects result = [] /\
 exists settled, find_task id (decision_world result) = Some settled /\
 task_lifecycle settled = Stopped Idle [].
Proof.
 intros execute id task phase value Owner Lifecycle [Phase|Phase]; subst phase;
 (unfold Scheduler.task_step; rewrite Lifecycle; cbn [Scheduler.ready_settlement];
 eexists; split; [reflexivity|]; split; [reflexivity|];
 exists (with_activity Idle task); split;
 [ cbn [decision_world Callbacks.acknowledged accept];
   rewrite (commit_changes_use_the_observed_owner id _ value task Owner);
   unfold Tasks.promote_changes; rewrite Lifecycle;
   change (find_task id (put_task id (with_activity Idle task) value) = Some (with_activity Idle task));
   unfold find_task, put_task, with_tasks; cbn;
   eapply registry_replace_selected; exact Owner
 | unfold with_activity; rewrite Lifecycle; reflexivity ]).
Qed.

Theorem stopped_tasks_can_finish_an_already_accepted_call :
 forall execute id task invocation remaining value,
 task_lifecycle task = Stopped (PendingCalls (invocation::remaining)) [] ->
 Scheduler.task_step execute id task value =
 Some (Scheduler.start_call execute id invocation remaining task value).
Proof. intros; unfold Scheduler.task_step; rewrite H; reflexivity. Qed.

(* A runnable task actually issues context observation. This positive obligation
   excludes a scheduler that preserves safety by never doing any work. *)
Theorem a_runnable_task_requests_context_before_inference :
 forall execute id task value,
 find_task id value = Some task ->
 TicketedRequest.Scoped.can_observe true task value = true ->
 task_lifecycle task = Running WantsModel [] ->
 exists result,
 Scheduler.task_step execute id task value = Some result /\
 In (ObserveContext id (world_next_ticket value) (Scheduler.publish_operations (Tasks.promote task)))
   (decision_effects result) /\
 world_next_ticket (decision_world result) = N.succ (world_next_ticket value).
Proof.
 intros execute id task value Found ObserveAllowed Lifecycle.
 unfold Scheduler.task_step; rewrite Lifecycle; cbn [Scheduler.ready_operation].
 eexists; split; [reflexivity|]. unfold Reasoning.observe_scheduled_context.
 rewrite (ScopedRequestProofs.observing_uses_the_current_task id value task true Found ObserveAllowed).
 split; [left; reflexivity|reflexivity].
Qed.
