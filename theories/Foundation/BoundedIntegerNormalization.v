From Stdlib Require Import String Bool ZArith NArith Lia DecimalString DecimalFacts DecimalPos.
From Selvedge.Foundation Require Import Numbers BoundedInteger BoundedIntegerSemantics.
Open Scope Z_scope.

Lemma decimal_nzhead_value numeral :
 Z.of_uint (Decimal.nzhead numeral) = Z.of_uint numeral.
Proof.
 induction numeral; cbn [Decimal.nzhead]; try reflexivity.
 rewrite (decimal_value_head (Decimal.D0 numeral)).
 cbn [DecimalPos.Unsigned.hd DecimalPos.Unsigned.tl Z.of_N]. nia.
Qed.

Theorem coefficient_normalization coefficient numeral :
 NilZero.uint_of_string coefficient = Some numeral ->
 (without_leading_zeroes coefficient = EmptyString /\ Z.of_uint numeral = 0) \/
 exists normal,
   without_leading_zeroes coefficient = NilEmpty.string_of_uint normal /\
   NilZero.uint_of_string (NilEmpty.string_of_uint normal) = Some normal /\
   canonical_decimal normal /\
   0 < Z.of_uint normal /\
   Z.of_uint normal = Z.of_uint numeral /\
   (0 < String.length (NilEmpty.string_of_uint normal))%nat.
Proof.
 intros parsed. apply NilZero.sus in parsed. subst coefficient.
 rewrite remove_leading_zeroes_unsigned.
 remember (Decimal.nzhead numeral) as normal eqn:normalized.
 assert (same_value : Z.of_uint normal = Z.of_uint numeral).
 { rewrite normalized. apply decimal_nzhead_value. }
 destruct (String.eqb (NilEmpty.string_of_uint normal) EmptyString) eqn:empty.
 - apply String.eqb_eq in empty. left. split; [assumption|].
   assert (normal_nil : normal = Decimal.Nil) by (destruct normal; cbn in empty; congruence).
   rewrite normal_nil in same_value. cbn in same_value. lia.
 - apply String.eqb_neq in empty.
   assert (normal_nonempty : normal <> Decimal.Nil) by (intros ->; contradiction).
   assert (normal_canonical : canonical_decimal normal).
   { pose proof (unsigned_normal_form_canonical numeral) as canonical.
     rewrite DecimalFacts.unorm_nzhead in canonical by (rewrite <- normalized; assumption).
     now rewrite <- normalized in canonical. }
   assert (normal_head_positive : (0 < DecimalPos.Unsigned.hd normal)%N).
   { destruct normal_canonical as [zero|positive]; [|assumption].
     exfalso. apply (DecimalFacts.nzhead_nonzero numeral Decimal.Nil).
     now rewrite <- normalized. }
   right. exists normal. repeat split; try assumption.
   + replace (NilEmpty.string_of_uint normal) with (NilZero.string_of_uint normal)
       by (destruct normal; contradiction || reflexivity).
     now apply NilZero.usu.
   + now apply decimal_positive_head_value.
   + destruct (NilEmpty.string_of_uint normal); cbn; [contradiction|lia].
Qed.
