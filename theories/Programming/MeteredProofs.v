From Stdlib Require Import Arith Lia.
From Selvedge.Programming Require Import Outcome Metered.

Definition budget_safe{A}(computation:metered A):Prop:=forall initial,(snd(computation initial)<=initial)%nat.
Lemma return_budget_safe{A}(value:A):budget_safe(met_return value).
Proof. intro initial;cbn;lia. Qed.
Lemma lift_budget_safe{A}(value:outcome A):budget_safe(met_lift value).
Proof. intro initial;cbn;lia. Qed.
Lemma bind_budget_safe{A B}(first:metered A)(next:A->metered B):
 budget_safe first->(forall value,budget_safe(next value))->budget_safe(met_bind first next).
Proof.
 intros Hfirst Hnext initial;unfold met_bind.
 specialize(Hfirst initial);destruct(first initial)as[[value|reason]remaining]eqn:E;cbn in *.
 - specialize(Hnext value remaining);lia.
 - exact Hfirst.
Qed.
