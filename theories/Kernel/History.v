From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec State ModelRequest ContextTypes Images Conversation.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Include ModelRequest.LeaseState.

Definition operation_result (operation : operation) (result : json) (error : bool) : message :=
 if operation_announced operation
 then OperationResult (operation_id operation) (operation_call operation) result error
 else FunctionOutput (call_id (operation_call operation)) result error.
Definition cancelled_operation (operation : operation) : message :=
 let outcome := match operation_stage operation with
 | AwaitingApproval _ _ | Granted _ => failure "cancelled"
   "Cancellation requested before execution. The operation did not start and made no external changes."
 | Executing _ | Elevated _ _ => failure "cancelled"
   "Cancellation requested. The operation may already have made changes; those changes are not undone."
 | AfterHooksReady _ _ _ | AwaitingAfterHook _ _ _ _ _ => failure "cancelled"
   "Cancellation requested after execution. The execution receipt remains in history; result processing stopped and neither the tool nor its callback will be repeated."
 end in operation_result operation outcome true.
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
Definition snapshot_operations (parent : N) (value : task) :=
 close_operations "inherited_operation_not_owned"
  ("This operation belongs to parent task " ++ number_text parent ++
   "; its execution was not copied. Read that task for its eventual result.") value.
Definition snapshot_history (parent : N) (value : task) :=
 snapshot_operations parent value ++
 map (inherited_call parent) (pending_invocations (task_activity value)).
Definition parent_context (change : context_change) :=
 let key := match change with Introduce value => snapshot_key value | Amend key _ _ _ | Remove key _ => key end in
 String.eqb (definition_kind (key_definition key)) "task_lifecycle".
Definition returned_content (value : message) :=
 match value with
 | ContextObservation change => negb (parent_context change)
 | SideConversationBirth _ _ _ => false
 | _ => true end.
Definition without_inherited_result (identity : string) (value : message) :=
 match value with
 | FunctionOutput actual _ _ => negb (String.eqb identity actual)
 | _ => true end.

Definition message_images (value : message) := match value with
 | UserMessage parts => Images.only_images parts
 | FunctionOutput _ result _ | OperationResult _ _ result _ => Images.result_images result
 | _ => [] end.

Definition fork_receipt_history (receipt : message) (history : list message) :=
 match rev history with
 | UserMessage contents :: rest => rev rest ++ [receipt; UserMessage contents]
 | _ => history ++ [receipt] end.

Definition cancelled_call (value : call) := FunctionOutput (call_id value)
 (match call_origin value with
 | InitialAttempt => failure "cancelled_before_execution" "This tool was cancelled before dispatch"
 | RecoveryAttempt => failure "outcome_unknown" "This tool may already have run; cancellation does not undo it" end) true.
Definition interrupted_phase (phase : activity) := match phase with
 | PendingCalls calls | ReadyForHooks _ _ calls => map cancelled_call (pending_invocations phase)
 | CheckingHook _ _ invocation _ remaining =>
   FunctionOutput (call_id invocation) (failure "hook_cancelled"
    "Authorization was interrupted; the tool was not dispatched. The plugin callback may already have run.") true :: map cancelled_call remaining
 | ObservingContext _ _ => [FailureMessage "Context observation interrupted by the user; no model request was sent"]
 | AskingModel _ _ _ => [FailureMessage "Model request interrupted by the user"]
 | EvaluatingReasoning _ _ => [FailureMessage "Reasoning evaluation interrupted by the user; no model request was sent"]
 | Idle | WantsModel | ReadyForModel => [] end.
