From Stdlib Require Import String List Bool NArith ZArith Ascii.
From Selvedge.Programming Require Import Schema.
From Selvedge.Foundation Require Import TextMetrics BoundedInteger.
From Selvedge.Programming Require ArgumentDeclaration DeclarationFields.
From Selvedge.Foundation Require KeyedCollection OptionList.
From Selvedge.Adapters Require Export AccountFields.
From Selvedge.Kernel Require Import ModelCapabilities AccountNamespace.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module D := ArgumentDeclaration.
Module F := DeclarationFields.

Definition ascii_alnum character := let code := nat_of_ascii character in
  (Nat.leb 48 code && Nat.leb code 57) || (Nat.leb 65 code && Nat.leb code 90) ||
  (Nat.leb 97 code && Nat.leb code 122).
Fixpoint slug_tail source := match source with EmptyString => true | String first rest =>
  (ascii_alnum first || existsb (Ascii.eqb first) ["."%char;"_"%char;":"%char;"/"%char;"-"%char]) && slug_tail rest end.
Definition slug source := match source with EmptyString => false
  | String first rest => ascii_alnum first && slug_tail rest end.
Definition label := D.checked bounded_name.
Definition model_name := D.checked (fun value => bounded_name value && slug value).
Definition priority := D.checked BoundedInteger.within_safe_integer.
Definition effort_list := D.checked (fun values : list label => Nat.leb (List.length values) 32).
Inductive visibility := Listed | Hidden | Unavailable.
Definition visibility_name value := match value with Listed => "list" | Hidden => "hide" | Unavailable => "none" end.
Definition visibility_declaration := D.Value (KEnum "list" ["hide";"none"]).
Definition visibility_value (value : D.denote visibility_declaration) :=
 if String.eqb (proj1_sig value) "list" then Listed else if String.eqb (proj1_sig value) "hide" then Hidden else Unavailable.
Definition effort_fields := [F.required "effort" (D.Value KText)].
Definition model_fields := [F.required "slug" (D.Value KText);F.required "display_name" (D.Value KText);
 F.required "visibility" visibility_declaration;F.optional "priority" D.Integer;
 F.optional "supported_reasoning_levels" (D.Array (D.OpenObject effort_fields));
 F.optional "default_reasoning_level" (D.nullable (D.Value KText));
 F.optional "context_window" (D.Natural 1 4294967295);
 F.optional "effective_context_window_percent" (D.Natural 1 100)].
Record model_descriptor := ModelDescriptor {
  model_slug : model_name; model_display : label; model_visibility : visibility;
  model_priority : option priority; model_efforts : option effort_list;
  model_reasoning : option (option label); model_window : option (D.denote (D.Natural 1 4294967295));
  model_percent : option (D.denote (D.Natural 1 100))
}.
Definition model_id value := proj1_sig value.(model_slug).
Definition optional_admission {A B : Set} (parse : A -> option B) (value : option A) :=
 match value with Some value => option_map Some (parse value) | None => Some None end.
Definition admit_efforts (values : list (D.denote (D.OpenObject effort_fields))) : option effort_list :=
 match OptionList.traverse (fun fields => D.admit bounded_name (fst (proj1_sig fields))) values with
 | Some values => D.admit (fun values => Nat.leb (List.length values) 32) values | None => None end.
Definition admit_reasoning (value : D.denote (D.nullable (D.Value KText))) : option (option label) :=
 match value with
 | inl value => option_map Some (D.admit bounded_name value)
 | inr (inl _) => Some None | inr (inr impossible) => match impossible with end end.
Definition admit_model (source : D.denote (D.OpenObject model_fields)) : option model_descriptor :=
 let '(id,(title,(visible,(rank,(levels,(baseline,(context,(percent,_)))))))) := proj1_sig source in
 match D.admit (fun value => bounded_name value && slug value) id,D.admit bounded_name title,
   optional_admission (D.admit BoundedInteger.within_safe_integer) rank,
   optional_admission admit_efforts levels,optional_admission admit_reasoning baseline with
 | Some id,Some title,Some rank,Some levels,Some baseline =>
   Some (ModelDescriptor id title (visibility_value visible) rank levels baseline context percent)
 | _,_,_,_,_ => None end.
Definition optional_member {A} (name : string) (encode : A -> json) (value : option A) :=
  match value with Some value => [(name,encode value)] | None => [] end.
Definition label_json (value : label) := JString (proj1_sig value).
Definition effort_json (values : effort_list) := JArray (map (fun value => JObject [("effort",label_json value)]) (proj1_sig values)).
Definition nullable_label value := match value with Some value => label_json value | None => JNull end.
Definition model_json value := JObject ([("slug",JString (model_id value));("display_name",label_json value.(model_display));
  ("visibility",JString (visibility_name value.(model_visibility)))] ++
  optional_member "priority" (fun n => JNumber (show_integer (proj1_sig n))) value.(model_priority) ++
  optional_member "default_reasoning_level" nullable_label value.(model_reasoning) ++
  optional_member "supported_reasoning_levels" effort_json value.(model_efforts) ++
  optional_member "context_window" (fun n => number (proj1_sig n)) value.(model_window) ++
  optional_member "effective_context_window_percent" (fun n => number (proj1_sig n)) value.(model_percent)).
Module ModelEntries.
 Definition t := model_descriptor.
 Definition key := string.
 Definition key_of := model_id.
 Definition key_eq_dec := String.string_dec.
