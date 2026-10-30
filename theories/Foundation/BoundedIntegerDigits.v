From Stdlib Require Import Bool ZArith NArith Lia DecimalZ DecimalPos DecimalFacts List.
From Selvedge.Foundation Require Import NumbersProofs BoundedInteger BoundedIntegerProofs BoundedIntegerSemantics.
Open Scope Z_scope.

Lemma decimal_app_value left right :
 Z.of_uint (Decimal.app left right) =
 Z.of_uint left * 10 ^ Z.of_nat (Decimal.nb_digits right) + Z.of_uint right.
Proof.
 rewrite <-(DecimalFacts.rev_rev (Decimal.app left right)),
   <-(DecimalFacts.of_list_to_list (Decimal.rev (Decimal.app left right))).
 rewrite DecimalFacts.rev_spec, DecimalFacts.app_spec, List.rev_app_distr.
 rewrite <-!DecimalFacts.rev_spec, <-DecimalFacts.app_spec, DecimalFacts.of_list_to_list.
 unfold Z.of_uint; rewrite DecimalPos.Unsigned.of_lu_rev.
 unfold Decimal.app; rewrite DecimalPos.Unsigned.of_lu_revapp, !DecimalFacts.rev_rev.
 rewrite <-!DecimalPos.Unsigned.of_lu_rev, !DecimalFacts.rev_rev.
 rewrite N2Z.inj_add, N2Z.inj_mul, N2Z.inj_pow, decimal_unsigned_size, nat_N_Z.
 cbn [Z.of_N]; ring.
Qed.


Lemma iter_ten_power count value : Nat.iter count (Z.mul 10) value = value * 10 ^ Z.of_nat count.
Proof.
 revert value; induction count; intro value; cbn [Nat.iter]; [change (value = value * 1); ring|].
 rewrite Nat.iter_succ, IHcount, Nat2Z.inj_succ, Z.pow_succ_r by lia. ring.
Qed.


Lemma integer_scale_negative coefficient shift magnitude : shift < 0 ->
 (decimal_integer_magnitude coefficient 0 shift magnitude <-> coefficient = magnitude * 10 ^ (-shift)).
Proof.
 intro Negative. unfold decimal_integer_magnitude.
 replace (shift - 0) with shift by ring.
 replace (0 - shift) with (-shift) by ring.
 rewrite (Z.max_r shift 0) by lia. rewrite (Z.max_l (-shift) 0) by lia.
 rewrite Z.pow_0_r, Z.mul_1_r. tauto.
Qed.

Lemma integer_scale_nonnegative coefficient shift magnitude : 0 <= shift ->
 (decimal_integer_magnitude coefficient 0 shift magnitude <-> coefficient * 10 ^ shift = magnitude).
Proof.
 intro Nonnegative. unfold decimal_integer_magnitude.
 replace (shift - 0) with shift by ring.
 replace (0 - shift) with (-shift) by ring.
 rewrite (Z.max_l shift 0) by lia. rewrite (Z.max_r (-shift) 0) by lia.
 rewrite Z.pow_0_r, Z.mul_1_r. tauto.
Qed.

Lemma decimal_split_value numeral count :
  (count <= Decimal.nb_digits numeral)%nat ->
  Z.of_uint numeral =
    Z.of_uint (Decimal.del_tail count numeral) * 10 ^ Z.of_nat count +
    Z.of_uint (Decimal.del_head (Decimal.nb_digits numeral - count) numeral) /\
  0 <= Z.of_uint (Decimal.del_head (Decimal.nb_digits numeral - count) numeral) < 10 ^ Z.of_nat count.
Proof.
  intro count_bound. pose proof (DecimalFacts.app_del_tail_head count numeral count_bound) as joined.
  pose proof (DecimalFacts.nb_digits_del_head_sub numeral count count_bound) as size.
  split.
  - rewrite <-joined at 1. now rewrite decimal_app_value, size.
  - split; [apply decimal_value_nonnegative|].
    pose proof (decimal_value_below_power (Decimal.del_head (Decimal.nb_digits numeral - count) numeral)).
    now rewrite size in H.
Qed.
Theorem integral_magnitude_exact coefficient shift magnitude :
  1 - Z.of_nat (Decimal.nb_digits coefficient) <= shift ->
  (integral_magnitude coefficient shift = Some magnitude <->
   decimal_integer_magnitude (Z.of_uint coefficient) 0 shift magnitude).
