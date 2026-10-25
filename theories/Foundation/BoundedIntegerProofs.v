From Stdlib Require Import String Ascii Bool ZArith Lia.
From Selvedge.Foundation Require Import Numbers BoundedInteger.
Open Scope Z_scope.

Theorem within_safe_integer_spec value :
  within_safe_integer value = true <->
  - safe_integer_limit <= value <= safe_integer_limit.
Proof.
  unfold within_safe_integer. rewrite Bool.andb_true_iff, !Z.leb_le. tauto.
Qed.

Theorem decoded_coefficient_is_safe negative coefficient fraction exponent value :
  decode_coefficient negative coefficient fraction exponent = Some value ->
  - safe_integer_limit <= value <= safe_integer_limit.
Proof.
  unfold decode_coefficient.
  destruct (without_leading_zeroes coefficient) as [|head tail].
  - intros equality. inversion equality. unfold safe_integer_limit. lia.
  - destruct (parse_bounded_exponent exponent _ _) as [power|]; try discriminate.
    destruct (integral_digits _ _) as [digits|]; try discriminate.
    destruct (parse_integer _) as [parsed|]; try discriminate.
    destruct (within_safe_integer parsed) eqn:safe; try discriminate.
    intros equality. inversion equality; subst. now apply within_safe_integer_spec.
Qed.

Theorem decoded_safe_integer_is_safe source value :
  decode_safe_integer source = Some value ->
  - safe_integer_limit <= value <= safe_integer_limit.
Proof.
  unfold decode_safe_integer.
  destruct (number_lexeme source); try discriminate.
  destruct (unsigned_text source) as [negative unsigned].
  destruct (take_digits unsigned) as [whole rest].
  destruct (match rest with
            | String c digits => if Ascii.eqb c "."%char then take_digits digits else ("", rest)
            | EmptyString => ("", rest)
            end) as [fraction remaining].
  apply decoded_coefficient_is_safe.
Qed.

Theorem decoded_safe_integer_has_valid_lexeme source value :
  decode_safe_integer source = Some value -> number_lexeme source = true.
Proof.
  unfold decode_safe_integer. destruct (number_lexeme source); congruence.
Qed.

Theorem zero_coefficient_ignores_exponent negative coefficient fraction exponent :
  without_leading_zeroes coefficient = EmptyString ->
  decode_coefficient negative coefficient fraction exponent = Some 0.
Proof. intros zero. unfold decode_coefficient. now rewrite zero. Qed.

(* Cross multiplication gives the ordinary mathematical meaning of decimal
   scaling without rational arithmetic or a decoder-dependent interpretation.
   Both powers have nonnegative exponents, even for enormous negative shifts. *)
Definition decimal_integer_magnitude
    (coefficient fractional exponent magnitude : Z) : Prop :=
  coefficient * 10 ^ Z.max (exponent - fractional) 0 =
  magnitude * 10 ^ Z.max (fractional - exponent) 0.

Theorem zero_decimal_magnitude fractional exponent :
  decimal_integer_magnitude 0 fractional exponent 0.
Proof. unfold decimal_integer_magnitude. ring. Qed.

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

Corollary safe_integer_exponent_window_complete coefficient width fractional exponent magnitude :
  1 <= width ->
  10 ^ (width - 1) <= coefficient < 10 ^ width ->
  1 <= magnitude <= safe_integer_limit ->
  decimal_integer_magnitude coefficient fractional exponent magnitude ->
  fractional + 1 - width <= exponent <= fractional + 16 - width.
Proof.
  intros width_positive coefficient_digits magnitude_safe scaling.
  apply (decimal_exponent_window_complete coefficient width fractional exponent magnitude 16);
    try assumption; try lia.
  unfold safe_integer_limit in magnitude_safe. cbn. lia.
Qed.

Lemma compare_magnitude_shorter left right :
  (String.length left < String.length right)%nat ->
  compare_magnitude left right = Lt.
Proof.
  intros shorter. unfold compare_magnitude.
  now rewrite (proj2 (Nat.compare_lt_iff _ _) shorter).
Qed.

Lemma compare_magnitude_longer left right :
  (String.length right < String.length left)%nat ->
  compare_magnitude left right = Gt.
Proof.
  intros longer. unfold compare_magnitude.
  now rewrite (proj2 (Nat.compare_gt_iff _ _) longer).
Qed.

