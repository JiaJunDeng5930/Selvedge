From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json TextJson Schema CallWire Utf8.
Import ListNotations.
Open Scope string_scope.

(* This theorem starts from the provider's original text.  Structural equality
   of fields retains ordering, repeated names and number spellings.  It does
   not assume a render/parse round trip or identify that law with validity. *)
Theorem admitted_argument_text_recovers_members : forall nesting id name text fields,
  Utf8.nonblank id = true -> Utf8.nonblank name = true ->
  TextJson.parse_json_members_at nesting text = Some (JObject fields) ->
  CallWire.decode_at nesting (JObject [
    ("id", JString id); ("name", JString name); ("arguments_json", JString text)]) =
    Some (id, name, JObject fields) /\
  CallWire.decode_item_at nesting (JObject [
    ("type", JString "call"); ("id", JString id); ("name", JString name);
    ("arguments_json", JString text)]) = Some (id, name, JObject fields).
Proof.
  intros nesting id name text fields Id Name Parsed.
  split; unfold CallWire.decode_at, CallWire.decode_item_at,
    CallWire.declaration, CallWire.item_declaration, Schema.decode,
    Schema.decode_fields; cbn; unfold CallWire.decode_fields;
    rewrite Id, Name; cbn; unfold CallWire.parse_arguments; rewrite Parsed; reflexivity.
Qed.

Lemma decoded_fields_have_text_origin : forall nesting id name text decoded,
  CallWire.decode_fields nesting id name text = Some decoded ->
  exists members,
    TextJson.parse_json_members_at nesting text = Some (JObject members) /\
    decoded = (id, name, JObject members).
Proof.
  intros nesting id name text decoded Decoded.
  unfold CallWire.decode_fields, CallWire.parse_arguments in Decoded.
  destruct (Utf8.nonblank id && Utf8.nonblank name); [|discriminate].
  destruct (TextJson.parse_json_members_at nesting text) as [arguments|];
    [|discriminate].
  destruct arguments; try discriminate.
  inversion Decoded; subst. eexists; split; reflexivity.
Qed.

(* Success is possible only for the exact object admitted from one text field;
   the wire decoder cannot replace or normalize its members. *)
Theorem decoded_call_has_exact_member_origin : forall nesting wire decoded,
  CallWire.decode_at nesting wire = Some decoded ->
  exists id name text members,
    TextJson.parse_json_members_at nesting text = Some (JObject members) /\
    decoded = (id, name, JObject members).
Proof.
  intros nesting wire decoded Decoded. unfold CallWire.decode_at in Decoded.
  destruct (Schema.decode CallWire.declaration wire) as [fields|];
    [|discriminate].
  apply decoded_fields_have_text_origin in Decoded as [members [Parsed Exact]].
  eexists; eexists; eexists; exists members; split; eassumption.
Qed.

Theorem decoded_call_item_has_exact_member_origin : forall nesting wire decoded,
  CallWire.decode_item_at nesting wire = Some decoded ->
  exists id name text members,
    TextJson.parse_json_members_at nesting text = Some (JObject members) /\
    decoded = (id, name, JObject members).
Proof.
  intros nesting wire decoded Decoded. unfold CallWire.decode_item_at in Decoded.
  destruct (Schema.decode CallWire.item_declaration wire) as [fields|];
    [|discriminate].
  apply decoded_fields_have_text_origin in Decoded as [members [Parsed Exact]].
  eexists; eexists; eexists; exists members; split; eassumption.
Qed.

Lemma old_argument_member_is_undeclared : forall description fields value,
  existsb (String.eqb "arguments") (Schema.declared_names description) = false ->
  In ("arguments", value) fields -> Schema.keys_declared description fields = false.
Proof.
  intros description fields value Undeclared Member.
  apply Bool.not_true_is_false. intro Declared.
  unfold Schema.keys_declared in Declared.
  apply forallb_forall with (x := "arguments") in Declared.
  - rewrite Undeclared in Declared; discriminate.
  - unfold Schema.source_keys. apply in_map_iff.
    exists ("arguments", value); split; [reflexivity|assumption].
Qed.

(* Rejecting the old object field also rejects records carrying both forms,
   irrespective of their order or the remaining members. *)
Theorem rejects_old_argument_authority : forall nesting fields value,
  In ("arguments", value) fields ->
  CallWire.decode_at nesting (JObject fields) = None /\
  CallWire.decode_item_at nesting (JObject fields) = None.
Proof.
  intros nesting fields value Member.
  assert (CallUnknown : Schema.keys_declared CallWire.declaration fields = false).
  { eapply old_argument_member_is_undeclared; [reflexivity|exact Member]. }
  assert (ItemUnknown : Schema.keys_declared CallWire.item_declaration fields = false).
  { eapply old_argument_member_is_undeclared; [reflexivity|exact Member]. }
  split; unfold CallWire.decode_at, CallWire.decode_item_at, Schema.decode;
    rewrite ?CallUnknown, ?ItemUnknown, !andb_false_r; reflexivity.
Qed.

Theorem encoded_call_fields_are_unique : forall id name arguments,
  match CallWire.encode id name arguments with
  | JObject fields => Schema.unique_names (Schema.source_keys fields) = true
  | _ => False
  end /\
  match CallWire.encode_item id name arguments with
  | JObject fields => Schema.unique_names (Schema.source_keys fields) = true
  | _ => False
  end.
Proof. intros; split; reflexivity. Qed.
