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

Lemma nonblank_text_has_content : forall value : D.denote D.nonblank_text,
 Utf8.nonblank (proj1_sig value) = true.
Proof.
 intros [value Valid]; cbn. unfold D.nonblank_text, D.check_text in Valid; cbn in Valid.
 destruct (Utf8.scalar_count value); try discriminate.
 repeat rewrite Bool.andb_true_iff in Valid; cbn in Valid; tauto.
Qed.
