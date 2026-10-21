From Stdlib Require Import String List Bool NArith ZArith Ascii.
From Selvedge.Foundation Require Import Schema TextMetrics.
From Selvedge.Adapters Require Export AccountFields.
From Selvedge.Kernel Require Import ModelCapabilities AccountNamespace.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition ascii_alnum character := let code := nat_of_ascii character in
  (Nat.leb 48 code && Nat.leb code 57) || (Nat.leb 65 code && Nat.leb code 90) ||
  (Nat.leb 97 code && Nat.leb code 122).
Fixpoint slug_tail source := match source with EmptyString => true | String first rest =>
  (ascii_alnum first || existsb (Ascii.eqb first) ["."%char;"_"%char;":"%char;"/"%char;"-"%char]) && slug_tail rest end.
Definition slug source := match source with EmptyString => false
  | String first rest => ascii_alnum first && slug_tail rest end.
Definition safe_integer value : option Z := match value with
  | JNumber spelling => match parse_integer spelling with
    | Some value => if Z.leb (Z.abs value) 9007199254740991 then Some value else None
    | None => None end | _ => None end.
Definition window maximum value : option N := match natural value with
  | Some value => if (1 <=? value) && (value <=? maximum) then Some value else None | _ => None end.
Inductive visibility := Listed | Hidden | Unavailable.
Definition visibility_name value := match value with Listed => "list" | Hidden => "hide" | Unavailable => "none" end.
Definition parse_visibility value :=
  if same value (JString "list") then Some Listed else
  if same value (JString "hide") then Some Hidden else
  if same value (JString "none") then Some Unavailable else None.
Definition optional_decode {A} (decode : json -> option A) source name :=
  if has source name then option_map Some (decode (get source name)) else Some None.
Definition reasoning_level value : option (option string) := match value with
  | JNull => Some None | JString value => if bounded_text (JString value) then Some (Some value) else None
  | _ => None end.
Definition effort value : option string := if is_object value && bounded_text (get value "effort")
  then Some (str value "effort") else None.
Definition efforts value : option (list string) := match value with
  | JArray values => if Nat.leb (List.length values) 32 then Schema.decode_list effort values else None | _ => None end.
Record model_descriptor := ModelDescriptor {
  model_slug : string; model_display : string; model_visibility : visibility;
  model_priority : option Z; model_efforts : option (list string);
  model_reasoning : option (option string); model_window : option N; model_percent : option N
}.
Definition admit_model seen source : option model_descriptor :=
  match as_string (get source "slug"), as_string (get source "display_name"), parse_visibility (get source "visibility"),
    optional_decode safe_integer source "priority", optional_decode efforts source "supported_reasoning_levels",
    optional_decode reasoning_level source "default_reasoning_level", optional_decode (window 4294967295) source "context_window",
    optional_decode (window 100) source "effective_context_window_percent" with
  | Some id,Some title,Some visible,Some priority,Some levels,Some baseline,Some context,Some percent =>
      if is_object source && bounded_text (JString id) && bounded_text (JString title) && slug id &&
        negb (existsb (String.eqb id) seen)
      then Some (ModelDescriptor id title visible priority levels baseline context percent) else None
  | _,_,_,_,_,_,_,_ => None end.
Definition optional_member {A} (name : string) (encode : A -> json) (value : option A) :=
  match value with Some value => [(name,encode value)] | None => [] end.
Definition effort_json values := JArray (map (fun value => JObject [("effort",JString value)]) values).
Definition nullable_text value := match value with Some value => JString value | None => JNull end.
Definition model_json value := JObject ([("slug",JString value.(model_slug));("display_name",JString value.(model_display));
  ("visibility",JString (visibility_name value.(model_visibility)))] ++
  optional_member "priority" (fun n => JNumber (show_integer n)) value.(model_priority) ++
  optional_member "default_reasoning_level" nullable_text value.(model_reasoning) ++
  optional_member "supported_reasoning_levels" effort_json value.(model_efforts) ++
  optional_member "context_window" number value.(model_window) ++
  optional_member "effective_context_window_percent" number value.(model_percent)).
Fixpoint admit_models seen values : outcome (list model_descriptor) := match values with
  | [] => Accepted [] | value::rest => match admit_model seen value with
    | None => reject "ChatGPT returned an invalid model descriptor"
    | Some value => bind (admit_models (value.(model_slug)::seen) rest) (fun tail => Accepted (value::tail)) end end.
Definition catalog source := let value := get source "value" in
  if is_object value && is_array (get value "models") && Nat.leb (List.length (items (get value "models"))) 512
  then render_outcome (fun values => JArray (map model_json values)) (admit_models [] (items (get value "models")))
  else err "ChatGPT returned an invalid model catalog".
Definition codex_auto_review model := same (get model "slug") (JString ModelCapabilities.codex_auto_review_model) &&
  (same (get model "visibility") (JString "list") || same (get model "visibility") (JString "hide")).
Definition selectable models := filter (fun model => same (get model "visibility") (JString "list") && negb (codex_auto_review model)) models.
Definition review_models := filter codex_auto_review.
Definition catalog_selectable source := let models := selectable (items (get source "models")) in
  if Nat.eqb (List.length models) 0 then err "This ChatGPT account advertised no selectable models" else success (JArray models).
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
  then let admitted := catalog (JObject [("value",value)]) in
    if boolean_field admitted "ok" then success (JObject [("models",get admitted "value");("age",get elapsed "value")])
    else success JNull
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
(* DEFENSE: A first discovery has no cache, and a cache containing invalid UTF-8
   is disposable like malformed JSON; other filesystem failures stay visible. *)
Definition cache_error source := if same (get source "code") (JString "ENOENT") ||
  same (get source "code") (JString "ERR_ENCODING_INVALID_ENCODED_DATA") then success JNull
  else err "Cannot read the ChatGPT model cache".
Definition catalog_result source := success (JObject [("account_id",get (get source "authorization") "account_id");
  ("models",if boolean_field source "cached_result" then get (get source "cached") "models" else get source "models");
  ("cached",get source "cached_result");("stale",get source "stale")]).
Definition account_summary source := let result := get source "result" in success (JObject [
  ("models",number (N.of_nat (List.length (selectable (items (get result "models"))))));
  ("cached",get result "cached");("stale",get result "stale")]).
