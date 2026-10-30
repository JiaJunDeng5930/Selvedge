From Stdlib Require Import String Ascii List Bool Arith Lia DecimalString.
From Selvedge.Foundation Require Import Json Numbers Utf8 TextJson.
Import ListNotations.
Open Scope string_scope.
Open Scope nat_scope.

Fixpoint escaped (text : string) : string :=
 match text with
 | EmptyString => EmptyString
 | String character rest => escape_char character ++ escaped rest
 end.

Lemma string_append_assoc : forall a b c : string, a ++ (b ++ c) = (a ++ b) ++ c.
Proof. induction a; cbn; intros; congruence. Qed.

Lemma string_append_nil : forall a : string, a ++ "" = a.
Proof. induction a; cbn; congruence. Qed.

Lemma concat_empty_cons : forall a l, String.concat "" (a :: l) = a ++ String.concat "" l.
Proof. intros a [|b l]; cbn; [symmetry; apply string_append_nil|reflexivity]. Qed.

Lemma concat_app_empty : forall first second,
 String.concat "" (first ++ second) = String.concat "" first ++ String.concat "" second.
Proof.
 induction first as [|head rest IH]; intros second; cbn [List.app]; [reflexivity|].
 repeat rewrite concat_empty_cons. rewrite IH, string_append_assoc. reflexivity.
Qed.

Lemma escape_acc_spec : forall text reversed,
 escape_acc text reversed = String.concat "" (List.rev reversed) ++ escaped text.
Proof.
 induction text as [|character rest IH]; intros reversed; cbn.
 - rewrite List.rev_alt, string_append_nil. reflexivity.
 - rewrite IH. cbn [List.rev]. rewrite concat_app_empty. cbn.
   rewrite string_append_assoc. reflexivity.
Qed.

Lemma escape_string_spec : forall text, escape_string text = escaped text.
Proof. intro text. unfold escape_string. rewrite escape_acc_spec. reflexivity. Qed.

Lemma quoted_acc_character : forall character fuel rest reversed,
 quoted_acc (S fuel) (escape_char character ++ rest) reversed =
 quoted_acc fuel rest (character :: reversed).
Proof.
 intros [a b c d e f g h] fuel rest reversed.
 destruct a,b,c,d,e,f,g,h; reflexivity.
Qed.

