From Stdlib Require Import List.
From Selvedge.Kernel Require Import State DecisionComposition.
Import ListNotations.

Definition retains_reply_and_effects (before after : decision) : Prop :=
 decision_reply after = decision_reply before /\
 exists appended, decision_effects after = decision_effects before ++ appended.

Lemma retention_is_reflexive : forall current, retains_reply_and_effects current current.
Proof. intros; split; [reflexivity|]. exists []; now rewrite app_nil_r. Qed.

Lemma retention_is_transitive : forall before current after,
 retains_reply_and_effects before current -> retains_reply_and_effects current after ->
 retains_reply_and_effects before after.
Proof.
 intros before current after [Reply [first Effects]] [NextReply [rest NextEffects]].
 split; [now rewrite NextReply, Reply|].
 exists (first ++ rest); now rewrite NextEffects, Effects, app_assoc.
Qed.

Lemma following_retains_reply_and_effects : forall first second,
 retains_reply_and_effects first (follow first second).
Proof. intros; split; [reflexivity|]. exists (decision_effects second); reflexivity. Qed.

Lemma replacing_world_retains_reply_and_effects : forall current after,
 retains_reply_and_effects current
   (Decision after (decision_reply current) (decision_effects current)).
Proof. intros; split; [reflexivity|]. exists []; now rewrite app_nil_r. Qed.

Lemma a_retaining_fold_keeps_reply_and_effects : forall A (step : decision -> A -> decision),
 (forall current item, retains_reply_and_effects current (step current item)) ->
 forall items current, retains_reply_and_effects current (fold_left step items current).
Proof.
 intros A step Step items; induction items as [|item rest IH]; intro current; cbn.
 - apply retention_is_reflexive.
 - eapply retention_is_transitive; [apply Step|apply IH].
Qed.

Ltac derive_retention_contract :=
 first [apply retention_is_reflexive | apply following_retains_reply_and_effects
       | match goal with
         | |- retains_reply_and_effects ?before ?current =>
           let body := eval cbv beta zeta in current in
           change (retains_reply_and_effects before body);
           match body with context [match ?observed with _ => _ end] =>
             destruct observed; derive_retention_contract
           end
         end].

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
