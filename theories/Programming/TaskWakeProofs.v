From Stdlib Require Import List Bool NArith.
From Selvedge.Programming Require TaskChange TaskResult.
From Selvedge.Foundation Require Import RegistryProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Domain State.
From Selvedge.Programming Require Import TaskScope TaskScopeProofs TaskChangeProofs.
Import ListNotations.
Module C := Selvedge.Features.CompactionTypes.
Module F := Selvedge.Features.Domain.

Lemma promotion_retains_history : forall current,
 exists suffix, task_history (TaskResult.promote current) = task_history current ++ suffix.
Proof. intros; apply append_only_changes_retain_history. Qed.

Lemma waking_retains_history : forall current,
 exists suffix, task_history (TaskResult.wake_after_result current) = task_history current ++ suffix.
Proof. intros; apply append_only_changes_retain_history. Qed.

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

Lemma context_wake_preserves_the_task_registry : forall owner current value,
 world_tasks (TaskResult.mark_context_wake owner current value) = world_tasks value.
Proof.
 intros; unfold TaskResult.mark_context_wake.
 destruct (task_lifecycle current) as [phase operations|phase operations|phase operations|operations];
   try destruct phase; reflexivity.
Qed.

Lemma context_wake_preserves_every_task_lookup : forall owner current value selected,
 find_task selected (TaskResult.mark_context_wake owner current value) = find_task selected value.
Proof. intros; unfold find_task; now rewrite context_wake_preserves_the_task_registry. Qed.

Lemma context_wake_preserves_execution_frame : forall owner current value,
 world_sequence (TaskResult.mark_context_wake owner current value) = world_sequence value /\
 world_next_ticket (TaskResult.mark_context_wake owner current value) = world_next_ticket value /\
 world_environment (TaskResult.mark_context_wake owner current value) = world_environment value /\
 world_projects (TaskResult.mark_context_wake owner current value) = world_projects value.
Proof.
 intros; unfold TaskResult.mark_context_wake.
 destruct (task_lifecycle current) as [phase operations|phase operations|phase operations|operations];
   try destruct phase; repeat split; reflexivity.
Qed.

Lemma context_wake_keeps_the_entry_key : forall owner ticket pair,
 fst (TaskResult.wake_context_entry owner ticket pair) = fst pair.
Proof.
 intros owner ticket [id entry]. unfold TaskResult.wake_context_entry; cbn.
 destruct (N.eqb owner id); [|reflexivity].
 destruct (C.entry_job entry); try reflexivity; destruct (N.eqb ticket ticket0); reflexivity.
Qed.

Lemma context_wake_lookup_is_the_same_receiver : forall entries owner ticket,
 find (fun pair => N.eqb owner (fst pair)) (map (TaskResult.wake_context_entry owner ticket) entries) =
 option_map (TaskResult.wake_context_entry owner ticket) (find (fun pair => N.eqb owner (fst pair)) entries).
Proof.
 induction entries as [|first rest IH]; intros; [reflexivity|].
 cbn [map find]. rewrite context_wake_keeps_the_entry_key.
 destruct (N.eqb owner (fst first)); cbn; [reflexivity|apply IH].
Qed.

Theorem an_actual_wake_keeps_its_pending_context_demand :
 forall owner ticket revision purpose demand current entry value operations,
 (task_lifecycle current = Running (ObservingContext ticket revision) operations \/
  task_lifecycle current = Frozen (ObservingContext ticket revision) operations) ->
 find (fun pair => N.eqb owner (fst pair)) (C.maintenance_entries (F.feature_compaction (world_features value))) = Some (owner,entry) ->
 C.entry_job entry = C.AwaitingContext ticket purpose demand ->
 exists updated,
 find (fun pair => N.eqb owner (fst pair))
   (C.maintenance_entries (F.feature_compaction (world_features (TaskResult.mark_context_wake owner current value)))) = Some (owner,updated) /\
 C.entry_job updated = C.AwaitingContext ticket purpose true.
Proof.
 intros owner ticket revision purpose demand current entry value operations Status Found Pending.
 unfold TaskResult.mark_context_wake; destruct Status as [Status|Status]; rewrite Status;
   change (exists updated,
     find (fun pair => N.eqb owner (fst pair))
       (map (TaskResult.wake_context_entry owner ticket)
         (C.maintenance_entries (F.feature_compaction (world_features value)))) = Some (owner,updated) /\
     C.entry_job updated = C.AwaitingContext ticket purpose true);
   rewrite context_wake_lookup_is_the_same_receiver, Found; cbn [option_map];
   unfold TaskResult.wake_context_entry; rewrite N.eqb_refl, Pending, N.eqb_refl;
   eexists; split; reflexivity.
Qed.

Theorem a_retired_receiver_is_not_revived_by_wake : forall owner ticket id entry,
 C.entry_job entry = C.NoJob -> TaskResult.wake_context_entry owner ticket (id,entry) = (id,entry).
Proof. intros; unfold TaskResult.wake_context_entry; destruct (N.eqb owner id); [now rewrite H|reflexivity]. Qed.

Theorem stopped_wakes_issue_no_new_context_demand : forall owner current value phase operations,
 task_lifecycle current = Stopped phase operations -> TaskResult.mark_context_wake owner current value = value.
Proof. intros; unfold TaskResult.mark_context_wake; now rewrite H. Qed.

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