Proof.
  intro window. unfold integral_magnitude. rewrite !decimal_width_count.
  destruct (Z.ltb_spec shift 0) as [negative|nonnegative].
  - assert (remove_bound : (Z.to_nat (-shift) <= Decimal.nb_digits coefficient)%nat).
    { apply Nat2Z.inj_le. rewrite Z2Nat.id by lia. lia. }
    destruct (decimal_split_value coefficient (Z.to_nat (-shift)) remove_bound) as [value bounds].
    rewrite Z2Nat.id in value,bounds by lia.
    rewrite integer_scale_negative by assumption.
    destruct (decimal_zero (Decimal.del_head (Decimal.nb_digits coefficient - Z.to_nat (-shift)) coefficient)) eqn:zero.
    + apply decimal_zero_value in zero. rewrite zero, Z.add_0_r in value.
      split; [intros [= <-]; assumption|]. intro scaled. f_equal.
      pose proof (Z.pow_pos_nonneg 10 (-shift) ltac:(lia) ltac:(lia)). nia.
    + split; [discriminate|]. intro scaled.
      pose proof (Z.pow_pos_nonneg 10 (-shift) ltac:(lia) ltac:(lia)) as positive.
      pose proof (Z.mod_unique (Z.of_uint coefficient) (10 ^ (-shift))
        (Z.of_uint (Decimal.del_tail (Z.to_nat (-shift)) coefficient))
        (Z.of_uint (Decimal.del_head (Decimal.nb_digits coefficient - Z.to_nat (-shift)) coefficient))
        (or_introl bounds) ltac:(nia)) as remainder.
      rewrite scaled, Z.mod_mul in remainder by lia.
      apply Bool.not_true_iff_false in zero. exfalso. apply zero, decimal_zero_value. exact remainder.
  - rewrite integer_scale_nonnegative by assumption.
    rewrite DecimalZ.of_uint_iter_D0, iter_ten_power, Z2Nat.id by assumption.
    split; intros; congruence.
Qed.

Lemma decimal_tail_width numeral remove :
  (remove <= Decimal.nb_digits numeral)%nat ->
  Decimal.nb_digits (Decimal.del_tail remove numeral) = (Decimal.nb_digits numeral - remove)%nat.
Proof.
  intro bounded. unfold Decimal.del_tail. rewrite DecimalFacts.nb_digits_rev.
  pose proof (DecimalFacts.nb_digits_del_head_sub (Decimal.rev numeral)
    (Decimal.nb_digits numeral - remove) ltac:(rewrite DecimalFacts.nb_digits_rev; lia)) as size.
  rewrite DecimalFacts.nb_digits_rev in size.
  replace (Decimal.nb_digits numeral - (Decimal.nb_digits numeral - remove))%nat with remove in size by lia.
  exact size.
Qed.
Lemma decimal_append_width left right :
  Decimal.nb_digits (Decimal.app left right) = (Decimal.nb_digits left + Decimal.nb_digits right)%nat.
Proof. rewrite !DecimalFacts.nb_digits_spec, DecimalFacts.app_spec, List.length_app. reflexivity. Qed.
Theorem integral_magnitude_digit_budget coefficient fractional exponent :
  (1 <= Decimal.nb_digits coefficient)%nat ->
  fractional + 1 - Z.of_nat (Decimal.nb_digits coefficient) <= exponent <=
    fractional + 16 - Z.of_nat (Decimal.nb_digits coefficient) ->
  (if (exponent - fractional <? 0)%Z then
     1 <= Decimal.nb_digits (Decimal.del_tail (Z.to_nat (fractional - exponent)) coefficient) <= 16
   else 1 <= Decimal.nb_digits (Decimal.app coefficient (Nat.iter (Z.to_nat (exponent - fractional)) Decimal.D0 Decimal.Nil)) <= 16)%nat.
Proof.
  intros width window. destruct (Z.ltb_spec (exponent - fractional) 0) as [negative|nonnegative].
  - assert (remove : (Z.to_nat (fractional - exponent) < Decimal.nb_digits coefficient)%nat).
    { apply Nat2Z.inj_lt. rewrite Z2Nat.id by lia. lia. }
    rewrite decimal_tail_width by lia. split; apply Nat2Z.inj_le;
      rewrite Nat2Z.inj_sub by lia; cbn; rewrite Z2Nat.id by lia; lia.
  - rewrite decimal_append_width, DecimalFacts.nb_digits_iter_D0. cbn [Decimal.nb_digits].
    rewrite Nat.add_0_r. split; apply Nat2Z.inj_le;
      rewrite Nat2Z.inj_add; cbn; rewrite Z2Nat.id by lia; lia.
Qed.
