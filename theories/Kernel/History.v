From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State ContextTypes.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition operation_result (operation : operation) (result : json) (error : bool) : message :=
 if operation_announced operation
 then OperationResult (operation_id operation) (operation_call operation) result error
 else FunctionOutput (call_id (operation_call operation)) result error.
Definition interrupted_result (code reason : string) (operation : operation) : message :=
 let outcome := match operation_stage operation with
 | AwaitingApproval _ _ => failure "approval_interrupted"
   "The approval request was interrupted before Bash execution. No command was started. Submit a new request if the operation is still needed."
 | Granted _ => failure "approval_expired"
   "The one-operation grant expired before Bash execution. No command was started. A fresh request and approval are required."
 | AfterHooksReady _ _ _ | AwaitingAfterHook _ _ _ _ _ => failure "after_hook_interrupted"
   ("Result processing was interrupted. The execution receipt remains in history; neither the tool nor its callback is repeated. " ++ reason)
 | Executing _ | Elevated _ _ => failure code reason end in
 operation_result operation outcome true.
Definition close_operations (code reason : string) (value : task) :=
 task_history value ++ map (interrupted_result code reason) (task_operations value).
Definition inherited_call (parent : N) (invocation : call) :=
 FunctionOutput (call_id invocation) (failure "inherited_operation_not_owned"
  ("This invocation belongs to parent task " ++ number_text parent ++
  "; its execution was not copied. Read that task for its eventual result.")) true.
Definition pending_invocations (phase : activity) := match phase with
 | PendingCalls calls => calls
 | ReadyForHooks invocation _ remaining | CheckingHook _ _ invocation _ remaining => invocation :: remaining
 | _ => [] end.
Definition snapshot_history (parent : N) (value : task) :=
 close_operations "inherited_operation_not_owned"
  ("This operation belongs to parent task " ++ number_text parent ++
   "; its execution was not copied. Read that task for its eventual result.") value ++
 map (inherited_call parent) (pending_invocations (task_activity value)).
Definition parent_context (change : context_change) :=
 let key := match change with Introduce value => snapshot_key value | Amend key _ _ _ | Remove key _ => key end in
 String.eqb (definition_kind (key_definition key)) "task_lifecycle".
Definition returned_content (value : message) :=
 match value with ContextObservation change => negb (parent_context change) | _ => true end.
Definition without_inherited_result (identity : string) (value : message) :=
 match value with
 | FunctionOutput actual _ _ => negb (String.eqb identity actual)
 | _ => true end.

Definition cancelled_call (value : call) := FunctionOutput (call_id value)
 (failure "cancelled_before_execution" "This tool was cancelled before dispatch") true.
Definition interrupted_phase (phase : activity) := match phase with
 | PendingCalls calls | ReadyForHooks _ _ calls => map cancelled_call (pending_invocations phase)
 | CheckingHook _ _ invocation _ remaining =>
   FunctionOutput (call_id invocation) (failure "hook_cancelled"
    "Authorization was interrupted; the tool was not dispatched. The plugin callback may already have run.") true :: map cancelled_call remaining
 | ObservingContext _ _ => [FailureMessage "Context observation interrupted by the user; no model request was sent"]
 | AskingModel _ _ _ => [FailureMessage "Model request interrupted by the user"]
 | EvaluatingReasoning _ _ => [FailureMessage "Reasoning evaluation interrupted by the user; no model request was sent"]
 | Idle | WantsModel | ReadyForModel => [] end.
