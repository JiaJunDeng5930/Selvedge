From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Inputs Callbacks Scheduler HookRules.
Import ListNotations.
Open Scope string_scope.

Definition hook_completed (id ticket : N) (outcome : hook_outcome) (value : world) :=
 match find_task id value with
 | None => ignored value
 | Some task => match task_activity task with
   | CheckingHook expected plugin invocation pending remaining =>
     if N.eqb expected ticket then
     let task := append_history [HookReceipt id invocation plugin (hook_json outcome)] task in
     match HookRules.before_apply invocation outcome with
     | HookRules.Proceed invocation =>
       acknowledged (put_task id (with_activity (ReadyForHooks invocation pending remaining) task) value)
     | HookRules.Refuse code reason => call_error id invocation code reason remaining task value
     end
     else ignored value
   | _ => ignored value
   end
 end.
Definition after_completed (id operation ticket : N) (outcome : after_outcome) (value : world) :=
 match find_task id value with
 | None => ignored value
 | Some task => match find (fun pending => N.eqb operation (operation_id pending)) (task_operations task) with
   | None => ignored value
   | Some operation => match operation_stage operation with
     | AwaitingAfterHook expected plugin pending result error =>
       if N.eqb expected ticket then
       let task := append_history [AfterReceipt id (operation_id operation) plugin (after_json outcome)] task in
       let failed := fun code reason => acknowledged
         (put_task id (settle_operation operation (State.failure code reason) true task) value) in
       match HookRules.after_apply result outcome with
       | HookRules.RefuseResult code reason => failed code reason
       | HookRules.ContinueResult result =>
         match pending with
         | [] => acknowledged (put_task id (settle_operation operation result error task) value)
         | _ => let waiting := Operation (operation_id operation) (operation_call operation)
           (operation_announced operation) (AfterHooksReady pending result error) in
           acknowledged (put_task id (with_operations (replace_operation waiting (task_operations task)) task) value)
         end
       end
       else ignored value
     | _ => ignored value end
   end
 end.
