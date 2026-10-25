From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State Tasks Scheduler.
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
 task_lifecycle task = Stopped phase [] ->
 (phase = WantsModel \/ phase = ReadyForModel) ->
 exists result, Scheduler.task_step execute id task value = Some result /\
 decision_effects result = [] /\
 task_lifecycle (with_activity Idle (Tasks.promote task)) = Stopped Idle [].
Proof.
 intros execute id task phase value Lifecycle [Phase|Phase]; subst phase;
 (unfold Scheduler.task_step; rewrite Lifecycle; cbn [Scheduler.ready_settlement];
 eexists; split; [reflexivity|]; split; [reflexivity|];
 unfold Tasks.promote, with_activity; rewrite Lifecycle;
 destruct (task_queued task); rewrite Lifecycle; reflexivity).
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
 task_lifecycle task = Running WantsModel [] ->
 exists result,
 Scheduler.task_step execute id task value = Some result /\
 In (ObserveContext id (world_next_ticket value) (Scheduler.publish_operations (Tasks.promote task)))
   (decision_effects result) /\
 world_next_ticket (decision_world result) = N.succ (world_next_ticket value).
Proof.
 intros execute id task value Lifecycle.
 unfold Scheduler.task_step; rewrite Lifecycle; cbn [Scheduler.ready_operation].
 eexists; split; [reflexivity|]; split; [left; reflexivity|reflexivity].
Qed.
