From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Utf8 ModelWire.
From Selvedge.Programming Require Import DeclarationFields.
From Selvedge.Adapters Require Import Common ProviderCatalog.
From Selvedge.Programming Require Import AdapterResult.
Import ListNotations.
Open Scope string_scope.
Module D := ArgumentDeclaration.
Module F := DeclarationFields.

Definition fence_declaration := D.Object [F.required "raw_info" D.text;
 F.required "fence_kind" D.text;F.required "info_complete" D.Boolean].
Definition fences_declaration := D.Array fence_declaration.
Definition fences := D.denote fences_declaration.
Definition encode_fences := D.encode fences_declaration.
Definition assistant_message text := JObject [
 ("type",JString "message");("role",JString "assistant");
 ("content",JArray [JObject [("type",JString "output_text");("text",text)]])].
Definition provider_fields := List.app ModelWire.context_fields
 [F.required "markdown_fences" fences_declaration].
Definition provider_observation part members fences := D.encode
 (D.Object provider_fields) (exist _ (tt,(part,(members,(fences,tt)))) eq_refl).
Definition observe_item item (observations : fences) : outcome ModelWire.value :=
 match ModelWire.decode item with
 | Some (inl text) => let fields := proj1_sig text in
   Accepted (ModelWire.context (fst (snd fields)) [
     ("type",JString "provider_receipt");("item",assistant_message (JString (proj1_sig (fst (snd (snd fields))))));
     ("markdown_fences",encode_fences observations)])
 | Some (inr (inl invocation)) =>
   Accepted (ModelWire.call (CallWire.of_item invocation))
 | _ => reject "Unsupported model output item for Markdown observation" end.
Definition observe_text_output source :=
 match array_field "items" source,D.decode (D.Array fences_declaration) (get source "markdown_observations") with
 (* The host maps Markdown observations over these exact output rows. *)
 | Some outputs,Some observations => render_outcome ModelWire.encode_items
     (traverse (fun pair => observe_item (fst pair) (snd pair)) (combine outputs observations))
 | _,_ => err "Model text output requires Markdown fence observations"
 end.
