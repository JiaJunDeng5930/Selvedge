From Stdlib Require Import String Ascii Bool ZArith NArith Lia DecimalString DecimalZ.
From Selvedge.Foundation Require Import Numbers BoundedInteger BoundedIntegerProofs BoundedIntegerSemantics BoundedIntegerDigits BoundedIntegerLexeme BoundedIntegerNormalization.
Open Scope Z_scope.
Definition signed_magnitude (negative : bool) (magnitude : Z) :=
  if negative then -magnitude else magnitude.
Lemma canonical_unsigned_normal_id numeral :
  canonical_decimal numeral -> Decimal.unorm numeral = numeral.
Proof.
 intro canonical. destruct canonical as [->|positive]; [reflexivity|].
 destruct numeral; cbn [DecimalPos.Unsigned.hd] in positive; try lia; reflexivity.
Qed.
Lemma canonical_signed_normal_id numeral :
  signed_decimal_canonical numeral -> Decimal.norm numeral = numeral.
Proof.
 destruct numeral as [magnitude|magnitude]; intro canonical.
 - unfold Decimal.norm. now rewrite canonical_unsigned_normal_id.
 - destruct magnitude; cbn [signed_decimal_canonical DecimalPos.Unsigned.hd] in canonical; try lia; reflexivity.
Qed.
Theorem parse_canonical_signed_integer numeral :
  signed_decimal_canonical numeral ->
  parse_integer (NilZero.string_of_int numeral) = Some (Z.of_int numeral).
Proof.
 intro canonical. rewrite <- (canonical_signed_normal_id numeral canonical) at 1.
 apply parse_normal_form_integer.
Qed.
Theorem parse_signed_uint_sound negative digits numeral value :
  NilZero.uint_of_string digits = Some numeral ->
  parse_integer (signed_pair_text (negative,digits)) = Some value ->
  value = signed_magnitude negative (Z.of_uint numeral).
Proof.
 intros parsed decoded.
 assert (nonempty : numeral <> Decimal.Nil).
 { intro equal. subst numeral. exact (NilZero.uint_of_string_nonnil digits parsed). }
 apply NilZero.sus in parsed. subst digits.
 unfold parse_integer in decoded.
 destruct (number_lexeme _) eqn:valid; try discriminate.
 destruct negative.
 - change (match NilZero.int_of_string (NilZero.string_of_int (Decimal.Neg numeral)) with
         | Some d => Some (Z.of_int d) | None => None end = Some value) in decoded.
   rewrite NilZero.isi in decoded by congruence. inversion decoded; reflexivity.
 - change (match NilZero.int_of_string (NilZero.string_of_int (Decimal.Pos numeral)) with
         | Some d => Some (Z.of_int d) | None => None end = Some value) in decoded.
   rewrite NilZero.isi in decoded by congruence. inversion decoded; reflexivity.
Qed.
Lemma canonical_positive_head numeral :
  canonical_decimal numeral -> 0 < Z.of_uint numeral ->
  (0 < DecimalPos.Unsigned.hd numeral)%N.
Proof. intros [->|positive]; [change (0 < 0 -> (0 < 0)%N); lia|intros; assumption]. Qed.
Theorem parse_signed_uint_complete negative digits numeral :
  NilZero.uint_of_string digits = Some numeral ->
  canonical_decimal numeral -> 0 < Z.of_uint numeral ->
  parse_integer (signed_pair_text (negative,digits)) =
    Some (signed_magnitude negative (Z.of_uint numeral)).
Proof.
 intros parsed canonical positive. apply NilZero.sus in parsed. subst digits.
 destruct negative.
 - change (parse_integer (NilZero.string_of_int (Decimal.Neg numeral)) = Some (Z.of_int (Decimal.Neg numeral))).
   apply parse_canonical_signed_integer. cbn [signed_decimal_canonical].
   now apply canonical_positive_head.
 - change (parse_integer (NilZero.string_of_int (Decimal.Pos numeral)) = Some (Z.of_int (Decimal.Pos numeral))).
   apply parse_canonical_signed_integer. exact canonical.
Qed.

Lemma decimal_signed_scaling negative coefficient fractional exponent value :
  decimal_integer_magnitude (signed_magnitude negative coefficient) fractional exponent value <->
  decimal_integer_magnitude coefficient fractional exponent (signed_magnitude negative value).
