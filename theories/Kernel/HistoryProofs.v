From Selvedge.Kernel Require Import CallbackChangesProofs.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain History.
Import ListNotations.
Open Scope list_scope.

Theorem an_unannounced_interruption_closes_the_provider_call : forall operation code reason,
 operation_announced operation = false ->
 exists result, History.interrupted_result code reason operation =
 FunctionOutput (call_id (operation_call operation)) result true.
Proof.
 intros operation code reason Silent; unfold History.interrupted_result, History.operation_result.
 rewrite Silent; eexists; reflexivity.
Qed.

Theorem native_results_append_their_completed_observation :
 forall owner ticket invocation remaining result error current,
 task_history (OperationEvent.native_result owner ticket invocation remaining result error current) =
 task_history current ++ match OperationEvent.after_plugins current with
 | nil => (FunctionOutput (call_id invocation) result error :: nil)%list
 | _ => (ToolReceipt owner ticket invocation result error :: nil)%list end.
Proof.
 intros; unfold OperationEvent.native_result.
 destruct (OperationEvent.after_plugins current);
 destruct current as [contract profile settings lifecycle history queued lineage parent cursor consumed];
 destruct lifecycle; reflexivity.
Qed.
Theorem an_announced_interruption_retains_operation_identity : forall operation code reason,
 operation_announced operation = true ->
 exists result, History.interrupted_result code reason operation =
 OperationResult (operation_id operation) (operation_call operation) result true.
Proof.
 intros operation code reason Announced; unfold History.interrupted_result, History.operation_result.
 rewrite Announced; eexists; reflexivity.
Qed.

From Selvedge.Kernel Require Import State Tasks Callbacks LifecycleProofs.
Import ListNotations.
Theorem an_after_hook_retains_the_original_execution_receipt :
 forall id ticket result error value task operation first rest,
 find_task id value = Some task ->
 find (Callbacks.operation_executing ticket) (task_operations task) = Some operation ->
 Callbacks.after_plugins task = first :: rest ->
 exists updated,
 find_task id (decision_world (Callbacks.tool_completed id ticket result error value)) = Some updated /\
 task_history updated = task_history task ++
 [ToolReceipt id (operation_id operation) (operation_call operation) result error].
Proof.
 intros id ticket result error value task operation first rest Found Owned Hooks.
 rewrite CallbackChangesProofs.tool_completed_expression; rewrite Found, Owned.
 unfold Callbacks.begin_result_plan, OperationEvent.plan, OperationEvent.returned.
 unfold Callbacks.after_plugins in Hooks; rewrite Hooks.
 eexists; split; [apply find_put_task with task; exact Found|].
 destruct task as [contract profile settings lifecycle history queued lineage parent cursor consumed];
 destruct lifecycle; reflexivity.
Qed.
