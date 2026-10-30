From Stdlib Require Import List Bool NArith.
From Selvedge.Kernel Require Import Domain TaskChangeProofs OperationEvent Recovery.
Import ListNotations.
Open Scope list_scope.

Theorem recovery_retires_every_operation : forall owner current,
 task_operations (Recovery.recover_task owner current) = [].
Proof.
 intros owner [contract profile settings lifecycle history queued lineage parent cursor consumed].
 destruct lifecycle as [phase operations|phase operations|phase operations|operations];
 try destruct phase; destruct operations; reflexivity.
Qed.

Theorem recovery_retains_committed_history : forall owner current,
 exists suffix, task_history (Recovery.recover_task owner current) = task_history current ++ suffix.
Proof. intros; apply append_only_changes_retain_history. Qed.

(** Repeated crash recovery cannot append another failure receipt or reopen an
    interrupted invocation. The first application retires the matching stage. *)
Theorem task_recovery_is_idempotent : forall owner current,
 Recovery.recover_task owner (Recovery.recover_task owner current) = Recovery.recover_task owner current.
Proof.
 intros owner [contract profile settings lifecycle history queued lineage parent cursor consumed].
 destruct lifecycle as [phase operations|phase operations|phase operations|operations];
 try destruct phase; destruct operations;
 unfold Recovery.recover_task, Recovery.recovery_changes;
 cbn; repeat rewrite app_nil_r; reflexivity.
Qed.
