From Stdlib Require Import String Bool ZArith NArith Lia DecimalZ DecimalPos DecimalFacts.
From Selvedge.Foundation Require Import NumbersProofs BoundedInteger.
Open Scope Z_scope.

Lemma decimal_unsigned_size numeral :
  DecimalPos.Unsigned.usize numeral = N.of_nat (Decimal.nb_digits numeral).
Proof.
 induction numeral; cbn [DecimalPos.Unsigned.usize Decimal.nb_digits];
   rewrite ?IHnumeral, ?Nat2N.inj_succ; reflexivity.
Qed.

Lemma decimal_value_head numeral :
  Z.of_uint numeral =
  Z.of_N (DecimalPos.Unsigned.hd numeral) *
    10 ^ Z.of_nat (Decimal.nb_digits (DecimalPos.Unsigned.tl numeral)) +
  Z.of_uint (DecimalPos.Unsigned.tl numeral).
Proof.
 destruct numeral; [reflexivity|..];
 unfold Z.of_uint; rewrite DecimalPos.Unsigned.of_uint_alt;
 cbn [Decimal.rev Decimal.revapp];
 rewrite DecimalPos.Unsigned.of_lu_revapp;
 rewrite <- DecimalPos.Unsigned.of_uint_alt;
 rewrite N2Z.inj_add, N2Z.inj_mul, N2Z.inj_pow;
 rewrite decimal_unsigned_size, nat_N_Z;
 cbn [DecimalPos.Unsigned.of_lu DecimalPos.Unsigned.hd DecimalPos.Unsigned.tl]; cbn; ring.
Qed.


Lemma decimal_value_nonnegative numeral : 0 <= Z.of_uint numeral.
Proof. apply N2Z.is_nonneg. Qed.

Lemma decimal_value_below_power numeral :
  Z.of_uint numeral < 10 ^ Z.of_nat (Decimal.nb_digits numeral).
Proof.
 induction numeral; [reflexivity|..];
 pose proof (decimal_value_nonnegative numeral);
 rewrite decimal_value_head;
 cbn [Decimal.nb_digits DecimalPos.Unsigned.hd DecimalPos.Unsigned.tl];
 rewrite Nat2Z.inj_succ, Z.pow_succ_r by lia; cbn [Z.of_N]; nia.
Qed.

Lemma decimal_nonzero_head_lower numeral :
  (0 < DecimalPos.Unsigned.hd numeral)%N ->
  10 ^ (Z.of_nat (Decimal.nb_digits numeral) - 1) <= Z.of_uint numeral.
Proof.
 destruct numeral; [cbn; lia|..]; intros head_nonzero;
 rewrite decimal_value_head;
 cbn [Decimal.nb_digits DecimalPos.Unsigned.hd DecimalPos.Unsigned.tl];
 rewrite Nat2Z.inj_succ;
 replace (Z.succ (Z.of_nat (Decimal.nb_digits numeral)) - 1)
   with (Z.of_nat (Decimal.nb_digits numeral)) by lia;
 pose proof (decimal_value_nonnegative numeral);
 pose proof (Z.pow_pos_nonneg 10 (Z.of_nat (Decimal.nb_digits numeral)) ltac:(lia) ltac:(lia));
 cbn [Z.of_N DecimalPos.Unsigned.hd] in *; nia.
Qed.

Definition canonical_decimal (numeral : Decimal.uint) : Prop :=
  numeral = Decimal.D0 Decimal.Nil \/ (0 < DecimalPos.Unsigned.hd numeral)%N.

Lemma canonical_decimal_nonempty numeral :
  canonical_decimal numeral -> numeral <> Decimal.Nil.
Proof. intros [->|positive]; [discriminate|intros ->; cbn in positive; lia]. Qed.

Lemma decimal_width_order left right :
  (0 < DecimalPos.Unsigned.hd right)%N ->
  (Decimal.nb_digits left < Decimal.nb_digits right)%nat ->
  Z.of_uint left < Z.of_uint right.
Proof.
 intros positive width.
 pose proof (decimal_value_below_power left).
 pose proof (decimal_nonzero_head_lower right positive).
 assert (10 ^ Z.of_nat (Decimal.nb_digits left) <=
   10 ^ (Z.of_nat (Decimal.nb_digits right) - 1)).
 { apply Z.pow_le_mono_r; lia. }
 lia.
Qed.

Lemma unsigned_normal_form_canonical numeral : canonical_decimal (Decimal.unorm numeral).
Proof.
 unfold canonical_decimal, Decimal.unorm.
 destruct (Decimal.nzhead numeral) eqn:normal.
 - now left.
 - exfalso. exact (DecimalFacts.nzhead_nonzero numeral _ normal).
 - right; cbn; lia.
 - right; cbn; lia.
 - right; cbn; lia.
 - right; cbn; lia.
 - right; cbn; lia.
 - right; cbn; lia.
 - right; cbn; lia.
 - right; cbn; lia.
 - right; cbn; lia.
Qed.

Lemma decimal_positive_head_value magnitude :
  (0 < DecimalPos.Unsigned.hd magnitude)%N -> 0 < Z.of_uint magnitude.
