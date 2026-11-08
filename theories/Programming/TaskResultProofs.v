From Stdlib Require Import List Bool NArith.
From Selvedge.Programming Require TaskChange TaskResult.
From Selvedge.Foundation Require Import RegistryProofs.
From Selvedge.Kernel Require Import Domain State TaskWakeProofs.
From Selvedge.Programming Require Import TaskScope TaskChangeProofs.
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

   unfold find_task, put_task, with_tasks; cbn;
   eapply registry_replace_selected; exact (TaskScope.observed target).
Qed.
