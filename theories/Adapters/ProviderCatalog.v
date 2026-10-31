From Stdlib Require Import String List Bool NArith Ascii.
From Selvedge.Foundation Require Import Json Utf8 JsonObjects.
From Selvedge.Programming Require Import DeclarationRegistry.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition local_tool_namespace := "selvedge".
Definition connection_keys := ["provider"; "endpoint"; "auth_file"; "issuer"; "timeout_ms"].
Definition nonempty value := is_text value && Utf8.nonblank (text value).
Inductive provider :=
  | Offline
  | EnvironmentSSE (name endpoint credential : string)
  | AccountSSE
  | WebConnection (endpoint credential : string).
Definition authentication connection := match connection with
  | Offline => "none" | EnvironmentSSE _ _ _ => "environment" | AccountSSE => "account" | WebConnection _ _ => "web" end.
Definition connection_transport connection := match connection with
  | Offline => "echo" | WebConnection _ _ => "web" | _ => "sse" end.
Definition connection_endpoint connection := match connection with
  | EnvironmentSSE _ endpoint _ | WebConnection endpoint _ => endpoint | _ => "" end.
Definition connection_credential connection := match connection with
  | EnvironmentSSE _ _ credential | WebConnection _ credential => credential | _ => "" end.
Definition connection_stream connection := match connection with AccountSSE => "chatgpt" | _ => "responses" end.
Definition connection_account connection := match connection with AccountSSE => true | _ => false end.
Definition connection_web connection := match connection with WebConnection _ _ => true | _ => false end.
Definition connection_live connection := match connection with Offline => false | _ => true end.
Definition connection_uses_endpoint connection := match connection with
  | EnvironmentSSE _ _ _ | WebConnection _ _ => true | _ => false end.

(** Responses-compatible registrations supply their own names. Account and Web
    connections are the concrete ChatGPT services, so their identities cannot
    disagree with their authentication and capability semantics. *)
Definition provider_name (value : provider) := match value with
 | Offline => "echo" | EnvironmentSSE name _ _ => name
 | AccountSSE => "chatgpt" | WebConnection _ _ => "chatgpt-web" end.
Definition responses_backend := EnvironmentSSE.
Definition account_backend := AccountSSE.
Definition web_backend := WebConnection.
(** A profile selects a backend by name. Registration establishes that this
    lookup is unambiguous, including names fixed by a service constructor. *)
Definition declare_providers entries `{Schema.DistinctNames (map provider_name entries)} :=
 DeclarationRegistry.declare provider_name entries.
Definition registered := declare_providers [Offline;
  responses_backend "responses" "https://api.openai.com/v1/responses" "OPENAI_API_KEY";
  account_backend;
  web_backend "http://127.0.0.1:8787/v1/responses" "CHATGPT_WEB_TOKEN"].
Definition providers := DeclarationRegistry.values registered.
Definition descriptor provider := JObject [
  ("provider",JString (provider_name provider));
  ("protocol",JString (if connection_live provider then "responses" else "echo"));
  ("stream_kind",JString (connection_stream provider)); ("conversation",JBool true);
  ("tools",JBool (connection_live provider)); ("independent_text",JBool (connection_live provider));
  ("auth",JString (authentication provider)); ("transport",JString (connection_transport provider));
  ("endpoint",JString (connection_endpoint provider)); ("api_key_env",JString (connection_credential provider))].
Definition catalog := map descriptor providers.
Definition backend profile := match as_string (get profile "provider") with
  | Some name => DeclarationRegistry.lookup name registered
  | None => None end.
Definition connection_of := backend.
Definition account profile := match connection_of profile with Some connection => connection_account connection | None => false end.
Definition web profile := match connection_of profile with Some connection => connection_web connection | None => false end.
Definition uses_endpoint profile := match connection_of profile with Some connection => connection_uses_endpoint connection | None => false end.
Definition supports_compaction profile := match connection_of profile with
 | Some (EnvironmentSSE _ _ _) | Some AccountSSE => true | _ => false end.
Definition default value fallback := if is_null value then fallback else value.
Definition endpoint profile := default (get profile "endpoint") (match connection_of profile with
  | Some connection => JString (connection_endpoint connection) | None => JNull end).
Definition credential profile := default (get profile "api_key_env") (match connection_of profile with
  | Some connection => JString (connection_credential connection) | None => JNull end).
Definition independent_kind kind := existsb (String.eqb kind) ["approval";"board_text";"task_title";"context_compaction"].
Definition contains values item := existsb (fun value => JsonObjects.equivalent value item) values.
Definition env_letter character := let code := nat_of_ascii character in
  ((Nat.leb 65 code) && (Nat.leb code 90)) ||
  ((Nat.leb 97 code) && (Nat.leb code 122)) || Ascii.eqb character "_"%char.
Definition env_digit character := let code := nat_of_ascii character in
  (Nat.leb 48 code) && (Nat.leb code 57).
Fixpoint env_tail value := match value with EmptyString => true
  | String first rest => (env_letter first || env_digit first) && env_tail rest end.
Definition env_name value := match value with EmptyString => false
  | String first rest => env_letter first && env_tail rest end.
Definition ends source suffix :=
  String.eqb (substring (String.length source - String.length suffix) (String.length suffix) source) suffix.
Fixpoint contains_text needle source :=
  String.prefix needle source || match source with EmptyString => false | String _ rest => contains_text needle rest end.
Fixpoint lower_ascii source := match source with EmptyString => EmptyString | String first rest =>
  let code := nat_of_ascii first in String (if (Nat.leb 65 code) && (Nat.leb code 90) then
    ascii_of_nat (code + 32) else first) (lower_ascii rest) end.
Fixpoint display value := match value with
  | JNull => "null" | JBool true => "true" | JBool false => "false"
  | JNumber lexeme => lexeme | JString content => content | JObject _ => "[object Object]"
  | JArray values => String.concat "," (map (fun item => if is_null item then "" else display item) values) end.
Definition display_field source name := if has source name then display (get source name) else "undefined".

Inductive outcome (A : Type) := Accepted (value : A) | Rejected (code message : string).
Arguments Accepted {A} _.
Arguments Rejected {A} _ _.
Definition render_outcome {A} (encode : A -> json) (result : outcome A) :=
  match result with Accepted value => success (encode value) | Rejected code message => failure code message end.
Definition bind {A B} (value : outcome A) (next : A -> outcome B) :=
  match value with Accepted value => next value | Rejected code message => Rejected code message end.
Fixpoint traverse {A B} (f : A -> outcome B) (values : list A) : outcome (list B) :=
  match values with [] => Accepted [] | value :: rest =>
    bind (f value) (fun head => bind (traverse f rest) (fun tail => Accepted (head :: tail))) end.
Definition reject {A} message : outcome A := Rejected "Error" message.
