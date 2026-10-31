From Stdlib Require Import String List Bool Arith NArith.
From Selvedge.Foundation Require Import Json TextJson Schema Utf8 DeclarationFields EncodedObject.
From Selvedge.Foundation Require ArgumentDeclaration.
Import ListNotations.
Open Scope string_scope.
Module D := ArgumentDeclaration.
Module F := DeclarationFields.

(** Arguments sit below the callback object, item array and call item. Their
    encoded-object constructor consumes this same logical nesting budget. *)
Definition callback_argument_nesting := (TextJson.input_nesting - 3)%nat.
Definition identity_format := D.ConstrainedText (D.TextConstraints
 0%N D.maximum_natural D.maximum_natural false true false None).
Definition declaration nesting :=
 [F.required "id" (D.Textual identity_format);F.required "name" (D.Textual identity_format);
  F.required "arguments_json" (D.EncodedObject nesting)].
Definition item_declaration nesting := F.required "type" (D.Const (JString "call")) :: declaration nesting.
Definition admitted nesting := D.denote (D.Object (declaration nesting)).
Definition tuple_of {nesting} (value : admitted nesting) := proj1_sig value.
Definition identity {nesting} (value : admitted nesting) := D.encode_text identity_format (fst (tuple_of value)).
Definition name {nesting} (value : admitted nesting) := D.encode_text identity_format (fst (snd (tuple_of value))).
Definition arguments {nesting} (value : admitted nesting) := EncodedObject.value (fst (snd (snd (tuple_of value)))).
Definition from_text nesting id name text := D.decode (D.Object (declaration nesting))
 (JObject [("id",JString id);("name",JString name);("arguments_json",JString text)]).
Definition admit_at nesting := D.decode (D.Object (declaration nesting)).
Definition item_of {nesting} (value : admitted nesting) : D.denote (D.Object (item_declaration nesting)) :=
 exist _ (tt,tuple_of value) eq_refl.
Definition of_item {nesting} (value : D.denote (D.Object (item_declaration nesting))) : admitted nesting :=
 exist _ (snd (proj1_sig value)) eq_refl.
Definition project {nesting} (value : admitted nesting) := (identity value,name value,arguments value).
Definition decode_at nesting value := option_map (@project nesting) (admit_at nesting value).
Definition parse_arguments nesting text := option_map (@EncodedObject.value nesting)
 (EncodedObject.Admitted.parse nesting text).

(** Stored calls retain their already admitted argument AST. Serializing a
    request preserves its member order and number spellings. *)
Definition fields id name arguments := [
 ("id",JString id);("name",JString name);("arguments_json",JString (TextJson.render_json arguments))].
Definition encode id name arguments := JObject (fields id name arguments).
Definition argument_text value := match string_field "arguments_json" value with Some text => text | None => "" end.
Definition external value := match decode_at TextJson.input_nesting value with
 | Some (id,name,arguments) => JObject [("id",JString id);("name",JString name);("arguments",arguments)]
 | None => JNull end.
