From Stdlib Require Import List Bool NArith.
From Selvedge.Programming Require TaskChange TaskResult.
From Selvedge.Foundation Require Import RegistryProofs.
From Selvedge.Kernel Require Import Domain State TaskWakeProofs.
From Selvedge.Programming Require Import TaskScope TaskScopeProofs TaskChangeProofs.
Import ListNotations.

Lemma prefixed_results_apply_the_prefix_once : forall prefix update current,
 TaskChange.apply (TaskResult.result_changes (TaskResult.prefix_result prefix update) current) current =
 TaskChange.apply (TaskResult.result_changes update (TaskChange.apply prefix current)) (TaskChange.apply prefix current).
Proof.
 intros; destruct update; cbn [TaskResult.prefix_result TaskResult.result_changes];
   repeat rewrite TaskChangeProofs.apply_app; reflexivity.
Qed.

Lemma prefixed_results_retain_their_history_record : forall messages update current,
 exists suffix,
 task_history (TaskChange.apply
   (TaskResult.result_changes (TaskResult.prefix_result [TaskChange.AppendHistory messages] update) current) current) =
 task_history current ++ messages ++ suffix.
Proof.
 intros messages update current; rewrite prefixed_results_apply_the_prefix_once.
 destruct (append_only_changes_retain_history (TaskResult.result_changes update (append_history messages current))
   (append_history messages current)) as [suffix Kept].
 exists suffix; change (task_history (TaskChange.apply
   (TaskResult.result_changes update (append_history messages current)) (append_history messages current)) =
   task_history current ++ messages ++ suffix).
 rewrite Kept; change ((task_history current ++ messages) ++ suffix = task_history current ++ messages ++ suffix).
 now rewrite app_assoc.
Qed.

Theorem interpreted_results_keep_their_exact_task_update : forall before target update,
 find_task (TaskScope.owner target) (@TaskResult.interpret_result before target update) =
 Some (TaskChange.apply (TaskResult.result_changes update (TaskScope.selected target)) (TaskScope.selected target)).
Proof.
 intros; unfold TaskResult.interpret_result, TaskResult.apply_result.
 destruct update; rewrite ?context_wake_preserves_every_task_lookup;
   unfold find_task, put_task, with_tasks; cbn;
   eapply registry_replace_selected; exact (TaskScope.observed target).
Qed.

Lemma commit_result_expression : forall id update before,
 TaskResult.commit_result id update before =
 match find_task id before with
 | Some current => TaskResult.apply_result id current (update current) before
 | None => before end.
Proof.
 intros. unfold TaskResult.commit_result.
 pattern (TaskScope.select id before) at 1.
 apply selected_reference_elimination.
 - intros reference Owner.
   pose proof (TaskScope.observed reference) as Selected; rewrite Owner in Selected.
   rewrite Selected. unfold TaskResult.interpret_result. now rewrite Owner.
 - intros Missing. now rewrite Missing.
Qed.
