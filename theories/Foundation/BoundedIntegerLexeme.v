From Stdlib Require Import String Ascii Bool ZArith NArith Lia DecimalString.
From Selvedge.Foundation Require Import Numbers BoundedInteger BoundedIntegerSemantics.
Open Scope string_scope.

Record decimal_parts := {
  parts_negative : bool;
  parts_coefficient : string;
  parts_fraction_digits : nat;
  parts_exponent : string
}.
Definition split_number (source : string) : decimal_parts :=
  let '(negative,unsigned) := unsigned_text source in
  let '(whole,rest) := take_digits unsigned in
  let '(fraction,remaining) :=
    match rest with
    | String c digits => if Ascii.eqb c "." then take_digits digits else ("",rest)
    | _ => ("",rest)
    end in
  {| parts_negative := negative;
     parts_coefficient := whole ++ fraction;
     parts_fraction_digits := String.length fraction;
     parts_exponent := match remaining with String _ digits => digits | _ => "0" end |}.

Theorem decode_safe_integer_split source :
  decode_safe_integer source =
  if number_lexeme source then
    let parts := split_number source in
    decode_coefficient (parts_negative parts) (parts_coefficient parts)
      (parts_fraction_digits parts) (parts_exponent parts)
  else None.
Proof.
 unfold decode_safe_integer, split_number. destruct (number_lexeme source); [|reflexivity].
 destruct (unsigned_text source) as [negative unsigned].
 destruct (take_digits unsigned) as [whole rest].
 destruct (match rest with
 | String c digits => if Ascii.eqb c "."%char then take_digits digits else ("",rest)
 | _ => ("",rest) end) as [fraction remaining]. reflexivity.
Qed.

Lemma skip_digits_length source :
  (String.length (skip_digits source) <= String.length source)%nat.
Proof.
 induction source as [|head tail IH]; cbn; [lia|].
 destruct (is_digit head); cbn; lia.
Qed.
Lemma take_digits_digit head tail :
  is_digit head = true ->
  take_digits (String head tail) =
    let '(digits,rest) := take_digits tail in (String head digits,rest).
Proof.
 intros digit. unfold take_digits. cbn [skip_digits]. rewrite digit.
 cbn [String.length]. rewrite Nat.sub_succ_l by apply skip_digits_length.
 reflexivity.
Qed.
Lemma take_digits_nondigit head tail :
  is_digit head = false -> take_digits (String head tail) = (EmptyString,String head tail).
Proof.
 intros nondigit. unfold take_digits. cbn [skip_digits]. rewrite nondigit, Nat.sub_diag.
 reflexivity.
Qed.

Lemma digit_parser_total head numeral :
  is_digit head = true -> exists parsed,
  uint_of_char head (Some numeral) = Some parsed.
Proof.
 destruct head as [[|] [|] [|] [|] [|] [|] [|] [|]];
   cbn [is_digit nat_of_ascii Ascii.nat_of_ascii Ascii.N_of_ascii uint_of_char];
   intros digit; try discriminate; eauto.
Qed.

Fixpoint all_decimal_digits (source : string) : Prop :=
 match source with EmptyString => True
 | String head tail => is_digit head = true /\ all_decimal_digits tail end.
Lemma decimal_digits_append left right :
 all_decimal_digits left -> all_decimal_digits right -> all_decimal_digits (left ++ right).
Proof.
 induction left; cbn; intros digits right_digits; [assumption|].
 destruct digits as [digit tail_digits]. split; [assumption|now apply IHleft].
Qed.
Lemma decimal_digits_parse source :
 all_decimal_digits source -> exists numeral, NilEmpty.uint_of_string source = Some numeral.
Proof.
 induction source; cbn; intros digits; [exists Decimal.Nil; reflexivity|].
 destruct digits as [digit tail_digits]. destruct (IHsource tail_digits) as [tail_decimal parsed].
 rewrite parsed. now apply digit_parser_total.
Qed.
Lemma nonempty_decimal_digits_parse source :
 source <> EmptyString -> all_decimal_digits source ->
 exists numeral, NilZero.uint_of_string source = Some numeral.
Proof.
 intros nonempty digits. destruct (decimal_digits_parse source digits) as [numeral parsed].
 exists numeral. unfold NilZero.uint_of_string. destruct source; [contradiction|assumption].
Qed.
Lemma take_digits_are_decimal source : all_decimal_digits (fst (take_digits source)).
Proof.
 induction source as [|head tail IH]; [exact I|].
 destruct (is_digit head) eqn:digit.
 - rewrite take_digits_digit by assumption. destruct (take_digits tail); cbn in *.
   now split.
 - rewrite take_digits_nondigit by assumption. exact I.
Qed.
Lemma take_digits_nonempty head tail :
 is_digit head = true -> fst (take_digits (String head tail)) <> EmptyString.
Proof.
 intros digit. rewrite take_digits_digit by assumption.
 destruct (take_digits tail). discriminate.
