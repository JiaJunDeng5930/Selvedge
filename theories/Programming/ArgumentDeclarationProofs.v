From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Foundation Require Import ComparisonProofs.
From Selvedge.Programming Require ArgumentDeclaration.
Open Scope string_scope.
Module D := ArgumentDeclaration.

Lemma same_text_format_refl : forall format, D.same_text_format format format = true.
Proof.
 induction format as [constraints|low high|low high|prefix suffix IH]; cbn [D.same_text_format].
 - unfold D.same_text_constraints.
   rewrite !N.eqb_refl, !Bool.eqb_reflx.
   rewrite ComparisonProofs.option_refl; [reflexivity|].
   apply ComparisonProofs.list_refl, String.eqb_refl.
 - now rewrite !N.eqb_refl.
 - now rewrite N.eqb_refl, (ComparisonProofs.option_refl N.eqb N.eqb_refl).
 - now rewrite String.eqb_refl, IH.
Qed.

Lemma same_refl : forall same_json,
 (forall value, same_json value value = true) ->
 forall declaration, D.same same_json declaration declaration = true.
Proof.
 intros same_json SameJson.
 fix Refl 1.
 intros declaration; destruct declaration; cbn [D.same]; try reflexivity.
 - apply Nat.eqb_refl.
 - destruct (Schema.kind_eq_dec kind kind); congruence.
 - apply SameJson.
 - apply same_text_format_refl.
 - now rewrite !N.eqb_refl.
 - now rewrite !Z.eqb_refl.
 - apply Refl.
 - now rewrite !N.eqb_refl, Refl.
 - induction properties as [|[[name required] field] rest IH]; cbn; [reflexivity|].
   now rewrite String.eqb_refl, Bool.eqb_reflx, Refl, IH.
 - induction properties as [|[[name required] field] rest IH]; cbn; [reflexivity|].
   now rewrite String.eqb_refl, Bool.eqb_reflx, Refl, IH.
 - induction alternatives as [|choice rest IH]; cbn; [reflexivity|].
   now rewrite Refl, IH.
Qed.
Lemma admitted_value_retains_its_constraint : forall (A : Set) (condition : A -> bool) value,
 D.present (D.admit condition value) = condition value.
Proof.
 intros. unfold D.admit, Refinement.admit. destruct (Bool.bool_dec (condition value) true) as [Valid|Invalid].
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
