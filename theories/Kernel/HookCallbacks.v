From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec State TaskScope RequestReceiver TaskChange Tasks Inputs Callbacks Scheduler HookRules.
Import ListNotations.
Open Scope string_scope.

Definition hook_completed (id ticket : N) (outcome : hook_outcome) (value : world) :=
 RequestReceiver.deliver id value (RequestReceiver.pending_phase RequestReceiver.HookReceiver ticket)
   (fun target payload => let '(plugin,invocation,pending,remaining) := payload in
    let receipt := TaskChange.AppendHistory [HookReceipt id invocation plugin (hook_json outcome)] in
    let changes := receipt :: match HookRules.before_apply invocation outcome with
    | HookRules.Proceed invocation => [TaskChange.ChangePhase (ReadyForHooks invocation pending remaining)]
    | HookRules.Refuse code reason =>
      [TaskChange.AppendHistory [FunctionOutput (call_id invocation) (State.failure code reason) true];
       TaskChange.ChangePhase (PendingCalls remaining)] end in
    acknowledged (TaskChange.interpret (TaskChange.Plan value target changes))).
Definition after_result_plan_for (id : N) (operation : operation) (plugin : json)
 (pending : list json) (error : bool) (outcome : after_outcome) (action : HookRules.after_action) :=
 let receipt := [AfterReceipt id (operation_id operation) plugin (after_json outcome)] in
 Tasks.prefix_result [TaskChange.AppendHistory receipt] (match action with
 | HookRules.RefuseResult code reason => settle_operation_plan operation (State.failure code reason) true
 | HookRules.ContinueResult result => match pending with
   | [] => settle_operation_plan operation result error
   | _ => Tasks.KeepDemand [TaskChange.ChangeOperationStage (operation_id operation) (AfterHooksReady pending result error)] end end).
Definition after_result_plan id operation plugin pending result error outcome :=
 after_result_plan_for id operation plugin pending error outcome (HookRules.after_apply result outcome).
Definition after_completed (id operation ticket : N) (outcome : after_outcome) (value : world) :=
 RequestReceiver.deliver id value (RequestReceiver.pending_after operation ticket)
   (fun target payload => let '(operation,plugin,pending,result,error) := payload in
    acknowledged (Tasks.interpret_result target
      (after_result_plan id operation plugin pending result error outcome))).
