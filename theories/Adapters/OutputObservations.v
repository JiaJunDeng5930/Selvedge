From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Utf8.
From Selvedge.Adapters Require Import Common ProviderCatalog.
Import ListNotations.
Open Scope string_scope.

Definition fence_observation_valid observation :=
 is_object observation && is_text (get observation "raw_info") &&
 is_text (get observation "fence_kind") && Json.is_bool (get observation "info_complete").

Definition assistant_message text := JObject [
 ("type",JString "message");("role",JString "assistant");
 ("content",JArray [JObject [("type",JString "output_text");("text",text)]])].

Definition provider_receipt text fences := JObject [
 ("type",JString "provider_receipt");("item",assistant_message text);
 ("markdown_fences",fences)].

Definition observed_context item fences := JObject [
 ("type",JString "context");("part",get item "part");
 ("value",provider_receipt (get item "text") fences)].

Definition observe_item item fences : outcome json :=
 if is_array fences && forallb fence_observation_valid (items fences) then
   if String.eqb (str item "type") "text" then
     if canonical_natural (get item "part") && is_text (get item "text") &&
        Utf8.well_formed (str item "text")
     then Accepted (observed_context item fences)
     else reject "Model text output is malformed"
   else if String.eqb (str item "type") "call" then
     if Nat.eqb (List.length (items fences)) 0 then Accepted item
     else reject "Tool output cannot carry Markdown fence observations"
   else reject "Unsupported model output item for Markdown observation"
 else reject "Markdown fence observations are malformed".

Fixpoint observe_items outputs observations : outcome (list json) :=
 match outputs,observations with
 | [],[] => Accepted []
 | output::rest, fences::fence_rest =>
     bind (observe_item output fences) (fun observed =>
       bind (observe_items rest fence_rest) (fun observed_rest =>
         Accepted (observed::observed_rest)))
 | _,_ => reject "Model output and Markdown fence observations are misaligned"
 end.

Definition observe_text_output source :=
 match array_field "items" source,array_field "markdown_observations" source with
 | Some outputs,Some observations => render_outcome JArray (observe_items outputs observations)
 | _,_ => err "Model text output has no aligned Markdown fence observations"
 end.