End ModelEntries.
Module Models := KeyedCollection.Make ModelEntries.
Module EffortEntries.
 Definition t := label.
 Definition key := string.
 Definition key_of (value : t) := proj1_sig value.
 Definition key_eq_dec := String.string_dec.
End EffortEntries.
Module Efforts := KeyedCollection.Make EffortEntries.
Definition model_effort_values value := match value.(model_efforts) with Some values => proj1_sig values | None => [] end.
Definition unique_efforts value := Efforts.values (Efforts.distinct (model_effort_values value)).
Definition models_declaration := D.BoundedArray 0 512 (D.OpenObject model_fields).
Definition admit_models (values : D.denote models_declaration) : outcome Models.t :=
 match OptionList.traverse admit_model (proj1_sig values) with
 | Some values => match Models.admit values with Some values => Accepted values
   (* DEFENSE: A remote catalog can repeat a slug; its identity must select one descriptor. *)
   | None => reject "ChatGPT returned an invalid model descriptor" end
 | None => reject "ChatGPT returned an invalid model descriptor" end.
Definition decode_models source := match D.decode models_declaration source with
 | Some values => admit_models values | None => reject "ChatGPT returned an invalid model descriptor" end.
Definition catalog_fields := [F.required "models" models_declaration].
Definition admit_catalog source := match D.decode (D.OpenObject catalog_fields) source with
 | Some fields => admit_models (fst (proj1_sig fields))
 | None => reject "ChatGPT returned an invalid model catalog" end.
Definition encode_models values := JArray (map model_json (Models.values values)).
Definition codex_auto_review model := String.eqb (model_id model) ModelCapabilities.codex_auto_review_model &&
  match model.(model_visibility) with Listed | Hidden => true | Unavailable => false end.
Definition selectable := Models.select (fun model =>
 (match model.(model_visibility) with Listed => true | _ => false end) && negb (codex_auto_review model)).
Definition review_models := Models.select codex_auto_review.
Definition catalog source := render_outcome encode_models (admit_catalog (get source "value")).
Definition discovery_catalog source := render_outcome encode_models (bind (admit_catalog (get source "value")) (fun values =>
 if Nat.eqb (Models.size (selectable values)) 0 then reject "This ChatGPT account advertised no selectable models" else Accepted values)).
Definition models_url source := let url := get source "url" in let path := str url "pathname" in
  if responses_path url then success (JString (substring 0
    (String.length path - if ends path "/responses/" then 11 else 10)%nat path ++ "/models"))
  else err "ChatGPT endpoint must end in /responses".
Definition connection_identity source := success (JString
  (str source "models_url" ++ String (ascii_of_nat 0) "" ++ str (get source "profile") "issuer")).
Definition candidate_identity source := success (JString
  (str source "resolved" ++ String (ascii_of_nat 0) "" ++ str source "connection")).
Definition model_cache_path source := success (JString (str source "resolved" ++ ".models-" ++ str source "hash" ++ ".json")).
Definition hash_prefix source := success (JString (substring 0 AccountNamespace.hash_width (str source "digest"))).
Definition account_namespace source := if AccountNamespace.hash_valid (str source "hash")
  then success (JString (AccountNamespace.make (str source "hash"))) else err "Invalid ChatGPT account namespace".

Definition cache_format := "selvedge-siwc-models-1".
Definition cache source :=
  let value := get source "value" in let elapsed := get source "elapsed" in
  if is_object value && same (get value "format") (JString cache_format) &&
    same (get value "account_id") (get source "account") && same (get value "connection") (get source "connection") &&
    is_object (get source "fetched") && is_object elapsed && between (get elapsed "floor") 0 86400000 &&
    between (get elapsed "ceil") 0 86400000
  then match admit_catalog value with
    | Accepted models => success (JObject [("models",encode_models models);("age",get elapsed "value")])
    | Rejected _ _ => success JNull end
  else success JNull.
Definition cache_fresh source := success (JBool (negb (boolean_field source "force") &&
  is_object (get source "cached") && between (get (get source "age_measurement") "floor") 0 299999)).
Definition cache_fallback source := success (JBool (negb (boolean_field source "force") && is_object (get source "cached") &&
  (boolean_field source "type_error" || same (get source "error_name") (JString "TimeoutError") ||
    same (get source "status") (number 429) || at_least (get source "status") 500))).
Definition cache_record source := if is_object (get source "now_date") then success (JObject [
  ("format",JString cache_format);("account_id",get source "account");("connection",get source "connection");
  ("fetched_at",get (get source "now_date") "iso");("models",get source "models")]) else range_error "Invalid time value".
Definition cache_size source := success (JBool (between (get source "size") 0 1048576)).
(* DEFENSE: Missing, malformed, special, oversized or concurrently edited cache
   files are disposable; permission and actual IO failures stay visible. *)
Definition cache_error source := if same (get source "code") (JString "ENOENT") ||
  same (get source "code") (JString "ERR_ENCODING_INVALID_ENCODED_DATA") ||
  existsb (fun code => same (get source "code") (JString code))
    ["NOT_REGULAR";"TOO_LARGE";"CHANGED"] then success JNull
  else err "Cannot read the ChatGPT model cache".
Definition catalog_result source := success (JObject [("account_id",get (get source "authorization") "account_id");
  ("models",if boolean_field source "cached_result" then get (get source "cached") "models" else get source "models");
  ("cached",get source "cached_result");("stale",get source "stale")]).
