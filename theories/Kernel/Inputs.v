From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json ModelWire.
From Selvedge.Kernel Require Export ApprovalProtocol.
From Selvedge.Kernel Require Import Numbers Domain ContextTypes Reasoning.
From Selvedge.Generated Require Import Commands.
Import ListNotations.
Open Scope string_scope.
Inductive model_outcome := ModelSuccess (items : ModelWire.batch)
 | ModelFailure (message : string) | ModelContextLimit.
Definition duplicate_model_identity := "Invalid model reply: duplicate output part or call identity".
Definition model_outcome_from_items (items : list ModelWire.value) :=
 match ModelWire.admit_batch items with
 | Some batch => ModelSuccess batch
 (* DEFENSE: A provider can repeat a part or call ID in a well-shaped response.
    Consume the pending request as a failure instead of leaving it awaiting. *)
 | None => ModelFailure duplicate_model_identity end.
Inductive input :=
| UserCommand (command : Selvedge.Generated.Commands.command)
| Configure (environment : environment)
| ContextCompleted (task_id ticket : N) (observations : option (list context_observation)) (diagnostic : string)
| ModelCompleted (task_id ticket : N) (outcome : model_outcome)
| ReasoningCompleted (task_id ticket : N) (outcome : Reasoning.outcome)
| ToolCompleted (task_id ticket : N) (value : json) (error : bool)
| HookCompleted (task_id ticket : N) (outcome : hook_outcome)
| AfterCompleted (task_id operation_id ticket : N) (outcome : after_outcome)
| ApprovalCompleted (task_id ticket : N) (outcome : approval_outcome)
| Recover
| Continue.