Proof. destruct negative; unfold signed_magnitude, decimal_integer_magnitude; [split; intro scaling; nia|reflexivity]. Qed.
Lemma decimal_scaling_at_shift coefficient fractional exponent magnitude :
  decimal_integer_magnitude coefficient fractional exponent magnitude <->
  decimal_integer_magnitude coefficient 0 (exponent - fractional) magnitude.
Proof.
 unfold decimal_integer_magnitude.
 replace (exponent - fractional - 0) with (exponent - fractional) by lia.
 replace (0 - (exponent - fractional)) with (fractional - exponent) by lia. reflexivity.
Qed.
Lemma decimal_scaling_positive coefficient fractional exponent magnitude :
  0 < coefficient -> decimal_integer_magnitude coefficient fractional exponent magnitude -> 0 < magnitude.
Proof.
 intros positive scaling. unfold decimal_integer_magnitude in scaling.
 pose proof (Z.pow_pos_nonneg 10 (Z.max (exponent - fractional) 0) ltac:(lia) ltac:(lia)).
 pose proof (Z.pow_pos_nonneg 10 (Z.max (fractional - exponent) 0) ltac:(lia) ltac:(lia)).
 nia.
Qed.
Lemma zero_decimal_scaling_iff fractional exponent value :
  decimal_integer_magnitude 0 fractional exponent value <-> value = 0.
Proof.
 unfold decimal_integer_magnitude.
 pose proof (Z.pow_pos_nonneg 10 (Z.max (fractional - exponent) 0) ltac:(lia) ltac:(lia)).
 split; intros; nia.
Qed.
Lemma signed_magnitude_involutive negative value :
  signed_magnitude negative (signed_magnitude negative value) = value.
Proof. destruct negative; unfold signed_magnitude; lia. Qed.
Lemma signed_magnitude_safe negative value :
  -safe_integer_limit <= value <= safe_integer_limit ->
  -safe_integer_limit <= signed_magnitude negative value <= safe_integer_limit.
Proof. destruct negative; unfold signed_magnitude; lia. Qed.
Lemma safe_integer_decimal_capacity value :
  0 < value -> value <= safe_integer_limit -> 1 <= value < 10 ^ 16.
Proof. unfold safe_integer_limit. change (0 < value -> value <= 9007199254740991 -> 1 <= value < 10000000000000000). lia. Qed.

Lemma bounded_exponent_outcome source value lower upper :
  exponent_denotes source value ->
  parse_bounded_exponent source lower upper =
    if decimal_in_interval source lower upper then Some value else None.
Proof.
 intro denotes. unfold parse_bounded_exponent.
 pose proof (parse_normalized_exponent_exact source value denotes) as parsing.
 unfold signed_pair_text in parsing.
 destruct (normalized_decimal source) as [negative magnitude]. cbn in parsing.
 change ((if decimal_in_interval source lower upper
   then parse_integer (if negative then String "-"%char magnitude else magnitude) else None) =
   if decimal_in_interval source lower upper then Some value else None).
 now rewrite parsing.
Qed.
Lemma decode_nonzero_coefficient_expand negative coefficient significant fraction exponent :
  significant <> EmptyString -> without_leading_zeroes coefficient = significant ->
  decode_coefficient negative coefficient fraction exponent =
  match parse_bounded_exponent exponent
    (Z.of_nat fraction + 1 - Z.of_nat (String.length significant))
    (Z.of_nat fraction + 16 - Z.of_nat (String.length significant)) with
  | None => None
  | Some power => match integral_digits significant (power - Z.of_nat fraction) with
    | None => None
    | Some digits => match parse_integer (signed_pair_text (negative,digits)) with
      | Some value => if within_safe_integer value then Some value else None
      | None => None end end end.
Proof.
 intros nonempty normalized. unfold decode_coefficient. rewrite normalized.
 destruct significant; [contradiction|]. destruct negative; reflexivity.
Qed.
Lemma safe_nonzero_exponent_window negative numeral fraction exponent value :
  canonical_decimal numeral -> 0 < Z.of_uint numeral ->
  -safe_integer_limit <= value <= safe_integer_limit ->
  decimal_integer_magnitude (signed_magnitude negative (Z.of_uint numeral))
    (Z.of_nat fraction) exponent value ->
  Z.of_nat fraction + 1 - Z.of_nat (String.length (NilEmpty.string_of_uint numeral)) <= exponent <=
  Z.of_nat fraction + 16 - Z.of_nat (String.length (NilEmpty.string_of_uint numeral)).
