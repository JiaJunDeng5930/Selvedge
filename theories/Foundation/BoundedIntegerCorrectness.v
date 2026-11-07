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
Lemma signed_magnitude_bounded negative limit value :
  -limit < value < limit -> -limit < signed_magnitude negative value < limit.
Proof. destruct negative; unfold signed_magnitude; lia. Qed.

Lemma decode_nonzero_coefficient_expand capacity negative coefficient significant fraction exponent :
  significant <> Decimal.Nil -> Decimal.nzhead coefficient = significant ->
  coefficient_integer capacity negative coefficient fraction exponent =
  match parse_bounded_exponent exponent
    (Z.of_nat fraction + 1 - Z.of_nat (Decimal.nb_digits significant))
    (Z.of_nat fraction + Z.of_nat capacity - Z.of_nat (Decimal.nb_digits significant)) with
  | None => None
  | Some power => match integral_magnitude significant (power - Z.of_nat fraction) with
    | None => None
    | Some magnitude => Some (signed_magnitude negative magnitude) end end.
Proof. intros nonempty normalized. unfold coefficient_integer. rewrite !decimal_width_count, normalized.
 destruct significant; contradiction || reflexivity. Qed.
Lemma nonzero_exponent_window capacity negative numeral fraction exponent value :
  (0 < capacity)%nat -> (0 < DecimalPos.Unsigned.hd numeral)%N ->
  -10 ^ Z.of_nat capacity < value < 10 ^ Z.of_nat capacity ->
  decimal_integer_magnitude (signed_magnitude negative (Z.of_uint numeral))
    (Z.of_nat fraction) exponent value ->
  Z.of_nat fraction + 1 - Z.of_nat (Decimal.nb_digits numeral) <= exponent <=
  Z.of_nat fraction + Z.of_nat capacity - Z.of_nat (Decimal.nb_digits numeral).
Proof.
 intros capacity_positive head bounded scaling. apply decimal_signed_scaling in scaling.
 pose proof (decimal_positive_head_value numeral head) as positive.
 assert (magnitude_positive : 0 < signed_magnitude negative value)
   by (eapply decimal_scaling_positive; eassumption).
 pose proof (signed_magnitude_bounded negative _ value bounded) as magnitude_bounded.
 eapply decimal_exponent_window_complete; [|lia| | |exact scaling].
 - destruct numeral; cbn [Decimal.nb_digits DecimalPos.Unsigned.hd] in *; lia.
 - split; [now apply decimal_nonzero_head_lower|apply decimal_value_below_power].
 - lia.
Qed.
Lemma integral_magnitude_capacity coefficient fractional exponent capacity magnitude :
  (1 <= Decimal.nb_digits coefficient)%nat ->
  fractional + 1 - Z.of_nat (Decimal.nb_digits coefficient) <= exponent <=
    fractional + Z.of_nat capacity - Z.of_nat (Decimal.nb_digits coefficient) ->
  integral_magnitude coefficient (exponent - fractional) = Some magnitude ->
  0 <= magnitude < 10 ^ Z.of_nat capacity.
Proof.
 intros width window integral.
 pose proof (integral_magnitude_digit_budget coefficient fractional exponent capacity width window) as budget.
 unfold integral_magnitude in integral.
 destruct (Z.ltb_spec (exponent - fractional) 0) as [negative|nonnegative].
 - replace (- (exponent - fractional)) with (fractional - exponent) in integral by ring.
   destruct (decimal_zero _) eqn:zero; [|discriminate]. inversion integral; subst magnitude.
   split; [apply decimal_value_nonnegative|].
   eapply Z.lt_le_trans; [apply decimal_value_below_power|]. apply Z.pow_le_mono_r; lia.
 - inversion integral; subst magnitude.
   split; [apply decimal_value_nonnegative|].
   eapply Z.lt_le_trans; [apply decimal_value_below_power|]. apply Z.pow_le_mono_r; lia.
