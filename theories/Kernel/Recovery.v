From Stdlib Require Import String List NArith Bool.
From Selvedge.Programming Require TaskResult.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State.
From Selvedge.Programming Require Import TaskChange.
From Selvedge.Kernel Require Import Tasks.
From Selvedge.Programming Require Import OperationEvent.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition recovery_changes (owner : N) (value : task) :=
 [TaskChange.AppendHistory (Tasks.unknown_operations (task_operations value)); TaskChange.ClearOperations] ++
 match task_activity value with
 | ObservingContext _ _ | AskingModel _ _ _ | EvaluatingReasoning _ _ =>
   [TaskChange.ChangePhase WantsModel]
 | CheckingHook _ plugin invocation _ remaining =>
   TaskResult.result_changes (OperationEvent.plan owner
     (OperationEvent.BeforeInterrupted plugin invocation remaining) value) value
 | Idle => if Nat.eqb (List.length (task_operations value)) 0
   then [] else [TaskChange.ChangePhase WantsModel]
 | _ => [] end.
Definition recover_task (owner : N) (value : task) :=
 TaskChange.apply (recovery_changes owner value) value.
Definition recover (value : world) :=
 accept (JObject [("recovered",JBool true)])
  (with_tasks (Selvedge.Foundation.Registry.indexed recover_task 0 (world_tasks value)) value) [].
