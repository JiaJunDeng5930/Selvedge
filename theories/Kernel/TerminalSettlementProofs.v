From Stdlib Require Import String List Bool NArith.
From Selvedge.Programming Require OperationEvent TaskResult.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State Inputs History Tasks.
From Selvedge.Programming Require Import TaskChange.
From Selvedge.Kernel Require Import HookRules HookCallbacks TerminalSettlement.
Import ListNotations.
Open Scope list_scope.

(** A final after-hook completion keeps both the raw hook observation and its
    processed result. Archival never reopens the task or starts another hook. *)
Theorem final_after_completion_retires_its_archived_operation :
 forall owner current operations original plugin pending previous failed outcome,
 task_lifecycle current = Archived operations ->
 (match HookCallbacks.after_result_plan owner original plugin pending previous failed outcome with
  | TaskResult.WakeDemand _ => True | TaskResult.KeepDemand _ => False end) ->
 let next := TaskChange.apply (TaskResult.result_changes
   (HookCallbacks.after_result_plan owner original plugin pending previous failed outcome) current) current in
 let '(result,error) := match HookRules.after_apply previous outcome with
   | HookRules.ContinueResult result => (result,failed)
   | HookRules.RefuseResult code reason => (State.failure code reason,true) end in
 task_lifecycle next = Archived
   (filter (fun operation => negb (N.eqb (operation_id original) (operation_id operation))) operations) /\
 task_history next = task_history current ++
   [AfterReceipt owner (operation_id original) plugin (Inputs.after_json outcome);
    History.operation_result original result error].
Proof.
 intros owner current operations original plugin pending previous failed outcome ArchivedTask Terminal.
 destruct outcome;
 cbn [HookCallbacks.after_result_plan OperationEvent.after_checked OperationEvent.after_result
   OperationEvent.settle TaskResult.prefix_result HookRules.after_apply] in Terminal |- *;
 try (destruct pending; try contradiction).
 all: destruct current as [contract profile settings lifecycle history queued lineage parent cursor consumed];
   cbn in ArchivedTask; subst lifecycle;
   cbn [HookCallbacks.after_result_plan OperationEvent.after_checked OperationEvent.after_result
     HookRules.after_apply OperationEvent.settle TaskResult.prefix_result TaskResult.result_changes
     TaskResult.wake_after_result_changes TaskResult.promote_changes TaskChange.apply fold_left];
   split; try reflexivity; cbn; now rewrite <- app_assoc.
Qed.
