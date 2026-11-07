From Selvedge.Kernel Require TaskWake.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Programming Require DecisionComposition TaskResult.
From Selvedge.Kernel Require Import Numbers Domain State Tasks SideContext Scheduler.
From Selvedge.Programming Require Import TaskChangeProofs.
From Selvedge.Kernel Require Import TicketedRequest ScopedRequestProofs.
From Selvedge.Kernel Require Import SchedulerChangesProofs TaskChangesProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Lemma runnable_selection_has_an_actual_step : forall execute permitted tasks first value,
 existsb (fun entry => let '(id,task) := entry in
   match Scheduler.next_runnable_step permitted id task value with Some _ => true | None => false end)
   (Selvedge.Foundation.Registry.indexed (fun id task => (id,task)) first tasks) =
 match Scheduler.find_step execute permitted first tasks value with Some _ => true | None => false end.
Proof.
 intros execute permitted tasks; induction tasks as [|task rest IH]; intros first value; [reflexivity|].
 cbn [Selvedge.Foundation.Registry.indexed existsb Scheduler.find_step].
 destruct (Scheduler.next_runnable_step permitted first task value); [reflexivity|].
 apply IH.
Qed.

Theorem continuation_tracks_available_work : forall execute permitted value,
 Scheduler.has_runnable_work permitted value =
 match Scheduler.find_step execute permitted 0 (world_tasks value) value with
 | Some _ => true | None => false end.
Proof. intros; apply runnable_selection_has_an_actual_step. Qed.

Theorem a_full_task_records_external_call_refusal :
 forall id before task tool invocation remaining authority,
 find_task id before = Some task ->
 TicketedRequest.Scoped.call_action task =
   Some (TicketedRequest.Scoped.StartCall tool invocation remaining authority) ->
 (Limits.operation_limit <= N.of_nat (List.length (task_operations task)))%N ->
 exists code reason,
 Scheduler.start_external id before =
 Callbacks.acknowledged (put_task id
   (with_activity (PendingCalls remaining)
     (append_history [FunctionOutput (call_id invocation) (State.failure code reason) true] task)) before).
Proof.
 intros id before task tool invocation remaining authority Found Selected Full.
 destruct (starting_selects_the_current_call id before task tool invocation remaining authority Found Selected)
   as [request [Started [Owner [Current Intent]]]].
 assert (NoRoom : N.ltb (N.of_nat (List.length (task_operations task))) Limits.operation_limit = false)
   by (apply N.ltb_ge; exact Full).
 unfold Scheduler.start_external; rewrite Started,Current,NoRoom.
 unfold Scheduler.call_error; rewrite (commit_changes_use_the_observed_owner id _ before task Found).
 do 2 eexists; reflexivity.
Qed.

Theorem a_full_task_refuses_native_result_work_before_execution :
 forall execute id definition invocation remaining task before,
 find_task id before = Some task ->
 Scheduler.call_admission definition invocation before = None ->
 (NativeTools.admit_command id invocation <> None \/ call_name invocation = "discover_tools") ->
 Callbacks.after_plugins task <> [] ->
 (Limits.operation_limit <= N.of_nat (List.length (task_operations task)))%N ->
 exists code reason,
 Scheduler.execute_checked_call execute id definition invocation remaining task before =
 Callbacks.acknowledged (put_task id
   (with_activity (PendingCalls remaining)
     (append_history [FunctionOutput (call_id invocation) (State.failure code reason) true] task)) before).
Proof.
 intros execute id definition invocation remaining task before Found Admitted Native Hooks Full.
 assert (NoRoom : Scheduler.internal_result_available task = false).
 { unfold Scheduler.internal_result_available.
   destruct (Callbacks.after_plugins task); [contradiction|].
   apply N.ltb_ge; exact Full. }
 unfold Scheduler.execute_checked_call; rewrite Admitted.
 destruct (NativeTools.admit_command id invocation) eqn:Command.
 - rewrite NoRoom.
   unfold Scheduler.call_error; rewrite (commit_changes_use_the_observed_owner id _ before task Found).
   do 2 eexists; reflexivity.
 - destruct Native as [Impossible|Name]; [contradiction|].
   rewrite Name,String.eqb_refl,NoRoom.
   unfold Scheduler.call_error; rewrite (commit_changes_use_the_observed_owner id _ before task Found).
   do 2 eexists; reflexivity.
Qed.

Theorem publishing_live_operations_only_marks_them_announced :
 forall task phase operations,
 task_lifecycle task = Running phase operations ->
 task_operations (TaskChange.apply (TicketedRequest.publication_changes task) task) = map TicketedRequest.announce_operation operations.
