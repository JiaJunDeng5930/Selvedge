From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json.
Import ListNotations.

Theorem equal_reflects_equality : forall left right,
  equal left right = true -> left = right.
Proof.
  fix recur 1.
  intros left right. destruct left; destruct right; cbn; try discriminate; try congruence.
  - intro H. apply Bool.eqb_prop in H. now subst.
  - intro H. apply String.eqb_eq in H. now subst.
  - intro H. apply String.eqb_eq in H. now subst.
  - revert values0. induction values as [|head rest IH]; intros [|other tail]; cbn; try discriminate.
    + reflexivity.
    + intro H. apply andb_true_iff in H as [same remaining].
      apply recur in same. apply IH in remaining. inversion remaining. now subst.
  - revert fields0. induction fields as [|[key value] rest IH]; intros [|[other replacement] tail]; cbn; try discriminate.
    + reflexivity.
    + intro H. repeat rewrite andb_true_iff in H. destruct H as [[keys values] remaining].
      apply String.eqb_eq in keys. apply recur in values. apply IH in remaining. inversion remaining. now subst.
Qed.

Theorem equal_is_reflexive : forall value, equal value value = true.
Proof.
  fix recur 1. intro value. destruct value; cbn.
  - reflexivity.
  - apply Bool.eqb_reflx.
  - apply String.eqb_refl.
  - apply String.eqb_refl.
  - induction values as [|head rest IH]; cbn; [reflexivity|]. rewrite recur,IH. reflexivity.
  - induction fields as [|[key value] rest IH]; cbn; [reflexivity|].
    rewrite String.eqb_refl,recur,IH. reflexivity.
Qed.

Theorem equal_specification : forall left right, equal left right = true <-> left = right.
Proof.
  split; [apply equal_reflects_equality|].
  intro H; subst. apply equal_is_reflexive.
Qed.
