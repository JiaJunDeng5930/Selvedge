From Stdlib Require Import String List Bool NArith.
From Selvedge.Programming Require OperationEvent TaskResult.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec State.
From Selvedge.Programming Require Import TaskScope.
From Selvedge.Kernel Require Import RequestReceiver.
From Selvedge.Programming Require Import TaskChange.
From Selvedge.Kernel Require Import Tasks Inputs Callbacks Scheduler HookRules.
Import ListNotations.
Open Scope string_scope.

Definition hook_completed (id ticket : N) (outcome : hook_outcome) (value : world) :=
 RequestReceiver.deliver id value (RequestReceiver.pending_phase RequestReceiver.HookReceiver ticket)
   (fun target payload => let '(plugin,invocation,pending,remaining) := payload in
    acknowledged (TaskResult.interpret_result target (OperationEvent.plan id
      (OperationEvent.BeforeChecked plugin invocation pending remaining outcome) (TaskScope.selected target)))).
Definition after_result_plan := OperationEvent.after_checked.
Definition after_completed (id operation ticket : N) (outcome : after_outcome) (value : world) :=
 RequestReceiver.deliver id value (RequestReceiver.pending_after operation ticket)
   (fun target payload => let '(operation,plugin,pending,result,error) := payload in
    acknowledged (TaskResult.interpret_result target
      (after_result_plan id operation plugin pending result error outcome))).
