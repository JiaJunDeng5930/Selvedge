From Stdlib Require Import String Ascii List Bool Arith NArith Lia.
From Selvedge.Foundation Require Import Json Numbers Utf8 TextJson.
From Selvedge.Foundation Require Import TextJsonRoundtripTokens.
Import ListNotations.
Open Scope string_scope.
Open Scope nat_scope.

Lemma continuation_append : forall count value prefix source result,
 Utf8.continuation count value prefix source = Some result ->
 forall suffix, Utf8.continuation count value prefix (source ++ suffix) =
 Some (Utf8.Decoded result.(Utf8.scalar) result.(Utf8.encoded) (result.(Utf8.remaining) ++ suffix)).
Proof.
 induction count as [|count IH]; intros value prefix source result Parsed suffix; cbn in *.
 - inversion Parsed; reflexivity.
 - destruct source as [|c rest]; [discriminate|].
   cbn in *. destruct ((128 <=? Utf8.byte c)%N && (Utf8.byte c <=? 191)%N); [|discriminate].
   now apply IH.
Qed.
Lemma bounded_append : forall low high value result,
 Utf8.bounded low high value = Some result -> value = Some result.
Proof.
 intros low high [value|] result Parsed; cbn in Parsed; try discriminate.
 destruct (_ && _ && _); inversion Parsed; reflexivity.
Qed.
Lemma decode_one_append : forall source result,
 Utf8.decode_one source = Some result ->
 forall suffix, Utf8.decode_one (source ++ suffix) =
 Some (Utf8.Decoded result.(Utf8.scalar) result.(Utf8.encoded) (result.(Utf8.remaining) ++ suffix)).
Proof.
 intros [|c rest] result Parsed suffix; [discriminate|].
 unfold Utf8.decode_one in *. cbn [String.append].
 destruct (Utf8.byte c <? 128)%N; [inversion Parsed; reflexivity|].
 destruct ((194 <=? Utf8.byte c)%N && (Utf8.byte c <=? 223)%N).
 - unfold Utf8.bounded in *.
   destruct (Utf8.continuation 1 _ _ rest) as [value|] eqn:Continuation; [|discriminate].
   rewrite (continuation_append _ _ _ _ _ Continuation suffix).
   cbn in *. destruct (_ && _ && _); inversion Parsed; reflexivity.
 - destruct ((224 <=? Utf8.byte c)%N && (Utf8.byte c <=? 239)%N).
   + unfold Utf8.bounded in *.
     destruct (Utf8.continuation 2 _ _ rest) as [value|] eqn:Continuation; [|discriminate].
     rewrite (continuation_append _ _ _ _ _ Continuation suffix).
     cbn in *. destruct (_ && _ && _); inversion Parsed; reflexivity.
   + destruct ((240 <=? Utf8.byte c)%N && (Utf8.byte c <=? 244)%N); [|discriminate].
     unfold Utf8.bounded in *.
     destruct (Utf8.continuation 3 _ _ rest) as [value|] eqn:Continuation; [|discriminate].
     rewrite (continuation_append _ _ _ _ _ Continuation suffix).
     cbn in *. destruct (_ && _ && _); inversion Parsed; reflexivity.
Qed.
Lemma validate_fuel_empty : forall fuel, Utf8.validate_fuel fuel "" = true.
Proof. intros [|fuel]; reflexivity. Qed.
Lemma validate_fuel_monotone : forall fuel source,
 Utf8.validate_fuel fuel source = true -> forall extra,
 Utf8.validate_fuel (fuel + extra) source = true.
Proof.
 induction fuel as [|fuel IH]; intros [|c rest] Valid extra.
 - apply validate_fuel_empty.
 - discriminate.
 - apply validate_fuel_empty.
 - change (match Utf8.decode_one (String c rest) with
           | Some result => Utf8.validate_fuel fuel result.(Utf8.remaining)
           | None => false end = true) in Valid.
   change (match Utf8.decode_one (String c rest) with
           | Some result => Utf8.validate_fuel (fuel + extra) result.(Utf8.remaining)
           | None => false end = true).
   destruct (Utf8.decode_one (String c rest)); try discriminate. now apply IH.