Proof.
 intros [contract profile settings lifecycle history queued lineage parent cursor consumed]
   phase operations RunningTask.
 cbn in RunningTask; subst lifecycle; reflexivity.
Qed.

Theorem operation_publication_preserves_its_completion_owner :
 forall task phase operations operation,
 task_lifecycle task = Running phase operations ->
 In operation operations ->
 exists published, In published (task_operations (TaskChange.apply (TicketedRequest.publication_changes task) task)) /\
   operation_id published = operation_id operation /\
   operation_call published = operation_call operation /\
   operation_stage published = operation_stage operation /\
   operation_announced published = true.
Proof.
 intros task phase operations operation RunningTask Member.
 rewrite (publishing_live_operations_only_marks_them_announced task phase operations RunningTask).
 exists (TicketedRequest.announce_operation operation); split.
 - apply in_map; exact Member.
 - unfold TicketedRequest.announce_operation; repeat split; reflexivity.
Qed.

Theorem exhausted_schedule_requests_another_step :
 forall advance execute permitted value effects accepted retained,
 existsb Scheduler.effect_requires_commit effects = false ->
 advance (SideContext.reconcile value) effects = Some (accepted,retained) ->
 Scheduler.has_runnable_work permitted accepted = true ->
 Scheduler.schedule_with advance 0 execute permitted value effects =
   (accepted,retained ++ [ContinueScheduling]).
Proof.
 intros advance execute permitted value effects accepted retained NoCommit Admitted Work.
 cbn [Scheduler.schedule_with]; rewrite NoCommit,Admitted.
 unfold Scheduler.continue_runnable; rewrite Work; reflexivity.
Qed.

Theorem a_required_commit_keeps_the_exact_scheduler_prefix :
 forall advance fuel execute permitted value effects,
 existsb Scheduler.effect_requires_commit effects = true ->
 Scheduler.schedule_with advance fuel execute permitted value effects =
   (value,Scheduler.continue_runnable permitted value effects).
Proof.
 intros advance fuel execute permitted value effects Commit.
 destruct fuel; cbn [Scheduler.schedule_with]; now rewrite Commit.
Qed.

Lemma frozen_inference_requires_commit : forall effects,
 existsb Scheduler.frozen_inference effects = true ->
 existsb Scheduler.effect_requires_commit effects = true.
Proof.
 intros effects Frozen.
 apply existsb_exists in Frozen as [request [Present Frozen]].
 apply existsb_exists; exists request; split; [exact Present|].
 destruct request; cbn [Scheduler.frozen_inference] in Frozen;
   try discriminate; reflexivity.
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
 apply a_required_commit_keeps_the_exact_scheduler_prefix.
 now apply frozen_inference_requires_commit.
Qed.

(* This equation covers public interruption and a cancellation emitted by any
   selected native command. No further reconciliation, advancement or task step
   runs; exactly one new continuation is appended iff work remains runnable. *)
Theorem task_cancellation_commits_before_further_scheduler_changes :
 forall advance fuel execute permitted value effects owner,
 In (CancelTask owner) effects ->
 Scheduler.schedule_with advance fuel execute permitted value effects =
   (value,if Scheduler.has_runnable_work permitted value
     then effects ++ [ContinueScheduling] else effects).
Proof.
 intros advance fuel execute permitted value effects owner Present.
 assert (Commit : existsb Scheduler.effect_requires_commit effects = true).
 { apply existsb_exists; exists (CancelTask owner); split; [exact Present|reflexivity]. }
 rewrite a_required_commit_keeps_the_exact_scheduler_prefix by exact Commit.
 reflexivity.
Qed.

Theorem an_admitted_task_cancellation_uses_the_dispatch_commit_boundary :
 forall advance execute permitted current owner,
 In (CancelTask owner) (decision_effects current) ->
 (DecisionComposition.transform (Scheduler.scheduling_with advance execute permitted) current) =
 let '(value,effects) := Dispatch.prepare (decision_world current)
   (Scheduler.continue_runnable permitted (decision_world current) (decision_effects current)) in
 Decision value (decision_reply current) effects.
Proof.
 intros advance execute permitted current owner Present.
 unfold DecisionComposition.transform,Scheduler.scheduling_with.
 rewrite task_cancellation_commits_before_further_scheduler_changes with (owner:=owner) by exact Present.
 unfold Scheduler.continue_runnable.
 destruct (Dispatch.prepare (decision_world current)
   (if Scheduler.has_runnable_work permitted (decision_world current)
    then decision_effects current ++ [ContinueScheduling] else decision_effects current)) as [value effects]; reflexivity.
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
 (DecisionComposition.transform (Scheduler.scheduling_with advance execute permitted) current) =
 let '(value,effects) := Dispatch.prepare (decision_world current)
   (Scheduler.continue_runnable permitted (decision_world current) (decision_effects current)) in
 Decision value (decision_reply current) effects.
