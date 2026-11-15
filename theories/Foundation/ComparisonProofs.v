From Stdlib Require Import List Bool.
From Selvedge.Foundation Require Comparison.

Lemma list_refl {A} (same : A -> A -> bool) :
 (forall value, same value value = true) ->
 forall values, Comparison.list same values values = true.
Proof.
 intros Refl values; induction values; cbn; [reflexivity|now rewrite Refl, IHvalues].
Qed.

Lemma option_refl {A} (same : A -> A -> bool) :
 (forall value, same value value = true) ->
 forall value, Comparison.option same value value = true.
Proof. intros Refl [value|]; cbn; auto. Qed.
