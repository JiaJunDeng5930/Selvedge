From Stdlib Require Import String List Bool NArith ZArith Ascii.
From Selvedge.Foundation Require Import Json Numbers Utf8.
From Selvedge.Programming Require Import Schema.
From Selvedge.Foundation Require Import JsonObjects TextMetrics.
From Selvedge.Adapters Require Export Common ProviderCatalog AccountContracts.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Inductive account_kind := ModelAccount | AudioAccount.
Definition kind_of source := if boolean_field source "audio" then AudioAccount else ModelAccount.
Definition is_audio kind := match kind with AudioAccount => true | _ => false end.
Definition credential_format kind := match kind with
  | ModelAccount => "selvedge-chatgpt-2" | AudioAccount => "selvedge-chatgpt-audio-1" end.
Definition same := JsonObjects.equivalent.
Definition supplied source key fallback := if has source key then get source key else fallback.
Definition nullable value := is_null value || nonempty value.
Definition utf16_within limit source := match TextMetrics.utf16_units source with
  | Some units => units <=? limit | None => false end.
Definition bounded_name value := negb (String.eqb value "") && utf16_within 256 value.
Definition bounded_text value := match value with JString value => bounded_name value | _ => false end.
(* DEFENSE: Account hashes separate issuer, client and subject with NUL; admitting
   that delimiter inside a component would alias distinct identity tuples. *)
Definition identity_text value := nonempty value && Utf8.no_nul (text value).
Definition client value := identity_text value && negb (same value (JString "dynamic_agent_client")).
Definition between value minimum maximum := match natural value with
  | Some n => (minimum <=? n) && (n <=? maximum) | None => false end.
Definition at_least value minimum := match natural value with Some n => minimum <=? n | None => false end.
Definition selected_fields source keys := filter (fun entry => existsb (String.eqb (fst entry)) keys) (object_fields source).
Definition project source keys := JObject (selected_fields source keys).
Definition field_description names nullable_names := map (fun name =>
  Schema.Field name (if existsb (String.eqb name) nullable_names then Schema.KOptional Schema.KText else Schema.KText)) names.
Definition credential_schema := field_description
  ["format";"issuer";"client_id";"subject";"account_id";"access_token";"refresh_token";
   "id_token";"scope";"expires_at";"earliest_refresh_at";"last_refresh";"name";"email"]
  ["scope";"earliest_refresh_at";"name";"email"].
Definition registration_schema := field_description ["format";"issuer";"client_id";"subject"] ["subject"].
Definition decode_complete description source :=
  if Nat.eqb (List.length (object_fields source)) (List.length description)
  then Schema.decode description source else None.
Definition encoded {description} (values : Schema.fields description) := Schema.encode description values.

Fixpoint split_scope (parts : list (N * string)) current acc := match parts with
  | [] => rev (String.concat "" (rev current) :: acc)
  | (code,bytes)::rest => if Utf8.whitespace code then
      split_scope rest [] (String.concat "" (rev current)::acc)
    else split_scope rest (bytes::current) acc end.
Definition scope value := nonempty value && match Utf8.chunks (text value) with
  | Some chunks => existsb (String.eqb "chatgpt.tokens.use.direct") (split_scope chunks [] [])
  | None => false end.
Definition date_valid value observation := is_text value && is_object observation && is_text (get observation "iso").
Definition ordered_epoch observation := match parse_natural (str observation "ordered_epoch") with
  | Some value => value | None => 0 end.
Definition epoch_greater left right := ordered_epoch right <? ordered_epoch left.

Definition loopback url := existsb (String.eqb (str url "hostname")) ["localhost";"127.0.0.1";"[::1]"].
Definition parsed url := is_object url && nonempty (get url "href").
Definition url_shape url := parsed url &&
  existsb (String.eqb (str url "protocol")) ["http:";"https:"] &&
  String.eqb (str url "username") "" && String.eqb (str url "password") "" && String.eqb (str url "hash") "".
Definition secure url := String.eqb (str url "protocol") "https:" || loopback url.
Definition responses_path url := ends (str url "pathname") "/responses" || ends (str url "pathname") "/responses/".
Definition endpoint_binding url := loopback url ||
  (String.eqb (str url "origin") "https://api.openai.com" && String.eqb (str url "pathname") "/v1/responses").