Lemma quoted_acc_escaped : forall text fuel suffix reversed,
 String.length text < fuel ->
 quoted_acc fuel (escaped text ++ """" ++ suffix) reversed =
 Scanned (finish_string (push_string text reversed)) suffix.
Proof.
 induction text as [|character rest IH]; intros [|fuel] suffix reversed Budget; try lia.
 - reflexivity.
 - cbn [escaped String.length] in *.
   rewrite <- string_append_assoc, quoted_acc_character.
   apply IH. lia.
Qed.

Lemma push_string_list : forall text reversed,
 push_string text reversed = (List.rev (String.list_ascii_of_string text) ++ reversed)%list.
Proof.
 induction text as [|character rest IH]; intros reversed; cbn; [reflexivity|].
 rewrite IH. cbn. rewrite <- List.app_assoc. reflexivity.
Qed.

Lemma finish_string_push : forall text,
 finish_string (push_string text []) = text.
Proof.
 intro text. rewrite push_string_list, List.app_nil_r.
 unfold finish_string. rewrite <- List.rev_alt, List.rev_involutive.
 apply String.string_of_list_ascii_of_string.
Qed.

Theorem quoted_quote : forall text fuel suffix,
 String.length text < fuel ->
 quoted fuel (quote text ++ suffix) = Scanned text suffix.
Proof.
 intros text fuel suffix Budget. unfold quoted, quote.
 cbn. rewrite escape_string_spec, <- string_append_assoc.
 unfold quoted_body. rewrite quoted_acc_escaped by exact Budget.
 rewrite finish_string_push. reflexivity.
Qed.

Fixpoint number_bytes (text : string) : bool :=
 match text with EmptyString => true | String c rest => number_char c && number_bytes rest end.
Lemma digit_number_char : forall c, is_digit c = true -> number_char c = true.
Proof. intros c Digit. unfold number_char. now rewrite Digit. Qed.
Lemma uint_character_digit character reversed next :
  uint_of_char character (Some reversed) = Some next -> is_digit character = true.
Proof.
  intro parsed. apply uint_of_char_spec in parsed.
  repeat (destruct parsed as [parsed|parsed]); destruct parsed as [-> _]; reflexivity.
Qed.
Lemma decimal_digits_bytes text reversed digits rest :
  decimal_digits_acc text reversed = (digits,rest) ->
  number_bytes rest = true -> number_bytes text = true.
Proof.
  revert reversed digits rest. induction text as [|head text IH]; intros reversed digits rest parsed bytes; [reflexivity|].
  cbn [decimal_digits_acc] in parsed.
  destruct (uint_of_char head (Some reversed)) as [next|] eqn:digit.
  - cbn [number_bytes]. rewrite (digit_number_char _ (uint_character_digit _ _ _ digit)).
    cbn. eapply IH; eauto.
  - inversion parsed; subst. exact bytes.
Qed.
Lemma required_decimal_bytes text digits rest :
  required_decimal_digits text = Some (digits,rest) ->
  number_bytes rest = true -> number_bytes text = true.
Proof.
  unfold required_decimal_digits, decimal_digits.
  destruct (decimal_digits_acc text Decimal.Nil) as [value remaining] eqn:scanned.
  destruct value; try discriminate; intros [= <- <-] bytes;
    eapply decimal_digits_bytes; eauto.
Qed.
Lemma decimal_integer_bytes text digits rest :
  decimal_integer text = Some (digits,rest) ->
  number_bytes rest = true -> number_bytes text = true.
Proof.
  destruct text as [|head text]; [discriminate|]. unfold decimal_integer.
  destruct (Ascii.eqb head "0") eqn:zero.
  - apply Ascii.eqb_eq in zero. subst. intros [= <- <-] bytes. exact bytes.
  - apply required_decimal_bytes.
Qed.
Lemma decimal_fraction_bytes text digits rest :
  decimal_fraction text = Some (digits,rest) ->
  number_bytes rest = true -> number_bytes text = true.
Proof.
  destruct text as [|head text]; [reflexivity|]. unfold decimal_fraction.
  destruct (Ascii.eqb head ".") eqn:dot.
  - apply Ascii.eqb_eq in dot. subst. cbn [number_bytes]. apply required_decimal_bytes.
  - intros [= <- <-] bytes. exact bytes.
Qed.
Lemma decimal_exponent_bytes text exponent :
  decimal_exponent text = Some exponent -> number_bytes text = true.
Proof.
  destruct text as [|head text]; [reflexivity|]. unfold decimal_exponent.
  destruct (Ascii.eqb head "e" || Ascii.eqb head "E") eqn:mark; [|discriminate].
  assert (character : number_char head = true).
  { apply orb_true_iff in mark as [mark|mark]; apply Ascii.eqb_eq in mark; subst; reflexivity. }
  cbn [number_bytes]. rewrite character. cbn.
  destruct text as [|sign digits]; [discriminate|].
  destruct (Ascii.eqb sign "-") eqn:negative.
  - apply Ascii.eqb_eq in negative. subst sign. cbn [number_bytes].
    destruct (required_decimal_digits digits) as [[value remaining]|] eqn:parsed; [|discriminate].
    destruct remaining; [|discriminate]. intros _. eapply required_decimal_bytes; eauto.
  - destruct (Ascii.eqb sign "+") eqn:positive.
    + apply Ascii.eqb_eq in positive. subst sign. cbn [number_bytes].
      destruct (required_decimal_digits digits) as [[value remaining]|] eqn:parsed; [|discriminate].
      destruct remaining; [|discriminate]. intros _. eapply required_decimal_bytes; eauto.
    + destruct (required_decimal_digits (String sign digits)) as [[value remaining]|] eqn:parsed; [|discriminate].
      destruct remaining; [|discriminate]. intros _. eapply required_decimal_bytes; eauto.
Qed.
Theorem number_lexeme_bytes : forall text,
  number_lexeme text = true -> number_bytes text = true.
Proof.
  intros [|head text] valid; [discriminate|]. unfold number_lexeme, parse_decimal in valid.
  destruct (Ascii.eqb head "-") eqn:negative;
    destruct (decimal_integer _) as [[whole rest]|] eqn:integer; try discriminate;
    destruct (decimal_fraction _) as [[fraction tail]|] eqn:fractional; try discriminate;
    destruct (decimal_exponent _) as [exponent|] eqn:power; try discriminate.
  - apply Ascii.eqb_eq in negative. subst head. cbn [number_bytes].
    eapply decimal_integer_bytes; [exact integer|].
    eapply decimal_fraction_bytes; [exact fractional|].
    eapply decimal_exponent_bytes; exact power.
  - eapply decimal_integer_bytes; [exact integer|].
    eapply decimal_fraction_bytes; [exact fractional|].
    eapply decimal_exponent_bytes; exact power.
Qed.

Lemma take_while_number : forall text suffix reversed,
 number_bytes text = true ->
 (match suffix with EmptyString => true | String c _ => negb (number_char c) end) = true ->
 take_while_acc number_char (text ++ suffix) reversed =
 (finish_string (push_string text reversed), suffix).
Proof.
 induction text as [|c rest IH]; intros suffix reversed Bytes End.
 - destruct suffix as [|c suffix]; cbn in *; [reflexivity|].
   apply negb_true_iff in End. now rewrite End.
 - cbn in *. apply andb_true_iff in Bytes as [Head Tail].
   rewrite Head. apply IH; assumption.
Qed.

Theorem scan_number_lexeme : forall text suffix,
 number_lexeme text = true ->
 (match suffix with EmptyString => true | String c _ => negb (number_char c) end) = true ->
 take_while number_char (text ++ suffix) = (text,suffix).
Proof.
 intros text suffix Valid End. unfold take_while.
 rewrite take_while_number; [rewrite finish_string_push; reflexivity|now apply number_lexeme_bytes|exact End].
Qed.

Lemma number_lexeme_initial : forall text,
 number_lexeme text = true -> exists c rest,
 text = String c rest /\ (Ascii.eqb c "-" || is_digit c) = true.
Proof.
 intros [|c rest] valid; [discriminate|]. exists c,rest. split; [reflexivity|].
 unfold number_lexeme, parse_decimal in valid.
 destruct (Ascii.eqb c "-") eqn:negative; [reflexivity|].
 cbn [decimal_integer] in valid. destruct (Ascii.eqb c "0") eqn:zero.
 - apply Ascii.eqb_eq in zero. subst. reflexivity.
 - unfold required_decimal_digits, decimal_digits in valid. cbn [decimal_digits_acc] in valid.
   destruct (uint_of_char c (Some Decimal.Nil)) as [next|] eqn:digit; [|discriminate].
   apply uint_character_digit in digit. now rewrite digit.
Qed.
Lemma number_initial_delimiters : forall c,
 (Ascii.eqb c "-" || is_digit c) = true ->
 whitespace c = false /\ Ascii.eqb c """" = false /\
 Ascii.eqb c "[" = false /\ Ascii.eqb c "{" = false /\
 Ascii.eqb c "]" = false /\ Ascii.eqb c "}" = false /\
 Ascii.eqb c "t" = false /\ Ascii.eqb c "f" = false /\ Ascii.eqb c "n" = false.
Proof.
 intros [a b c d e f g h]. destruct a,b,c,d,e,f,g,h; vm_compute; intros; intuition congruence.
Qed.
