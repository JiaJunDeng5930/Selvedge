From Stdlib Require Import List Bool NArith.
From Selvedge.Programming Require TaskChange.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Domain State TaskWake.
From Selvedge.Programming Require Import TaskChangeProofs.
Import ListNotations.
Module C := Selvedge.Features.CompactionTypes.
Module F := Selvedge.Features.Domain.

Lemma promotion_retains_history : forall current,
 exists suffix, task_history (TaskWake.promote current) = task_history current ++ suffix.
Proof. intros; apply append_only_changes_retain_history. Qed.

Lemma waking_retains_history : forall current,
 exists suffix, task_history (TaskWake.wake_after_result current) = task_history current ++ suffix.
Proof. intros; apply append_only_changes_retain_history. Qed.

Lemma context_wake_preserves_the_task_registry : forall owner current value,
 world_tasks (TaskWake.mark_context_wake owner current value) = world_tasks value.
Proof.
 intros; unfold TaskWake.mark_context_wake.
 destruct (task_lifecycle current) as [phase operations|phase operations|phase operations|operations];
   try destruct phase; reflexivity.
Qed.

Lemma context_wake_preserves_every_task_lookup : forall owner current value selected,
 find_task selected (TaskWake.mark_context_wake owner current value) = find_task selected value.
Proof. intros; unfold find_task; now rewrite context_wake_preserves_the_task_registry. Qed.

Lemma context_wake_preserves_execution_frame : forall owner current value,
 world_sequence (TaskWake.mark_context_wake owner current value) = world_sequence value /\
 world_next_ticket (TaskWake.mark_context_wake owner current value) = world_next_ticket value /\
 world_environment (TaskWake.mark_context_wake owner current value) = world_environment value /\
 world_projects (TaskWake.mark_context_wake owner current value) = world_projects value.
Proof.
 intros; unfold TaskWake.mark_context_wake.
 destruct (task_lifecycle current) as [phase operations|phase operations|phase operations|operations];
   try destruct phase; repeat split; reflexivity.
Qed.

Lemma context_wake_keeps_the_entry_key : forall owner ticket pair,
 fst (TaskWake.wake_context_entry owner ticket pair) = fst pair.
Proof.
 intros owner ticket [id entry]. unfold TaskWake.wake_context_entry; cbn.
 destruct (N.eqb owner id); [|reflexivity].
 destruct (C.entry_job entry); try reflexivity; destruct (N.eqb ticket ticket0); reflexivity.
Qed.

Lemma context_wake_lookup_is_the_same_receiver : forall entries owner ticket,
 find (fun pair => N.eqb owner (fst pair)) (map (TaskWake.wake_context_entry owner ticket) entries) =
 option_map (TaskWake.wake_context_entry owner ticket) (find (fun pair => N.eqb owner (fst pair)) entries).
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
   (C.maintenance_entries (F.feature_compaction (world_features (TaskWake.mark_context_wake owner current value)))) = Some (owner,updated) /\
 C.entry_job updated = C.AwaitingContext ticket purpose true.
Proof.
 intros owner ticket revision purpose demand current entry value operations Status Found Pending.
 unfold TaskWake.mark_context_wake; destruct Status as [Status|Status]; rewrite Status;
   change (exists updated,
     find (fun pair => N.eqb owner (fst pair))
       (map (TaskWake.wake_context_entry owner ticket)
         (C.maintenance_entries (F.feature_compaction (world_features value)))) = Some (owner,updated) /\
     C.entry_job updated = C.AwaitingContext ticket purpose true);
   rewrite context_wake_lookup_is_the_same_receiver, Found; cbn [option_map];
   unfold TaskWake.wake_context_entry; rewrite N.eqb_refl, Pending, N.eqb_refl;
   eexists; split; reflexivity.
Qed.

Theorem a_retired_receiver_is_not_revived_by_wake : forall owner ticket id entry,
 C.entry_job entry = C.NoJob -> TaskWake.wake_context_entry owner ticket (id,entry) = (id,entry).
Proof. intros; unfold TaskWake.wake_context_entry; destruct (N.eqb owner id); [now rewrite H|reflexivity]. Qed.

Theorem stopped_wakes_issue_no_new_context_demand : forall owner current value phase operations,
 task_lifecycle current = Stopped phase operations -> TaskWake.mark_context_wake owner current value = value.
Proof. intros; unfold TaskWake.mark_context_wake; now rewrite H. Qed.