Definition issuer_binding url := loopback url || String.eqb (str url "origin") "https://auth.openai.com".
Definition trim_slashes value :=
  let reversed := rev (list_ascii_of_string value) in
  let fix drop values := match values with
    | first::rest => if Ascii.eqb first "/"%char then drop rest else values | [] => [] end in
  string_of_list_ascii (rev (drop reversed)).
Definition require (condition : bool) (message : string) : outcome unit :=
  if condition then Accepted tt else reject message.
Definition invalid_url url label := if parsed url then "Invalid ChatGPT " ++ label else "Invalid URL".

Record connection := Connection {
  endpoint : string; issuer : string; auth_file : string; timeout_ms : N
}.
Definition connection_json value := JObject [("provider",JString "chatgpt");
  ("endpoint",JString value.(endpoint));("auth_file",JString value.(auth_file));
  ("issuer",JString value.(issuer));("timeout_ms",number value.(timeout_ms))].
Definition admit_connection value urls : outcome connection :=
  let defaults := AccountContracts.defaults in
  let endpoint := supplied value "endpoint" (get defaults "endpoint") in
  let issuer := supplied value "issuer" (get defaults "issuer") in
  let auth_file := supplied value "auth_file" (get defaults "auth_file") in
  let timeout := supplied value "timeout_ms" (get defaults "timeout_ms") in
  let endpoint_url := get urls "endpoint" in let issuer_url := get urls "issuer" in
  bind (require (is_object value) "ChatGPT account must be an object") (fun _ =>
  match find (fun entry => negb (existsb (String.eqb (fst entry)) connection_keys)) (object_fields value) with
  | Some (name,_) => reject ("Unknown ChatGPT account field: " ++ name)
  | None =>
  bind (require (same (supplied value "provider" (JString "chatgpt")) (JString "chatgpt")) "The account provider must be chatgpt") (fun _ =>
  bind (require (nonempty endpoint) "ChatGPT endpoint must be a nonempty string") (fun _ =>
  bind (require (url_shape endpoint_url) (invalid_url endpoint_url "endpoint")) (fun _ =>
  bind (require (secure endpoint_url) "ChatGPT endpoint requires HTTPS except on loopback") (fun _ =>
  bind (require (responses_path endpoint_url) "ChatGPT endpoint must end in /responses") (fun _ =>
  bind (require (endpoint_binding endpoint_url) "ChatGPT requires the official public Responses endpoint") (fun _ =>
  bind (require (identity_text issuer) "ChatGPT issuer must be a nonempty string without NUL") (fun _ =>
  bind (require (url_shape issuer_url) (invalid_url issuer_url "issuer")) (fun _ =>
  bind (require (secure issuer_url) "ChatGPT issuer requires HTTPS except on loopback") (fun _ =>
  bind (require (issuer_binding issuer_url) "ChatGPT requires the official issuer") (fun _ =>
  bind (require (String.eqb (str issuer_url "pathname") "/" && String.eqb (str issuer_url "search") "") "ChatGPT issuer must be an origin") (fun _ =>
  bind (require (nonempty auth_file) "ChatGPT auth_file must be a nonempty string") (fun _ =>
  bind (require (between timeout 100 1800000) "ChatGPT timeout must be in 100..1800000") (fun _ =>
  Accepted (Connection (text endpoint) (trim_slashes (text issuer)) (text auth_file) (nat_value timeout))))))))))))))) end).
Definition connection_call source := render_outcome connection_json (admit_connection (get source "value") (get source "urls")).
Definition profile_connection_value profile :=
  let selected := project profile connection_keys in
  JObject ([("endpoint",default (get selected "endpoint") (get AccountContracts.defaults "endpoint"));
    ("auth_file",default (get selected "auth_file") (get AccountContracts.defaults "auth_file"));
    ("issuer",default (get selected "issuer") (get AccountContracts.defaults "issuer"))] ++
    selected_fields selected ["provider";"timeout_ms"]).
Definition profile_connection source := success (profile_connection_value (get source "profile")).
