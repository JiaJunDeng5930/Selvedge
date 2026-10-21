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
  then success (if is_audio (kind_of source)
    then set value "authorization_endpoint" (JString (str value "issuer" ++ "/oauth/authorize")) else value)
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
  | RejectCallback (received : bool) (message : string)
  | AcceptCallback (client_id : json).
Definition decide_callback source :=
  if negb (parsed (get source "url")) then IgnoreCallback 400
  else if negb (same (get (get source "url") "pathname") (JString "/auth/callback")) then IgnoreCallback 404
  else if boolean_field source "received" then IgnoreCallback 409
  else if negb (callback_bound source) then RejectCallback false "Invalid ChatGPT authorization callback"
  else if negb (Nat.eqb (List.length (parameters source "error")) 0)
    then RejectCallback true "ChatGPT authorization was declined or failed"
  else let id := default (first (parameters source "client_id")) (get (get source "registered") "client_id") in
    if nonempty (first (parameters source "code")) && client id &&
      (negb (is_object (get source "registered")) || same id (get (get source "registered") "client_id"))
    then AcceptCallback id else RejectCallback true "Invalid ChatGPT issued client".
Definition encode_callback decision :=
  let '(action,status,received,message,id,body,headers) := match decision with
    | IgnoreCallback status => ("ignore",status,false,"",JNull,"",JObject [])
    | RejectCallback received message => ("reject",400,received,message,JNull,
        "ChatGPT authorization failed. Return to the terminal.",JObject [])
    | AcceptCallback id => ("accept",200,true,"",id,
        "ChatGPT authorization received. Return to the terminal.",
        JObject [("content-type",JString "text/plain");("cache-control",JString "no-store")]) end in
  JObject [("action",JString action);("status",number status);("received",JBool received);
    ("message",JString message);("clientId",id);("body",JString body);("headers",headers)].
Definition callback source := success (encode_callback (decide_callback source)).

Definition hex character := let code := nat_of_ascii character in
  (Nat.leb 48 code && Nat.leb code 57) || (Nat.leb 97 code && Nat.leb code 102).
Fixpoint uuid_chars source (index : nat) := match source with
  | EmptyString => Nat.eqb index 36
  | String first rest =>
    let separator := existsb (Nat.eqb index) [8;13;18;23]%nat in
    (if separator then Ascii.eqb first "-"%char else hex first &&
      (negb (Nat.eqb index 14) || Ascii.eqb first "4"%char) &&
      (negb (Nat.eqb index 19) || existsb (Ascii.eqb first) ["8"%char;"9"%char;"a"%char;"b"%char])) &&
    uuid_chars rest (S index) end.
Definition host_format := "selvedge-chatgpt-host-1".
Definition host_registration source :=
  let value := get source "value" in let id := str value "ext_agent_host_id" in
  if is_object value && same (get value "format") (JString host_format) &&
    Nat.eqb (List.length (object_fields value)) 2 && starts id "urn:uuid:" &&
    uuid_chars (lower_ascii (substring 9 (String.length id) id)) 0
  then success (get value "ext_agent_host_id") else err "Invalid ChatGPT host registration".
Definition host_registration_record source := success (JObject [
  ("format",JString host_format);("ext_agent_host_id",get source "ext_agent_host_id")]).
Definition auth_parameters source :=
  let common := [("response_type",JString "code");("redirect_uri",get source "redirectUri");
    ("state",get source "state");("nonce",get source "nonce");("code_challenge",get source "challenge");
    ("code_challenge_method",JString "S256")] in
  success (JObject (common ++ if is_audio (kind_of source) then
    [("client_id",get AccountContracts.audio_contract "client_id");("scope",get AccountContracts.audio_contract "scopes");
      ("id_token_add_organizations",JString "true");("codex_cli_simplified_flow",JString "true");("originator",JString "selvedge_audio")]
  else [("resource",get AccountContracts.contract "resource");("scope",get AccountContracts.contract "scopes");
    ("ext_agent_host_id",get source "ext_agent_host_id");
    ("client_id",default (get (get source "registered") "client_id") (JString "dynamic_agent_client"))] ++
    optional (negb (is_object (get source "registered"))) "agent_name_hint" (JString "Selvedge"))).
Definition authorize_prompt source := success (JObject [("url",get source "url");("redirect_uri",get source "redirectUri")]).
Definition code_grant_checks source := success (JObject [
  ("expectedNonce",get source "nonce");("expectedState",get source "state");
  ("idTokenExpected",JBool true);("pkceCodeVerifier",get source "verifier")]).
Definition read_failure source := success (JBool
  (boolean_field source "optional" && same (get source "code") (JString "ENOENT"))).
Definition record_parse_failure (_ : json) := err "Invalid ChatGPT authentication record; sign in again".
Definition record_read_failure := read_failure.
Definition candidate_read source :=
  let read := get source "read" in
  let action := if boolean_field read "ok" then "accept"
    else if same (get (get read "error") "code") (JString "ENOENT") then "skip" else "fail" in
  success (JObject [("action",JString action);("candidate",get source "candidate")]).
Definition optional_registration source := if is_null (get source "value") then success JNull else registration source.
Definition host_saved source := if is_null (get source "value") then success JNull else host_registration source.
