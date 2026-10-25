From Stdlib Require Import String Ascii Bool ZArith NArith Lia DecimalString DecimalZ DecimalPos DecimalFacts List.
From Selvedge.Foundation Require Import BoundedInteger BoundedIntegerProofs BoundedIntegerSemantics.
Open Scope string_scope.
Open Scope Z_scope.

Lemma decimal_app_step left right : Decimal.app left right =
 match left with
 | Decimal.Nil => right | Decimal.D0 rest => Decimal.D0 (Decimal.app rest right)
 | Decimal.D1 rest => Decimal.D1 (Decimal.app rest right) | Decimal.D2 rest => Decimal.D2 (Decimal.app rest right)
 | Decimal.D3 rest => Decimal.D3 (Decimal.app rest right) | Decimal.D4 rest => Decimal.D4 (Decimal.app rest right)
 | Decimal.D5 rest => Decimal.D5 (Decimal.app rest right) | Decimal.D6 rest => Decimal.D6 (Decimal.app rest right)
 | Decimal.D7 rest => Decimal.D7 (Decimal.app rest right) | Decimal.D8 rest => Decimal.D8 (Decimal.app rest right)
 | Decimal.D9 rest => Decimal.D9 (Decimal.app rest right) end.
Proof.
 destruct left; apply DecimalFacts.to_list_inj; rewrite !DecimalFacts.app_spec;
 cbn; now rewrite ?DecimalFacts.app_spec.
Qed.
Lemma decimal_render_app left right :
 NilEmpty.string_of_uint (Decimal.app left right) = NilEmpty.string_of_uint left ++ NilEmpty.string_of_uint right.
Proof. induction left; rewrite decimal_app_step; cbn; now rewrite ?IHleft. Qed.

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

Lemma zero_digits_value numeral :
 only_zeroes (NilEmpty.string_of_uint numeral) = true <-> Z.of_uint numeral = 0.
Proof.
 induction numeral; [cbn; tauto|..]; rewrite decimal_value_head;
 cbn [NilEmpty.string_of_uint only_zeroes DecimalPos.Unsigned.hd DecimalPos.Unsigned.tl];
 pose proof (decimal_value_nonnegative numeral);
 pose proof (Z.pow_pos_nonneg 10 (Z.of_nat (Decimal.nb_digits numeral)) ltac:(lia) ltac:(lia));
 cbn [Z.of_N]; try (rewrite IHnumeral; split; intro; lia).
 all: split; intro E; [discriminate|exfalso; nia].
Qed.

Lemma zeroes_render count : zeroes count = NilEmpty.string_of_uint (Nat.iter count Decimal.D0 Decimal.Nil).
Proof. induction count; cbn; now rewrite ?IHcount. Qed.
Lemma iter_ten_power count value : Nat.iter count (Z.mul 10) value = value * 10 ^ Z.of_nat count.
Proof.
 revert value; induction count; intro value; cbn [Nat.iter]; [change (value = value * 1); ring|].
 rewrite Nat.iter_succ, IHcount, Nat2Z.inj_succ, Z.pow_succ_r by lia. ring.
Qed.

Lemma appended_zeroes_exact coefficient numeral count :
 NilZero.uint_of_string coefficient = Some numeral ->
 exists result, NilZero.uint_of_string (coefficient ++ zeroes count) = Some result /\
 Z.of_uint result = Z.of_uint numeral * 10 ^ Z.of_nat count.
Proof.
 intro parsed. pose proof (NilZero.sus coefficient numeral parsed) as rendered.
 assert (nonempty : numeral <> Decimal.Nil).
 { intro empty; subst numeral. cbn [NilZero.string_of_uint] in rendered.
   subst coefficient; discriminate parsed. }
 assert (rendered_empty : NilEmpty.string_of_uint numeral = coefficient).
 { destruct numeral; [contradiction|..]; exact rendered. }
 assert (app_nonempty : Decimal.app numeral (Nat.iter count Decimal.D0 Decimal.Nil) <> Decimal.Nil).
 { destruct numeral; [contradiction|..]; rewrite decimal_app_step; discriminate. }
 exists (Decimal.app numeral (Nat.iter count Decimal.D0 Decimal.Nil)). split.
 - rewrite <-rendered_empty, zeroes_render, <-decimal_render_app.
   assert (same : NilZero.string_of_uint (Decimal.app numeral (Nat.iter count Decimal.D0 Decimal.Nil)) =
      NilEmpty.string_of_uint (Decimal.app numeral (Nat.iter count Decimal.D0 Decimal.Nil)))
     by (destruct (Decimal.app numeral (Nat.iter count Decimal.D0 Decimal.Nil)) eqn:E; [exfalso; apply app_nonempty; reflexivity|reflexivity..]).
   rewrite <-same. now apply NilZero.usu.
 - rewrite DecimalZ.of_uint_iter_D0. apply iter_ten_power.
