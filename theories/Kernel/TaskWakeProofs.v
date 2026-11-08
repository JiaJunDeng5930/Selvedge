From Stdlib Require Import List Bool NArith.
From Selvedge.Programming Require TaskChange.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Domain State TaskWake.
From Selvedge.Programming Require Import TaskChangeProofs.
Import ListNotations.

Lemma promotion_retains_history : forall current,
 exists suffix, task_history (TaskWake.promote current) = task_history current ++ suffix.
Proof. intros; apply append_only_changes_retain_history. Qed.

Theorem an_actual_wake_keeps_its_pending_context_demand :
 forall current ticket revision purpose operations,
 (task_lifecycle current = Running (ObservingContext ticket revision (ForMaintenance purpose false)) operations \/
  task_lifecycle current = Frozen (ObservingContext ticket revision (ForMaintenance purpose false)) operations) ->
 TaskChange.apply (TaskWake.wake_after_result_changes current) current =
 with_activity (ObservingContext ticket revision (ForMaintenance purpose true)) current.
Proof.
 intros current ticket revision purpose operations [Status|Status];
 unfold TaskWake.wake_after_result_changes; rewrite Status; reflexivity.
Qed.
