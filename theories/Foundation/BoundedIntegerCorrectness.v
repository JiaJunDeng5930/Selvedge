From Stdlib Require Import String Bool ZArith NArith Lia DecimalZ DecimalPos DecimalFacts.
From Selvedge.Foundation Require Import Numbers NumbersProofs.
From Selvedge.Programming Require Import Refinement.
From Selvedge.Foundation Require Import BoundedInteger BoundedIntegerProofs BoundedIntegerSemantics BoundedIntegerDigits.
Open Scope Z_scope.

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

Lemma decode_nonzero_coefficient_expand negative coefficient significant fraction exponent :
  significant <> Decimal.Nil -> Decimal.nzhead coefficient = significant ->
  decode_coefficient negative coefficient fraction exponent =
  match parse_bounded_exponent exponent
    (Z.of_nat fraction + 1 - Z.of_nat (Decimal.nb_digits significant))
    (Z.of_nat fraction + 16 - Z.of_nat (Decimal.nb_digits significant)) with
  | None => None
  | Some power => match integral_magnitude significant (power - Z.of_nat fraction) with
    | None => None
    | Some magnitude => let value := signed_magnitude negative magnitude in
        Refinement.admit within_safe_integer value end end.
Proof. intros nonempty normalized. unfold decode_coefficient. rewrite !decimal_width_count, normalized.
 destruct significant; contradiction || reflexivity. Qed.
Lemma safe_nonzero_exponent_window negative numeral fraction exponent value :
  (0 < DecimalPos.Unsigned.hd numeral)%N ->
  -safe_integer_limit <= value <= safe_integer_limit ->
  decimal_integer_magnitude (signed_magnitude negative (Z.of_uint numeral))
    (Z.of_nat fraction) exponent value ->
  Z.of_nat fraction + 1 - Z.of_nat (Decimal.nb_digits numeral) <= exponent <=
  Z.of_nat fraction + 16 - Z.of_nat (Decimal.nb_digits numeral).
Proof.
 intros head safe scaling. apply decimal_signed_scaling in scaling.
 pose proof (decimal_positive_head_value numeral head) as positive.
 assert (magnitude_positive : 0 < signed_magnitude negative value)
   by (eapply decimal_scaling_positive; eassumption).
 pose proof (signed_magnitude_safe negative value safe) as magnitude_safe.
 apply safe_integer_decimal_capacity in magnitude_positive as magnitude_capacity; [|lia].
 eapply decimal_exponent_window_complete; [|lia| |exact magnitude_capacity|exact scaling].
 - destruct numeral; cbn [Decimal.nb_digits DecimalPos.Unsigned.hd] in *; lia.
 - split; [now apply decimal_nonzero_head_lower|apply decimal_value_below_power].
Qed.
Theorem decode_coefficient_mathematical_iff negative coefficient fraction exponent value :
  (option_map integer_value (decode_coefficient negative coefficient fraction exponent) = Some value <->
    (-safe_integer_limit <= value <= safe_integer_limit) /\
    decimal_integer_magnitude (signed_magnitude negative (Z.of_uint coefficient))
      (Z.of_nat fraction) (Z.of_int exponent) value).