Qed.

Lemma substring_full source total : (String.length source <= total)%nat -> substring 0 total source = source.
Proof.
 revert total; induction source; intros total enough; destruct total; cbn in *; try reflexivity; try lia.
 f_equal. apply IHsource. lia.
Qed.
Fixpoint decimal_cut count numeral : Decimal.uint * Decimal.uint :=
 match count with
 | O => (Decimal.Nil,numeral)
 | S rest => match numeral with
 | Decimal.Nil => (Decimal.Nil,Decimal.Nil)
 | Decimal.D0 tail => let '(prefix,suffix) := decimal_cut rest tail in (Decimal.D0 prefix,suffix)
 | Decimal.D1 tail => let '(prefix,suffix) := decimal_cut rest tail in (Decimal.D1 prefix,suffix)
 | Decimal.D2 tail => let '(prefix,suffix) := decimal_cut rest tail in (Decimal.D2 prefix,suffix)
 | Decimal.D3 tail => let '(prefix,suffix) := decimal_cut rest tail in (Decimal.D3 prefix,suffix)
 | Decimal.D4 tail => let '(prefix,suffix) := decimal_cut rest tail in (Decimal.D4 prefix,suffix)
 | Decimal.D5 tail => let '(prefix,suffix) := decimal_cut rest tail in (Decimal.D5 prefix,suffix)
 | Decimal.D6 tail => let '(prefix,suffix) := decimal_cut rest tail in (Decimal.D6 prefix,suffix)
 | Decimal.D7 tail => let '(prefix,suffix) := decimal_cut rest tail in (Decimal.D7 prefix,suffix)
 | Decimal.D8 tail => let '(prefix,suffix) := decimal_cut rest tail in (Decimal.D8 prefix,suffix)
 | Decimal.D9 tail => let '(prefix,suffix) := decimal_cut rest tail in (Decimal.D9 prefix,suffix)
 end end.
Lemma decimal_cut_properties count numeral :
 let '(prefix,suffix) := decimal_cut count numeral in
 Decimal.app prefix suffix = numeral /\
 String.length (NilEmpty.string_of_uint prefix) = Nat.min count (String.length (NilEmpty.string_of_uint numeral)) /\
 substring 0 count (NilEmpty.string_of_uint numeral) = NilEmpty.string_of_uint prefix /\
 forall total, (String.length (NilEmpty.string_of_uint numeral) <= total)%nat ->
 substring count total (NilEmpty.string_of_uint numeral) = NilEmpty.string_of_uint suffix.
Proof.
 revert numeral. induction count as [|count IH]; intro numeral.
 - cbn [decimal_cut]. rewrite DecimalFacts.app_nil_l. repeat split; try reflexivity.
   + destruct numeral; reflexivity.
   + intros. now apply substring_full.
 - destruct numeral; cbn [decimal_cut]; [repeat split; reflexivity|..].
   all: destruct (decimal_cut count numeral) as [prefix suffix] eqn:Cut;
     specialize (IH numeral); rewrite Cut in IH;
     destruct IH as [Join [Size [Prefix Suffix]]];
     rewrite decimal_app_step; cbn [NilEmpty.string_of_uint];
     repeat split.
   all: try (f_equal; exact Join).
   all: try (cbn [String.length Nat.min]; now rewrite Size).
   all: try (cbn [substring]; now rewrite Prefix).
   all: intros total Enough; destruct total; [cbn in Enough; lia|];
     cbn [substring]; apply Suffix; cbn [String.length] in Enough; lia.
Qed.

Lemma parsed_uint_render source numeral :
 NilZero.uint_of_string source = Some numeral -> NilEmpty.string_of_uint numeral = source.
Proof. destruct source; cbn [NilZero.uint_of_string]; try discriminate; apply NilEmpty.sus. Qed.
Lemma canonical_positive_head numeral :
 canonical_decimal numeral -> 0 < Z.of_uint numeral -> (0 < DecimalPos.Unsigned.hd numeral)%N.
Proof. intros [Zero|Head] Positive; [subst numeral; cbn in Positive; lia|exact Head]. Qed.
Lemma positive_decimal_head numeral :
 (0 < DecimalPos.Unsigned.hd numeral)%N -> 0 < Z.of_uint numeral.
