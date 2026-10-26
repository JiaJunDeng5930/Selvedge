From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json JsonProofs Schema SchemaProofs.
From Selvedge.Kernel Require Import ModelDeclarations CallbackDeclarations ProtocolProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

(** Each external value is checked by the declared field decoder. The common
    law below owns object assembly, omission, lookup and discriminant handling. *)
Inductive raw_decodes : forall description, fields (raw_schema description) -> fields description -> Prop :=
| RawNil : raw_decodes [] FNil FNil
| RawCons : forall field rest raw value raw_rest values,
 decode_field field raw = Some value -> raw_decodes rest raw_rest values ->
 raw_decodes (field :: rest) (FCons (field:=raw_field field) raw raw_rest) (FCons value values).
Lemma raw_field_names : forall description,
 declared_names (raw_schema description) = declared_names description.
Proof. intros; unfold declared_names, raw_schema; rewrite map_map; reflexivity. Qed.
Lemma raw_fields_are_decoded : forall description raw values,
 raw_decodes description raw values -> schema_valid description = true ->
 decode_fields description (encode_fields raw) = Some values.
Proof.
 intros description raw values Decoded; induction Decoded; intro Unique; [reflexivity|].
 cbn [schema_valid declared_names unique_names] in Unique.
 apply andb_true_iff in Unique as [Absent Unique]; apply negb_true_iff in Absent.
 cbn [decode_fields encode_fields encode_field raw_field].
 destruct raw as [raw|]; cbn [raw_field OmittableField encode_field option_map encode_value field_name lookup].
 - rewrite String.eqb_refl, decode_fields_ignores_other_name by exact Absent.
   rewrite H, IHDecoded by exact Unique; reflexivity.
 - rewrite (encoded_lookup_is_absent (raw_schema rest) raw_rest (field_name field))
     by now rewrite raw_field_names.
   rewrite H, IHDecoded by exact Unique; reflexivity.
Qed.
Theorem raw_schema_roundtrip : forall description raw values,
 schema_valid description = true -> raw_decodes description raw values ->
 Schema.decode description (Schema.encode (raw_schema description) raw) = Some values.
Proof.
 intros description raw values Unique Decoded.
 assert (RawUnique : schema_valid (raw_schema description) = true).
 { unfold schema_valid; now rewrite raw_field_names. }
 assert (Keys : keys_declared description (encode_fields raw) = true).
 { unfold keys_declared; rewrite <-raw_field_names; apply encoded_keys_are_declared. }
 unfold Schema.decode, Schema.encode, source_keys.
 rewrite Unique, Keys, (encoded_names_are_unique _ raw RawUnique); cbn.
 now apply raw_fields_are_decoded.
Qed.
Lemma remove_absent_field : forall name members,
 existsb (String.eqb name) (map fst members) = false -> remove_field name members = members.
Proof.
 intros name members; induction members as [|[key value] rest IH]; cbn; intro Absent; [reflexivity|].
 apply orb_false_iff in Absent as [Different Absent]; now rewrite Different, IH by exact Absent.
Qed.
Theorem raw_variant_roundtrip : forall description raw values,
 unique_names (tag_field description :: declared_names (ModelDeclarations.payload_fields description)) = true ->
 raw_decodes (ModelDeclarations.payload_fields description) raw values ->
 ModelDeclarations.decode description (ModelDeclarations.encode (raw_variant description) raw) = Some values.
Proof.
 intros [tag name description safe callback] raw values Unique Decoded; cbn in *.
 apply andb_true_iff in Unique as [Absent Unique]; apply negb_true_iff in Absent.
 assert (AbsentRaw : existsb (String.eqb tag) (map fst (encode_fields raw)) = false).
 { apply encoded_name_is_absent; now rewrite raw_field_names. }
 unfold ModelDeclarations.decode, ModelDeclarations.matches, ModelDeclarations.encode, raw_variant.
 cbn [tag_field tag_value ModelDeclarations.payload_fields Json.field lookup remove_field].
 rewrite String.eqb_refl, equal_is_reflexive; cbn.
 rewrite remove_absent_field by exact AbsentRaw.
 now apply raw_schema_roundtrip.
