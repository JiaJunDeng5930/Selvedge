From Stdlib Require Import String Bool.
From Selvedge.Foundation Require Import Json.
From Selvedge.Foundation Require ArgumentDeclaration.
Open Scope string_scope.
Module D := ArgumentDeclaration.
Lemma admitted_value_retains_its_constraint : forall (A : Set) (condition : A -> bool) value,
 D.present (D.admit condition value) = condition value.
Proof.
 intros. unfold D.admit. destruct (Bool.bool_dec (condition value) true) as [Valid|Invalid].
 - cbn [D.present]. symmetry; exact Valid.
 - cbn [D.present]. destruct (condition value); [contradict Invalid; reflexivity|reflexivity].
Qed.
Lemma check_text_reflects : forall constraints source,
 D.check (D.Textual (D.ConstrainedText constraints)) (JString source) = D.check_text constraints source.
Proof.
 intros; unfold D.check; cbn [D.Text D.decode D.decode_text]. apply admitted_value_retains_its_constraint.
Qed.