Proof.
 intro Head. pose proof (decimal_nonzero_head_lower numeral Head) as Lower.
 assert (Width : (1 <= Decimal.nb_digits numeral)%nat).
 { destruct numeral; cbn [DecimalPos.Unsigned.hd Decimal.nb_digits] in *; lia. }
 assert (0 <= Z.of_nat (Decimal.nb_digits numeral) - 1) by lia.
 pose proof (Z.pow_pos_nonneg 10 (Z.of_nat (Decimal.nb_digits numeral) - 1) ltac:(lia) H). lia.
Qed.
Lemma cut_preserves_head count numeral prefix suffix :
 (0 < count)%nat -> decimal_cut count numeral = (prefix,suffix) ->
 DecimalPos.Unsigned.hd prefix = DecimalPos.Unsigned.hd numeral.
Proof.
 destruct count; [lia|]. destruct numeral; cbn [decimal_cut]; intros Positive Cut;
 try (inversion Cut; reflexivity).
 all: destruct (decimal_cut count numeral); inversion Cut; reflexivity.
Qed.
Lemma appended_preserves_canonical numeral suffix :
 (0 < DecimalPos.Unsigned.hd numeral)%N -> canonical_decimal (Decimal.app numeral suffix).
Proof.
 destruct numeral; intro Head; cbn [DecimalPos.Unsigned.hd] in Head; try lia;
 rewrite decimal_app_step; right; exact Head.
Qed.
Lemma cut_value_bounds source numeral count prefix suffix :
 NilZero.uint_of_string source = Some numeral ->
 (count <= String.length source)%nat -> decimal_cut count numeral = (prefix,suffix) ->
 Z.of_uint numeral = Z.of_uint prefix * 10 ^ Z.of_nat (String.length source - count) + Z.of_uint suffix /\
 0 <= Z.of_uint suffix < 10 ^ Z.of_nat (String.length source - count).
Proof.
 intros Parsed Count Cut.
 pose proof (decimal_cut_properties count numeral) as Properties; rewrite Cut in Properties.
 destruct Properties as [Join [Size [Prefix Suffix]]].
 pose proof (parsed_uint_render source numeral Parsed) as Render.
 assert (SuffixSize : Decimal.nb_digits suffix = (String.length source - count)%nat).
 { rewrite <-decimal_render_size. rewrite <-Render in Count.
   rewrite Nat.min_l in Size by exact Count.
   pose proof (f_equal String.length (decimal_render_app prefix suffix)) as Length.
   rewrite Join, append_length, Size, Render in Length. lia. }
 split.
 - rewrite <-Join at 1. rewrite decimal_app_value, SuffixSize. reflexivity.
 - split; [apply decimal_value_nonnegative|].
   rewrite <-SuffixSize. apply decimal_value_below_power.
Qed.

Lemma nonempty_render_parses numeral : numeral <> Decimal.Nil ->
 NilZero.uint_of_string (NilEmpty.string_of_uint numeral) = Some numeral.
Proof. destruct numeral; [contradiction|..]; intros; apply NilEmpty.usu. Qed.
Lemma zero_digits_boolean numeral :
 only_zeroes (NilEmpty.string_of_uint numeral) = Z.eqb (Z.of_uint numeral) 0.
Proof. apply Bool.eq_true_iff_eq. rewrite zero_digits_value, Z.eqb_eq. tauto. Qed.
Lemma integral_negative_spec coefficient numeral shift :
 NilZero.uint_of_string coefficient = Some numeral -> canonical_decimal numeral -> 0 < Z.of_uint numeral ->
 shift < 0 -> 1 - Z.of_nat (String.length coefficient) <= shift ->
 exists prefix suffix,
 integral_digits coefficient shift =
   (if Z.eqb (Z.of_uint suffix) 0 then Some (NilEmpty.string_of_uint prefix) else None) /\
 NilZero.uint_of_string (NilEmpty.string_of_uint prefix) = Some prefix /\
 canonical_decimal prefix /\ 0 < Z.of_uint prefix /\
 Z.of_uint numeral = Z.of_uint prefix * 10 ^ (-shift) + Z.of_uint suffix /\
 0 <= Z.of_uint suffix < 10 ^ (-shift).
