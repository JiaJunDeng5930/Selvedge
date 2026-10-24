From Stdlib Require Import List Bool NArith.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain State Tasks SideContext Scheduler.
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
 unfold Scheduler.publish_operations, Domain.with_operations.
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
 existsb (fun entry => let '(id, task) := entry in
   permitted id (SideContext.reconcile value) && Scheduler.task_has_work task)
   (Numbers.indexed (fun id task => (id, task)) 0 (world_tasks (SideContext.reconcile value))) = true ->
 Scheduler.schedule 0 execute permitted value effects =
   (SideContext.reconcile value, effects ++ [ContinueScheduling]).
Proof.
 intros execute permitted value effects Work.
 unfold Scheduler.schedule; rewrite Work; reflexivity.
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
 { unfold Tasks.promote; rewrite Pending.
   destruct (task_queued task) as [|first rest].
   - right; exact Pending.
   - left; apply lifecycle_after_with_lifecycle. }
 assert (PromotedOperations : task_operations (Tasks.promote task) = operations).
 { destruct Promoted as [Promoted|Promoted];
     unfold Domain.task_operations; rewrite Promoted; reflexivity. }
 assert (SomeWork : existsb Scheduler.process_needs_model
   (task_operations (Tasks.promote task)) = true).
 { rewrite PromotedOperations. apply existsb_exists; exists operation; split; assumption. }
 unfold Scheduler.continue_after_calls. rewrite SomeWork, Bool.orb_true_r.
 assert (NextPhase : task_lifecycle (Domain.with_activity WantsModel (Tasks.promote task)) =
   Running WantsModel operations).
 { unfold Domain.with_activity; destruct Promoted as [Promoted|Promoted];
     rewrite Promoted; apply lifecycle_after_with_lifecycle. }
 assert (NextOperations : task_operations (Domain.with_activity WantsModel (Tasks.promote task)) = operations).
 { unfold Domain.with_activity; destruct Promoted as [Promoted|Promoted];
     rewrite Promoted; apply operations_after_running_lifecycle. }
 rewrite NextPhase, NextOperations; split; [reflexivity|exact Member].
Qed.
