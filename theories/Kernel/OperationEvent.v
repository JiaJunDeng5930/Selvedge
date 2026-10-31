From Stdlib Require Import String List Bool NArith.
From Selvedge.Programming Require TaskResult.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State.
From Selvedge.Programming Require Import TaskChange.
From Selvedge.Kernel Require Import History Inputs Capabilities ApprovalProtocol HookRules.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

(** An operation observation determines both its durable receipt and its next
    continuation. Consumers supply the observation once; they cannot choose a
    receipt, a hook action and an operation stage independently. This language
    describes the tool protocol, not the set of tools or API backends. *)
Inductive event :=
| Returned (operation : operation) (result : json) (error : bool)
| Reviewed (operation : operation) (actor : reviewer) (outcome : approval_outcome)
| BeforeChecked (plugin : json) (invocation : call) (pending : list json)
    (remaining : list call) (outcome : hook_outcome)
| BeforeInterrupted (plugin : json) (invocation : call) (remaining : list call)
| AfterUnavailable (operation : operation) (plugin : json).

Definition after_plugins (task : task) :=
 Capabilities.hook_references Capabilities.AfterTool (contract_plugins (task_contract task)).
Definition settle (operation : operation) (result : json) (error : bool) :=
 TaskResult.WakeDemand [TaskChange.Edit
   (TaskChange.update (TaskChange.RemoveOperation (operation_id operation)))
   (Some [History.operation_result operation result error])].
Definition result_stage (pending : list json) (result : json) (error : bool) :=
 AfterHooksReady pending result error.
Definition result_receipt (owner : N) (operation : operation) (result : json) (error : bool) :=
 ToolReceipt owner (operation_id operation) (operation_call operation) result error.
Definition returned (owner : N) (operation : operation) (result : json) (error : bool) (task : task) :=
 match after_plugins task with
 | [] => settle operation result error
 | pending => TaskResult.KeepDemand
   [TaskChange.AppendHistory [result_receipt owner operation result error];
    TaskChange.ChangeOperationStage (operation_id operation) (result_stage pending result error)]
 end.
Definition call_result (invocation : call) (result : json) (error : bool) (remaining : list call) :=
 [TaskChange.AppendHistory [FunctionOutput (call_id invocation) result error];
  TaskChange.ChangePhase (PendingCalls remaining)].
Definition after_result (operation : operation) (pending : list json) (error : bool)
 (action : HookRules.after_action) := match action with
 | HookRules.RefuseResult code reason => settle operation (State.failure code reason) true
 | HookRules.ContinueResult result => match pending with
   | [] => settle operation result error
   | _ => TaskResult.KeepDemand
     [TaskChange.ChangeOperationStage (operation_id operation) (result_stage pending result error)] end end.
Definition after_checked (owner : N) (operation : operation) (plugin : json)
 (pending : list json) (result : json) (error : bool) (outcome : after_outcome) :=
 TaskResult.prefix_result [TaskChange.AppendHistory
   [AfterReceipt owner (operation_id operation) plugin (Inputs.after_json outcome)]]
   (after_result operation pending error (HookRules.after_apply result outcome)).
Definition before_interruption_reason :=
 "Hook outcome unknown after restart; callback not repeated; tool not dispatched".
Definition plan (owner : N) (observation : event) (task : task) := match observation with
 | Returned operation result error => returned owner operation result error task
 | Reviewed operation actor outcome =>
   let receipt := [ApprovalReceipt owner (operation_id operation) (operation_call operation)
     actor (ApprovalProtocol.encode_outcome outcome)] in
   TaskResult.prefix_result [TaskChange.AppendHistory receipt] (if ApprovalProtocol.allows outcome then TaskResult.KeepDemand
     [TaskChange.ChangeOperationStage (operation_id operation) (Granted actor)]
   else returned owner operation
     (State.failure "approval_denied" ("Bash was not started. " ++ ApprovalProtocol.outcome_reason outcome)) true
     (append_history receipt task))
 | BeforeChecked plugin invocation pending remaining outcome =>
   TaskResult.KeepDemand (TaskChange.AppendHistory [HookReceipt owner invocation plugin (Inputs.hook_json outcome)] ::
    match HookRules.before_apply invocation outcome with
    | HookRules.Proceed invocation => [TaskChange.ChangePhase (ReadyForHooks invocation pending remaining)]
    | HookRules.Refuse code reason => call_result invocation (State.failure code reason) true remaining end)
 | BeforeInterrupted plugin invocation remaining =>
   TaskResult.KeepDemand (TaskChange.AppendHistory
     [HookReceipt owner invocation plugin (Inputs.hook_json (HookFailure before_interruption_reason))] ::
     call_result invocation (State.failure "hook_interrupted" before_interruption_reason) true remaining)
 | AfterUnavailable operation plugin =>
   TaskResult.prefix_result [TaskChange.AppendHistory [AfterReceipt owner (operation_id operation) plugin
     (Inputs.after_json (AfterFailure "The frozen result-processing plugin revision is unavailable"))]]
     (settle operation (State.failure "after_hook_unavailable"
       "The frozen result-processing plugin revision is unavailable; the tool has already completed") true)
 end.

(** Native calls have already completed. They create the result-processing
    operation directly; there is no fictitious execution receiver or callback.
    The scheduler and its preservation arguments use this same constructor. *)
Definition native_result (owner ticket : N) (invocation : call) (remaining : list call)
 (result : json) (error : bool) (source : task) :=
 TaskChange.apply (match after_plugins source with
 | [] => call_result invocation result error remaining
 | pending =>
   let operation := Operation ticket invocation false (result_stage pending result error) in
   [TaskChange.AppendHistory [result_receipt owner operation result error];
    TaskChange.AddOperation operation; TaskChange.ChangePhase (PendingCalls remaining)]
 end) source.
