From Stdlib Require Import String List Bool Arith Lia.
From Selvedge.Foundation Require Import Json TextJson CallWire Utf8.
From Selvedge.Foundation Require Import TextJsonRoundtrip.

Theorem decode_encode_legal_arguments : forall nesting id name members,
 Utf8.nonblank id = true -> Utf8.nonblank name = true ->
 legal_json (JObject members) -> json_height (JObject members) <= nesting ->
 decode_at nesting (CallWire.encode id name (JObject members)) = Some (id,name,JObject members).
Proof.
 intros nesting id name members Id Name Legal Depth.
 apply decoding_recovers_member_ast; [exact Id|exact Name|].
 unfold parse_arguments. rewrite parse_render_members_at by assumption. reflexivity.
Qed.

Theorem decode_encode_legal_call_item : forall nesting id name members,
 Utf8.nonblank id = true -> Utf8.nonblank name = true ->
 legal_json (JObject members) -> json_height (JObject members) <= nesting ->
 decode_item_at nesting (encode_item id name (JObject members)) = Some (id,name,JObject members).
Proof.
 intros nesting id name members Id Name Legal Depth.
 change (decode_at nesting (CallWire.encode id name (JObject members)) = Some (id,name,JObject members)).
 now apply decode_encode_legal_arguments.
Qed.

Corollary callback_call_wire_roundtrip : forall id name members,
 Utf8.nonblank id = true -> Utf8.nonblank name = true ->
 legal_json (JObject members) ->
 json_height (JObject members) <= callback_argument_nesting ->
 decode_at callback_argument_nesting (CallWire.encode id name (JObject members)) = Some (id,name,JObject members).
Proof. exact (decode_encode_legal_arguments callback_argument_nesting). Qed.

Corollary callback_call_item_wire_roundtrip : forall id name members,
 Utf8.nonblank id = true -> Utf8.nonblank name = true ->
 legal_json (JObject members) ->
 json_height (JObject members) <= callback_argument_nesting ->
 decode_item_at callback_argument_nesting (encode_item id name (JObject members)) = Some (id,name,JObject members).
Proof. exact (decode_encode_legal_call_item callback_argument_nesting). Qed.

Lemma callback_logical_nesting_budget : forall height,
 3 + height <= TextJson.input_nesting <-> height <= callback_argument_nesting.
Proof. intro height. unfold callback_argument_nesting, TextJson.input_nesting. vm_compute. lia. Qed.

Corollary callback_logical_call_wire_roundtrip : forall id name members,
 Utf8.nonblank id = true -> Utf8.nonblank name = true ->
 legal_json (JObject members) ->
 3 + json_height (JObject members) <= TextJson.input_nesting ->
 decode_at callback_argument_nesting (CallWire.encode id name (JObject members)) = Some (id,name,JObject members).
Proof.
 intros id name members Id Name Legal Depth. apply callback_call_wire_roundtrip; try assumption.
 now apply callback_logical_nesting_budget.
Qed.
