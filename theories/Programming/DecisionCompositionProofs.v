From Stdlib Require Import List.
From Selvedge.Kernel Require Import State.
From Selvedge.Programming Require Import DecisionComposition.
Import ListNotations.

Theorem transformation_retains_reply : forall change current,
 decision_reply (transform change current) = decision_reply current.
Proof. reflexivity. Qed.

Definition retains_reply_and_effects (before after : decision) : Prop :=
 decision_reply after = decision_reply before /\
 exists appended, decision_effects after = decision_effects before ++ appended.

(** Every extension uses the same interpreter; no per-feature retention
    obligation is needed when a new maintenance step is composed. *)
Theorem maintenance_retains_reply_and_effects : forall maintenance current,
 retains_reply_and_effects current (run maintenance current).
Proof.
 intros; split; [reflexivity|].
 exists (appended_effects (maintenance (decision_world current) (decision_effects current))).
 reflexivity.
Qed.
