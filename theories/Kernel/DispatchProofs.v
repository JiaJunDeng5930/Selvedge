From Stdlib Require Import List Bool NArith.
From Selvedge.Kernel Require Import Domain State Dispatch.
From Selvedge.Foundation Require Import Json RegistryProofs.
Import ListNotations.

(** Ordinary tasks and side conversations share the final context-capture
    operation. A later native result may extend either task before this
    decision is committed; no parent-membership premise is needed. *)
Theorem matching_uncommitted_context_captures_the_current_history :
 forall value owner ticket original current revision,
 find_task owner value = Some current ->
 task_activity current = ObservingContext ticket revision ->
 Dispatch.capture_request (ObserveContext owner ticket original) value =
   (put_task owner (Reasoning.capture ticket current) value,
    ObserveContext owner ticket (with_history (task_history current) original)).
Proof.
 intros value owner ticket original current revision Found Phase.
 unfold Dispatch.capture_request; now rewrite Found, Phase, N.eqb_refl.
Qed.

Theorem nonmatching_context_capture_keeps_the_original_request :
 forall value owner ticket original current,
 find_task owner value = Some current ->
 (forall revision, task_activity current <> ObservingContext ticket revision) ->
 Dispatch.capture_request (ObserveContext owner ticket original) value =
   (value,ObserveContext owner ticket original).
Proof.
 intros value owner ticket original current Found WrongPhase.
 unfold Dispatch.capture_request; rewrite Found.
 destruct (task_activity current) as
   [| | | expected revision | modelTicket callable mode
    | reasoningTicket length | calls | invocation pending remaining
    | hookTicket plugin invocation pending remaining] eqn:Phase; try reflexivity.
 destruct (N.eqb expected ticket) eqn:Matches; [|reflexivity].
 apply N.eqb_eq in Matches; subst expected.
 exfalso; apply (WrongPhase revision); reflexivity.
Qed.

Theorem a_prepared_context_read_has_the_committed_history_and_revision :
 forall value owner ticket original current revision,
 find_task owner value = Some current ->
 task_activity current = ObservingContext ticket revision ->
 let prepared := Dispatch.prepare value [ObserveContext owner ticket original] in
 exists committed snapshot,
   find_task owner (fst prepared) = Some committed /\
   snd prepared = [ObserveContext owner ticket snapshot] /\
   task_history snapshot = task_history committed /\
   task_activity committed = ObservingContext ticket (List.length (task_history committed)).
Proof.
 intros value owner ticket original current revision Found Phase.
 cbn zeta; unfold Dispatch.prepare; cbn [Dispatch.capture_requests].
 rewrite (matching_uncommitted_context_captures_the_current_history
   value owner ticket original current revision Found Phase).
 cbn [Dispatch.capture_requests fst snd].
 exists (Reasoning.capture ticket current), (with_history (task_history current) original).
 split.
 - unfold find_task, put_task, with_tasks; cbn.
   eapply registry_replace_selected; exact Found.
 - split; [reflexivity|].
   destruct current as [contract chosen settings lifecycle history queued lineage parent cursor consumed].
   destruct original as [original_contract original_chosen original_settings original_lifecycle original_history
     original_queued original_lineage original_parent original_cursor original_consumed].
   destruct lifecycle; cbn in Phase; try discriminate; split; reflexivity.
Qed.

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
