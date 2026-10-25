From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec State TaskScope TaskChange Tasks Inputs Callbacks Scheduler HookRules.
Import ListNotations.
Open Scope string_scope.

Definition hook_completed (id ticket : N) (outcome : hook_outcome) (value : world) :=
 match TaskScope.select id value with
 | None => ignored value
 | Some target => let task := TaskScope.selected target in match task_activity task with
   | CheckingHook expected plugin invocation pending remaining =>
     if N.eqb expected ticket then
     let receipt := TaskChange.AppendHistory [HookReceipt id invocation plugin (hook_json outcome)] in
     let changes := receipt :: match HookRules.before_apply invocation outcome with
     | HookRules.Proceed invocation => [TaskChange.ChangePhase (ReadyForHooks invocation pending remaining)]
     | HookRules.Refuse code reason =>
       [TaskChange.AppendHistory [FunctionOutput (call_id invocation) (State.failure code reason) true];
        TaskChange.ChangePhase (PendingCalls remaining)]
     end in
     acknowledged (TaskChange.interpret (TaskChange.Plan value target changes))
     else ignored value
   | _ => ignored value
   end
 end.
Definition after_completed (id operation ticket : N) (outcome : after_outcome) (value : world) :=
 match TaskScope.select id value with
 | None => ignored value
 | Some target => let task := TaskScope.selected target in match find (fun pending => N.eqb operation (operation_id pending)) (task_operations task) with
   | None => ignored value
   | Some operation => match operation_stage operation with
     | AwaitingAfterHook expected plugin pending result error =>
       if N.eqb expected ticket then
       let receipt := [AfterReceipt id (operation_id operation) plugin (after_json outcome)] in
       let recorded := append_history receipt task in
       let changes := TaskChange.AppendHistory receipt :: match HookRules.after_apply result outcome with
       | HookRules.RefuseResult code reason => settle_operation_changes operation (State.failure code reason) true recorded
       | HookRules.ContinueResult result =>
         match pending with
         | [] => settle_operation_changes operation result error recorded
         | _ => [TaskChange.ChangeOperationStage (operation_id operation) (AfterHooksReady pending result error)]
         end
       end in
       acknowledged (TaskChange.interpret (TaskChange.Plan value target changes))
       else ignored value
     | _ => ignored value end
   end
 end.