Proof.
 intros canonical positive safe scaling.
 apply decimal_signed_scaling in scaling.
 assert (magnitude_positive : 0 < signed_magnitude negative value)
   by (eapply decimal_scaling_positive; eassumption).
 pose proof (signed_magnitude_safe negative value safe) as magnitude_safe.
 apply safe_integer_decimal_capacity in magnitude_positive as magnitude_capacity; [|lia].
 rewrite decimal_render_size.
 eapply decimal_exponent_window_complete; [|lia| |exact magnitude_capacity|exact scaling].
 - pose proof (canonical_decimal_nonempty numeral canonical).
   destruct numeral; [contradiction|cbn [Decimal.nb_digits]; lia..].
 - split; [apply decimal_nonzero_head_lower; now apply canonical_positive_head|apply decimal_value_below_power].
Qed.

Lemma positive_decimal_nzhead_id numeral :
  (0 < DecimalPos.Unsigned.hd numeral)%N -> Decimal.nzhead numeral = numeral.
Proof. destruct numeral; cbn [DecimalPos.Unsigned.hd]; intros positive; try lia; reflexivity. Qed.
Theorem decode_positive_coefficient_exact negative coefficient numeral fraction exponent power value :
  NilZero.uint_of_string coefficient = Some numeral ->
  canonical_decimal numeral -> 0 < Z.of_uint numeral ->
  exponent_denotes exponent power ->
  (decode_coefficient negative coefficient fraction exponent = Some value <->
    (-safe_integer_limit <= value <= safe_integer_limit) /\
    decimal_integer_magnitude (signed_magnitude negative (Z.of_uint numeral))
      (Z.of_nat fraction) power value).
Proof.
 intros parsed canonical positive denotes.
 assert (render : coefficient = NilEmpty.string_of_uint numeral).
 { apply NilZero.sus in parsed. rewrite <-parsed. now apply canonical_unsigned_printing_agrees. }
 assert (nonempty : coefficient <> EmptyString).
 { rewrite render. intro empty. apply (f_equal NilEmpty.uint_of_string) in empty.
   rewrite NilEmpty.usu in empty. cbn in empty. inversion empty.
   pose proof (canonical_decimal_nonempty numeral canonical). contradiction. }
 assert (normalized : without_leading_zeroes coefficient = coefficient).
 { rewrite render, remove_leading_zeroes_decimal, positive_decimal_nzhead_id by now apply canonical_positive_head.
   reflexivity. }
 rewrite (decode_nonzero_coefficient_expand negative coefficient coefficient fraction exponent nonempty normalized).
 rewrite (bounded_exponent_outcome exponent power _ _ denotes).
 destruct (decimal_in_interval exponent _ _) eqn:accepted.
 - assert (window : Z.of_nat fraction + 1 - Z.of_nat (String.length coefficient) <= power <=
       Z.of_nat fraction + 16 - Z.of_nat (String.length coefficient))
     by (apply (proj1 (decimal_interval_exact exponent power _ _ denotes)); exact accepted).
   assert (lower_window : 1 - Z.of_nat (String.length coefficient) <= power - Z.of_nat fraction) by lia.
   split.
   + destruct (integral_digits coefficient (power - Z.of_nat fraction)) as [digits|] eqn:integral; [|discriminate].
     destruct (parse_integer (signed_pair_text (negative,digits))) as [actual|] eqn:decoded; [|discriminate].
     destruct (within_safe_integer actual) eqn:safe; [|discriminate].
     intro equality. inversion equality; subst actual.
     destruct (integral_digits_sound coefficient numeral _ digits parsed canonical positive lower_window integral)
       as [result [parsed_result [canonical_result [positive_result mathematical]]]].
     pose proof (parse_signed_uint_sound negative digits result value parsed_result decoded) as signed_value.
     split; [now apply within_safe_integer_spec|].
     apply decimal_signed_scaling. rewrite signed_value, signed_magnitude_involutive.
     now apply decimal_scaling_at_shift.
   + intros [safe mathematical]. apply decimal_signed_scaling in mathematical.
     assert (magnitude_positive : 0 < signed_magnitude negative value)
       by (eapply decimal_scaling_positive; eassumption).
     apply decimal_scaling_at_shift in mathematical.
     destruct (integral_digits_complete coefficient numeral _ (signed_magnitude negative value)
       parsed canonical positive lower_window mathematical magnitude_positive)
       as [digits [result [integral [parsed_result [canonical_result result_value]]]]].
     rewrite integral.
     rewrite (parse_signed_uint_complete negative digits result parsed_result canonical_result) by lia.
     rewrite result_value, signed_magnitude_involutive.
     rewrite (proj2 (within_safe_integer_spec value) safe). reflexivity.
 - split; [discriminate|]. intros [safe mathematical].
   pose proof (safe_nonzero_exponent_window negative numeral fraction power value canonical positive safe mathematical)
     as window.
   rewrite <-render in window.
   apply (proj2 (decimal_interval_exact exponent power _ _ denotes)) in window.
   congruence.
