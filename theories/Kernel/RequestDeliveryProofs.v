From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State StateProofs TaskScope TaskChange TaskChangeProofs
 Dispatch Scheduler Delivery DeferredCommit Inputs Packet RequestDelivery
 CallbackChangesProofs CallbacksProofs LifecycleProofs TaskWakeProofs HookRules.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Theorem a_transport_refusal_retains_the_complete_task_history : forall current,
 let next := TaskChange.apply RequestDelivery.refusal_changes current in
 task_history next = task_history current ++ [FailureMessage RequestDelivery.failure_message] /\
 task_operations next = task_operations current /\
 task_queued next = task_queued current /\
 task_contract next = task_contract current /\
 task_current_profile next = task_current_profile current /\
 task_current_settings next = task_current_settings current.
Proof.
 intros [contract profile settings lifecycle history queued lineage parent cursor consumed].
 destruct lifecycle; repeat split; reflexivity.
Qed.

Theorem a_running_transport_refusal_retires_inference_demand : forall current phase operations,
 task_lifecycle current = Running phase operations ->
 task_lifecycle (TaskChange.apply RequestDelivery.refusal_changes current) = Running Idle operations.
Proof.
 intros [contract profile settings lifecycle history queued lineage parent cursor consumed]
   phase operations Current.
 cbn in Current; subst lifecycle; reflexivity.
Qed.

Theorem refusing_a_current_request_changes_only_its_owned_task :
 forall result request owner ticket (target : TaskScope.task_reference (decision_world result)) other,
 RequestDelivery.inference_coordinate request = Some (owner,ticket) ->
 TaskScope.select owner (decision_world result) = Some target ->
 RequestDelivery.owns_inference request (TaskScope.selected target) = true ->
 TaskScope.owner target <> other ->
 find_task other (decision_world (RequestDelivery.refuse request result)) =
   find_task other (decision_world result).
Proof.
 intros result request owner ticket target other Coordinate Selected Owned Other.
 unfold RequestDelivery.refuse; rewrite Coordinate, Selected, Owned; cbn [decision_world].
 apply a_field_plan_preserves_every_other_task; exact Other.
Qed.

Theorem refusing_a_current_request_installs_the_exact_history_preserving_changes :
 forall result request owner ticket (target : TaskScope.task_reference (decision_world result)),
 RequestDelivery.inference_coordinate request = Some (owner,ticket) ->
 TaskScope.select owner (decision_world result) = Some target ->
 RequestDelivery.owns_inference request (TaskScope.selected target) = true ->
 find_task (TaskScope.owner target) (decision_world (RequestDelivery.refuse request result)) =
   Some (TaskChange.apply RequestDelivery.refusal_changes (TaskScope.selected target)).
Proof.
 intros result request owner ticket target Coordinate Selected Owned.
 unfold RequestDelivery.refuse; rewrite Coordinate, Selected, Owned; cbn [decision_world].
 exact (a_field_plan_installs_its_exact_interpretation (decision_world result)
   (TaskChange.Plan (decision_world result) target RequestDelivery.refusal_changes)).
Qed.

Theorem a_refused_request_cannot_still_be_emitted :
 forall result request owner ticket (target : TaskScope.task_reference (decision_world result)),
 RequestDelivery.inference_coordinate request = Some (owner,ticket) ->
 TaskScope.select owner (decision_world result) = Some target ->
 RequestDelivery.owns_inference request (TaskScope.selected target) = true ->
 ~ In request (decision_effects (RequestDelivery.refuse request result)).
Proof.
 intros result request owner ticket target Coordinate Selected Owned.
 unfold RequestDelivery.refuse; rewrite Coordinate, Selected, Owned; cbn [decision_effects].
 intro Present; apply filter_In in Present; destruct Present as [_ Accepted].
 unfold RequestDelivery.same_inference in Accepted; rewrite Coordinate, !N.eqb_refl in Accepted.
 discriminate.
Qed.

Theorem request_refusal_preserves_the_original_business_reply : forall request result,
 decision_reply (RequestDelivery.refuse request result) = decision_reply result.
Proof.
 intros request result; unfold RequestDelivery.refuse.
 destruct (RequestDelivery.inference_coordinate request) as [[owner ticket]|]; [|reflexivity].
 destruct (TaskScope.select owner (decision_world result)) as [target|]; [|reflexivity].
 destruct (RequestDelivery.owns_inference request (TaskScope.selected target)); reflexivity.
Qed.

Theorem after_request_refusal_preserves_the_original_business_reply : forall request result,
 decision_reply (RequestDelivery.refuse_after request result) = decision_reply result.
Proof. intros request result; destruct request; reflexivity. Qed.

