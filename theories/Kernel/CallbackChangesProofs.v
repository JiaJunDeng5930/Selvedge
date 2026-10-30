From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec State TaskScope TaskScopeProofs TaskChange TaskChangeProofs Tasks TaskChangesProofs TaskWakeProofs History Context ContextUpdates Callbacks HookCallbacks Reasoning Inputs
 ApprovalProtocol Scheduler HookRules RequestReceiver ScopedRequestProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition applying_change_lists := TaskChangeProofs.apply_app.

Ltac reduce_callback_plan expression :=
 let reduced := reduce_task_plan expression in
 eval fold Callbacks.operation_executing Callbacks.find_pending_approval in reduced.

Ltac derive_callback_view program expression id before :=
 let selected := eval cbv beta iota zeta delta [RequestReceiver.deliver RequestReceiver.deliver_or
   RequestReceiver.pending_phase RequestReceiver.phase_receiver RequestReceiver.pending_tool
   RequestReceiver.pending_approval RequestReceiver.pending_human_approval RequestReceiver.pending_after
   RequestReceiver.operation_at RequestReceiver.operation_receiver] in expression in
 derive_task_lookup_view program selected id before reduce_callback_plan.

Definition model_completed_expression (id ticket : N) (outcome : model_outcome) (value : world) := ltac:(
 let body := eval unfold Callbacks.model_completed in (Callbacks.model_completed id ticket outcome value) in
 derive_callback_view constr:(Callbacks.model_completed id ticket outcome value) body id value).

Lemma settle_model_expression : forall task,
 Callbacks.settle_model task = Tasks.promote (with_activity
 (if unseen_model_input task then WantsModel else Idle) task).
Proof. reflexivity. Qed.

Lemma settle_operation_expression : forall operation result error task,
 Callbacks.settle_operation operation result error task =
 Tasks.wake_after_result (with_operations (Callbacks.remove_operation (operation_id operation) (task_operations task))
 (append_history [History.operation_result operation result error] task)).
Proof.
 intros; unfold Callbacks.settle_operation, Callbacks.settle_operation_changes,
   Callbacks.settle_operation_plan, OperationEvent.settle, Tasks.result_changes.
 rewrite applying_change_lists.
 destruct task as [contract profile settings lifecycle history queued lineage parent cursor consumed];
   destruct lifecycle; reflexivity.
Qed.

Definition tool_completed_expression (id ticket : N) (result : json) (error : bool) (value : world) := ltac:(
 let body := eval unfold Callbacks.tool_completed in (Callbacks.tool_completed id ticket result error value) in
 derive_callback_view constr:(Callbacks.tool_completed id ticket result error value) body id value).

Definition approval_completed_expression (id ticket : N) (outcome : approval_outcome) (value : world) := ltac:(
 let body := eval unfold Callbacks.approval_completed in (Callbacks.approval_completed id ticket outcome value) in
 derive_callback_view constr:(Callbacks.approval_completed id ticket outcome value) body id value).

Definition review_approval_expression (id operation : N) (outcome : approval_outcome) (value : world) := ltac:(
 let body := eval unfold Callbacks.review_approval in (Callbacks.review_approval id operation outcome value) in
 derive_callback_view constr:(Callbacks.review_approval id operation outcome value) body id value).

Definition reasoning_completed_expression (id ticket : N) (outcome : Reasoning.outcome) (value : world) := ltac:(
 let body := eval unfold Callbacks.reasoning_completed in (Callbacks.reasoning_completed id ticket outcome value) in
 derive_callback_view constr:(Callbacks.reasoning_completed id ticket outcome value) body id value).







Definition context_ready_expression (accepted : bool) (id : N) (task : task) (value : world) := ltac:(
 let body := eval unfold Callbacks.context_ready in (Callbacks.context_ready accepted id task value) in
 derive_callback_view constr:(Callbacks.context_ready accepted id task value) body id value).

Lemma context_retry_uses_the_current_task : forall id value current,
 find_task id value = Some current ->
 Reasoning.context_retry id value =
 if TicketedRequest.Scoped.can_observe false current value then
   TicketedRequest.issue id (TicketedRequest.Observe current) value
 else Reasoning.context_retry_wait id current value.
Proof.
 intros id value current Found.
 destruct (selecting_an_existing_task_retains_its_key id value current Found)
   as [reference [Selected [Owner Current]]].
 unfold Reasoning.context_retry; rewrite Selected, observe_selected_erases_its_capability.
 now rewrite Owner, Current.
Qed.

Definition context_completed_expression (id ticket : N) (observations : option (list context_observation)) (diagnostic : string) (value : world) := ltac:(
 let body := eval unfold Callbacks.context_completed in (Callbacks.context_completed id ticket observations diagnostic value) in
 derive_callback_view constr:(Callbacks.context_completed id ticket observations diagnostic value) body id value).

Lemma task_changes_preserve_the_frozen_contract : forall changes task,
 task_contract (TaskChange.apply changes task) = task_contract task.
Proof.
 intros changes task; exact (proj1 (TaskChangeProofs.field_changes_keep_the_immutable_task_identity changes task)).
Qed.

Definition hook_completed_expression (id ticket : N) (outcome : hook_outcome) (value : world) := ltac:(
 let body := eval unfold HookCallbacks.hook_completed in (HookCallbacks.hook_completed id ticket outcome value) in
 derive_callback_view constr:(HookCallbacks.hook_completed id ticket outcome value) body id value).

Definition after_completed_expression (id operation ticket : N) (outcome : after_outcome) (value : world) := ltac:(
 let body := eval unfold HookCallbacks.after_completed in (HookCallbacks.after_completed id operation ticket outcome value) in
 derive_callback_view constr:(HookCallbacks.after_completed id operation ticket outcome value) body id value).