Proof.
 intros Parsed Canonical Positive Negative Window.
 pose proof (parsed_uint_render coefficient numeral Parsed) as Render.
 assert (Drop : Z.of_nat (Z.to_nat (-shift)) = -shift) by (apply Z2Nat.id; lia).
 assert (Smaller : (Z.to_nat (-shift) < String.length coefficient)%nat) by lia.
 set (keep := (String.length coefficient - Z.to_nat (-shift))%nat).
 assert (KeepPositive : (0 < keep)%nat) by (unfold keep; lia).
 assert (KeepBound : (keep <= String.length coefficient)%nat) by (unfold keep; lia).
 destruct (decimal_cut keep numeral) as [prefix suffix] eqn:Cut.
 pose proof (decimal_cut_properties keep numeral) as Properties; rewrite Cut in Properties.
 destruct Properties as [Join [Size [Prefix Suffix]]].
 pose proof (canonical_positive_head numeral Canonical Positive) as Head.
 pose proof (cut_preserves_head keep numeral prefix suffix KeepPositive Cut) as SameHead.
 assert (PrefixHead : (0 < DecimalPos.Unsigned.hd prefix)%N) by (rewrite SameHead; exact Head).
 assert (PrefixNonempty : prefix <> Decimal.Nil) by (intro Empty; subst prefix; cbn in PrefixHead; lia).
 pose proof (cut_value_bounds coefficient numeral keep prefix suffix Parsed KeepBound Cut) as [Value Bounds].
 assert (Removed : (String.length coefficient - keep)%nat = Z.to_nat (-shift)) by (unfold keep; lia).
 rewrite Removed, Drop in Value, Bounds.
 exists prefix, suffix. split.
 - unfold integral_digits. rewrite (proj2 (Z.ltb_lt shift 0) Negative).
   fold keep. rewrite <-Render, Prefix, Suffix by (rewrite Render; lia).
   now rewrite zero_digits_boolean.
 - repeat split.
   + now apply nonempty_render_parses.
   + right; exact PrefixHead.
   + now apply positive_decimal_head.
   + exact Value.
   + exact (proj1 Bounds).
   + exact (proj2 Bounds).
Qed.

Lemma decimal_render_injective left right :
 NilEmpty.string_of_uint left = NilEmpty.string_of_uint right -> left = right.
Proof.
 intro Same. apply (f_equal NilEmpty.uint_of_string) in Same.
 rewrite !NilEmpty.usu in Same. now inversion Same.
Qed.
Lemma integral_nonnegative_spec coefficient numeral shift :
 NilZero.uint_of_string coefficient = Some numeral -> canonical_decimal numeral -> 0 < Z.of_uint numeral ->
 0 <= shift -> exists digits result,
 integral_digits coefficient shift = Some digits /\
 NilZero.uint_of_string digits = Some result /\ canonical_decimal result /\
 0 < Z.of_uint result /\ Z.of_uint result = Z.of_uint numeral * 10 ^ shift.
Proof.
 intros Parsed Canonical Positive Nonnegative.
 destruct (appended_zeroes_exact coefficient numeral (Z.to_nat shift) Parsed) as [result [ParsedResult Value]].
 assert (Shift : Z.of_nat (Z.to_nat shift) = shift) by now apply Z2Nat.id.
 rewrite Shift in Value.
 assert (ResultForm : result = Decimal.app numeral (Nat.iter (Z.to_nat shift) Decimal.D0 Decimal.Nil)).
 { apply decimal_render_injective. rewrite decimal_render_app, <-zeroes_render.
   rewrite (parsed_uint_render coefficient numeral Parsed).
   now apply parsed_uint_render. }
 exists (coefficient ++ zeroes (Z.to_nat shift)), result. repeat split.
 - unfold integral_digits. rewrite (proj2 (Z.ltb_ge shift 0) Nonnegative). reflexivity.
 - exact ParsedResult.
 - rewrite ResultForm. apply appended_preserves_canonical. now apply canonical_positive_head.
 - rewrite Value. apply Z.mul_pos_pos; [exact Positive|]. now apply Z.pow_pos_nonneg.
 - exact Value.
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

Theorem integral_digits_sound coefficient numeral shift digits :
 NilZero.uint_of_string coefficient = Some numeral -> canonical_decimal numeral -> 0 < Z.of_uint numeral ->
 1 - Z.of_nat (String.length coefficient) <= shift -> integral_digits coefficient shift = Some digits ->
 exists result, NilZero.uint_of_string digits = Some result /\ canonical_decimal result /\
 0 < Z.of_uint result /\ decimal_integer_magnitude (Z.of_uint numeral) 0 shift (Z.of_uint result).