Theorem the_shared_after_budget_failure_emits_no_additional_effect :
 forall owner identity ticket value,
 decision_effects (HookCallbacks.after_completed owner identity ticket
   (AfterFailure RequestDelivery.after_failure_message) value) = [].
Proof.
 intros; rewrite after_completed_expression.
 destruct (find_task owner value) as [task|]; [|reflexivity].
 destruct (find (fun pending => N.eqb identity (operation_id pending))
   (task_operations task)) as [operation|]; [|reflexivity].
 destruct (operation_stage operation) as
   [executing|elevated reviewer|reviewer|approved reviewer|pending result error|expected plugin pending result error];
   try reflexivity.
 destruct (N.eqb expected ticket); reflexivity.
Qed.

Theorem a_refused_after_request_cannot_still_be_emitted :
 forall current owner ticket identity plugin invocation result error,
 let request := CheckResult owner ticket identity plugin invocation result error in
 ~ In request (decision_effects (RequestDelivery.refuse_after request current)).
Proof.
 intros current owner ticket identity plugin invocation result error; cbv zeta.
 cbn [RequestDelivery.refuse_after decision_effects].
 intro Present; apply filter_In in Present; destruct Present as [_ Accepted].
 cbn [RequestDelivery.same_after] in Accepted.
 rewrite !N.eqb_refl in Accepted; discriminate.
Qed.

Lemma after_request_refusal_introduces_no_effect : forall request current emitted,
 In emitted (decision_effects (RequestDelivery.refuse_after request current)) ->
 In emitted (decision_effects current).
Proof.
 intros request current emitted Present; destruct request;
   cbn [RequestDelivery.refuse_after decision_effects] in Present; try exact Present.
 apply filter_In in Present; exact (proj1 Present).
Qed.

Lemma after_request_refusal_fold_keeps_absent_effects_absent : forall requests current request,
 ~ In request (decision_effects current) ->
 ~ In request (decision_effects
   (fold_left (fun result request => RequestDelivery.refuse_after request result) requests current)).
Proof.
 induction requests as [|first rest IH]; intros current request Absent; [exact Absent|].
 cbn [fold_left]; apply IH.
 intro Present; apply Absent.
 eapply after_request_refusal_introduces_no_effect; exact Present.
Qed.

Lemma after_request_refusal_fold_retires_each_selected_request :
 forall requests current owner ticket identity plugin invocation result error,
 let request := CheckResult owner ticket identity plugin invocation result error in
 In request requests ->
 ~ In request (decision_effects
   (fold_left (fun result request => RequestDelivery.refuse_after request result) requests current)).
Proof.
 induction requests as [|first rest IH]; intros current owner ticket identity plugin invocation result error;
   cbv zeta; intro Member; [contradiction|].
 cbn [fold_left]; destruct Member as [Same|Later].
 - subst first; apply after_request_refusal_fold_keeps_absent_effects_absent.
   apply a_refused_after_request_cannot_still_be_emitted.
 - apply IH; exact Later.
Qed.

Theorem normalization_retires_every_individually_oversized_after_request :
 forall current owner ticket identity plugin invocation result error,
 let request := CheckResult owner ticket identity plugin invocation result error in
 let encoded := Selvedge.Features.Runtime.finish (RequestDelivery.capture current) in
 In request (decision_effects encoded) ->
 RequestDelivery.request_fits (decision_world encoded) request = false ->
 ~ In request (decision_effects (RequestDelivery.normalize current)).
Proof.
 intros current owner ticket identity plugin invocation result error; cbv zeta.
 intros Present Oversized; unfold RequestDelivery.normalize.
 apply after_request_refusal_fold_retires_each_selected_request.
 apply filter_In; split; [exact Present|].
 cbn [RequestDelivery.oversized_after]; rewrite Oversized; reflexivity.
Qed.

Theorem an_after_budget_refusal_uses_the_owned_failure_settlement :
 forall current owner ticket identity plugin invocation result error task operation pending,
 find_task owner (decision_world current) = Some task ->
 find (fun operation => N.eqb identity (operation_id operation)) (task_operations task) = Some operation ->
 operation_stage operation = AwaitingAfterHook ticket plugin pending result error ->
 decision_world (RequestDelivery.refuse_after
   (CheckResult owner ticket identity plugin invocation result error) current) =
 Tasks.apply_result owner task
   (HookCallbacks.after_result_plan owner operation plugin pending result error
     (AfterFailure RequestDelivery.after_failure_message)) (decision_world current).
Proof.
 intros current owner ticket identity plugin invocation result error task operation pending Found Owned Waiting.
 unfold RequestDelivery.refuse_after.
 rewrite after_completed_expression, Found, Owned, Waiting, N.eqb_refl.
 reflexivity.
