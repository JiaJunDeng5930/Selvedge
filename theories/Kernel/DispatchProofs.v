From Stdlib Require Import List Bool NArith.
From Selvedge.Kernel Require Import Domain State Dispatch.
Import ListNotations.

Theorem a_prepared_model_request_has_an_unarchived_owner :
 forall value effects id ticket model captured scope reserve,
 let '(committed,requests) := Dispatch.prepare value effects in
 In (RequestModel id ticket model captured scope reserve) requests ->
 exists owner, find_task id committed = Some owner /\ task_archived owner = false.
Proof.
 intros value effects id ticket model captured scope reserve.
 unfold Dispatch.prepare. destruct (Dispatch.capture_requests effects value) as [committed requests].
 intro Included. apply filter_In in Included as [_ Live].
 cbn [Dispatch.live_request Dispatch.request_coordinate] in Live.
 destruct (find_task id committed) as [owner|] eqn:Owned; [|discriminate].
 exists owner; split; [reflexivity|].
 unfold task_archived. destruct (task_lifecycle owner); try reflexivity; discriminate.
Qed.
Theorem a_prepared_result_callback_has_its_current_operation_right :
 forall value effects id ticket operation plugin invocation result error,
 let '(committed,requests) := Dispatch.prepare value effects in
 In (CheckResult id ticket operation plugin invocation result error) requests ->
 exists owner pending expected_plugin remaining original original_error,
 find_task id committed = Some owner /\ In pending (task_operations owner) /\
 operation_id pending = operation /\
 operation_stage pending = AwaitingAfterHook ticket expected_plugin remaining original original_error.
Proof.
 intros value effects id ticket operation plugin invocation result error.
 unfold Dispatch.prepare. destruct (Dispatch.capture_requests effects value) as [committed requests].
 intro Included. apply filter_In in Included as [_ Live].
 cbn [Dispatch.live_request Dispatch.request_coordinate] in Live.
 destruct (find_task id committed) as [owner|] eqn:Owned; [|discriminate].
 apply existsb_exists in Live as [pending [Member Checked]].
 apply andb_true_iff in Checked as [Identity Stage]. apply N.eqb_eq in Identity.
 destruct (operation_stage pending) as [execution|execution reviewer|reviewer|execution reviewer|chain original raw_error|expected expected_plugin remaining original original_error] eqn:Phase; try discriminate.
 apply N.eqb_eq in Stage; subst expected.
 exists owner,pending,expected_plugin,remaining,original,original_error; repeat split; try assumption; congruence.
Qed.

From Selvedge.Kernel Require Import Scheduler.
Theorem the_actual_scheduler_never_dispatches_a_model_for_an_archived_owner :
 forall execute permitted before id ticket model captured scope reserve,
 let result := Scheduler.run execute permitted before in
 In (RequestModel id ticket model captured scope reserve) (decision_effects result) ->
 exists owner, find_task id (decision_world result) = Some owner /\ task_archived owner = false.
Proof.
 intros execute permitted before id ticket model captured scope reserve.
 unfold Scheduler.run.
 destruct (Scheduler.schedule Limits.schedule_steps execute permitted
   (decision_world before) (decision_effects before)) as [value effects].
 pose proof (a_prepared_model_request_has_an_unarchived_owner value effects id ticket model captured scope reserve) as Safe.
 destruct (Dispatch.prepare value effects) as [committed requests]. exact Safe.
Qed.