Qed.
Lemma skip_digits_empty_decimal source :
 skip_digits source = EmptyString -> all_decimal_digits source.
Proof.
 induction source as [|head tail IH]; cbn; intros scanned; [exact I|].
 destruct (is_digit head) eqn:digit; [|discriminate].
 split; [reflexivity|now apply IH].
Qed.
Lemma after_digits_parse source :
 after_digits source = Some EmptyString ->
 exists numeral, NilZero.uint_of_string source = Some numeral.
Proof.
 destruct source as [|head tail]; [discriminate|].
 cbn [after_digits]. destruct (is_digit head) eqn:digit; [|discriminate].
 intros parsed. inversion parsed as [scanned].
 apply nonempty_decimal_digits_parse; [discriminate|]. cbn.
 split; [assumption|now apply skip_digits_empty_decimal].
Qed.

Lemma after_exponent_nondigit source :
 after_exponent source = Some EmptyString -> skip_digits source = source.
Proof.
 destruct source as [|head tail]; [reflexivity|].
 unfold after_exponent. destruct (Ascii.eqb head "e" || Ascii.eqb head "E") eqn:marker.
 - apply Bool.orb_true_iff in marker. destruct marker as [marker|marker];
   apply Ascii.eqb_eq in marker; subst head; reflexivity.
 - discriminate.
Qed.
Lemma fractional_suffix_nondigit source remaining :
 after_fraction source = Some remaining ->
 after_exponent remaining = Some EmptyString -> skip_digits source = source.
Proof.
 destruct source as [|head tail]; [reflexivity|].
 unfold after_fraction. destruct (Ascii.eqb head ".") eqn:point.
 - apply Ascii.eqb_eq in point. subst head. reflexivity.
 - intros equality. inversion equality; subst remaining. apply after_exponent_nondigit.
Qed.
Lemma after_integer_is_scanned source rest :
 after_integer source = Some rest -> skip_digits rest = rest ->
 snd (take_digits source) = rest /\ fst (take_digits source) <> EmptyString.
Proof.
 destruct source as [|head tail]; [discriminate|].
 unfold after_integer. destruct (Ascii.eqb head "0") eqn:zero.
 - apply Ascii.eqb_eq in zero. subst head.
   intros equality no_digits. inversion equality; subst rest.
   split.
   + unfold take_digits. cbn [skip_digits]. now rewrite no_digits.
   + apply take_digits_nonempty. reflexivity.
 - destruct (is_digit head) eqn:digit; [|discriminate].
   intros equality no_digits. inversion equality; subst rest. split.
   + unfold take_digits. cbn [skip_digits]. now rewrite digit.
   + now apply take_digits_nonempty.
Qed.
Lemma after_fraction_scanned source remaining :
 after_fraction source = Some remaining ->
 (let '(digits,rest) :=
   match source with
   | String head tail => if Ascii.eqb head "." then take_digits tail else ("",source)
   | _ => ("",source) end in rest) = remaining /\
 all_decimal_digits (fst
   (match source with
   | String head tail => if Ascii.eqb head "." then take_digits tail else ("",source)
   | _ => ("",source) end)).
Proof.
 destruct source as [|head tail]; cbn [after_fraction];
   [intros equality; inversion equality; now split|].
 destruct (Ascii.eqb head ".") eqn:point; [|intros equality; inversion equality; now split].
 unfold after_digits. destruct tail as [|first rest]; [discriminate|].
 destruct (is_digit first) eqn:digit; [|discriminate].
 intros equality. inversion equality; subst remaining.
 split.
 - unfold take_digits. cbn [skip_digits]. rewrite digit. reflexivity.
 - apply take_digits_are_decimal.
Qed.

Lemma exponent_sign_digits_denote source :
 (match source with
 | String sign digits => after_digits
     (if Ascii.eqb sign "+" || Ascii.eqb sign "-" then digits else source)
 | _ => None end) = Some EmptyString ->
 exists power, exponent_denotes source power.
Proof.
 destruct source as [|sign digits]; [discriminate|].
 destruct (Ascii.eqb sign "-") eqn:minus.
 - apply Ascii.eqb_eq in minus. subst sign. cbn.
   intros parsed. destruct (after_digits_parse _ parsed) as [numeral parsed_numeral].
   exists (Z.of_int (Decimal.Neg numeral)). unfold exponent_denotes.
   exists true, digits, numeral. repeat split; assumption || reflexivity.
 - destruct (Ascii.eqb sign "+") eqn:plus.
   + apply Ascii.eqb_eq in plus. subst sign. cbn.
     intros parsed. destruct (after_digits_parse _ parsed) as [numeral parsed_numeral].
     exists (Z.of_int (Decimal.Pos numeral)). unfold exponent_denotes.
     exists false, digits, numeral. repeat split; assumption || reflexivity.
   + intros parsed.
     destruct (after_digits_parse _ parsed) as [numeral parsed_numeral].
     exists (Z.of_int (Decimal.Pos numeral)). unfold exponent_denotes.
     exists false, (String sign digits), numeral.
     repeat split; try assumption; try reflexivity.
     unfold unsigned_text. now rewrite minus, plus.