Qed.
Lemma validate_fuel_append : forall fuel source,
 Utf8.validate_fuel fuel source = true -> forall extra suffix,
 Utf8.validate_fuel extra suffix = true ->
 Utf8.validate_fuel (fuel + extra) (source ++ suffix) = true.
Proof.
 induction fuel as [|fuel IH]; intros [|c rest] Valid extra suffix Tail.
 - exact Tail.
 - discriminate.
 - cbn [String.append]. replace (S fuel + extra) with (extra + S fuel) by lia.
   now apply validate_fuel_monotone.
 - change (match Utf8.decode_one (String c rest) with
           | Some result => Utf8.validate_fuel fuel result.(Utf8.remaining)
           | None => false end = true) in Valid.
   change (match Utf8.decode_one (String c (rest ++ suffix)) with
           | Some result => Utf8.validate_fuel (fuel + extra) result.(Utf8.remaining)
           | None => false end = true).
   destruct (Utf8.decode_one (String c rest)) as [value|] eqn:Decoded; [|discriminate].
   pose proof (decode_one_append _ _ Decoded suffix) as App.
   cbn [String.append] in App. rewrite App. cbn [Utf8.remaining]. now apply IH.
Qed.
Lemma string_length_append : forall a b,
 String.length (a ++ b) = String.length a + String.length b.
Proof. induction a; cbn; intros; [reflexivity|now rewrite IHa]. Qed.
Theorem well_formed_append : forall first second,
 Utf8.well_formed first = true -> Utf8.well_formed second = true ->
 Utf8.well_formed (first ++ second) = true.
Proof.
 intros first second A B. unfold Utf8.well_formed, Utf8.byte_length in *.
 rewrite string_length_append. now apply validate_fuel_append.
Qed.

Lemma escaped_append : forall first second,
 escaped (first ++ second) = escaped first ++ escaped second.
Proof.
 induction first as [|c rest IH]; intros second; cbn; [reflexivity|].
 rewrite IH, string_append_assoc. reflexivity.
Qed.
Lemma escaped_length : forall text, String.length text <= String.length (escaped text).
Proof.
 induction text as [|c rest IH]; cbn; [lia|].
 rewrite string_length_append.
 assert (0 < String.length (escape_char c)).
 { destruct c as [a b c d e f g h]. destruct a,b,c,d,e,f,g,h; vm_compute; lia. }
 lia.
Qed.
Lemma high_byte_escaped : forall c,
 (Utf8.byte c <? 128)%N = false -> escape_char c = String c "".
Proof. intros [a b c d e f g h]. destruct a,b,c,d,e,f,g,h; vm_compute; intros; congruence. Qed.
Lemma continuation_byte_escaped : forall c,
 ((128 <=? Utf8.byte c)%N && (Utf8.byte c <=? 191)%N) = true ->
 escape_char c = String c "".
Proof. intros [a b c d e f g h]. destruct a,b,c,d,e,f,g,h; vm_compute; intros; congruence. Qed.
Lemma continuation_structure : forall count value prefix source result,
 Utf8.continuation count value prefix source = Some result ->
 prefix ++ source = result.(Utf8.encoded) ++ result.(Utf8.remaining) /\
 String.length prefix <= String.length result.(Utf8.encoded).
Proof.
 induction count as [|count IH]; intros value prefix [|c rest] result Parsed;
 cbn [Utf8.continuation] in Parsed.
 - inversion Parsed; cbn; split; [reflexivity|lia].
 - inversion Parsed; cbn; split; [reflexivity|lia].
 - discriminate.
 - destruct (_ && _) eqn:Byte; [|discriminate].
   apply IH in Parsed as [Shape Size]. split.
   + rewrite <- Shape, <- string_append_assoc. reflexivity.
   + rewrite string_length_append in Size. cbn in Size. lia.
