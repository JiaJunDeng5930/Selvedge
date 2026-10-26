From Stdlib Require Import List Bool NArith.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain State Tasks SideContext Scheduler TicketedRequest ScopedRequestProofs TaskChangeProofs SchedulerChangesProofs TaskChangesProofs.
Import ListNotations.

Local Lemma lifecycle_after_with_lifecycle : forall state task,
 task_lifecycle (Domain.with_lifecycle state task) = state.
Proof.
 intros state task; unfold Domain.with_lifecycle.
 exact (@set_get Domain.task Domain.lifecycle task_lifecycle _ (fun _ => state) task).
Qed.

Local Lemma operations_after_running_lifecycle : forall phase operations task,
 task_operations (Domain.with_lifecycle (Running phase operations) task) = operations.
Proof.
 intros; unfold Domain.task_operations; rewrite lifecycle_after_with_lifecycle; reflexivity.
Qed.

Local Lemma lifecycle_after_history_append : forall messages task,
 task_lifecycle (Domain.append_history messages task) = task_lifecycle task.
Proof.
 intros messages [contract profile settings lifecycle history queued lineage parent cursor consumed].
 destruct lifecycle; reflexivity.
Qed.

Theorem publishing_live_operations_only_marks_them_announced :
 forall task phase operations,
 task_lifecycle task = Running phase operations ->
 task_operations (Scheduler.publish_operations task) = map Scheduler.announce_operation operations.
Proof.
 intros task phase operations RunningTask.
 unfold Scheduler.publish_operations, TicketedRequest.publish_operations, Domain.with_operations.
 rewrite lifecycle_after_history_append, RunningTask.
 rewrite operations_after_running_lifecycle.
 unfold Domain.task_operations; rewrite RunningTask; reflexivity.
Qed.

Theorem operation_publication_preserves_its_completion_owner :
 forall task phase operations operation,
 task_lifecycle task = Running phase operations ->
 In operation operations ->
 exists published, In published (task_operations (Scheduler.publish_operations task)) /\
   operation_id published = operation_id operation /\
   operation_call published = operation_call operation /\
   operation_stage published = operation_stage operation /\
   operation_announced published = true.
Proof.
 intros task phase operations operation RunningTask Member.
 rewrite (publishing_live_operations_only_marks_them_announced task phase operations RunningTask).
 exists (Scheduler.announce_operation operation); split.
 - apply in_map; exact Member.
 - unfold Scheduler.announce_operation; repeat split; reflexivity.
Qed.

Theorem exhausted_schedule_requests_another_step : forall execute permitted value effects,
 existsb Scheduler.frozen_inference effects = false ->
 existsb (fun entry => let '(id, task) := entry in
   match Scheduler.next_runnable_step permitted id task (SideContext.reconcile value) with Some _ => true | None => false end)
   (Selvedge.Foundation.Registry.indexed (fun id task => (id, task)) 0 (world_tasks (SideContext.reconcile value))) = true ->
 Scheduler.schedule 0 execute permitted value effects =
   (SideContext.reconcile value, effects ++ [ContinueScheduling]).
Proof.
 intros execute permitted value effects Unfrozen Work.
 cbn [Scheduler.schedule Scheduler.schedule_with Scheduler.unrestricted]; rewrite Unfrozen.
 unfold Scheduler.continue_runnable, Scheduler.has_runnable_work; rewrite Work; reflexivity.
Qed.

(** Model and evaluator selection are commit boundaries, not a callback that
    can be followed by more mutations in the same transaction. This statement
    constrains the scheduler used by Packet, for arbitrary other runnable work. *)
Theorem frozen_inference_keeps_the_exact_world_and_existing_effects :
 forall advance fuel execute permitted value effects,
 existsb Scheduler.frozen_inference effects = true ->
 Scheduler.schedule_with advance fuel execute permitted value effects =
   (value,Scheduler.continue_runnable permitted value effects).
