From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json JsonProofs Schema SchemaProofs.
From Selvedge.Kernel Require Import ModelDeclarations ProtocolProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Lemma remove_absent_field : forall name members,
 existsb (String.eqb name) (map fst members) = false -> remove_field name members = members.
Proof.
 intros name members; induction members as [|[key value] rest IH]; cbn; intro Absent; [reflexivity|].
 apply orb_false_iff in Absent as [Different Absent]; now rewrite Different, IH by exact Absent.
Qed.

From Selvedge.Kernel Require Import InputDecoder.
Lemma input_find_is_named : forall name source,
 field "kind" source = Some (JString name) ->
 find (fun entry => ModelDeclarations.matches (decoder_declaration entry) source) InputDecoder.decoders =
 find (fun entry => String.eqb name (InputDecoder.decoder_name entry)) InputDecoder.decoders.
Proof.
 intros name source Tag.
 assert (Named : Forall (fun entry => tag_field (decoder_declaration entry) = "kind" /\
   tag_value (decoder_declaration entry) = JString (InputDecoder.decoder_name entry)) InputDecoder.decoders)
   by repeat constructor.
 revert Named; generalize InputDecoder.decoders as cases.
 induction cases as [|entry rest IH]; intro Named; [reflexivity|].
 inversion Named as [|? ? [Key Value] Tail]; subst.
 cbn [find]; unfold ModelDeclarations.matches at 1.
 rewrite Key, Tag, Value; cbn [equal].
 destruct (String.eqb name (InputDecoder.decoder_name entry)); [reflexivity|].
 now apply IH.
Qed.
(** The declared schema owns the wire roundtrip; this law adds only the public
    input tag lookup. Nullable values may decode to a canonical representative. *)
Theorem declared_input_wire : forall name description construct values,
 find (fun entry => String.eqb name (InputDecoder.decoder_name entry)) InputDecoder.decoders =
   Some (InputDecoder.Decoder name description construct) ->
 unique_names ("kind" :: declared_names description) = true ->
 protocol_schema description = true ->
 exists canonical,
 Schema.decode description (Schema.encode description values) = Some canonical /\
 InputDecoder.decode (ModelDeclarations.encode (Variant "kind" (JString name) description [] None) values) = construct canonical.
Proof.
 intros name description construct values Selected Unique Supported.
 pose proof Unique as Names; cbn in Names; apply andb_true_iff in Names as [Absent Names].
 apply negb_true_iff in Absent.
 destruct (schema_wire_roundtrip description values Names Supported) as [canonical [Decoded _]].
 exists canonical; split; [exact Decoded|].
 assert (AbsentEncoded : existsb (String.eqb "kind") (map fst (encode_fields values)) = false)
   by now apply encoded_name_is_absent.
 assert (SourceNames : unique_names ("kind" :: map fst (encode_fields values)) = true).
 { cbn [unique_names]; rewrite AbsentEncoded, (encoded_names_are_unique _ values Names); reflexivity. }
 change ((if unique_names ("kind" :: map fst (encode_fields values)) then
   ModelDeclarations.decode_cases InputDecoder.decoders (ModelDeclarations.encode (Variant "kind" (JString name) description [] None) values)
   else None) = construct canonical).
 rewrite SourceNames; unfold ModelDeclarations.decode_cases.
 rewrite input_find_is_named with (name:=name) by reflexivity; rewrite Selected.
 cbn [InputDecoder.Decoder decoder_declaration ModelDeclarations.decoder_construct].
 unfold ModelDeclarations.decode, ModelDeclarations.matches, ModelDeclarations.encode.
 cbn [tag_field tag_value ModelDeclarations.payload_fields Json.field lookup remove_field].
 rewrite String.eqb_refl, equal_is_reflexive; cbn.
 rewrite remove_absent_field by exact AbsentEncoded.
 change (match Schema.decode description (Schema.encode description values) with
 | Some decoded => construct decoded | None => None end = construct canonical).
 now rewrite Decoded.
Qed.