Qed.

Lemma decode_coefficient_same_normalization negative left right fraction exponent :
  without_leading_zeroes left = without_leading_zeroes right ->
  decode_coefficient negative left fraction exponent = decode_coefficient negative right fraction exponent.
Proof. intro same. unfold decode_coefficient. now rewrite same. Qed.
Theorem decode_coefficient_mathematical_iff negative coefficient numeral fraction exponent power value :
  NilZero.uint_of_string coefficient = Some numeral -> exponent_denotes exponent power ->
  (decode_coefficient negative coefficient fraction exponent = Some value <->
    (-safe_integer_limit <= value <= safe_integer_limit) /\
    decimal_integer_magnitude (signed_magnitude negative (Z.of_uint numeral))
      (Z.of_nat fraction) power value).
Proof.
 intros parsed denotes.
 destruct (coefficient_normalization coefficient numeral parsed)
   as [[zero zero_value]|[normal [normalized [parsed_normal [canonical [positive [normal_value width]]]]]]].
 - unfold decode_coefficient. rewrite zero, zero_value.
   assert (signed_zero : signed_magnitude negative 0 = 0) by (destruct negative; reflexivity).
   rewrite signed_zero, zero_decimal_scaling_iff.
   split.
   + intro equality. inversion equality; subst value. unfold safe_integer_limit. lia.
   + intros [safe ->]. reflexivity.
 - assert (normal_stable : without_leading_zeroes (NilEmpty.string_of_uint normal) = NilEmpty.string_of_uint normal).
   { rewrite remove_leading_zeroes_decimal, positive_decimal_nzhead_id by now apply canonical_positive_head.
     reflexivity. }
   rewrite (decode_coefficient_same_normalization negative coefficient (NilEmpty.string_of_uint normal)
     fraction exponent ltac:(now rewrite normal_stable)).
   rewrite <-normal_value.
   now apply decode_positive_coefficient_exact.
Qed.

(* The shared scan only identifies lexical components. Their denotation uses
   standard-library decimal coefficients and an unbounded integer exponent,
   then exact cross multiplication. No decoder decision occurs in this meaning. *)
Definition json_integer_denotes (source : string) (value : Z) : Prop :=
  number_lexeme source = true /\
  exists numeral power,
    NilZero.uint_of_string (parts_coefficient (split_number source)) = Some numeral /\
    exponent_denotes (parts_exponent (split_number source)) power /\
    decimal_integer_magnitude
      (signed_magnitude (parts_negative (split_number source)) (Z.of_uint numeral))
      (Z.of_nat (parts_fraction_digits (split_number source))) power value.

Theorem decode_safe_integer_mathematical_iff source value :
  decode_safe_integer source = Some value <->
  json_integer_denotes source value /\ -safe_integer_limit <= value <= safe_integer_limit.
Proof.
 rewrite decode_safe_integer_split. split.
 - destruct (number_lexeme source) eqn:valid; [|discriminate].
   destruct (valid_lexeme_parts_denote source valid) as [numeral [power [parsed denotes]]].
   intro decoded.
   apply (proj1 (decode_coefficient_mathematical_iff _ _ numeral _ _ power value parsed denotes)) in decoded.
   destruct decoded as [safe mathematical]. split; [|exact safe].
   split; [exact valid|]. exists numeral, power. auto.
 - intros [[valid [numeral [power [parsed [denotes mathematical]]]]] safe].
   rewrite valid.
   apply (proj2 (decode_coefficient_mathematical_iff _ _ numeral _ _ power value parsed denotes)).
   auto.
Qed.
