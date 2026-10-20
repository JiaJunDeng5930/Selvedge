From Stdlib Require Import String List Bool Arith Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction.Interactive Require Import Bounds Builtins Expression Sources.
Import ListNotations.
Open Scope string_scope.
Definition budget_safe{A}(computation:metered A):Prop:=forall initial,(snd(computation initial)<=initial)%nat.
Lemma return_budget_safe{A}(value:A):budget_safe(met_return value).
Proof. intro initial;cbn;lia. Qed.
Lemma lift_budget_safe{A}(value:outcome A):budget_safe(met_lift value).
Proof. intro initial;cbn;lia. Qed.
Lemma charge_budget_safe cost:budget_safe(met_charge cost).
Proof. intro initial;unfold met_charge;destruct(Nat.leb cost initial);cbn;lia. Qed.
Lemma bind_budget_safe{A B}(first:metered A)(next:A->metered B):
 budget_safe first->(forall value,budget_safe(next value))->budget_safe(met_bind first next).
Proof.
 intros Hfirst Hnext initial;unfold met_bind.
 specialize(Hfirst initial);destruct(first initial)as[[value|reason]remaining]eqn:E;cbn in *.
 - specialize(Hnext value remaining);lia.
 - exact Hfirst.
Qed.
Ltac simple_budget:=first[apply return_budget_safe|apply lift_budget_safe|apply charge_budget_safe|unfold met_fail;apply lift_budget_safe].
Lemma insert_budget_safe path descending value xs:budget_safe(insert_metered path descending value xs).
Proof.
 induction xs as[|x xs IH];cbn[insert_metered];[apply return_budget_safe|].
 apply bind_budget_safe;[apply charge_budget_safe|intros[]].
 apply bind_budget_safe;[apply lift_budget_safe|intro order].
 destruct order;cbn;try destruct descending.
 all:first[apply return_budget_safe|apply bind_budget_safe;[exact IH|intro;apply return_budget_safe]].
Qed.
Lemma sort_budget_safe path descending xs:budget_safe(sort_metered path descending xs).
Proof.
 induction xs as[|x xs IH];cbn[sort_metered];[apply return_budget_safe|].
 apply bind_budget_safe;[exact IH|intro;apply insert_budget_safe].
Qed.
Lemma sum_budget_safe path xs acc:budget_safe(sum_metered path xs acc).
Proof.
 revert acc;induction xs as[|x xs IH];intro acc;cbn[sum_metered];[apply return_budget_safe|].
 apply bind_budget_safe;[apply charge_budget_safe|intros[]].
 apply bind_budget_safe;[apply lift_budget_safe|intro d].
 apply bind_budget_safe;[apply lift_budget_safe|intro n;apply IH].
Qed.
Lemma filter_budget_safe path wanted xs:budget_safe(filter_metered path wanted xs).
Proof.
 induction xs as[|x xs IH];cbn[filter_metered];[apply return_budget_safe|].
 apply bind_budget_safe;[apply charge_budget_safe|intros[]].
 apply bind_budget_safe;[exact IH|intro values;apply return_budget_safe].
Qed.
Ltac prove_budget:=
 repeat first[simple_budget|apply sort_budget_safe|apply sum_budget_safe|apply filter_budget_safe|
  apply bind_budget_safe;[prove_budget|intro]|
  match goal with |-budget_safe(if ?test then _ else _)=>destruct test end|
  match goal with |-budget_safe(match ?value with _=>_ end)=>destruct value end];
 try simple_budget.
Lemma builtin_body_budget_safe kind args:budget_safe(builtin_body kind args).
Proof. unfold builtin_body;destruct kind;prove_budget. Qed.
Lemma builtin_budget_safe name args:budget_safe(builtin name args).
Proof. unfold builtin;apply bind_budget_safe;[apply charge_budget_safe|intros[]].
 apply bind_budget_safe;[apply lift_budget_safe|intro;apply builtin_body_budget_safe]. Qed.
Theorem false_and_does_not_evaluate_rhs budget environment rhs:
 evaluate(S(S(S(S(S budget)))))environment(Binary "&&"(Value(JBool false))rhs)=(Good(JBool false),budget).
Proof. destruct budget;reflexivity. Qed.
Theorem true_or_does_not_evaluate_rhs budget environment rhs:
 evaluate(S(S(S(S(S budget)))))environment(Binary "||"(Value(JBool true))rhs)=(Good(JBool true),budget).
Proof. destruct budget;reflexivity. Qed.