Proof.
 intros Parsed Canonical Positive Window Decoded.
 destruct (Z.lt_ge_cases shift 0) as [Negative|Nonnegative].
 - destruct (integral_negative_spec coefficient numeral shift Parsed Canonical Positive Negative Window)
   as [prefix [suffix [Integral [ParsedPrefix [CanonicalPrefix [PositivePrefix [Value Bounds]]]]]]].
   rewrite Integral in Decoded. destruct (Z.eqb (Z.of_uint suffix) 0) eqn:Zero; [|discriminate].
   inversion Decoded; subst digits. exists prefix. repeat split; try assumption.
   apply (proj2 (integer_scale_negative _ _ _ Negative)). apply Z.eqb_eq in Zero. lia.
 - destruct (integral_nonnegative_spec coefficient numeral shift Parsed Canonical Positive Nonnegative)
   as [rendered [result [Integral [ParsedResult [CanonicalResult [PositiveResult Value]]]]]].
   rewrite Integral in Decoded. inversion Decoded; subst digits. exists result. repeat split; try assumption.
   apply (proj2 (integer_scale_nonnegative _ _ _ Nonnegative)). symmetry; exact Value.
Qed.

Theorem integral_digits_complete coefficient numeral shift magnitude :
 NilZero.uint_of_string coefficient = Some numeral -> canonical_decimal numeral -> 0 < Z.of_uint numeral ->
 1 - Z.of_nat (String.length coefficient) <= shift ->
 decimal_integer_magnitude (Z.of_uint numeral) 0 shift magnitude -> 0 < magnitude ->
 exists digits result, integral_digits coefficient shift = Some digits /\
 NilZero.uint_of_string digits = Some result /\ canonical_decimal result /\ Z.of_uint result = magnitude.
Proof.
 intros Parsed Canonical Positive Window Mathematical MagnitudePositive.
 destruct (Z.lt_ge_cases shift 0) as [Negative|Nonnegative].
 - destruct (integral_negative_spec coefficient numeral shift Parsed Canonical Positive Negative Window)
   as [prefix [suffix [Integral [ParsedPrefix [CanonicalPrefix [PositivePrefix [Value Bounds]]]]]]].
   apply (proj1 (integer_scale_negative _ _ _ Negative)) in Mathematical.
   assert (PowerPositive : 0 < 10 ^ (-shift)) by (apply Z.pow_pos_nonneg; lia).
   pose proof (Z.mod_unique (Z.of_uint numeral) (10 ^ (-shift)) (Z.of_uint prefix) (Z.of_uint suffix)
     (or_introl Bounds) ltac:(nia)) as Remainder.
   rewrite Mathematical, Z.mod_mul in Remainder by lia.
   assert (Same : Z.of_uint prefix = magnitude).
   { apply (Z.mul_reg_r _ _ (10 ^ (-shift))); [lia|]. nia. }
   exists (NilEmpty.string_of_uint prefix), prefix. repeat split; try assumption.
   rewrite Integral, Remainder, Z.eqb_refl. reflexivity.
 - destruct (integral_nonnegative_spec coefficient numeral shift Parsed Canonical Positive Nonnegative)
   as [digits [result [Integral [ParsedResult [CanonicalResult [PositiveResult Value]]]]]].
   apply (proj1 (integer_scale_nonnegative _ _ _ Nonnegative)) in Mathematical.
   exists digits, result. repeat split; try assumption. lia.
Qed.

Theorem integral_digits_exact coefficient numeral shift magnitude :
 NilZero.uint_of_string coefficient = Some numeral -> canonical_decimal numeral -> 0 < Z.of_uint numeral ->
 1 - Z.of_nat (String.length coefficient) <= shift ->
 ((exists digits result, integral_digits coefficient shift = Some digits /\
    NilZero.uint_of_string digits = Some result /\ Z.of_uint result = magnitude) <->
  decimal_integer_magnitude (Z.of_uint numeral) 0 shift magnitude /\ 0 < magnitude).
Proof.
 intros Parsed Canonical Positive Window. split.
 - intros [digits [result [Integral [ParsedResult Value]]]].
   destruct (integral_digits_sound coefficient numeral shift digits Parsed Canonical Positive Window Integral)
     as [actual [ParsedActual [CanonicalActual [PositiveActual Mathematical]]]].
   rewrite ParsedResult in ParsedActual; inversion ParsedActual; subst actual.
   now rewrite <-Value.
 - intros [Mathematical MagnitudePositive].
   destruct (integral_digits_complete coefficient numeral shift magnitude Parsed Canonical Positive Window
     Mathematical MagnitudePositive) as [digits [result [Integral [ParsedResult [CanonicalResult Value]]]]].
   exists digits, result. auto.
Qed.