Proof.
 intros advance fuel execute permitted value effects Frozen.
 destruct fuel; cbn [Scheduler.schedule_with]; now rewrite Frozen.
Qed.

Theorem a_pending_model_request_commits_before_further_scheduler_changes :
 forall advance fuel execute permitted value effects request,
 In (RequestModel request) effects ->
 fst (Scheduler.schedule_with advance fuel execute permitted value effects) = value /\
 In (RequestModel request) (snd (Scheduler.schedule_with advance fuel execute permitted value effects)).
Proof.
 intros advance fuel execute permitted value effects request Present.
 assert (Frozen : existsb Scheduler.frozen_inference effects = true).
 { apply existsb_exists; exists (RequestModel request); split; [exact Present|reflexivity]. }
 rewrite frozen_inference_keeps_the_exact_world_and_existing_effects by exact Frozen.
 cbn; split; [reflexivity|].
 unfold Scheduler.continue_runnable; destruct (Scheduler.has_runnable_work permitted value);
   [apply in_or_app; left; exact Present|exact Present].
Qed.

Theorem a_pending_evaluator_request_commits_before_further_scheduler_changes :
 forall advance fuel execute permitted value effects owner ticket snapshot,
 In (RequestReasoning owner ticket snapshot) effects ->
 fst (Scheduler.schedule_with advance fuel execute permitted value effects) = value /\
 In (RequestReasoning owner ticket snapshot)
   (snd (Scheduler.schedule_with advance fuel execute permitted value effects)).
Proof.
 intros advance fuel execute permitted value effects owner ticket snapshot Present.
 assert (Frozen : existsb Scheduler.frozen_inference effects = true).
 { apply existsb_exists; exists (RequestReasoning owner ticket snapshot); split; [exact Present|reflexivity]. }
 rewrite frozen_inference_keeps_the_exact_world_and_existing_effects by exact Frozen.
 cbn; split; [reflexivity|].
 unfold Scheduler.continue_runnable; destruct (Scheduler.has_runnable_work permitted value);
   [apply in_or_app; left; exact Present|exact Present].
Qed.

Theorem a_frozen_inference_preserves_the_continuation_for_other_work :
 forall advance fuel execute permitted value effects,
 existsb Scheduler.frozen_inference effects = true ->
 Scheduler.has_runnable_work permitted value = true ->
 Scheduler.schedule_with advance fuel execute permitted value effects = (value,effects ++ [ContinueScheduling]).
Proof.
 intros advance fuel execute permitted value effects Frozen Pending.
 rewrite frozen_inference_keeps_the_exact_world_and_existing_effects by exact Frozen.
 unfold Scheduler.continue_runnable; now rewrite Pending.
Qed.

Theorem an_admitted_frozen_request_uses_the_dispatch_commit_boundary :
 forall advance execute permitted current,
 existsb Scheduler.frozen_inference (decision_effects current) = true ->
 Scheduler.run_with advance execute permitted current =
 let '(value,effects) := Dispatch.prepare (decision_world current)
   (Scheduler.continue_runnable permitted (decision_world current) (decision_effects current)) in
 Decision value (decision_reply current) effects.
Proof.
 intros advance execute permitted current Frozen.
 unfold Scheduler.run_with.
 rewrite frozen_inference_keeps_the_exact_world_and_existing_effects by exact Frozen.
 reflexivity.
Qed.

Theorem a_refused_scheduler_step_keeps_the_complete_accepted_prefix :
 forall advance fuel execute permitted value effects accepted prior step,
 existsb Scheduler.frozen_inference effects = false ->
 advance (SideContext.reconcile value) effects = Some (accepted,prior) ->
 Scheduler.first_native_fork permitted 0 (world_tasks accepted) accepted = None ->
 Scheduler.find_step execute permitted 0 (world_tasks accepted) accepted = Some step ->
 advance (decision_world step) (prior ++ decision_effects step) = None ->
 Scheduler.schedule_with advance (S fuel) execute permitted value effects =
   (accepted,prior ++ [ContinueScheduling]).
