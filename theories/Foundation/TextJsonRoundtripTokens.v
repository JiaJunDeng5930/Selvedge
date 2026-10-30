From Stdlib Require Import String Ascii List Bool Arith Lia.
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
Lemma skip_digits_number_bytes : forall text,
 number_bytes (skip_digits text) = true -> number_bytes text = true.
Proof.
 induction text as [|c rest IH]; cbn; [reflexivity|].
 destruct (is_digit c) eqn:Digit; [|exact (fun H => H)].
 intro Rest. rewrite (digit_number_char _ Digit). cbn. now apply IH.
Qed.
Lemma after_digits_number_bytes : forall text rest,
 after_digits text = Some rest -> number_bytes rest = true -> number_bytes text = true.
Proof.
 intros [|c text] rest Parsed Bytes; cbn in Parsed; try discriminate.
 destruct (is_digit c) eqn:Digit; inversion Parsed; subst.
 cbn. rewrite (digit_number_char _ Digit). cbn. now apply skip_digits_number_bytes.
Qed.
Lemma after_integer_number_bytes : forall text rest,
 after_integer text = Some rest -> number_bytes rest = true -> number_bytes text = true.
Proof.
 intros [|c text] rest Parsed Bytes; cbn in Parsed; try discriminate.
 destruct (Ascii.eqb c "0") eqn:Zero.
 - apply Ascii.eqb_eq in Zero. subst c. inversion Parsed; subst. exact Bytes.
 - destruct (is_digit c) eqn:Digit; inversion Parsed; subst.
   cbn. rewrite (digit_number_char _ Digit). cbn. now apply skip_digits_number_bytes.
Qed.
Lemma after_fraction_number_bytes : forall text rest,
 after_fraction text = Some rest -> number_bytes rest = true -> number_bytes text = true.
Proof.
 intros [|c text] rest Parsed Bytes; cbn in Parsed; [reflexivity|].
 destruct (Ascii.eqb c ".") eqn:Dot.
 - apply Ascii.eqb_eq in Dot. subst c. cbn. eapply after_digits_number_bytes; eauto.
 - inversion Parsed; subst. exact Bytes.
Qed.
Lemma after_exponent_number_bytes : forall text rest,
 after_exponent text = Some rest -> number_bytes rest = true -> number_bytes text = true.
Proof.
 intros [|c text] rest Parsed Bytes; cbn in Parsed; [reflexivity|].
 destruct (Ascii.eqb c "e" || Ascii.eqb c "E") eqn:Exponent.
 - assert (Head : number_char c = true).
   { apply orb_true_iff in Exponent. destruct Exponent as [H|H]; apply Ascii.eqb_eq in H; subst; reflexivity. }
   cbn. rewrite Head. cbn.
   destruct text as [|sign digits]; [discriminate|].
   destruct (Ascii.eqb sign "+" || Ascii.eqb sign "-") eqn:Sign.
   + cbn. assert (SignByte : number_char sign = true).
     { apply orb_true_iff in Sign. destruct Sign as [H|H]; apply Ascii.eqb_eq in H; subst; reflexivity. }
     rewrite SignByte. cbn. eapply after_digits_number_bytes; eauto.
   + eapply after_digits_number_bytes; eauto.
 - inversion Parsed; subst. exact Bytes.
Qed.
Theorem number_lexeme_bytes : forall text,
 number_lexeme text = true -> number_bytes text = true.
Proof.
 intros text Valid. unfold number_lexeme in Valid.
 destruct text as [|c text]; [discriminate|].
 destruct (Ascii.eqb c "-") eqn:Negative;
 destruct (after_integer _) eqn:Integer; try discriminate;
 destruct (after_fraction _) eqn:Fraction; try discriminate;
 destruct (after_exponent _) eqn:Exponent; try discriminate;
 destruct s1; try discriminate.
 - apply Ascii.eqb_eq in Negative. subst c. cbn.
   eapply after_integer_number_bytes; [exact Integer|].
   eapply after_fraction_number_bytes; [exact Fraction|].
   eapply after_exponent_number_bytes; [exact Exponent|reflexivity].
 - eapply after_integer_number_bytes; [exact Integer|].
   eapply after_fraction_number_bytes; [exact Fraction|].
   eapply after_exponent_number_bytes; [exact Exponent|reflexivity].
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
 intros [|c rest] Valid; [discriminate|]. exists c,rest. split; [reflexivity|].
 unfold number_lexeme in Valid. destruct (Ascii.eqb c "-") eqn:Negative; [reflexivity|].
 cbn [after_integer] in Valid. destruct (Ascii.eqb c "0") eqn:Zero.
 - apply Ascii.eqb_eq in Zero. subst. reflexivity.
 - destruct (is_digit c) eqn:Digit; [reflexivity|discriminate].
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
