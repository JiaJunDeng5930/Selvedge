From Stdlib Require Import String List Bool NArith Ascii.
From Selvedge.Programming Require Import Schema.
From Selvedge.Adapters Require Export AccountFields.
From Selvedge.Programming Require Import AdapterResult.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition credential_binding source :=
  let value := get source "value" in
  identity_text (get value "issuer") && identity_text (get value "client_id") &&
  identity_text (get value "subject") && identity_text (get value "account_id") &&
  same (get value "client_id") AccountContracts.client_id.
Definition credential_content source :=
  let value := get source "value" in let dates := get source "dates" in
  nonempty (get value "access_token") && nonempty (get value "refresh_token") &&
  nullable (get value "scope") &&
  date_valid (get value "expires_at") (get dates "expires_at") &&
  (is_null (get value "earliest_refresh_at") || date_valid (get value "earliest_refresh_at") (get dates "earliest_refresh_at")) &&
  nullable (get value "name") && nullable (get value "email").
Definition credential_checks source :=
  same (get (get source "value") "format") (JString credential_format) &&
  credential_binding source && credential_content source.
Definition admit_credential source : outcome (Schema.fields credential_schema) :=
  match decode_complete credential_schema (get source "value") with
  | Some values => if credential_checks source then Accepted values
      else reject "Invalid current-format ChatGPT credential; sign in again"
  | None => reject "Invalid current-format ChatGPT credential; sign in again" end.
Definition credential source := render_outcome encoded (admit_credential source).
Definition same_request_identity (expected current : json) :=
  forallb (fun field => same (get expected field) (get current field))
    ["issuer";"client_id";"subject";"account_id"].
Definition request_identity_retained source :=
  negb (has source "requestCredential") ||
    same_request_identity (get source "requestCredential") (get source "value").
Definition request_identity_failure :=
  "ChatGPT account changed during an active request; start a new request".
(* A rejected request owns its original principal. Token rotation may replace
   secrets, but cannot change that principal underneath the retained body,
   provider scope, model catalog cache or audio session. *)
Definition refresh_admission source accepted :=
  if request_identity_retained source then accepted else err request_identity_failure.
Definition issuer_admission source := if same (get (get source "value") "issuer") (get source "issuer")
  then success JNull else err "ChatGPT credential belongs to a different issuer; sign in again".
Inductive refresh_action := Keep | Refresh.
Definition rejected_current source := has source "rejectedToken" &&
  same (get source "rejectedToken") (get (get source "value") "access_token").
Definition before_expiration source := epoch_greater (get (get source "dates") "expires_at") (get source "threshold").
Definition refresh_action_for source :=
  if (before_expiration source && negb (rejected_current source)) ||
    (negb (is_null (get (get source "value") "earliest_refresh_at")) &&
      epoch_greater (get (get source "dates") "earliest_refresh_at") (get source "now_date") &&
      negb (has source "rejectedToken"))
  then Keep else Refresh.
Definition refresh_action_name action := match action with
  | Keep => "keep" | Refresh => "refresh" end.
Definition refresh source := refresh_admission source
  (success (JString (refresh_action_name (refresh_action_for source)))).

Fixpoint mantissa_nonzero source := match source with
  | EmptyString => false | String first rest =>
    if Ascii.eqb first "e"%char || Ascii.eqb first "E"%char then false
    else (Nat.leb 49 (nat_of_ascii first) && Nat.leb (nat_of_ascii first) 57) || mantissa_nonzero rest end.
Definition positive_number value := match value with
  | JNumber lexeme => number_lexeme lexeme && negb (starts lexeme "-") && mantissa_nonzero lexeme
  | _ => false end.
Definition token_grant source :=
  let tokens := get source "tokens" in let previous := get source "previous" in
  nonempty (get tokens "access_token") &&
  nonempty (default (get tokens "refresh_token") (get previous "refresh_token")) &&
  is_text (get tokens "token_type") && String.eqb (lower_ascii (str tokens "token_type")) "bearer" &&
  (is_null (get tokens "expires_in") || positive_number (get tokens "expires_in")) &&
  (is_object previous || nonempty (get tokens "id_token")).
Definition claims_valid source :=
  let claims := get source "claims" in
  let previous := get source "previous" in
  (is_object previous || is_object claims) &&
  (is_null claims || (identity_text (get claims "sub") &&
    (negb (is_object previous) || same (get claims "sub") (get previous "subject")) &&
    (negb (has claims "azp") || same (get claims "azp") AccountContracts.client_id))).
Definition identity_message := "ChatGPT identity verification failed; sign in again".
Definition grant_message := "ChatGPT returned an invalid token grant".
Definition identity_field claims previous claim name :=
  if is_object claims then if nonempty (get claims claim) then get claims claim else JNull else get previous name.
Definition token_record source :=
  let tokens := get source "tokens" in let claims := get source "claims" in let previous := get source "previous" in
  JObject [("format",JString credential_format);
    ("issuer",get (get source "metadata") "issuer");("client_id",AccountContracts.client_id);
    ("subject",if is_object claims then get claims "sub" else get previous "subject");
    ("account_id",get source "account_id");("name",identity_field claims previous "name" "name");
    ("email",identity_field claims previous "email" "email");("access_token",get tokens "access_token");
    ("refresh_token",default (get tokens "refresh_token") (get previous "refresh_token"));
    ("scope",default (get tokens "scope") (get previous "scope"));
    ("expires_at",get (get source "expires") "iso");("earliest_refresh_at",get (get source "earliest") "iso")].
(* Claims passed here come from the verified OpenID grant. A refresh can omit
   an ID token, in which case the admitted previous principal still owns it. *)
Definition token source :=
  let previous := get source "previous" in let claims := get source "claims" in
  let workspace := if is_object claims then get (get claims "https://api.openai.com/auth") "chatgpt_account_id"
    else get previous "account_id" in
  if negb (token_grant source) then err grant_message
  else if negb (claims_valid source) then err identity_message
  else if negb (identity_text workspace && (negb (is_object previous) || same workspace (get previous "account_id")))
    then err "ChatGPT authorization has no matching workspace identity; sign in again"
  else if negb (is_object (get source "expires")) then range_error "Invalid time value"
  else if negb (is_null (get (get source "tokens") "earliest_refresh_at") || is_text (get (get source "earliest") "iso"))
    then err "Invalid ChatGPT token refresh time"
  else credential (JObject [("value",token_record (set source "account_id" workspace));
    ("dates",JObject [("expires_at",get source "expires");("earliest_refresh_at",get source "earliest")])]).
Definition audio_connection source := if same (get source "connectionId") (JString "chatgpt-voice")
  then success JNull else err "Unknown ChatGPT audio account".
Definition authorization_view source :=
  let credential := get source "credential" in
  success (JObject [("account_id",get source "principal");("headers",JObject
    [("authorization",JString ("Bearer " ++ str credential "access_token"));
     ("ChatGPT-Account-Id",get credential "account_id");("originator",AccountContracts.originator)])]).
Definition login_result source := let saved := get source "saved" in success (JObject
  [("account_id",get saved "account_id");("filename",get source "filename");
    ("name",get saved "name");("email",get saved "email")]).