Qed.
Lemma after_exponent_denotes source :
 after_exponent source = Some EmptyString ->
 exists power, exponent_denotes
   (match source with String _ digits => digits | _ => "0" end) power.
Proof.
 destruct source as [|marker digits].
 - intros _. exists 0%Z. unfold exponent_denotes.
   exists false, "0", (Decimal.D0 Decimal.Nil). repeat split; reflexivity.
 - unfold after_exponent.
   destruct (Ascii.eqb marker "e" || Ascii.eqb marker "E"); [|discriminate].
   apply exponent_sign_digits_denote.
Qed.

Lemma after_integer_has_no_sign source rest :
 after_integer source = Some rest -> unsigned_text source = (false,source).
Proof.
 destruct source as [|head tail]; [discriminate|].
 unfold after_integer. destruct (Ascii.eqb head "0") eqn:zero.
 - apply Ascii.eqb_eq in zero. subst head. reflexivity.
 - destruct (is_digit head) eqn:digit; [|discriminate]. intros parsed.
   unfold unsigned_text. destruct (Ascii.eqb head "-") eqn:minus.
   { apply Ascii.eqb_eq in minus. subst head. discriminate digit. }
   destruct (Ascii.eqb head "+") eqn:plus; [|reflexivity].
   apply Ascii.eqb_eq in plus. subst head. discriminate digit.
Qed.
Lemma valid_number_component_scan source :
 number_lexeme source = true ->
 exists negative unsigned rest remaining,
 unsigned_text source = (negative,unsigned) /\
 after_integer unsigned = Some rest /\
 after_fraction rest = Some remaining /\
 after_exponent remaining = Some EmptyString.
Proof.
 unfold number_lexeme.
 remember (match source with
 | String head tail => if Ascii.eqb head "-" then tail else source
 | _ => source end) as unsigned eqn:unsigned_equality.
 destruct (after_integer unsigned) as [rest|] eqn:integer; [|discriminate].
 destruct (after_fraction rest) as [remaining|] eqn:fraction; [|discriminate].
 destruct (after_exponent remaining) as [suffix|] eqn:exponent; [|discriminate].
 destruct suffix; [|discriminate]. intros _.
 assert (signed : exists negative, unsigned_text source = (negative,unsigned)).
 { destruct source as [|head tail]; [exists false; now subst unsigned|].
   destruct (Ascii.eqb head "-") eqn:minus.
   - apply Ascii.eqb_eq in minus. subst head. cbn in unsigned_equality.
     exists true. subst unsigned. reflexivity.
   - subst unsigned.
     exists false. now apply (after_integer_has_no_sign _ rest). }
 destruct signed as [negative signed].
 exists negative, unsigned, rest, remaining. repeat split; assumption.
Qed.

Theorem valid_lexeme_parts_denote source :
 number_lexeme source = true ->
 exists numeral power,
 NilZero.uint_of_string (parts_coefficient (split_number source)) = Some numeral /\
 exponent_denotes (parts_exponent (split_number source)) power.
Proof.
 intros valid.
 destruct (valid_number_component_scan source valid) as
   [negative [unsigned [rest [remaining [sign [integer [fraction exponent]]]]]]].
 assert (rest_nondigit : skip_digits rest = rest)
   by (eapply fractional_suffix_nondigit; eassumption).
 destruct (after_integer_is_scanned unsigned rest integer rest_nondigit)
   as [whole_suffix whole_nonempty].
 pose proof (take_digits_are_decimal unsigned) as whole_digits.
 destruct (take_digits unsigned) as [whole suffix] eqn:whole_scan.
 cbn in whole_suffix, whole_nonempty, whole_digits. subst suffix.
 pose proof (after_fraction_scanned rest remaining fraction) as fraction_scanned.
 destruct (match rest with
 | String head tail => if Ascii.eqb head "." then take_digits tail else ("",rest)
 | _ => ("",rest) end) as [fraction_digits suffix] eqn:fraction_scan.
 cbn in fraction_scanned. destruct fraction_scanned as [suffix_equal fraction_decimal].
 subst suffix.
 assert (coefficient_nonempty : whole ++ fraction_digits <> EmptyString).
 { destruct whole; [contradiction|discriminate]. }
 assert (coefficient_decimal : all_decimal_digits (whole ++ fraction_digits))
   by now apply decimal_digits_append.
 destruct (nonempty_decimal_digits_parse _ coefficient_nonempty coefficient_decimal)
   as [numeral coefficient_parsed].
 destruct (after_exponent_denotes remaining exponent) as [power power_denotes].
 exists numeral, power.
 unfold split_number. rewrite sign, whole_scan, fraction_scan. cbn.
 now split.
Qed.
