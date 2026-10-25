From Stdlib Require Import String List NArith Bool.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State History.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition recovered_phase (phase : activity) := match phase with
 | ObservingContext _ _ | AskingModel _ _ _ | EvaluatingReasoning _ _ => WantsModel
 | CheckingHook _ _ _ _ remaining => PendingCalls remaining
 | other => other end.
Definition recovery_receipts (owner : N) (phase : activity) := match phase with
 | CheckingHook ticket plugin invocation _ _ =>
   [HookReceipt owner invocation plugin (JObject [("decision",JString "failed");
    ("reason",JString "Hook outcome unknown after restart; callback not repeated; tool not dispatched")]);
    FunctionOutput (call_id invocation) (failure "hook_interrupted"
     "Hook outcome unknown after restart; callback not repeated; tool not dispatched") true]
 | _ => [] end.
Definition recover_task (owner : N) (value : task) :=
 let pending := negb (Nat.eqb (List.length (task_operations value)) 0) in
 let phase := recovered_phase (task_activity value) in
 let ready := match phase with Idle => if pending then WantsModel else Idle | other => other end in
 let lifecycle := match task_lifecycle value with
 | Running _ _ => Running ready [] | Frozen _ _ => Frozen ready []
 | Stopped _ _ => Stopped ready [] | Archived _ => (Archived []) end in
 with_lifecycle lifecycle (with_history
  (close_operations "outcome_unknown"
   "The external operation may already have run. Its side effects cannot be inferred or undone; it will not be repeated automatically." value ++
   recovery_receipts owner (task_activity value)) value).
Definition recover (value : world) :=
 accept (JObject [("recovered",JBool true)])
  (with_tasks (Selvedge.Foundation.Registry.indexed recover_task 0 (world_tasks value)) value) [].