Qed.
Theorem coefficient_integer_mathematical_iff capacity negative coefficient fraction exponent value :
  (0 < capacity)%nat ->
  (coefficient_integer capacity negative coefficient fraction exponent = Some value <->
    (-10 ^ Z.of_nat capacity < value < 10 ^ Z.of_nat capacity) /\
    decimal_integer_magnitude (signed_magnitude negative (Z.of_uint coefficient))
      (Z.of_nat fraction) (Z.of_int exponent) value).
Proof.
  intro capacity_positive.
  remember (Decimal.nzhead coefficient) as normal eqn:normalized.
  pose proof (decimal_nzhead_value coefficient) as magnitude.
  rewrite <-normalized in magnitude.
  destruct (Decimal.uint_eq_dec normal Decimal.Nil) as [empty|nonempty].
  - rewrite empty in normalized,magnitude. cbn in magnitude. unfold coefficient_integer. rewrite <-normalized.
    rewrite <-magnitude. assert (signed_zero : signed_magnitude negative 0 = 0) by (destruct negative; reflexivity).
    rewrite signed_zero, zero_decimal_scaling_iff. split.
    + intros [= <-]. pose proof (Z.pow_pos_nonneg 10 (Z.of_nat capacity) ltac:(lia) ltac:(lia)). split; lia.
    + intros [_ ->]. reflexivity.
  - assert (head : (0 < DecimalPos.Unsigned.hd normal)%N).
    { destruct normal; [contradiction|..]; cbn [DecimalPos.Unsigned.hd]; try lia.
      exfalso. exact (DecimalFacts.nzhead_nonzero coefficient normal (eq_sym normalized)). }
    assert (width : (1 <= Decimal.nb_digits normal)%nat).
    { destruct normal; [contradiction|..]; cbn; lia. }
    rewrite <-magnitude.
    rewrite (decode_nonzero_coefficient_expand capacity negative coefficient normal fraction exponent nonempty (eq_sym normalized)).
    rewrite bounded_exponent_outcome.
    destruct ((Z.of_nat fraction + 1 - Z.of_nat (Decimal.nb_digits normal) <=? Z.of_int exponent) &&
      (Z.of_int exponent <=? Z.of_nat fraction + Z.of_nat capacity - Z.of_nat (Decimal.nb_digits normal)))%Z eqn:accepted.
    + apply Bool.andb_true_iff in accepted as [low high]; apply Z.leb_le in low,high.
      assert (window : 1 - Z.of_nat (Decimal.nb_digits normal) <= Z.of_int exponent - Z.of_nat fraction) by lia.
      split.
      * destruct (integral_magnitude normal (Z.of_int exponent - Z.of_nat fraction)) as [result|] eqn:integral; [|discriminate].
        intros [= <-]. split.
        -- pose proof (integral_magnitude_capacity normal (Z.of_nat fraction) (Z.of_int exponent)
             capacity result width (conj low high) integral).
           destruct negative; unfold signed_magnitude; lia.
        -- apply decimal_signed_scaling. rewrite signed_magnitude_involutive.
           apply decimal_scaling_at_shift. now apply (proj1 (integral_magnitude_exact _ _ _ window)).
      * intros [bounded mathematical]. apply decimal_signed_scaling, decimal_scaling_at_shift in mathematical.
        apply (proj2 (integral_magnitude_exact _ _ _ window)) in mathematical.
        now rewrite mathematical, signed_magnitude_involutive.
    + split; [discriminate|]. intros [bounded mathematical].
      pose proof (nonzero_exponent_window capacity negative normal fraction (Z.of_int exponent) value
        capacity_positive head bounded mathematical).
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
Theorem decode_integer_mathematical_iff capacity source value :
  (0 < capacity)%nat ->
  (decode_integer capacity source = Some value <->
  json_integer_denotes source value /\ -10 ^ Z.of_nat capacity < value < 10 ^ Z.of_nat capacity).
Proof.
  intro capacity_positive. unfold decode_integer, json_integer_denotes.
  destruct (parse_decimal source) as [decimal|] eqn:parsed.
  - destruct (decimal_components decimal) as [[[negative coefficient] fraction] exponent] eqn:components.
    rewrite coefficient_integer_mathematical_iff by assumption. split.
    + intros [bounded meaning]. split; [exists decimal; split; [reflexivity|now rewrite components]|assumption].
    + intros [[other [[= <-] meaning]] bounded]. rewrite components in meaning. auto.
  - split; [discriminate|]. intros [[decimal [impossible _]] _]. discriminate.
