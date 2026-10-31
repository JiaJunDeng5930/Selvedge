From Stdlib Require Import List NArith Bool.
From Selvedge.Programming Require TaskResult.
From Selvedge.Foundation Require Import RegistryProofs.
From Selvedge.Kernel Require Import Domain State.
From Selvedge.Programming Require Import TaskScope TaskScopeProofs TaskChange TaskChangeProofs.
From Selvedge.Kernel Require Import Tasks TaskChangesProofs Scheduler.
Import ListNotations.

Definition commit_changes_expression (id : N) (changes : task -> list TaskChange.edit) (before : world) := ltac:(
 let body := eval unfold Scheduler.commit_changes in (Scheduler.commit_changes id changes before) in
 derive_task_lookup_view constr:(Scheduler.commit_changes id changes before) body id before reduce_task_plan).

Lemma commit_changes_use_the_observed_owner : forall id changes before task,
 find_task id before = Some task ->
 Scheduler.commit_changes id changes before =
 put_task id (TaskChange.apply (changes task) task) before.
Proof. intros; rewrite commit_changes_expression, H; reflexivity. Qed.

Lemma continue_after_calls_expression : forall task,
 Scheduler.continue_after_calls task =
 let promoted := TaskResult.promote task in
 with_activity (if unseen_model_input promoted ||
   existsb Scheduler.process_needs_model (task_operations promoted) then WantsModel else Idle) promoted.
Proof.
 intros; unfold Scheduler.continue_after_calls, Scheduler.continue_after_calls_changes.
 rewrite apply_app; reflexivity.
Qed.
