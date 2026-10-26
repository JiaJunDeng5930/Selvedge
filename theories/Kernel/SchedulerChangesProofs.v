From Stdlib Require Import List NArith Bool.
From Selvedge.Foundation Require Import RegistryProofs.
From Selvedge.Kernel Require Import Domain State TaskScope TaskScopeProofs TaskChange TaskChangeProofs Tasks TaskChangesProofs Scheduler.
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
 let promoted := Tasks.promote task in
 with_activity (if unseen_model_input promoted ||
   existsb Scheduler.process_needs_model (task_operations promoted) then WantsModel else Idle) promoted.
Proof.
 intros; unfold Scheduler.continue_after_calls, Scheduler.continue_after_calls_changes.
 rewrite apply_app; reflexivity.
Qed.

Theorem scheduled_field_changes_preserve_unrelated_tasks : forall id changes before other,
 id <> other ->
 find_task other (Scheduler.commit_changes id changes before) = find_task other before.
Proof.
 intros id changes before other Different.
 rewrite commit_changes_expression.
 destruct (find_task id before); [|reflexivity].
 unfold find_task, put_task, with_tasks; cbn.
 now apply registry_replace_other.
Qed.

Theorem scheduled_field_changes_preserve_the_world_frame : forall id changes before,
 let after := Scheduler.commit_changes id changes before in
 world_sequence after = world_sequence before /\
 world_next_ticket after = world_next_ticket before /\
 world_environment after = world_environment before /\
 world_projects after = world_projects before /\
 world_features after = world_features before /\
 List.length (world_tasks after) = List.length (world_tasks before).
Proof.
 intros id changes before; unfold Scheduler.commit_changes.
 destruct (TaskScope.select id before) as [target|].
 - exact (a_field_plan_preserves_the_world_frame before
     (TaskChange.Plan before target (changes (TaskScope.selected target)))).
 - repeat split; reflexivity.
Qed.