Qed.
Lemma decode_one_structure : forall source result,
 Utf8.decode_one source = Some result ->
 source = result.(Utf8.encoded) ++ result.(Utf8.remaining) /\
 0 < String.length result.(Utf8.encoded).
Proof.
 intros [|c rest] result Parsed; [discriminate|].
 unfold Utf8.decode_one in Parsed.
 destruct (Utf8.byte c <? 128)%N; [inversion Parsed; cbn; split; [reflexivity|lia]|].
 destruct (_ && _).
 - apply bounded_append in Parsed. apply continuation_structure in Parsed. cbn in Parsed. intuition lia.
 - destruct (_ && _).
   + apply bounded_append in Parsed. apply continuation_structure in Parsed. cbn in Parsed. intuition lia.
   + destruct (_ && _); [|discriminate].
     apply bounded_append in Parsed. apply continuation_structure in Parsed. cbn in Parsed. intuition lia.
Qed.
Lemma validate_fuel_normalize : forall fuel source,
 Utf8.validate_fuel fuel source = true -> Utf8.well_formed source = true.
Proof.
 induction fuel as [|fuel IH]; intros [|c rest] Valid; [reflexivity|discriminate|reflexivity|].
 change (match Utf8.decode_one (String c rest) with
         | Some result => Utf8.validate_fuel fuel result.(Utf8.remaining)
         | None => false end = true) in Valid.
 destruct (Utf8.decode_one (String c rest)) as [result|] eqn:Decoded; [|discriminate].
 apply IH in Valid. pose proof (decode_one_structure _ _ Decoded) as [Shape Size].
 pose proof (f_equal String.length Shape) as Length. rewrite string_length_append in Length. cbn in Length.
 unfold Utf8.well_formed, Utf8.byte_length in *.
 change (match Utf8.decode_one (String c rest) with
         | Some result => Utf8.validate_fuel (String.length rest) result.(Utf8.remaining)
         | None => false end = true).
 rewrite Decoded.
 replace (String.length rest) with (String.length result.(Utf8.remaining) + (String.length rest - String.length result.(Utf8.remaining))) by lia.
 now apply validate_fuel_monotone.
Qed.

Lemma continuation_escaped : forall count value prefix source result,
 Utf8.continuation count value prefix source = Some result ->
 Utf8.continuation count value prefix (escaped source) =
 Some (Utf8.Decoded result.(Utf8.scalar) result.(Utf8.encoded) (escaped result.(Utf8.remaining))).
Proof.
 induction count as [|count IH]; intros value prefix [|c rest] result Parsed;
 cbn [Utf8.continuation] in Parsed.
 - inversion Parsed; reflexivity.
 - inversion Parsed; reflexivity.
 - discriminate.
 - destruct (_ && _) eqn:Byte; [|discriminate].
   cbn [escaped]. rewrite (continuation_byte_escaped _ Byte). cbn [String.append Utf8.continuation].
   rewrite Byte. now apply IH.
Qed.
Lemma decode_one_high_escaped : forall c rest result,
 (Utf8.byte c <? 128)%N = false ->
 Utf8.decode_one (String c rest) = Some result ->
 Utf8.decode_one (escaped (String c rest)) =
 Some (Utf8.Decoded result.(Utf8.scalar) result.(Utf8.encoded) (escaped result.(Utf8.remaining))).