Proof.
 intro positive. pose proof (decimal_nonzero_head_lower magnitude positive).
 pose proof (Z.pow_pos_nonneg 10 (Z.of_nat (Decimal.nb_digits magnitude) - 1)).
 destruct magnitude; cbn [DecimalPos.Unsigned.hd Decimal.nb_digits] in *; try lia.
Qed.

Lemma canonical_decimal_width_order left right :
  canonical_decimal left -> canonical_decimal right ->
  Z.of_uint left <= Z.of_uint right ->
  (Decimal.nb_digits left <= Decimal.nb_digits right)%nat.
Proof.
  intros left_canonical right_canonical values.
  destruct (Nat.le_gt_cases (Decimal.nb_digits left) (Decimal.nb_digits right)); [assumption|].
  assert (positive : (0 < DecimalPos.Unsigned.hd left)%N).
  { destruct left_canonical as [->|positive]; [|assumption].
    pose proof (canonical_decimal_nonempty right right_canonical).
    destruct right; cbn in *; contradiction || lia. }
  pose proof (decimal_width_order right left positive H). lia.
Qed.
Lemma decimal_magnitude_value numeral :
  Z.of_uint (Decimal.abs numeral) = Z.abs (Z.of_int numeral).
Proof.
  destruct numeral; cbn [Decimal.abs Z.of_int];
    rewrite ?Z.abs_opp, Z.abs_eq by apply decimal_value_nonnegative; reflexivity.
Qed.
Lemma printed_integer_normal value : Decimal.norm (Z.to_int value) = Z.to_int value.
Proof. rewrite <- DecimalZ.to_of, DecimalZ.of_to. reflexivity. Qed.
Lemma exponent_in_interval_fits_digits source lower upper :
  lower <= Z.of_int source <= upper ->
  (Decimal.nb_digits (Decimal.abs (Decimal.norm source)) <= exponent_digit_limit lower upper)%nat.
Proof.
  intro bounds. unfold exponent_digit_limit. rewrite !decimal_width_count.
  destruct (Z_le_gt_dec (Z.of_int source) 0) as [negative|positive].
  - eapply Nat.le_trans; [|apply Nat.le_max_l].
    apply canonical_decimal_width_order.
    + rewrite DecimalFacts.abs_norm. apply unsigned_normal_form_canonical.
    + rewrite <- (printed_integer_normal lower), DecimalFacts.abs_norm. apply unsigned_normal_form_canonical.
    + rewrite !decimal_magnitude_value, DecimalZ.of_int_norm, DecimalZ.of_to.
      rewrite !Z.abs_neq by lia. lia.
  - eapply Nat.le_trans; [|apply Nat.le_max_r].
    apply canonical_decimal_width_order.
    + rewrite DecimalFacts.abs_norm. apply unsigned_normal_form_canonical.
    + rewrite <- (printed_integer_normal upper), DecimalFacts.abs_norm. apply unsigned_normal_form_canonical.
    + rewrite !decimal_magnitude_value, DecimalZ.of_int_norm, DecimalZ.of_to.
      rewrite !Z.abs_eq by lia. lia.
Qed.
Theorem bounded_exponent_outcome source lower upper :
  parse_bounded_exponent source lower upper =
  if ((lower <=? Z.of_int source) && (Z.of_int source <=? upper))%Z
  then Some (Z.of_int source) else None.
Proof.
  unfold parse_bounded_exponent. rewrite !decimal_width_count. rewrite DecimalZ.of_int_norm.
  destruct (Nat.leb (Decimal.nb_digits (Decimal.abs (Decimal.norm source)))
    (exponent_digit_limit lower upper)) eqn:fits; [reflexivity|].
  destruct ((lower <=? Z.of_int source) && (Z.of_int source <=? upper))%Z eqn:inside; [|reflexivity].
  apply Bool.andb_true_iff in inside as [low high]; apply Z.leb_le in low,high.
  pose proof (exponent_in_interval_fits_digits source lower upper (conj low high)).
  apply Nat.leb_gt in fits. lia.
Qed.
Lemma decimal_nzhead_value numeral : Z.of_uint (Decimal.nzhead numeral) = Z.of_uint numeral.
Proof.
  induction numeral; cbn [Decimal.nzhead]; try reflexivity.
  rewrite (decimal_value_head (Decimal.D0 numeral)).
  cbn [DecimalPos.Unsigned.hd DecimalPos.Unsigned.tl Z.of_N]. nia.
Qed.
Lemma decimal_zero_value numeral : decimal_zero numeral = true <-> Z.of_uint numeral = 0.
Proof.
  unfold decimal_zero. rewrite <- (decimal_nzhead_value numeral).
  destruct (Decimal.nzhead numeral) eqn:normal;
    try solve [cbn; tauto];
    try solve [exfalso; exact (DecimalFacts.nzhead_nonzero numeral _ normal)].
  all: match goal with |- _ <-> Z.of_uint ?digits = 0 =>
    pose proof (decimal_positive_head_value digits ltac:(cbn; lia)) end;
    split; intros; discriminate || lia.
Qed.
