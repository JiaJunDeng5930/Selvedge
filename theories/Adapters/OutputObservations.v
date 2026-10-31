From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Utf8 ModelWire DeclarationFields.
From Selvedge.Adapters Require Import Common ProviderCatalog.
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
   if Nat.eqb (List.length observations) 0
   then Accepted (ModelWire.call (CallWire.of_item invocation))
   else reject "Tool output cannot carry Markdown fence observations"
 | _ => reject "Unsupported model output item for Markdown observation" end.
Fixpoint observe_items outputs observations : outcome (list ModelWire.value) :=
 match outputs,observations with
 | [],[] => Accepted []
 | output::rest, fences::fence_rest =>
     bind (observe_item output fences) (fun observed =>
       bind (observe_items rest fence_rest) (fun observed_rest =>
         Accepted (observed::observed_rest)))
 | _,_ => reject "Model output and Markdown fence observations are misaligned"
 end.
Definition observe_text_output source :=
 match array_field "items" source,D.decode (D.Array fences_declaration) (get source "markdown_observations") with
 | Some outputs,Some observations => render_outcome ModelWire.encode_items (observe_items outputs observations)
 | _,_ => err "Model text output has no aligned Markdown fence observations"
 end.
