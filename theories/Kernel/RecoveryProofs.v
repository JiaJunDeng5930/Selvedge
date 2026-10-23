From Stdlib Require Import String List Bool NArith.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain History Recovery.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Open Scope record_set.

Theorem recovered_phase_is_idempotent : forall phase,
 Recovery.recovered_phase (Recovery.recovered_phase phase) = Recovery.recovered_phase phase.
Proof.
 intros phase. destruct phase; reflexivity.
Qed.

Local Lemma lifecycle_after_lifecycle_update : forall state task,
 task_lifecycle (Domain.with_lifecycle state task) = state.
Proof.
 intros state task. unfold Domain.with_lifecycle.
 change (task_lifecycle (task <| task_lifecycle ::= (fun _ => state) |>) = state).
 exact (@set_get Domain.task lifecycle task_lifecycle _ (fun _ => state) task).
Qed.

Local Lemma history_after_history_update : forall history task,
 task_history (Domain.with_history history task) = history.
Proof.
 intros history task. unfold Domain.with_history.
 change (task_history (task <| task_history ::= (fun _ => history) |>) = history).
 exact (@set_get Domain.task (list message) task_history _ (fun _ => history) task).
Qed.

Local Lemma history_after_lifecycle_update : forall state task,
 task_history (Domain.with_lifecycle state task) = task_history task.
Proof.
 intros state [contract profile settings lifecycle history queued lineage side_parent side_cursor model_cursor].
 reflexivity.
Qed.

Local Lemma recovery_lifecycle_projection : forall owner task,
 task_lifecycle (Recovery.recover_task owner task) =
   let pending := negb (Nat.eqb (List.length (task_operations task)) 0) in
   let phase := Recovery.recovered_phase (task_activity task) in
   let ready := match phase with Idle => if pending then WantsModel else Idle | other => other end in
   match task_lifecycle task with
   | Running _ _ => Running ready []
   | Frozen _ _ => Frozen ready []
   | Stopped _ _ => Stopped ready []
   | Archived _ => (Archived [])
   end.
Proof.
 intros owner task.
 unfold Recovery.recover_task.
 rewrite lifecycle_after_lifecycle_update. reflexivity.
Qed.

Local Lemma recovery_history_projection : forall owner task,
 task_history (Recovery.recover_task owner task) =
   History.close_operations "outcome_unknown"
     "The external operation may already have run. Its side effects cannot be inferred or undone; it will not be repeated automatically."
     task ++ Recovery.recovery_receipts owner (task_activity task).
Proof.
 intros owner task. unfold Recovery.recover_task.
 rewrite history_after_lifecycle_update, history_after_history_update. reflexivity.
Qed.

Theorem recovery_receipts_are_not_replayed : forall owner task,
 Recovery.recovery_receipts owner (task_activity (Recovery.recover_task owner task)) = [].
Proof.
 intros owner [contract profile settings lifecycle history queued lineage side_parent side_cursor model_cursor].
 unfold Domain.task_activity.
 rewrite recovery_lifecycle_projection.
 destruct lifecycle as [phase operations | phase operations | phase operations |].
 - destruct phase; cbn [Domain.task_lifecycle Domain.task_activity Domain.task_operations Recovery.recovered_phase
     Recovery.recovery_receipts].
   all: try destruct (Nat.eqb (List.length operations) 0); reflexivity.
 - destruct phase; cbn [Domain.task_lifecycle Domain.task_activity Domain.task_operations Recovery.recovered_phase
     Recovery.recovery_receipts].
   all: try destruct (Nat.eqb (List.length operations) 0); reflexivity.
 - destruct phase; cbn [Domain.task_lifecycle Domain.task_activity Domain.task_operations Recovery.recovered_phase
     Recovery.recovery_receipts].
   all: try destruct (Nat.eqb (List.length operations) 0); reflexivity.
 - cbn [Domain.task_lifecycle Domain.task_activity Domain.task_operations Recovery.recovered_phase
     Recovery.recovery_receipts]. reflexivity.
Qed.

Theorem task_recovery_lifecycle_is_idempotent : forall owner task,
 task_lifecycle (Recovery.recover_task owner (Recovery.recover_task owner task)) =
   task_lifecycle (Recovery.recover_task owner task).
Proof.
 intros owner [contract profile settings lifecycle history queued lineage side_parent side_cursor model_cursor].
 rewrite (recovery_lifecycle_projection owner (Recovery.recover_task owner
   (Task contract profile settings lifecycle history queued lineage side_parent side_cursor model_cursor))).
 unfold Domain.task_activity, Domain.task_operations.
 rewrite (recovery_lifecycle_projection owner
   (Task contract profile settings lifecycle history queued lineage side_parent side_cursor model_cursor)).
 destruct lifecycle as [phase operations | phase operations | phase operations |].
 - destruct phase; cbn [Recovery.recovered_phase Domain.task_lifecycle Domain.task_activity Domain.task_operations].
   all: try destruct (Nat.eqb (List.length operations) 0); reflexivity.
 - destruct phase; cbn [Recovery.recovered_phase Domain.task_lifecycle Domain.task_activity Domain.task_operations].
   all: try destruct (Nat.eqb (List.length operations) 0); reflexivity.
 - destruct phase; cbn [Recovery.recovered_phase Domain.task_lifecycle Domain.task_activity Domain.task_operations].
   all: try destruct (Nat.eqb (List.length operations) 0); reflexivity.
 - cbn [Recovery.recovered_phase Domain.task_lifecycle Domain.task_activity Domain.task_operations]. reflexivity.
Qed.

Theorem task_recovery_history_is_idempotent : forall owner task,
 task_history (Recovery.recover_task owner (Recovery.recover_task owner task)) =
   task_history (Recovery.recover_task owner task).
Proof.
 intros owner [contract profile settings lifecycle history queued lineage side_parent side_cursor model_cursor].
 rewrite (recovery_history_projection owner (Recovery.recover_task owner
   (Task contract profile settings lifecycle history queued lineage side_parent side_cursor model_cursor))).
 rewrite (recovery_history_projection owner
   (Task contract profile settings lifecycle history queued lineage side_parent side_cursor model_cursor)).
 assert (Hoperations : task_operations (Recovery.recover_task owner
   (Task contract profile settings lifecycle history queued lineage side_parent side_cursor model_cursor)) = []).
 { unfold Domain.task_operations. rewrite recovery_lifecycle_projection.
   destruct lifecycle; cbn [Domain.task_lifecycle Domain.task_operations]; reflexivity. }
 unfold History.close_operations. rewrite Hoperations.
 rewrite recovery_receipts_are_not_replayed. simpl.
 repeat rewrite app_nil_r. repeat rewrite app_assoc. reflexivity.
Qed.
