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
Lemma decimal_render_compare_heads left right :
  left <> Decimal.Nil -> right <> Decimal.Nil ->
  String.compare (NilEmpty.string_of_uint left) (NilEmpty.string_of_uint right) =
  match N.compare (DecimalPos.Unsigned.hd left) (DecimalPos.Unsigned.hd right) with
  | Eq => String.compare (NilEmpty.string_of_uint (DecimalPos.Unsigned.tl left))
                         (NilEmpty.string_of_uint (DecimalPos.Unsigned.tl right))
  | result => result
  end.
Proof. destruct left; destruct right; cbn; intros; congruence. Qed.

Lemma positional_compare_same_width dl dr vl vr power :
  0 <= vl < power -> 0 <= vr < power ->
  Z.compare (dl * power + vl) (dr * power + vr) =
  match Z.compare dl dr with Eq => Z.compare vl vr | result => result end.
Proof.
 intros [vl_nonnegative vl_upper] [vr_nonnegative vr_upper].
 destruct (Z.compare_spec dl dr) as [equal|less|greater].
 - subst dr. destruct (Z.compare_spec vl vr); apply Z.compare_eq_iff || apply Z.compare_lt_iff || apply Z.compare_gt_iff; nia.
 - apply Z.compare_lt_iff. nia.
 - apply Z.compare_gt_iff. nia.
Qed.

Lemma decimal_equal_width_compare left right :
  Decimal.nb_digits left = Decimal.nb_digits right ->
  String.compare (NilEmpty.string_of_uint left) (NilEmpty.string_of_uint right) =
  Z.compare (Z.of_uint left) (Z.of_uint right).
Proof.
 revert right. induction left; intros right same_width; destruct right;
   cbn [Decimal.nb_digits] in same_width; try discriminate; [reflexivity|..];
   inversion same_width as [same_tail_width];
   rewrite decimal_render_compare_heads by discriminate;
   match goal with
   | |- _ = Z.compare (Z.of_uint ?left) (Z.of_uint ?right) =>
     rewrite (decimal_value_head left), (decimal_value_head right)
   end;
   cbn [DecimalPos.Unsigned.hd DecimalPos.Unsigned.tl];
   rewrite <- same_tail_width;
   rewrite positional_compare_same_width by
     (split; [apply decimal_value_nonnegative|first [apply decimal_value_below_power|rewrite same_tail_width; apply decimal_value_below_power]]);
   rewrite <- N2Z.inj_compare;
   cbn [N.compare]; try reflexivity;
   apply IHleft; exact same_tail_width.
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
Theorem compare_magnitude_denotes_integer_order left right :
  canonical_decimal left -> canonical_decimal right ->
  compare_magnitude (NilEmpty.string_of_uint left) (NilEmpty.string_of_uint right) =
  Z.compare (Z.of_uint left) (Z.of_uint right).
Proof.
 intros left_canonical right_canonical. unfold compare_magnitude.
 rewrite !decimal_render_size.
 destruct (Nat.compare_spec (Decimal.nb_digits left) (Decimal.nb_digits right)) as [equal|less|greater].
 - now apply decimal_equal_width_compare.
 - symmetry. apply Z.compare_lt_iff. apply decimal_width_order; [|assumption].
   destruct right_canonical as [->|positive]; [|assumption].
   pose proof (canonical_decimal_nonempty left left_canonical).
   destruct left; cbn in less; [contradiction|lia..].
 - symmetry. apply Z.compare_gt_iff. apply decimal_width_order; [|assumption].
   destruct left_canonical as [->|positive]; [|assumption].
   pose proof (canonical_decimal_nonempty right right_canonical).
   destruct right; cbn in greater; [contradiction|lia..].
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

Definition signed_decimal_canonical numeral :=
  match numeral with
  | Decimal.Pos magnitude => canonical_decimal magnitude
  | Decimal.Neg magnitude => (0 < DecimalPos.Unsigned.hd magnitude)%N
  end.
Definition raw_decimal_pair numeral : bool * string :=
  match numeral with
  | Decimal.Pos magnitude => (false,NilEmpty.string_of_uint magnitude)
  | Decimal.Neg magnitude => (true,NilEmpty.string_of_uint magnitude)
  end.
