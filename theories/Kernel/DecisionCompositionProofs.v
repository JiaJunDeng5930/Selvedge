From Stdlib Require Import List.
From Selvedge.Kernel Require Import State DecisionComposition.
Import ListNotations.

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

(** Branches can share an emission contract. This does not propagate it
    through a later world update: that update must preserve the receivers. *)
Definition emissions_satisfy (ready : effect -> world -> Prop) (current : decision) :=
 forall emitted, In emitted (decision_effects current) ->
 ready emitted (decision_world current).

Lemma empty_effects_satisfy : forall ready current,
 decision_effects current = [] -> emissions_satisfy ready current.
Proof. intros ready current Empty emitted Member; rewrite Empty in Member; contradiction. Qed.

(** Derive guarded propagation from the actual producer. The leaf solver
    supplies already proved contracts; no branch tree is maintained here. *)
Ltac derive_emission_contract leaves :=
 first [solve [leaves]
       | apply empty_effects_satisfy; reflexivity
       | match goal with
         | |- emissions_satisfy ?ready ?current =>
           let body := eval cbv beta zeta in current in
           change (emissions_satisfy ready body);
           match body with context [match ?observed with _ => _ end] =>
             destruct observed; derive_emission_contract leaves
           end
         end].
