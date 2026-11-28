From Stdlib Require Import String List Bool NArith.
From Selvedge.Kernel Require Import Domain Conversation TaskMonitoring TaskWake.
From Selvedge.Kernel Require Runnable.
From Selvedge.Programming Require Import TaskChange TaskResult.
Import ListNotations.

Theorem monitoring_preserves_actual_assistant_output source item delivered :
 monitored_message source item = Some delivered ->
 exists origin text phase, delivered = MonitoredOutput origin text /\
 assistant_output item = Some (origin,text) /\ origin_assistant_phase origin = Some phase /\
 origin_producer origin = source.
Proof.
 unfold monitored_message.
 destruct (assistant_output item) as [[origin text]|] eqn:Output; [|discriminate].
 destruct (origin_assistant_phase origin) as [phase|] eqn:Phase; [|discriminate].
 destruct (N.eqb source (origin_producer origin) && negb (String.eqb text ""%string)) eqn:Owned; [|discriminate].
 intro Delivered; inversion Delivered; subst.
 apply andb_true_iff in Owned as [Source _]. apply N.eqb_eq in Source.
 exists origin, text, phase. repeat split; auto.
Qed.

Theorem a_wait_cannot_suspend_with_unseen_input invocation remaining task :
 unseen_model_input task = true \/ task_queued task <> [] ->
 wait_for_input invocation remaining task = finish_wait invocation remaining.
Proof.
 intros [Unseen|Queued]; unfold wait_for_input, waiting_input_available.
 - now rewrite Unseen.
 - destruct (task_queued task); [contradiction|now rewrite Bool.orb_true_r].
Qed.

Theorem a_wait_without_input_has_no_main_action task invocation remaining operations :
 task_lifecycle task = Running (WaitingForInput invocation remaining) operations ->
 Runnable.ready_operation operations = None ->
 waiting_input_available task = false ->
 Runnable.task_action task = None.
Proof.
 intros Waiting Operations Input. unfold Runnable.task_action.
 now rewrite Waiting, Operations, Input.
Qed.

Theorem monitored_input_resumes_a_suspended_call invocation remaining task operations outputs :
 task_lifecycle task = Running (WaitingForInput invocation remaining) operations ->
 exists demand, TaskResult.result_changes (delivery_changes outputs task) task =
   [AppendHistory [wait_result invocation]; ChangePhase (PendingCalls remaining); AppendHistory outputs] ++ demand.
Proof.
 intro Waiting. unfold delivery_changes, TaskResult.result_changes, resume_for_input.
 now rewrite Waiting; eexists.
Qed.
