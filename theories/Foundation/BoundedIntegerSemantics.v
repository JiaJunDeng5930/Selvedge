From Stdlib Require Import String Ascii Bool ZArith NArith Lia DecimalString DecimalZ DecimalPos.
From Selvedge.Foundation Require Import Numbers BoundedInteger.
Open Scope Z_scope.

Lemma decimal_unsigned_size numeral :
  DecimalPos.Unsigned.usize numeral = N.of_nat (Decimal.nb_digits numeral).
Proof.
 induction numeral; cbn [DecimalPos.Unsigned.usize Decimal.nb_digits];
   rewrite ?IHnumeral, ?Nat2N.inj_succ; reflexivity.
Qed.
Lemma decimal_render_size numeral :
  String.length (NilEmpty.string_of_uint numeral) = Decimal.nb_digits numeral.
Proof. induction numeral; cbn; now rewrite ?IHnumeral. Qed.

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
Lemma remove_leading_zeroes_decimal numeral :
  without_leading_zeroes (NilEmpty.string_of_uint numeral) =
  NilEmpty.string_of_uint (Decimal.nzhead numeral).
Proof. induction numeral; cbn; now rewrite ?IHnumeral. Qed.

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
Lemma remove_leading_zeroes_unsigned numeral :
  without_leading_zeroes (NilZero.string_of_uint numeral) =
  NilEmpty.string_of_uint (Decimal.nzhead numeral).
Proof. destruct numeral; [reflexivity|apply remove_leading_zeroes_decimal..]. Qed.
Lemma unsigned_text_unsigned_decimal numeral :
  unsigned_text (NilZero.string_of_uint numeral) = (false,NilZero.string_of_uint numeral).
Proof. destruct numeral; reflexivity. Qed.
Lemma normalized_unsigned_decimal numeral :
  normalized_decimal (NilZero.string_of_uint numeral) =
  (false,NilEmpty.string_of_uint (Decimal.unorm numeral)).
Proof.
 unfold normalized_decimal. rewrite unsigned_text_unsigned_decimal.
 rewrite remove_leading_zeroes_unsigned. unfold Decimal.unorm.
 destruct (Decimal.nzhead numeral); reflexivity.
Qed.
Definition decimal_normal_pair (numeral : Decimal.int) : bool * string :=
  match Decimal.norm numeral with
  | Decimal.Pos magnitude => (false,NilEmpty.string_of_uint magnitude)
  | Decimal.Neg magnitude => (true,NilEmpty.string_of_uint magnitude)
  end.
Lemma normalized_signed_decimal numeral :
  normalized_decimal (NilZero.string_of_int numeral) = decimal_normal_pair numeral.
Proof.
 destruct numeral as [magnitude|magnitude].
 - apply normalized_unsigned_decimal.
 - unfold NilZero.string_of_int, normalized_decimal.
   change ((let magnitude := without_leading_zeroes (NilZero.string_of_uint magnitude) in
       match magnitude with EmptyString => (false,"0"%string) | _ => (true,magnitude) end) = decimal_normal_pair (Decimal.Neg magnitude)).
   rewrite remove_leading_zeroes_unsigned. unfold decimal_normal_pair, Decimal.norm.
   destruct (Decimal.nzhead magnitude); reflexivity.
Qed.



Lemma decimal_positive_head_value magnitude :
  (0 < DecimalPos.Unsigned.hd magnitude)%N -> 0 < Z.of_uint magnitude.
Proof.
 intro positive. pose proof (decimal_nonzero_head_lower magnitude positive).
 pose proof (Z.pow_pos_nonneg 10 (Z.of_nat (Decimal.nb_digits magnitude) - 1)).
 destruct magnitude; cbn [DecimalPos.Unsigned.hd Decimal.nb_digits] in *; try lia.
Qed.
Definition exponent_denotes (source : string) (value : Z) : Prop :=
  exists negative digits numeral,
    unsigned_text source = (negative,digits) /\
    NilZero.uint_of_string digits = Some numeral /\
    value = Z.of_int (if negative then Decimal.Neg numeral else Decimal.Pos numeral).
Lemma normalized_exponent_standard_decimal source value :
  exponent_denotes source value ->
  exists numeral, normalized_decimal source = normalized_decimal (NilZero.string_of_int numeral) /\
    value = Z.of_int numeral.
Proof.
 intros [negative [digits [numeral [pieces [parsed value_equality]]]]].
 exists (if negative then Decimal.Neg numeral else Decimal.Pos numeral).
 split; [|exact value_equality].
 apply NilZero.sus in parsed. subst digits.
 unfold normalized_decimal at 1. rewrite pieces.
 destruct negative; [reflexivity|].
 unfold NilZero.string_of_int, normalized_decimal.
 now rewrite unsigned_text_unsigned_decimal.