Lemma signed_normal_form_canonical numeral : signed_decimal_canonical (Decimal.norm numeral).
Proof.
 destruct numeral as [magnitude|magnitude].
 - apply unsigned_normal_form_canonical.
 - unfold Decimal.norm. destruct (Decimal.nzhead magnitude) eqn:normal; cbn [signed_decimal_canonical].
   + now left.
   + exfalso. exact (DecimalFacts.nzhead_nonzero magnitude _ normal).
   + cbn; lia.
   + cbn; lia.
   + cbn; lia.
   + cbn; lia.
   + cbn; lia.
   + cbn; lia.
   + cbn; lia.
   + cbn; lia.
   + cbn; lia.
Qed.
Lemma decimal_positive_head_value magnitude :
  (0 < DecimalPos.Unsigned.hd magnitude)%N -> 0 < Z.of_uint magnitude.
Proof.
 intro positive. pose proof (decimal_nonzero_head_lower magnitude positive).
 pose proof (Z.pow_pos_nonneg 10 (Z.of_nat (Decimal.nb_digits magnitude) - 1)).
 destruct magnitude; cbn [DecimalPos.Unsigned.hd Decimal.nb_digits] in *; try lia.
Qed.
Lemma raw_decimal_pair_compare left right :
  signed_decimal_canonical left -> signed_decimal_canonical right ->
  compare_decimal (raw_decimal_pair left) (raw_decimal_pair right) =
  Z.compare (Z.of_int left) (Z.of_int right).
Proof.
 destruct left as [left|left]; destruct right as [right|right];
   cbn [signed_decimal_canonical raw_decimal_pair compare_decimal Z.of_int];
   intros lc rc.
 - now apply compare_magnitude_denotes_integer_order.
 - symmetry. apply Z.compare_gt_iff.
   pose proof (decimal_positive_head_value right rc).
   pose proof (decimal_value_nonnegative left). lia.
 - symmetry. apply Z.compare_lt_iff.
   pose proof (decimal_positive_head_value left lc).
   pose proof (decimal_value_nonnegative right). lia.
 - rewrite compare_magnitude_denotes_integer_order by now right.
   now rewrite Z.compare_opp.
Qed.
Theorem normalized_decimal_denotes_integer_order left right :
  compare_decimal (normalized_decimal (NilZero.string_of_int left))
                  (normalized_decimal (NilZero.string_of_int right)) =
  Z.compare (Z.of_int left) (Z.of_int right).
Proof.
 rewrite !normalized_signed_decimal.
 unfold decimal_normal_pair.
 change (compare_decimal (raw_decimal_pair (Decimal.norm left))
                         (raw_decimal_pair (Decimal.norm right)) = Z.compare (Z.of_int left) (Z.of_int right)).
 rewrite raw_decimal_pair_compare by apply signed_normal_form_canonical.
 now rewrite !DecimalZ.of_int_norm.
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
Theorem decimal_interval_exact source value lower upper :
  exponent_denotes source value ->
  (decimal_in_interval source lower upper = true <-> lower <= value <= upper).
Proof.
 intro denotes. destruct (normalized_exponent_standard_decimal source value denotes)
   as [numeral [normal value_equality]].
 unfold decimal_in_interval. rewrite normal. unfold show_integer.
 rewrite !normalized_decimal_denotes_integer_order, !DecimalZ.of_to.
 rewrite <- value_equality.
 destruct (Z.compare_spec value lower); destruct (Z.compare_spec value upper); cbn;
   split; intros; intuition lia.
Qed.

Lemma skip_digits_decimal numeral : skip_digits (NilEmpty.string_of_uint numeral) = EmptyString.
Proof. induction numeral; cbn; assumption || reflexivity. Qed.
Lemma canonical_unsigned_integer_end numeral :
  canonical_decimal numeral -> after_integer (NilEmpty.string_of_uint numeral) = Some EmptyString.
Proof.
 destruct numeral; intro canonical.
 { destruct canonical as [impossible|positive]; [discriminate|cbn in positive; lia]. }
 { destruct canonical as [same|positive].
   - inversion same; reflexivity.
   - cbn in positive; lia. }
 all: cbn [NilEmpty.string_of_uint]; unfold after_integer; cbn;
   match goal with |- context[is_digit ?c] =>
     let digit := fresh "digit" in assert (digit : is_digit c = true) by (vm_compute; reflexivity);
       rewrite digit
   end; now rewrite skip_digits_decimal.
