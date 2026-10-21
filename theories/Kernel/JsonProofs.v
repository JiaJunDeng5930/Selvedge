From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json.
Import ListNotations.

Theorem json_comparison_is_exact : forall left right,
 Json.equal left right = true -> left = right.
Proof.
 fix IH 1. intros left right H.
 destruct left as [|b|n|s|items|fields]; destruct right as [|b'|n'|s'|items'|fields'];
  cbn in H; try discriminate; try reflexivity.
 - destruct b, b'; cbn in H; try discriminate; reflexivity.
 - apply String.eqb_eq in H; subst; reflexivity.
 - apply String.eqb_eq in H; subst; reflexivity.
 - f_equal. revert items' H. induction items as [|item rest IHL]; intros items' H;
    destruct items' as [|item' rest']; cbn in H; try discriminate; try reflexivity.
   apply andb_true_iff in H as [Hitem Hrest]. f_equal; [apply IH; exact Hitem|apply IHL; exact Hrest].
 - f_equal. revert fields' H. induction fields as [|[key item] rest IHL]; intros fields' H;
    destruct fields' as [|[key' item'] rest']; cbn in H; try discriminate; try reflexivity.
   apply andb_true_iff in H as [Hhead Hrest]. apply andb_true_iff in Hhead as [Hkey Hitem].
   apply String.eqb_eq in Hkey. f_equal; [f_equal; [exact Hkey|apply IH; exact Hitem]|apply IHL; exact Hrest].
Qed.
Theorem json_comparison_reflexive : forall value, Json.equal value value = true.
Proof.
 fix IH 1. intros value; destruct value as [|b|n|s|items|fields]; cbn; try reflexivity.
 - destruct b; reflexivity.
 - apply String.eqb_refl.
 - apply String.eqb_refl.
 - induction items; cbn; [reflexivity|rewrite IH, IHitems; reflexivity].
 - induction fields as [|[key item] rest IHL]; cbn; [reflexivity|rewrite String.eqb_refl, IH, IHL; reflexivity].
Qed.