Qed.
Theorem decode_safe_integer_mathematical_iff source value :
  option_map integer_value (decode_safe_integer source) = Some value <->
  json_integer_denotes source value /\ -safe_integer_limit <= value <= safe_integer_limit.
Proof.
  unfold decode_safe_integer.
  destruct (decode_integer 16 source) as [decoded|] eqn:parsed.
  - unfold Refinement.admit. destruct (Bool.bool_dec (within_safe_integer decoded) true) as [safe|unsafe].
    + cbn [option_map integer_value proj1_sig]. split.
      * intros [= <-]. split.
        -- apply (decode_integer_mathematical_iff 16 source decoded ltac:(lia)) in parsed as [meaning _]. exact meaning.
        --
        now apply within_safe_integer_spec.
      * intros [meaning bounded].
        assert (decode_integer 16 source = Some value) as same.
        { apply decode_integer_mathematical_iff; [lia|]. split; [assumption|].
          unfold safe_integer_limit in bounded. change (-10000000000000000 < value < 10000000000000000). lia. }
        congruence.
    + split; [discriminate|]. intros [meaning bounded].
      assert (decode_integer 16 source = Some value) as same.
      { apply decode_integer_mathematical_iff; [lia|]. split; [assumption|].
        unfold safe_integer_limit in bounded. change (-10000000000000000 < value < 10000000000000000). lia. }
      assert (decoded = value) by congruence. subst decoded. exfalso. apply unsafe, within_safe_integer_spec; assumption.
  - split; [discriminate|]. intros [meaning bounded].
    assert (decode_integer 16 source = Some value) as same.
    { apply decode_integer_mathematical_iff; [lia|]. split; [assumption|].
      unfold safe_integer_limit in bounded. change (-10000000000000000 < value < 10000000000000000). lia. }
    congruence.
Qed.
Theorem decode_natural_mathematical_iff capacity source value :
  (0 < capacity)%nat ->
  (decode_natural capacity source = Some value <->
   json_integer_denotes source (Z.of_N value) /\ Z.of_N value < 10 ^ Z.of_nat capacity).
Proof.
 intro capacity_positive. unfold decode_natural.
 destruct (decode_integer capacity source) as [decoded|] eqn:parsed.
 - destruct (Z.ltb_spec decoded 0) as [negative|nonnegative].
   + split; [discriminate|]. intros [meaning bounded].
     assert (decode_integer capacity source = Some (Z.of_N value)) as same.
     { apply decode_integer_mathematical_iff; [assumption|]. split; [assumption|].
       pose proof (Z.pow_pos_nonneg 10 (Z.of_nat capacity) ltac:(lia) ltac:(lia)). lia. }
     assert (decoded = Z.of_N value) by congruence. lia.
   + split.
     * intros [= <-]. rewrite Z2N.id by assumption.
       apply decode_integer_mathematical_iff in parsed as [meaning bounded]; [tauto|assumption].
     * intros [meaning bounded].
       assert (decode_integer capacity source = Some (Z.of_N value)) as same.
       { apply decode_integer_mathematical_iff; [assumption|]. split; [assumption|].
         pose proof (Z.pow_pos_nonneg 10 (Z.of_nat capacity) ltac:(lia) ltac:(lia)). lia. }
       assert (decoded = Z.of_N value) by congruence. now rewrite H, N2Z.id.
 - split; [discriminate|]. intros [meaning bounded].
   assert (decode_integer capacity source = Some (Z.of_N value)) as same.
   { apply decode_integer_mathematical_iff; [assumption|]. split; [assumption|].
     pose proof (Z.pow_pos_nonneg 10 (Z.of_nat capacity) ltac:(lia) ltac:(lia)). lia. }
   congruence.
Qed.
Theorem unbounded_natural_print_parse value :
  decode_unbounded_natural (show_natural value) = Some value.
Proof. unfold decode_unbounded_natural. now rewrite natural_print_parse. Qed.