Proof.
  remember (Decimal.nzhead coefficient) as normal eqn:normalized.
  pose proof (decimal_nzhead_value coefficient) as magnitude.
  rewrite <-normalized in magnitude.
  destruct (Decimal.uint_eq_dec normal Decimal.Nil) as [empty|nonempty].
  - rewrite empty in normalized,magnitude. cbn in magnitude. unfold decode_coefficient. rewrite <-normalized.
    rewrite <-magnitude. assert (signed_zero : signed_magnitude negative 0 = 0) by (destruct negative; reflexivity).
    rewrite signed_zero, zero_decimal_scaling_iff. cbn [option_map integer_value proj1_sig]. split.
    + intros [= <-]. unfold safe_integer_limit. split; lia.
    + intros [_ ->]. reflexivity.
  - assert (head : (0 < DecimalPos.Unsigned.hd normal)%N).
    { destruct normal; [contradiction|..]; cbn [DecimalPos.Unsigned.hd]; try lia.
      exfalso. exact (DecimalFacts.nzhead_nonzero coefficient normal (eq_sym normalized)). }
    rewrite <-magnitude.
    rewrite (decode_nonzero_coefficient_expand negative coefficient normal fraction exponent nonempty (eq_sym normalized)).
    rewrite bounded_exponent_outcome.
    destruct ((Z.of_nat fraction + 1 - Z.of_nat (Decimal.nb_digits normal) <=? Z.of_int exponent) &&
      (Z.of_int exponent <=? Z.of_nat fraction + 16 - Z.of_nat (Decimal.nb_digits normal)))%Z eqn:accepted.
    + apply Bool.andb_true_iff in accepted as [low high]; apply Z.leb_le in low,high.
      assert (window : 1 - Z.of_nat (Decimal.nb_digits normal) <= Z.of_int exponent - Z.of_nat fraction) by lia.
      split.
      * destruct (integral_magnitude normal (Z.of_int exponent - Z.of_nat fraction)) as [result|] eqn:integral; [|discriminate].
        cbn beta iota zeta. unfold Refinement.admit.
        destruct (Bool.bool_dec (within_safe_integer (signed_magnitude negative result)) true) as [safe|unsafe]; [|discriminate].
        cbn [option_map integer_value proj1_sig].
        intros [= <-]. split; [now apply within_safe_integer_spec|].
        apply decimal_signed_scaling. rewrite signed_magnitude_involutive.
        apply decimal_scaling_at_shift. now apply (proj1 (integral_magnitude_exact _ _ _ window)).
      * intros [safe mathematical]. apply decimal_signed_scaling, decimal_scaling_at_shift in mathematical.
        apply (proj2 (integral_magnitude_exact _ _ _ window)) in mathematical.
        rewrite mathematical, signed_magnitude_involutive. cbn beta iota zeta.
        unfold Refinement.admit.
        destruct (Bool.bool_dec (within_safe_integer value) true) as [bounded|unbounded]; [reflexivity|].
        exfalso. apply unbounded. now apply within_safe_integer_spec.
    + split; [discriminate|]. intros [safe mathematical].
      pose proof (safe_nonzero_exponent_window negative normal fraction (Z.of_int exponent) value head safe mathematical).
      apply Bool.andb_false_iff in accepted as [low|high];
        apply Z.leb_gt in low || apply Z.leb_gt in high; lia.
Qed.

(** The number grammar constructs standard decimal syntax. Its mathematical
    meaning is exact positional scaling, independently of bounded admission. *)
Definition json_integer_denotes (source : string) (value : Z) : Prop :=
  exists decimal, parse_decimal source = Some decimal /\
  let '(negative,coefficient,fraction,exponent) := decimal_components decimal in
  decimal_integer_magnitude (signed_magnitude negative (Z.of_uint coefficient))
    (Z.of_nat fraction) (Z.of_int exponent) value.
Theorem decode_safe_integer_mathematical_iff source value :
  option_map integer_value (decode_safe_integer source) = Some value <->
  json_integer_denotes source value /\ -safe_integer_limit <= value <= safe_integer_limit.
Proof.
  unfold decode_safe_integer, json_integer_denotes.
  destruct (parse_decimal source) as [decimal|] eqn:parsed.
  - destruct (decimal_components decimal) as [[[negative coefficient] fraction] exponent] eqn:components.
    rewrite decode_coefficient_mathematical_iff. split.
    + intros [safe meaning]. split; [exists decimal; split; [reflexivity|now rewrite components]|assumption].
    + intros [[other [[= <-] meaning]] safe]. rewrite components in meaning. auto.
  - split; [discriminate|]. intros [[decimal [impossible _]] _]. discriminate.
Qed.
