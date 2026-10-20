From Stdlib Require Import String List Bool NArith Ascii.
From Selvedge.Foundation Require Import Json Utf8 JsonObjects.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition local_tool_namespace := "selvedge".
Definition connection_keys := ["provider"; "endpoint"; "auth_file"; "issuer"; "timeout_ms"].
Definition nonempty value := is_text value && Utf8.nonblank (text value).
Inductive connection :=
  | EnvironmentSSE (endpoint credential : string)
  | AccountSSE
  | WebConnection (endpoint credential : string).
Definition authentication connection := match connection with
  | EnvironmentSSE _ _ => "environment" | AccountSSE => "account" | WebConnection _ _ => "web" end.
Definition connection_transport connection := match connection with WebConnection _ _ => "web" | _ => "sse" end.
Definition connection_endpoint connection := match connection with
  | EnvironmentSSE endpoint _ | WebConnection endpoint _ => endpoint | AccountSSE => "" end.
Definition connection_credential connection := match connection with
  | EnvironmentSSE _ credential | WebConnection _ credential => credential | AccountSSE => "" end.
Definition connection_stream connection := match connection with AccountSSE => "chatgpt" | _ => "responses" end.
Definition descriptor identity connection := JObject [
  ("provider",JString identity); ("protocol",JString "responses");
  ("stream_kind",JString (connection_stream connection)); ("conversation",JBool true);
  ("tools",JBool true); ("independent_text",JBool true);
  ("auth",JString (authentication connection)); ("transport",JString (connection_transport connection));
  ("endpoint",JString (connection_endpoint connection)); ("api_key_env",JString (connection_credential connection))].
Definition echo_descriptor :=
  set (set (set (set (descriptor "echo" (EnvironmentSSE "" "")) "protocol" (JString "echo"))
    "tools" (JBool false)) "independent_text" (JBool false)) "auth" (JString "none").
Definition catalog := [set echo_descriptor "transport" (JString "echo");
  descriptor "responses" (EnvironmentSSE "https://api.openai.com/v1/responses" "OPENAI_API_KEY");
  descriptor "chatgpt" AccountSSE;
  descriptor "chatgpt-web" (WebConnection "http://127.0.0.1:8787/v1/responses" "CHATGPT_WEB_TOKEN")].
Definition backend profile := match find (fun entry => JsonObjects.equivalent
  (get entry "provider") (get profile "provider")) catalog with Some entry => entry | None => JNull end.
Definition account profile := String.eqb (str (backend profile) "auth") "account".
Definition default value fallback := if is_null value then fallback else value.
Definition endpoint profile := default (get profile "endpoint") (get (backend profile) "endpoint").
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
