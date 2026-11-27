From Stdlib Require Import List.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain.
Import ListNotations.

Definition ready_operation (operations : list operation) := find (fun operation =>
 match operation_stage operation with Granted _ | AfterHooksReady _ _ _ => true | _ => false end) operations.
Definition ready_settlement (operations : list operation) := find (fun operation =>
 match operation_stage operation with AfterHooksReady _ _ _ => true | _ => false end) operations.
Inductive runnable_step :=
| OperationStep (pending : operation)
| ContextStep | ModelStep
| HookStep (invocation : call) (pending : list json) (remaining : list call)
| CallStep (invocation : call) (remaining : list call)
| FinishCallsStep | PromoteInputStep | StopInferenceStep.
Definition task_action (task : task) : option runnable_step :=
 match task_lifecycle task with
 | Running phase operations =>
   match ready_operation operations with
   | Some operation => Some (OperationStep operation)
   | None => match phase with
     | WantsModel => Some ContextStep
     | ReadyForModel => Some ModelStep
     | ReadyForHooks invocation pending remaining => Some (HookStep invocation pending remaining)
     | PendingCalls (first :: rest) => Some (CallStep first rest)
     | PendingCalls [] => Some FinishCallsStep
     | Idle => match task_queued task with [] => None | _ => Some PromoteInputStep end
     | WaitingForInput _ _ => if waiting_input_available task then Some PromoteInputStep else None
     | _ => None end end
 | Stopped phase operations => match ready_settlement operations with
   | Some operation => Some (OperationStep operation)
   | None => match phase with
     | PendingCalls (first :: rest) => Some (CallStep first rest)
     | ReadyForHooks invocation pending remaining => Some (HookStep invocation pending remaining)
     | PendingCalls [] | WantsModel | ReadyForModel => Some StopInferenceStep
     | _ => None end end
 | Frozen _ operations | Archived operations =>
   option_map OperationStep (ready_settlement operations)
 end.
Definition settlement (task : task) :=
 option_map OperationStep (ready_settlement (task_operations task)).

(* Permit changes may admit or block the main action. Settling a returned
   result can still be runnable while the main action is blocked. *)
Definition candidate (task : task) :=
 match task_action task with
 | Some _ => true
 | None => match settlement task with Some _ => true | None => false end end.