Proof.
 intros c rest result High Parsed. cbn [escaped]. rewrite (high_byte_escaped _ High).
 unfold Utf8.decode_one in *. cbn [String.append]. rewrite High in *.
 destruct (_ && _).
 - unfold Utf8.bounded in *.
   destruct (Utf8.continuation 1 _ _ rest) as [value|] eqn:Continuation; [|discriminate].
   rewrite (continuation_escaped _ _ _ _ _ Continuation).
   cbn in *. destruct (_ && _ && _); inversion Parsed; reflexivity.
 - destruct (_ && _).
   + unfold Utf8.bounded in *.
     destruct (Utf8.continuation 2 _ _ rest) as [value|] eqn:Continuation; [|discriminate].
     rewrite (continuation_escaped _ _ _ _ _ Continuation).
     cbn in *. destruct (_ && _ && _); inversion Parsed; reflexivity.
   + destruct (_ && _); [|discriminate].
     unfold Utf8.bounded in *.
     destruct (Utf8.continuation 3 _ _ rest) as [value|] eqn:Continuation; [|discriminate].
     rewrite (continuation_escaped _ _ _ _ _ Continuation).
     cbn in *. destruct (_ && _ && _); inversion Parsed; reflexivity.
Qed.

Lemma ascii_escape_well_formed : forall c,
 (Utf8.byte c <? 128)%N = true -> Utf8.well_formed (escape_char c) = true.
Proof. intros [a b c d e f g h]. destruct a,b,c,d,e,f,g,h; vm_compute; intros; congruence. Qed.
Lemma validate_escaped : forall fuel text,
 Utf8.validate_fuel fuel text = true -> Utf8.well_formed (escaped text) = true.
Proof.
 induction fuel as [|fuel IH]; intros [|c rest] Valid; [reflexivity|discriminate|reflexivity|].
 change (match Utf8.decode_one (String c rest) with
         | Some result => Utf8.validate_fuel fuel result.(Utf8.remaining)
         | None => false end = true) in Valid.
 destruct (Utf8.byte c <? 128)%N eqn:Ascii.
 - assert (Decoded : Utf8.decode_one (String c rest) = Some (Utf8.Decoded (Utf8.byte c) (String c "") rest)).
   { unfold Utf8.decode_one. now rewrite Ascii. }
   rewrite Decoded in Valid. cbn [Utf8.remaining] in Valid.
   cbn [escaped]. apply well_formed_append; [now apply ascii_escape_well_formed|now apply IH].
 - destruct (Utf8.decode_one (String c rest)) as [result|] eqn:Decoded; [|discriminate].
   apply IH in Valid.
   pose proof (decode_one_high_escaped _ _ _ Ascii Decoded) as EscapeDecoded.
   cbn [escaped] in EscapeDecoded |- *.
   rewrite (high_byte_escaped _ Ascii) in EscapeDecoded |- *.
   cbn [String.append] in EscapeDecoded |- *.
   apply (validate_fuel_normalize (S (String.length (escaped result.(Utf8.remaining))))).
   change (match Utf8.decode_one (String c (escaped rest)) with
           | Some decoded => Utf8.validate_fuel (String.length (escaped result.(Utf8.remaining))) decoded.(Utf8.remaining)
           | None => false end = true).
   rewrite EscapeDecoded. exact Valid.
Qed.
Theorem escaped_well_formed : forall text,
 Utf8.well_formed text = true -> Utf8.well_formed (escaped text) = true.
Proof. intros text Valid. exact (validate_escaped _ _ Valid). Qed.
Theorem quote_well_formed : forall text,
 Utf8.well_formed text = true -> Utf8.well_formed (quote text) = true.
Proof.
 intros text Valid. unfold quote. rewrite escape_string_spec.
 repeat apply well_formed_append; try reflexivity. now apply escaped_well_formed.
Qed.

Lemma number_character_well_formed : forall c,
 number_char c = true -> Utf8.well_formed (String c "") = true.
Proof. intros [a b c d e f g h]. destruct a,b,c,d,e,f,g,h; vm_compute; intros; congruence. Qed.
Theorem number_lexeme_well_formed : forall text,
 number_lexeme text = true -> Utf8.well_formed text = true.
Proof.
 intros text Valid. apply number_lexeme_bytes in Valid.
 induction text as [|c rest IH]; [reflexivity|].
 cbn in Valid. apply andb_true_iff in Valid as [Head Tail].
 change (Utf8.well_formed ((String c "") ++ rest) = true).
 apply well_formed_append; [now apply number_character_well_formed|now apply IH].
Qed.
