From Stdlib Require Import List Bool NArith.
From Selvedge.Kernel Require Import Domain State Dispatch.
From Selvedge.Foundation Require Import Json.
Import ListNotations.

Theorem a_retained_model_request_has_an_unarchived_owner :
 forall value effects request,
 let committed := value in
 let requests := decision_effects (Dispatch.retain_live_effects (Decision value (Json.JObject []) effects)) in
 In (RequestModel request) requests ->
 exists owner, find_task (ModelRequest.owner request) value = Some owner /\ task_archived owner = false.
Proof.
 intros value effects request.
 cbn [Dispatch.retain_live_effects decision_effects decision_world].
 intro Included. apply filter_In in Included as [_ Live].
 cbn [Dispatch.live_request Dispatch.request_coordinate] in Live.
 destruct (find_task (ModelRequest.owner request) value) as [owner|] eqn:Owned; [|discriminate].
 exists owner; split; [reflexivity|].
 unfold task_archived. destruct (task_lifecycle owner); try reflexivity; discriminate.
Qed.
Theorem a_retained_result_callback_has_its_current_operation_right :
 forall value effects id ticket operation plugin invocation result error,
 let committed := value in
 let requests := decision_effects (Dispatch.retain_live_effects (Decision value (Json.JObject []) effects)) in
 In (CheckResult id ticket operation plugin invocation result error) requests ->
 exists owner pending expected_plugin remaining original original_error,
 find_task id value = Some owner /\ In pending (task_operations owner) /\
 operation_id pending = operation /\
 operation_stage pending = AwaitingAfterHook ticket expected_plugin remaining original original_error.
Proof.
 intros value effects id ticket operation plugin invocation result error.
 cbn [Dispatch.retain_live_effects decision_effects decision_world].
 intro Included. apply filter_In in Included as [_ Live].
 cbn [Dispatch.live_request Dispatch.request_coordinate] in Live.
 destruct (find_task id value) as [owner|] eqn:Owned; [|discriminate].
 apply existsb_exists in Live as [pending [Member Checked]].
 apply andb_true_iff in Checked as [Identity Stage]. apply N.eqb_eq in Identity.
 destruct (operation_stage pending) as [execution|execution reviewer|reviewer|execution reviewer|chain original raw_error|expected expected_plugin remaining original original_error] eqn:Phase; try discriminate.
 apply N.eqb_eq in Stage; subst expected.
 exists owner,pending,expected_plugin,remaining,original,original_error; repeat split; try assumption; congruence.
Qed.
