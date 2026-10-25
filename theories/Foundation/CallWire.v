From Stdlib Require Import String List Bool Arith.
From Selvedge.Foundation Require Import Json TextJson Schema Utf8.
Import ListNotations.
Open Scope string_scope.

(* A model callback places arguments below its object, items array and call item.
   Text transport must consume the same logical nesting as the former AST field. *)
Definition callback_argument_nesting := (TextJson.input_nesting - 3)%nat.
Definition declaration := [Field "id" KText; Field "name" KText; Field "arguments_json" KText].
Definition item_declaration := Field "type" (KEnum "call" []) :: declaration.
Definition fields id name arguments := [
 ("id", JString id); ("name", JString name);
 ("arguments_json", JString (TextJson.render_json arguments))].
Definition encode id name arguments := JObject (fields id name arguments).
Definition encode_item id name arguments := JObject (("type",JString "call") :: fields id name arguments).
Definition parse_arguments nesting text := match TextJson.parse_json_members_at nesting text with
 | Some (JObject fields) => Some (JObject fields) | _ => None end.
Definition decode_fields nesting id name text :=
 if Utf8.nonblank id && Utf8.nonblank name then
 option_map (fun arguments => (id,name,arguments)) (parse_arguments nesting text) else None.
Definition decode_at nesting value := match Schema.decode declaration value with
 | Some fields => decode_fields nesting (head fields) (head (tail fields)) (head (tail (tail fields)))
 | None => None end.
Definition decode_item_at nesting value := match Schema.decode item_declaration value with
 | Some fields => decode_fields nesting (head (tail fields)) (head (tail (tail fields))) (head (tail (tail (tail fields))))
 | None => None end.
Definition argument_text value := match string_field "arguments_json" value with Some text => text | None => "" end.
(* The external plugin protocol owns parsed objects. This is the one explicit
   projection from internal wire calls; it is never a source of executable calls. *)
Definition external value := match decode_at TextJson.input_nesting value with
 | Some (id,name,arguments) => JObject [("id",JString id);("name",JString name);("arguments",arguments)]
 | None => JNull end.

Theorem encode_preserves_argument_text : forall id name arguments,
 string_field "arguments_json" (encode id name arguments) = Some (TextJson.render_json arguments).
Proof. reflexivity. Qed.
Theorem decoding_recovers_member_ast : forall nesting id name arguments,
 Utf8.nonblank id = true -> Utf8.nonblank name = true ->
 parse_arguments nesting (TextJson.render_json arguments) = Some arguments ->
 decode_at nesting (encode id name arguments) = Some (id,name,arguments).
Proof.
 intros nesting id name arguments Id Name Parsed.
 unfold decode_at, encode, fields, declaration, Schema.decode, Schema.decode_fields.
 cbn. unfold decode_fields. rewrite Id, Name. cbn. rewrite Parsed. reflexivity.
Qed.