Qed.
Lemma decimal_has_no_minus numeral :
  (match NilEmpty.string_of_uint numeral with
   | String c rest => if Ascii.eqb c "-"%char then rest else NilEmpty.string_of_uint numeral
   | EmptyString => NilEmpty.string_of_uint numeral end) = NilEmpty.string_of_uint numeral.
Proof. destruct numeral; reflexivity. Qed.
Lemma canonical_integer_lexeme numeral :
  signed_decimal_canonical numeral -> number_lexeme (NilEmpty.string_of_int numeral) = true.
Proof.
 destruct numeral as [magnitude|magnitude]; cbn [signed_decimal_canonical]; intro canonical.
 - unfold NilEmpty.string_of_int, number_lexeme.
   rewrite decimal_has_no_minus, canonical_unsigned_integer_end by assumption. reflexivity.
 - assert (magnitude_canonical : canonical_decimal magnitude) by now right.
   unfold NilEmpty.string_of_int, number_lexeme. cbn.
   rewrite canonical_unsigned_integer_end by assumption. reflexivity.
Qed.

Lemma canonical_unsigned_printing_agrees numeral :
  canonical_decimal numeral -> NilZero.string_of_uint numeral = NilEmpty.string_of_uint numeral.
Proof. intro canonical; destruct numeral; [exfalso; now apply (canonical_decimal_nonempty _ canonical)|reflexivity..]. Qed.
Lemma canonical_signed_printing_agrees numeral :
  signed_decimal_canonical numeral -> NilZero.string_of_int numeral = NilEmpty.string_of_int numeral.
Proof.
 destruct numeral as [magnitude|magnitude]; intro canonical;
 unfold NilZero.string_of_int, NilEmpty.string_of_int;
 rewrite canonical_unsigned_printing_agrees; [reflexivity|exact canonical|reflexivity|now right].
Qed.
Lemma canonical_signed_nonnil numeral :
  signed_decimal_canonical numeral -> numeral <> Decimal.Pos Decimal.Nil /\ numeral <> Decimal.Neg Decimal.Nil.
Proof.
 destruct numeral as [magnitude|magnitude]; intro canonical; split; try discriminate;
   intros equal; inversion equal; subst;
   cbn [signed_decimal_canonical] in canonical.
 - exact (canonical_decimal_nonempty _ canonical eq_refl).
 - cbn in canonical; lia.
Qed.
Theorem parse_normal_form_integer numeral :
  parse_integer (NilZero.string_of_int (Decimal.norm numeral)) = Some (Z.of_int numeral).
Proof.
 pose proof (signed_normal_form_canonical numeral) as canonical.
 unfold parse_integer.
 rewrite canonical_signed_printing_agrees at 1 by assumption.
 rewrite canonical_integer_lexeme by assumption.
 destruct (canonical_signed_nonnil _ canonical) as [nonempty_positive nonempty_negative].
 rewrite NilZero.isi by assumption.
 now rewrite DecimalZ.of_int_norm.
Qed.
Definition signed_pair_text (decimal : bool * string) : string :=
  if fst decimal then ("-" ++ snd decimal)%string else snd decimal.
Lemma canonical_pair_printing numeral :
  signed_decimal_canonical numeral ->
  signed_pair_text (raw_decimal_pair numeral) = NilZero.string_of_int numeral.
Proof.
 destruct numeral as [magnitude|magnitude]; intro canonical;
   cbn [raw_decimal_pair signed_pair_text NilZero.string_of_int];
   rewrite canonical_unsigned_printing_agrees; [reflexivity|exact canonical|reflexivity|now right].
Qed.
Lemma normalized_pair_printing numeral :
  signed_pair_text (normalized_decimal (NilZero.string_of_int numeral)) =
  NilZero.string_of_int (Decimal.norm numeral).
Proof.
 rewrite normalized_signed_decimal. unfold decimal_normal_pair.
 change (signed_pair_text (raw_decimal_pair (Decimal.norm numeral)) = NilZero.string_of_int (Decimal.norm numeral)).
 now apply canonical_pair_printing, signed_normal_form_canonical.
Qed.
Theorem parse_normalized_exponent_exact source value :
  exponent_denotes source value ->
  parse_integer (signed_pair_text (normalized_decimal source)) = Some value.
Proof.
 intro denotes. destruct (normalized_exponent_standard_decimal source value denotes)
   as [numeral [normal value_equality]].
 rewrite normal, normalized_pair_printing, parse_normal_form_integer.
 now rewrite value_equality.
Qed.