Qed.

Theorem an_after_budget_refusal_keeps_raw_evidence_and_retires_the_operation :
 forall current owner ticket identity plugin invocation result error task operation pending,
 find_task owner (decision_world current) = Some task ->
 find (fun operation => N.eqb identity (operation_id operation)) (task_operations task) = Some operation ->
 operation_stage operation = AwaitingAfterHook ticket plugin pending result error ->
 let refused := RequestDelivery.refuse_after
   (CheckResult owner ticket identity plugin invocation result error) current in
 exists updated released,
 find_task owner (decision_world refused) = Some updated /\
 task_operations updated = Callbacks.remove_operation (operation_id operation) (task_operations task) /\
 task_history updated = task_history task ++
   [AfterReceipt owner (operation_id operation) plugin
     (Inputs.after_json (AfterFailure RequestDelivery.after_failure_message))] ++
   [History.operation_result operation
     (State.failure "after_hook_failed" RequestDelivery.after_failure_message) true] ++
   map UserMessage released /\
 (released = [] \/ released = task_queued task).
Proof.
 intros current owner ticket identity plugin invocation result error task operation pending Found Owned Waiting.
 cbv zeta.
 rewrite an_after_budget_refusal_uses_the_owned_failure_settlement with
   (task:=task) (operation:=operation) (pending:=pending); try assumption.
 unfold HookCallbacks.after_result_plan,HookCallbacks.after_result_plan_for; cbn [HookRules.after_apply].
 change (Tasks.apply_result owner task
   (Tasks.prefix_result [TaskChange.AppendHistory
     [AfterReceipt owner (operation_id operation) plugin
       (Inputs.after_json (AfterFailure RequestDelivery.after_failure_message))]]
     (Callbacks.settle_operation_plan operation
       (State.failure "after_hook_failed" RequestDelivery.after_failure_message) true))
   (decision_world current)) with
   (Tasks.mark_context_wake owner task (put_task owner
     (Callbacks.settle_operation operation
       (State.failure "after_hook_failed" RequestDelivery.after_failure_message) true
       (append_history [AfterReceipt owner (operation_id operation) plugin
         (Inputs.after_json (AfterFailure RequestDelivery.after_failure_message))] task))
     (decision_world current))).
 rewrite context_wake_preserves_every_task_lookup, settle_operation_expression.
 set (settled := with_operations
   (Callbacks.remove_operation (operation_id operation) (task_operations task))
   (append_history [History.operation_result operation
     (State.failure "after_hook_failed" RequestDelivery.after_failure_message) true]
     (append_history [AfterReceipt owner (operation_id operation) plugin
       (Inputs.after_json (AfterFailure RequestDelivery.after_failure_message))] task))).
 pose proof (waking_a_result_preserves_operations_and_only_releases_queued_input settled)
   as [Operations [released [History Released]]].
 exists (Tasks.wake_after_result settled), released; split.
 - apply find_put_task with task; exact Found.
 - unfold settled in *.
   destruct task as [contract profile settings lifecycle history queued lineage parent cursor consumed].
   destruct lifecycle;
   cbn [task_operations task_history task_queued with_operations append_history
     with_lifecycle with_history] in Operations, History, Released |- *;
   rewrite Operations, History; repeat split; try assumption; try reflexivity;
   cbn; rewrite <- !app_assoc; reflexivity.
Qed.

Theorem a_stale_after_budget_refusal_cannot_change_the_current_operation :
 forall current owner ticket expected identity plugin invocation result error task operation pending,
 find_task owner (decision_world current) = Some task ->
 find (fun operation => N.eqb identity (operation_id operation)) (task_operations task) = Some operation ->
 operation_stage operation = AwaitingAfterHook expected plugin pending result error ->
 ticket <> expected ->
 decision_world (RequestDelivery.refuse_after
   (CheckResult owner ticket identity plugin invocation result error) current) = decision_world current.
Proof.
 intros current owner ticket expected identity plugin invocation result error task operation pending Found Owned Waiting Stale.
 unfold RequestDelivery.refuse_after.
 rewrite after_completed_expression, Found, Owned, Waiting.
 assert (Mismatch : N.eqb expected ticket = false) by (apply N.eqb_neq; congruence).
 rewrite Mismatch; reflexivity.
Qed.

Theorem normalized_delivery_preserves_reply : forall current,
 decision_reply (RequestDelivery.normalize current) = decision_reply current.