Proof.
 intros advance fuel execute permitted value effects accepted prior step
   Unfrozen Prefix NoFork Selected Refused.
 cbn [Scheduler.schedule_with].
 now rewrite Unfrozen,Prefix,NoFork,Selected,Refused.
Qed.

Theorem unfinished_bash_keeps_its_completion_owner_across_inference :
 forall task operations operation,
 task_lifecycle task = Running (PendingCalls []) operations ->
 In operation operations ->
 Scheduler.process_needs_model operation = true ->
 task_lifecycle (Scheduler.continue_after_calls task) = Running WantsModel operations /\
 In operation (task_operations (Scheduler.continue_after_calls task)).
Proof.
 intros task operations operation Pending Member NeedsModel.
 assert (Promoted : task_lifecycle (Tasks.promote task) = Running WantsModel operations \/
   task_lifecycle (Tasks.promote task) = Running (PendingCalls []) operations).
 { rewrite promotion_expression, Pending.
   destruct (task_queued task) as [|first rest].
   - right; exact Pending.
   - left; apply lifecycle_after_with_lifecycle. }
 assert (PromotedOperations : task_operations (Tasks.promote task) = operations).
 { destruct Promoted as [Promoted|Promoted];
     unfold Domain.task_operations; rewrite Promoted; reflexivity. }
 assert (SomeWork : existsb Scheduler.process_needs_model
   (task_operations (Tasks.promote task)) = true).
 { rewrite PromotedOperations. apply existsb_exists; exists operation; split; assumption. }
 rewrite !continue_after_calls_expression; cbv zeta.
 rewrite SomeWork, Bool.orb_true_r.
 assert (NextPhase : task_lifecycle (Domain.with_activity WantsModel (Tasks.promote task)) =
   Running WantsModel operations).
 { unfold Domain.with_activity; destruct Promoted as [Promoted|Promoted];
     rewrite Promoted; apply lifecycle_after_with_lifecycle. }
 assert (NextOperations : task_operations (Domain.with_activity WantsModel (Tasks.promote task)) = operations).
 { unfold Domain.with_activity; destruct Promoted as [Promoted|Promoted];
     rewrite Promoted; apply operations_after_running_lifecycle. }
 rewrite NextPhase, NextOperations; split; [reflexivity|exact Member].
Qed.

Theorem a_blocked_environment_still_admits_archived_settlement :
 forall permitted owner task value operations pending,
 permitted owner value = false ->
 task_lifecycle task = Archived operations ->
 Scheduler.ready_settlement operations = Some pending ->
 Scheduler.next_runnable_step permitted owner task value = Some (Scheduler.SettlementStep pending).
Proof.
 intros permitted owner task value operations pending Blocked ArchivedTask Pending.
 unfold Scheduler.next_runnable_step; rewrite Blocked.
 unfold task_operations; rewrite ArchivedTask, Pending; reflexivity.
Qed.
Theorem archived_after_hook_dispatches_its_retained_result :
 forall owner task value operations pending plugin remaining result error,
 find_task owner value = Some task ->
 TicketedRequest.Scoped.operation_at (operation_id pending) task = Some pending ->
 task_lifecycle task = Archived operations ->
 operation_stage pending = AfterHooksReady (plugin :: remaining) result error ->
 Capabilities.hook_available Capabilities.AfterTool plugin
   (environment_plugins (world_environment value)) = true ->
 Scheduler.after_hooks_step owner pending task value =
 TicketedRequest.issue owner (TicketedRequest.After pending plugin remaining result error task) value.
Proof.
 intros owner task value operations pending plugin remaining result error Found Owned ArchivedTask Stage Available.
 unfold Scheduler.after_hooks_step; rewrite Stage, Available.
 now apply ScopedRequestProofs.after_uses_the_current_operation.
Qed.