Qed.

From Selvedge.Kernel Require Import InputDecoder.
Lemma input_find_is_named : forall name members,
 find (fun entry => ModelDeclarations.matches (decoder_declaration entry) (JObject (("kind",JString name)::members))) InputDecoder.decoders =
 find (fun entry => String.eqb name (InputDecoder.decoder_name entry)) InputDecoder.decoders.
Proof. reflexivity. Qed.
Theorem declared_input_wire : forall name description construct raw values,
 find (fun entry => String.eqb name (InputDecoder.decoder_name entry)) InputDecoder.decoders =
   Some (InputDecoder.Decoder name description construct) ->
 unique_names ("kind" :: declared_names description) = true ->
 InputDecoder.variant_fields_valid name
   (ModelDeclarations.encode (raw_variant (Variant "kind" (JString name) description [] None)) raw) = true ->
 raw_decodes description raw values ->
 InputDecoder.decode (ModelDeclarations.encode (raw_variant (Variant "kind" (JString name) description [] None)) raw) = construct values.
Proof.
 intros name description construct raw values Selected Unique VariantValid Decoded.
 pose proof Unique as Names; cbn in Names; apply andb_true_iff in Names as [Absent Names].
 apply negb_true_iff in Absent.
 assert (RawNames : schema_valid (raw_schema description) = true).
 { unfold schema_valid; now rewrite raw_field_names. }
 assert (RawAbsent : existsb (String.eqb "kind") (declared_names (raw_schema description)) = false).
 { rewrite raw_field_names; exact Absent. }
 assert (SourceNames : unique_names ("kind" :: map fst (encode_fields raw)) = true).
 { cbn [unique_names]; rewrite (encoded_name_is_absent _ raw "kind" RawAbsent).
   rewrite (encoded_names_are_unique _ raw RawNames); reflexivity. }
 change ((if unique_names ("kind" :: map fst (encode_fields raw)) then
   if InputDecoder.variant_fields_valid name (ModelDeclarations.encode (raw_variant (Variant "kind" (JString name) description [] None)) raw)
   then ModelDeclarations.decode_cases InputDecoder.decoders (ModelDeclarations.encode (raw_variant (Variant "kind" (JString name) description [] None)) raw)
   else None else None) = construct values).
 rewrite SourceNames, VariantValid; unfold ModelDeclarations.decode_cases.
 change (match find (fun entry => ModelDeclarations.matches (decoder_declaration entry) (JObject (("kind",JString name)::encode_fields raw))) InputDecoder.decoders with
 | Some entry => match ModelDeclarations.decode (decoder_declaration entry) (ModelDeclarations.encode (raw_variant (Variant "kind" (JString name) description [] None)) raw) with
   | Some fields => ModelDeclarations.decoder_construct entry fields | None => None end
 | None => None end = construct values).
 rewrite input_find_is_named, Selected; cbn [InputDecoder.Decoder decoder_declaration ModelDeclarations.decoder_construct].
 rewrite (raw_variant_roundtrip _ raw values Unique Decoded); reflexivity.
Qed.
Theorem full_callback_roundtrip : forall kind ok raw values,
 schema_valid (full_schema kind ok) = true ->
 raw_decodes (ModelDeclarations.payload_fields (declaration kind ok)) raw values ->
 Schema.decode (full_schema kind ok) (ModelDeclarations.encode (raw_variant (declaration kind ok)) raw) =
 Some (FCons (field:=Field "kind" KText) (callback_text kind) values).
Proof.
 intros kind ok raw values Unique Decoded.
 change (Schema.decode (full_schema kind ok)
   (Schema.encode (raw_schema (full_schema kind ok))
     (FCons (field:=raw_field (Field "kind" KText)) (Some (JString (callback_text kind))) raw)) =
   Some (FCons (field:=Field "kind" KText) (callback_text kind) values)).
 apply raw_schema_roundtrip; [exact Unique|apply RawCons; [reflexivity|exact Decoded]].
Qed.