Proof.
 intros advance execute permitted current Frozen.
 unfold DecisionComposition.transform,Scheduler.scheduling_with.
 rewrite frozen_inference_keeps_the_exact_world_and_existing_effects by exact Frozen.
 unfold Scheduler.continue_runnable.
 destruct (Dispatch.prepare (decision_world current)
   (if Scheduler.has_runnable_work permitted (decision_world current)
    then decision_effects current ++ [ContinueScheduling] else decision_effects current)) as [value effects]; reflexivity.
Qed.

Theorem a_refused_scheduler_step_keeps_the_complete_accepted_prefix :
 forall advance fuel execute permitted value effects accepted prior step,
 existsb Scheduler.effect_requires_commit effects = false ->
 advance (SideContext.reconcile value) effects = Some (accepted,prior) ->
 Scheduler.first_native_fork permitted 0 (world_tasks accepted) accepted = None ->
 Scheduler.find_step execute permitted 0 (world_tasks accepted) accepted = Some step ->
 advance (decision_world step) (prior ++ decision_effects step) = None ->
 Scheduler.schedule_with advance (S fuel) execute permitted value effects =
   (accepted,prior ++ [ContinueScheduling]).
Proof.
 intros advance fuel execute permitted value effects accepted prior step
   NoCommit Prefix NoFork Selected Refused.
 cbn [Scheduler.schedule_with].
 now rewrite NoCommit,Prefix,NoFork,Selected,Refused.
Qed.

Theorem unfinished_bash_keeps_its_completion_owner_across_inference :
 forall task operations operation,
 task_lifecycle task = Running (PendingCalls []) operations ->
 In operation operations ->
 Scheduler.process_needs_model operation = true ->
 task_lifecycle (TaskChange.apply (Scheduler.continue_after_calls_changes task) task) = Running WantsModel operations /\
 In operation (task_operations (TaskChange.apply (Scheduler.continue_after_calls_changes task) task)).
Proof.
 intros task operations operation Pending Member NeedsModel.
 assert (Promoted : task_lifecycle (TaskWake.promote task) = Running WantsModel operations \/
   task_lifecycle (TaskWake.promote task) = Running (PendingCalls []) operations).
 { unfold TaskWake.promote, TaskWake.promote_changes; rewrite Pending.
   destruct (task_queued task) as [|first rest].
   - right; exact Pending.
   - left; change (change_activity WantsModel (task_lifecycle task) = Running WantsModel operations).
     now rewrite Pending. }
 assert (PromotedOperations : task_operations (TaskWake.promote task) = operations).
 { destruct Promoted as [Promoted|Promoted];
     unfold Domain.task_operations; rewrite Promoted; reflexivity. }
 assert (SomeWork : existsb Scheduler.process_needs_model
   (task_operations (TaskWake.promote task)) = true).
 { rewrite PromotedOperations. apply existsb_exists; exists operation; split; assumption. }
 rewrite !continue_after_calls_expression; cbv zeta.
 rewrite SomeWork, Bool.orb_true_r.
 assert (NextPhase : task_lifecycle (Domain.with_activity WantsModel (TaskWake.promote task)) =
   Running WantsModel operations).
 { change (change_activity WantsModel (task_lifecycle (TaskWake.promote task)) = Running WantsModel operations).
   destruct Promoted as [Promoted|Promoted]; now rewrite Promoted. }
 assert (NextOperations : task_operations (Domain.with_activity WantsModel (TaskWake.promote task)) = operations).
 { unfold task_operations; now rewrite NextPhase. }
 rewrite NextPhase, NextOperations; split; [reflexivity|exact Member].
Qed.

Theorem a_blocked_environment_still_admits_archived_settlement :
 forall permitted owner task value operations pending,
 permitted owner value = false ->
 task_lifecycle task = Archived operations ->
 Scheduler.ready_settlement operations = Some pending ->
 Scheduler.next_runnable_step permitted owner task value = Some (Scheduler.OperationStep pending).
Proof.
 intros permitted owner task value operations pending Blocked ArchivedTask Pending.
 unfold Scheduler.next_runnable_step; rewrite Blocked.
 unfold task_operations; rewrite ArchivedTask, Pending; reflexivity.
Qed.
