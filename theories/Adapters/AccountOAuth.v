From Stdlib Require Import String List Bool NArith Ascii.
From Selvedge.Adapters Require Export AccountIdentity.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition discovery_url url issuer := url_shape url && same (get url "origin") (get issuer "origin") &&
  (String.eqb (str url "protocol") "https:" || (String.eqb (str issuer "protocol") "http:" && loopback issuer)).
Definition discovery source :=
  let value := get source "value" in let issuer := get source "issuer_url" in let urls := get source "urls" in
  if same (get value "issuer") (get source "issuer") &&
    forallb (fun name => discovery_url (get urls name) issuer) ["authorization_endpoint";"token_endpoint";"jwks_uri"]
  (* Public discovery advertises the third-party OAuth paths. The Codex client
     uses the first-party paths on the same admitted issuer. *)
  then success (if loopback issuer then value else
    set (set value "authorization_endpoint" (JString (str value "issuer" ++ "/oauth/authorize")))
      "token_endpoint" (JString (str value "issuer" ++ "/oauth/token")))
  else err "Invalid ChatGPT OpenID discovery".
Definition insecure source := success (JBool
  (String.eqb (str (get source "url") "protocol") "http:" && loopback (get source "url"))).
Definition http source := success (JBool (same (get (get source "url") "protocol") (JString "http:"))).
Definition sdk_timeout source := success
  (default (get (get source "profile") "timeout_ms") (get AccountContracts.defaults "timeout_ms")).
Definition parameters source name := items (get (get source "parameters") name).
Definition first values := hd JNull values.
Definition callback_bound source :=
  let request := get source "request" in let redirect := get source "redirect" in
  same (get request "method") (JString "GET") && same (get request "host") (get redirect "host") &&
  same (get (get source "url") "origin") (get redirect "origin") &&
  forallb (fun name => Nat.leb (List.length (parameters source name)) 1) ["code";"state";"client_id";"error"] &&
  same (first (parameters source "state")) (get source "state").
Inductive callback_decision :=
  | IgnoreCallback (status : N)
  | RejectCallback (message : string)
  | AcceptCallback (client_id : json).
Definition decide_callback source :=
  if negb (parsed (get source "url")) then IgnoreCallback 400
  else if negb (same (get (get source "url") "pathname") AccountContracts.callback_path) then IgnoreCallback 404
  else if negb (callback_bound source) then RejectCallback "Invalid ChatGPT authorization callback"
  else if negb (Nat.eqb (List.length (parameters source "error")) 0)
    then RejectCallback "ChatGPT authorization was declined or failed"
  else let id := default (first (parameters source "client_id")) AccountContracts.client_id in
    if nonempty (first (parameters source "code")) && same id AccountContracts.client_id
    then AcceptCallback id else RejectCallback "Invalid ChatGPT authorization client".
Definition encode_callback decision :=
  let '(action,status,message,id,body,headers) := match decision with
    | IgnoreCallback status => ("ignore",status,"",JNull,"",JObject [])
    | RejectCallback message => ("reject",400,message,JNull,
        "ChatGPT authorization failed. Return to Selvedge.",JObject [])
    | AcceptCallback id => ("accept",200,"",id,
        "ChatGPT authorization received. Return to Selvedge.",
        JObject [("content-type",JString "text/plain");("cache-control",JString "no-store")]) end in
  JObject [("action",JString action);("status",number status);
    ("message",JString message);("clientId",id);("body",JString body);("headers",headers)].
Definition callback source := success (encode_callback (decide_callback source)).

Definition callback_ports source := success
  (if loopback (get source "issuer_url") then JArray [JNumber "0"]
   else get AccountContracts.contract "callback_ports").
Definition auth_parameters source :=
  success (JObject [("response_type",JString "code");("redirect_uri",get source "redirectUri");
    ("state",get source "state");("nonce",get source "nonce");("code_challenge",get source "challenge");
    ("code_challenge_method",JString "S256");("client_id",AccountContracts.client_id);
    ("scope",AccountContracts.scopes);("id_token_add_organizations",JString "true");
    ("codex_cli_simplified_flow",JString "true");("originator",AccountContracts.originator)]).
Definition code_grant_checks source := success (JObject [
  ("expectedNonce",get source "nonce");("expectedState",get source "state");
  ("idTokenExpected",JBool true);("pkceCodeVerifier",get source "verifier")]).
Definition record_read_failure source := success (JBool
  (boolean_field source "optional" && same (get source "code") (JString "ENOENT"))).
Definition record_parse_failure (_ : json) := err "Invalid ChatGPT authentication record; sign in again".
Definition candidate_read source :=
  let read := get source "read" in
  let action := if boolean_field read "ok" then "accept"
    else if same (get (get read "error") "code") (JString "ENOENT") then "skip" else "fail" in
  success (JString action).