Proof.
 intro current; unfold RequestDelivery.normalize.
 rewrite reply_preserving_fold by (intros; apply after_request_refusal_preserves_the_original_business_reply).
 rewrite reply_preserving_fold by (intros; apply request_refusal_preserves_the_original_business_reply).
 unfold RequestDelivery.capture; destruct (Dispatch.prepare _ _); reflexivity.
Qed.

Theorem scheduling_retains_the_operation_reply : forall advance execute permitted current,
 decision_reply (Scheduler.run_with advance execute permitted current) = decision_reply current.
Proof.
 intros; unfold Scheduler.run_with.
 destruct (Scheduler.schedule_with _ _ _ _ _ _); destruct (Dispatch.prepare _ _); reflexivity.
Qed.

Theorem finishing_retains_the_operation_reply : forall current,
 decision_reply (Selvedge.Features.Runtime.finish current) = decision_reply current.
Proof.
 intros; unfold Selvedge.Features.Runtime.finish, TitleCommit.enqueue.
 destruct (TitleCommit.resolve _); reflexivity.
Qed.

Lemma deferred_continuation_preserves_reply : forall current,
 decision_reply (DeferredCommit.continue current) = decision_reply current.
Proof.
 intros; unfold DeferredCommit.continue.
 destruct (Codec.bool_default "ok" (decision_reply current) false); reflexivity.
Qed.

Theorem bounded_scheduling_preserves_reply : forall execute permitted current,
 decision_reply (RequestDelivery.run execute permitted current) = decision_reply current.
Proof.
 intros execute permitted current; unfold RequestDelivery.run; cbv beta zeta.
 destruct (RequestDelivery.advance (decision_reply (RequestDelivery.normalize current))
   (decision_world (RequestDelivery.normalize current))
   (decision_effects (RequestDelivery.normalize current))) as [[next emitted]|].
 - unfold RequestDelivery.finish; rewrite finishing_retains_the_operation_reply,
     scheduling_retains_the_operation_reply; cbn [decision_reply].
   apply normalized_delivery_preserves_reply.
 - unfold RequestDelivery.finish; rewrite finishing_retains_the_operation_reply,
     deferred_continuation_preserves_reply.
   apply normalized_delivery_preserves_reply.
Qed.

Theorem deferred_delivery_preserves_reply : forall current,
 decision_reply (RequestDelivery.defer current) = decision_reply current.
Proof.
 intro current; unfold RequestDelivery.defer, RequestDelivery.finish.
 rewrite finishing_retains_the_operation_reply, deferred_continuation_preserves_reply.
 apply normalized_delivery_preserves_reply.
Qed.

Theorem budget_admission_checks_the_final_envelope_and_its_continuation :
 forall reply value effects next emitted,
 RequestDelivery.advance reply value effects = Some (next,emitted) ->
 Delivery.fits true (RequestDelivery.finish (Decision next reply emitted)) = true /\
 Delivery.fits true (RequestDelivery.finish
   (RequestDelivery.continuing (Decision next reply emitted))) = true.
Proof.
 intros reply value effects next emitted Accepted.
 unfold RequestDelivery.advance in Accepted.
 remember (RequestDelivery.normalize
   (if existsb Scheduler.frozen_inference effects then Decision value reply effects
    else Selvedge.Features.Compaction.synchronize_all (Decision value reply effects))) as prepared.
 destruct prepared as [prepared_world prepared_reply prepared_effects].
 cbn [decision_world decision_effects] in Accepted.
 destruct (Delivery.fits true (RequestDelivery.finish (Decision prepared_world reply prepared_effects)) &&
   Delivery.fits true (RequestDelivery.finish
     (RequestDelivery.continuing (Decision prepared_world reply prepared_effects)))) eqn:Budget;
   [|discriminate].
 inversion Accepted; subst next emitted.
 now apply andb_true_iff in Budget.
Qed.

Theorem context_completion_commits_before_following_scheduling : forall owner ticket observations diagnostic before,
 Packet.prepare true (Some (ContextCompleted owner ticket observations diagnostic))
   (Packet.core_transition (ContextCompleted owner ticket observations diagnostic) before) =
 RequestDelivery.defer (Selvedge.Features.Runtime.after_transition before
   (Callbacks.context_completed owner ticket observations diagnostic before)).
Proof. reflexivity. Qed.

Theorem model_completion_keeps_its_feature_delta_before_deferral : forall owner ticket outcome before,
 Packet.prepare true (Some (ModelCompleted owner ticket outcome))
   (Packet.core_transition (ModelCompleted owner ticket outcome) before) =
 RequestDelivery.defer (Selvedge.Features.Runtime.after_transition before
   (Callbacks.model_completed owner ticket outcome before)).
Proof. reflexivity. Qed.
