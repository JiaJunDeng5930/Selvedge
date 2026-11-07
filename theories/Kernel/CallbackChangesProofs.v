From Selvedge.Kernel Require TaskWake.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Programming Require TaskResult.
From Selvedge.Kernel Require OperationEvent.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec State.
From Selvedge.Programming Require Import TaskScope TaskScopeProofs TaskChange TaskChangeProofs.
From Selvedge.Kernel Require Import Tasks TaskChangesProofs.
From Selvedge.Kernel Require Import TaskWakeProofs.
From Selvedge.Kernel Require Import History Context ContextUpdates Callbacks HookCallbacks Reasoning Inputs Scheduler HookRules RequestReceiver.
From Selvedge.Kernel Require Import ScopedRequestProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition applying_change_lists := TaskChangeProofs.apply_app.

Ltac reduce_callback_plan expression :=
 let reduced := reduce_task_plan expression in
 eval fold RequestReceiver.operation_executing RequestReceiver.find_approval in reduced.

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
 (TaskChange.apply (Callbacks.settle_model_changes task) task) = TaskWake.promote (with_activity
 (if unseen_model_input task then WantsModel else Idle) task).
Proof. reflexivity. Qed.

Lemma settle_operation_expression : forall operation result error task,
 let settled := with_lifecycle
   (change_operations (filter (fun pending => negb (N.eqb (operation_id operation) (operation_id pending))))
     (task_lifecycle task))
   (append_history [History.operation_result operation result error] task) in
 TaskChange.apply (TaskResult.result_changes (OperationEvent.settle operation result error) task) task =
 TaskChange.apply (TaskWake.wake_after_result_changes settled) settled.
Proof.
 intros; unfold OperationEvent.settle, TaskResult.result_changes.
 rewrite applying_change_lists.
 destruct task as [contract profile settings lifecycle history queued lineage parent cursor consumed];
   destruct lifecycle; reflexivity.
Qed.

Definition tool_completed_expression (id ticket : N) (result : json) (error : bool) (value : world) := ltac:(
 let body := eval unfold Callbacks.tool_completed in (Callbacks.tool_completed id ticket result error value) in
 derive_callback_view constr:(Callbacks.tool_completed id ticket result error value) body id value).

Definition reasoning_completed_expression (id ticket : N) (outcome : Reasoning.outcome) (value : world) := ltac:(
 let body := eval unfold Callbacks.reasoning_completed in (Callbacks.reasoning_completed id ticket outcome value) in
 derive_callback_view constr:(Callbacks.reasoning_completed id ticket outcome value) body id value).

Definition context_ready_expression (accepted : bool) (id : N) (task : task) (value : world) := ltac:(
 let body := eval unfold Callbacks.context_ready in (Callbacks.context_ready accepted id task value) in
 derive_callback_view constr:(Callbacks.context_ready accepted id task value) body id value).

Definition context_completed_expression (id ticket : N) (observations : option (list context_observation)) (diagnostic : string) (value : world) := ltac:(
 let body := eval unfold Callbacks.context_completed in (Callbacks.context_completed id ticket observations diagnostic value) in
 derive_callback_view constr:(Callbacks.context_completed id ticket observations diagnostic value) body id value).

Definition hook_completed_expression (id ticket : N) (outcome : hook_outcome) (value : world) := ltac:(
 let body := eval unfold HookCallbacks.hook_completed in (HookCallbacks.hook_completed id ticket outcome value) in
 derive_callback_view constr:(HookCallbacks.hook_completed id ticket outcome value) body id value).

Definition after_completed_expression (id operation ticket : N) (outcome : after_outcome) (value : world) := ltac:(
 let body := eval unfold HookCallbacks.after_completed in (HookCallbacks.after_completed id operation ticket outcome value) in
 derive_callback_view constr:(HookCallbacks.after_completed id operation ticket outcome value) body id value).
