From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json Schema DeclarationFields CallWire.
From Selvedge.Foundation Require ArgumentDeclaration.
Import ListNotations.
Open Scope string_scope.
Module D := ArgumentDeclaration.
Module F := DeclarationFields.

Definition text_fields :=
 [F.required "type" (D.Const (JString "text"));F.required "part" (D.Value KNatural);F.required "text" D.text].
Definition context_fields :=
 [F.required "type" (D.Const (JString "context"));F.required "part" (D.Value KNatural);F.required "value" D.RawObject].
Definition declaration := D.Union [D.Object text_fields;
 D.Object (CallWire.item_declaration CallWire.callback_argument_nesting);D.Object context_fields].
Definition value := D.denote declaration.
Definition decode := D.decode declaration.
Definition encode := D.encode declaration.
Definition text part (contents : D.denote D.text) : value :=
 inl (exist _ (tt,(part,(contents,tt))) eq_refl).
Definition text_from_string part source := option_map (text part)
 (D.decode_text (D.ConstrainedText D.unconstrained_text) source).
Definition call (invocation : CallWire.admitted CallWire.callback_argument_nesting) : value :=
 inr (inl (CallWire.item_of invocation)).
Definition context part (members : list (string * json)) : value :=
 inr (inr (inl (exist _ (tt,(part,(members,tt))) eq_refl))).
Definition items := D.Array declaration.
Definition decode_items := D.decode items.
Definition encode_items := D.encode items.