Qed.
Lemma canonical_unsigned_printing_agrees numeral :
  canonical_decimal numeral -> NilZero.string_of_uint numeral = NilEmpty.string_of_uint numeral.
Proof. intro canonical; destruct numeral; [exfalso; now apply (canonical_decimal_nonempty _ canonical)|reflexivity..]. Qed.

Theorem parse_normalized_exponent_exact source value :
  exponent_denotes source value ->
  (let '(negative,digits) := normalized_decimal source in
   parse_signed_digits negative digits) = Some value.
Proof.
  intro denotes. destruct (normalized_exponent_standard_decimal source value denotes)
    as [numeral [normal meaning]].
  rewrite normal, meaning, <- (DecimalZ.of_int_norm numeral), normalized_signed_decimal.
  assert (nonempty : Decimal.abs (Decimal.norm numeral) <> Decimal.Nil).
  { rewrite DecimalFacts.abs_norm. apply DecimalFacts.unorm_nonnil. }
  unfold decimal_normal_pair.
  destruct (Decimal.norm numeral); cbn [Decimal.abs] in nonempty;
    unfold parse_signed_digits;
    replace (NilEmpty.string_of_uint d) with (NilZero.string_of_uint d)
      by (destruct d; contradiction || reflexivity);
    rewrite NilZero.usu by assumption; reflexivity.
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
Lemma normalized_magnitude_value numeral :
  Z.of_uint (Decimal.abs (Decimal.norm numeral)) = Z.abs (Z.of_int numeral).
Proof.
  rewrite <- (DecimalZ.of_int_norm numeral).
  destruct (Decimal.norm numeral); cbn [Decimal.abs Z.of_int];
    rewrite ?Z.abs_opp, Z.abs_eq by apply decimal_value_nonnegative; reflexivity.
Qed.
Lemma normalized_magnitude_width numeral :
  String.length (snd (normalized_decimal (NilZero.string_of_int numeral))) =
  Decimal.nb_digits (Decimal.abs (Decimal.norm numeral)).
Proof.
  rewrite normalized_signed_decimal. unfold decimal_normal_pair.
  destruct (Decimal.norm numeral); cbn [snd Decimal.abs]; apply decimal_render_size.
Qed.
Lemma normalized_decimal_width_order left right :
  Z.abs (Z.of_int left) <= Z.abs (Z.of_int right) ->
  (String.length (snd (normalized_decimal (NilZero.string_of_int left))) <=
   String.length (snd (normalized_decimal (NilZero.string_of_int right))))%nat.
Proof.
  intro values. rewrite !normalized_magnitude_width.
  apply canonical_decimal_width_order;
    [rewrite DecimalFacts.abs_norm; apply unsigned_normal_form_canonical
    |rewrite DecimalFacts.abs_norm; apply unsigned_normal_form_canonical
    |now rewrite !normalized_magnitude_value].
Qed.
Lemma exponent_in_interval_fits_digits source value lower upper :
  exponent_denotes source value -> lower <= value <= upper ->
  (String.length (snd (normalized_decimal source)) <= exponent_digit_limit lower upper)%nat.
Proof.
  intros denotes bounds.
  destruct (normalized_exponent_standard_decimal source value denotes)
    as [numeral [normal meaning]].
  rewrite normal. unfold exponent_digit_limit, show_integer.
  destruct (Z_le_gt_dec value 0) as [negative|positive].
  - eapply Nat.le_trans; [|apply Nat.le_max_l].
    apply normalized_decimal_width_order. rewrite DecimalZ.of_to, <- meaning.
    rewrite !Z.abs_neq by lia. lia.
  - eapply Nat.le_trans; [|apply Nat.le_max_r].
    apply normalized_decimal_width_order. rewrite DecimalZ.of_to, <- meaning.
    rewrite !Z.abs_eq by lia. lia.
Qed.
Theorem bounded_exponent_outcome source value lower upper :
  exponent_denotes source value ->
  parse_bounded_exponent source lower upper =
    if ((lower <=? value) && (value <=? upper))%Z then Some value else None.
Proof.
  intro denotes. pose proof (parse_normalized_exponent_exact source value denotes) as parsed.
  unfold parse_bounded_exponent.
  destruct (normalized_decimal source) as [negative digits] eqn:normal; cbn [fst snd] in parsed.
  destruct (Nat.leb (String.length digits) (exponent_digit_limit lower upper)) eqn:fits.
  - now rewrite parsed.
  - destruct ((lower <=? value) && (value <=? upper))%Z eqn:inside; [|reflexivity].
    apply Bool.andb_true_iff in inside as [low high].
    apply Z.leb_le in low,high.
    pose proof (exponent_in_interval_fits_digits source value lower upper denotes (conj low high)) as bound.
    rewrite normal in bound; cbn [snd] in bound. apply Nat.leb_gt in fits. lia.
Qed.
