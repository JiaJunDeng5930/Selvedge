From Stdlib Require Import String Ascii Bool ZArith Lia.
From Selvedge.Foundation Require Import Numbers NumbersProofs BoundedInteger.
Open Scope Z_scope.

Theorem within_safe_integer_spec value :
  within_safe_integer value = true <->
  - safe_integer_limit <= value <= safe_integer_limit.
Proof.
  unfold within_safe_integer. rewrite Bool.andb_true_iff, !Z.leb_le. tauto.
Qed.

(* Cross multiplication gives the ordinary mathematical meaning of decimal
   scaling without rational arithmetic or a decoder-dependent interpretation.
   Both powers have nonnegative exponents, even for enormous negative shifts. *)
Definition decimal_integer_magnitude
    (coefficient fractional exponent magnitude : Z) : Prop :=
  coefficient * 10 ^ Z.max (exponent - fractional) 0 =
  magnitude * 10 ^ Z.max (fractional - exponent) 0.

(* A nonzero coefficient with [width] decimal digits can denote a positive
   integer with at most [capacity] digits only inside this exponent window.
   This is independent of parsing, string comparison, and the decoder. *)
Theorem decimal_exponent_window_complete coefficient width fractional exponent magnitude capacity :
  1 <= width ->
  1 <= capacity ->
  10 ^ (width - 1) <= coefficient < 10 ^ width ->
  1 <= magnitude < 10 ^ capacity ->
  decimal_integer_magnitude coefficient fractional exponent magnitude ->
  fractional + 1 - width <= exponent <= fractional + capacity - width.
Proof.
  intros width_positive capacity_positive [coefficient_lower coefficient_upper]
    [magnitude_positive magnitude_upper] scaling.
  unfold decimal_integer_magnitude in scaling.
  destruct (Z_le_gt_dec fractional exponent) as [positive_shift|negative_shift].
  - rewrite Z.max_l in scaling by lia.
    rewrite Z.max_r in scaling by lia.
    rewrite Z.pow_0_r, Z.mul_1_r in scaling.
    split; [lia|].
    destruct (Z_le_gt_dec exponent (fractional + capacity - width)); [assumption|].
    assert (power_positive : 0 < 10 ^ (exponent - fractional))
      by (apply Z.pow_pos_nonneg; lia).
    assert (power_bound : 10 ^ capacity <= 10 ^ ((width - 1) + (exponent - fractional)))
      by (apply Z.pow_le_mono_r; lia).
    rewrite Z.pow_add_r in power_bound by lia.
    nia.
  - rewrite Z.max_r in scaling by lia.
    rewrite Z.max_l in scaling by lia.
    rewrite Z.pow_0_r, Z.mul_1_r in scaling.
    assert (power_positive : 0 < 10 ^ (fractional - exponent))
      by (apply Z.pow_pos_nonneg; lia).
    split.
    + destruct (Z_le_gt_dec (fractional + 1 - width) exponent); [assumption|].
      assert (power_bound : 10 ^ width <= 10 ^ (fractional - exponent))
        by (apply Z.pow_le_mono_r; lia).
      nia.
    + destruct (Z_le_gt_dec exponent (fractional + capacity - width)); [assumption|].
      assert (power_bound : 10 ^ (capacity + (fractional - exponent)) <= 10 ^ (width - 1))
        by (apply Z.pow_le_mono_r; lia).
      rewrite Z.pow_add_r in power_bound by lia.
      nia.
Qed.

Theorem parsed_exponent_text_is_bounded source lower upper power :
  parse_bounded_exponent source lower upper = Some power ->
  (Decimal.nb_digits (Decimal.abs (Decimal.norm source)) <= exponent_digit_limit lower upper)%nat.
Proof.
  unfold parse_bounded_exponent. rewrite !decimal_width_count.
  destruct (Nat.leb _ _) eqn:bounded; [intros _; now apply Nat.leb_le|discriminate].
Qed.
Theorem exponent_window_bounds_allocation width fractional exponent :
  1 <= width -> fractional + 1 - width <= exponent <= fractional + 16 - width ->
  (fractional <= exponent -> 0 <= exponent - fractional <= 15) /\
  (exponent < fractional -> 0 < fractional - exponent < width).
Proof. intros width_positive window. split; intros sign; lia. Qed.
