From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json JsonObjects.
Import ListNotations.

Theorem equivalent_is_reflexive : forall value, equivalent value value = true.
Proof.
 fix recur 1. intro value. destruct value; cbn.
 - reflexivity.
 - apply Bool.eqb_reflx.
 - apply String.eqb_refl.
 - apply String.eqb_refl.
 - induction values as [|head rest IH]; cbn; [reflexivity|].
   rewrite recur, IH. reflexivity.
 - induction fields as [|[key value] rest IH]; cbn; [reflexivity|].
   rewrite String.eqb_refl. cbn. rewrite recur, IH. reflexivity.
Qed.