(* Even before establishing the numeric interpretation of text comparison,
   the executable guard bounds the amount of text reaching the integer parser.
   This covers huge signed exponents and arbitrary runs of leading zeroes. *)
Theorem admitted_exponent_text_is_bounded source lower upper :
  decimal_in_interval source lower upper = true ->
  (String.length (snd (normalized_decimal source)) <=
   Nat.max (String.length (snd (normalized_decimal (show_integer lower))))
           (String.length (snd (normalized_decimal (show_integer upper)))))%nat.
Proof.
  unfold decimal_in_interval.
  destruct (normalized_decimal source) as [negative digits].
  destruct (normalized_decimal (show_integer lower)) as [lower_negative lower_digits].
  destruct (normalized_decimal (show_integer upper)) as [upper_negative upper_digits].
  cbn [snd].
  intros admitted.
  destruct (Nat.le_gt_cases (String.length digits)
    (Nat.max (String.length lower_digits) (String.length upper_digits)))
    as [bounded|too_long]; [assumption|].
  assert (lower_shorter : (String.length lower_digits < String.length digits)%nat)
    by lia.
  assert (upper_shorter : (String.length upper_digits < String.length digits)%nat)
    by lia.
  destruct negative, lower_negative, upper_negative;
    cbn [compare_decimal] in admitted;
    try rewrite (compare_magnitude_shorter _ _ lower_shorter) in admitted;
    try rewrite (compare_magnitude_longer _ _ upper_shorter) in admitted;
    cbn in admitted; try rewrite Bool.andb_false_r in admitted;
    discriminate.
Qed.

Corollary parsed_exponent_text_is_bounded source lower upper power :
  parse_bounded_exponent source lower upper = Some power ->
  (String.length (snd (normalized_decimal source)) <=
   Nat.max (String.length (snd (normalized_decimal (show_integer lower))))
           (String.length (snd (normalized_decimal (show_integer upper)))))%nat.
Proof.
  unfold parse_bounded_exponent.
  destruct (decimal_in_interval source lower upper) eqn:admitted; try discriminate.
  intros _. now apply admitted_exponent_text_is_bounded.
Qed.

Theorem exponent_window_bounds_allocation width fractional exponent :
  1 <= width ->
  fractional + 1 - width <= exponent <= fractional + 16 - width ->
  (fractional <= exponent -> 0 <= exponent - fractional <= 15) /\
  (exponent < fractional -> 0 < fractional - exponent < width).
Proof. intros width_positive window. split; intros sign; lia. Qed.

Lemma zeroes_length count : String.length (zeroes count) = count.
Proof. induction count; cbn; congruence. Qed.

Lemma append_length left right :
  String.length (left ++ right) = (String.length left + String.length right)%nat.
Proof. induction left; cbn; congruence. Qed.

Lemma initial_substring_length source count :
  String.length (substring 0 count source) = Nat.min count (String.length source).
Proof.
  revert source. induction count; intros [|head tail]; cbn; try reflexivity.
  now rewrite IHcount.
Qed.

Theorem integral_digits_retains_bounded_width coefficient fractional exponent digits :
  (1 <= String.length coefficient)%nat ->
  fractional + 1 - Z.of_nat (String.length coefficient) <= exponent <=
    fractional + 16 - Z.of_nat (String.length coefficient) ->
  integral_digits coefficient (exponent - fractional) = Some digits ->
  (1 <= String.length digits <= 16)%nat.
Proof.
  intros nonempty window. unfold integral_digits.
  destruct ((exponent - fractional) <? 0) eqn:negative.
  - apply Z.ltb_lt in negative.
    assert (removed_bound : (Z.to_nat (-(exponent - fractional)) <
      String.length coefficient)%nat).
    { apply Nat2Z.inj_lt. rewrite Z2Nat.id by lia. lia. }
    destruct (only_zeroes _); try discriminate.
    intros equality. inversion equality; subst digits.
    rewrite initial_substring_length, Nat.min_l by lia.
    split; [lia|].
    assert (removed : Z.of_nat (Z.to_nat (-(exponent - fractional))) =
      -(exponent - fractional)) by (apply Z2Nat.id; lia).
    lia.
  - apply Z.ltb_ge in negative.
    intros equality. inversion equality; subst digits.
    rewrite append_length, zeroes_length.
    assert (appended : Z.of_nat (Z.to_nat (exponent - fractional)) =
      exponent - fractional) by (apply Z2Nat.id; lia).
    lia.
Qed.
