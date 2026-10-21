From Stdlib Require Import String List Bool NArith Ascii.
From Selvedge.Foundation Require Import Schema.
From Selvedge.Adapters Require Export AccountFields.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition credential_binding source :=
  let value := get source "value" in let kind := kind_of source in
  identity_text (get value "issuer") && client (get value "client_id") &&
  identity_text (get value "subject") && nonempty (get value "account_id") &&
  (if is_audio kind then same (get value "client_id") (get AccountContracts.audio_contract "client_id")
   else same (get value "account_id") (get source "identity")).
Definition credential_content source :=
  let value := get source "value" in let dates := get source "dates" in
  nonempty (get value "access_token") && nonempty (get value "refresh_token") &&
  nonempty (get value "id_token") &&
  (if is_audio (kind_of source) then nullable (get value "scope") else scope (get value "scope")) &&
  date_valid (get value "expires_at") (get dates "expires_at") &&
  date_valid (get value "last_refresh") (get dates "last_refresh") &&
  (is_null (get value "earliest_refresh_at") || date_valid (get value "earliest_refresh_at") (get dates "earliest_refresh_at")) &&
  nullable (get value "name") && nullable (get value "email").
Definition credential_checks source :=
  same (get (get source "value") "format") (JString (credential_format (kind_of source))) &&
  credential_binding source && credential_content source.
Definition admit_credential source : outcome (Schema.fields credential_schema) :=
  match decode_complete credential_schema (get source "value") with
  | Some values => if credential_checks source then Accepted values
      else reject "Invalid current-format ChatGPT credential; sign in again"
  | None => reject "Invalid current-format ChatGPT credential; sign in again" end.
Definition credential source := render_outcome encoded (admit_credential source).
Definition registration_format := "selvedge-chatgpt-registration-1".
Definition registration_binding source := same (get (get source "value") "issuer") (get source "issuer").
Definition registration_checks source :=
  same (get (get source "value") "format") (JString registration_format) &&
  client (get (get source "value") "client_id") &&
  (is_null (get (get source "value") "subject") || identity_text (get (get source "value") "subject")) &&
  identity_text (get (get source "value") "issuer") && registration_binding source.
Definition admit_registration source : outcome (Schema.fields registration_schema) :=
  match decode_complete registration_schema (get source "value") with
  | Some values => if registration_checks source then Accepted values
      else reject "Invalid ChatGPT client registration; sign in again"
  | None => reject "Invalid ChatGPT client registration; sign in again" end.
Definition registration source := render_outcome encoded (admit_registration source).
Definition same_registration source :=
  let registered := get source "registered" in let value := get source "value" in
  same (get registered "client_id") (get value "client_id") &&
  same (get registered "subject") (get value "subject").
Definition identity_failure := "ChatGPT credential does not match its registered identity".
Definition issuer_admission source := if same (get (get source "value") "issuer") (get source "issuer")
  then success (get source "value") else err "ChatGPT credential belongs to a different issuer; sign in again".
Definition refresh_registration source := if same_registration source then success JNull else err identity_failure.
Inductive refresh_action := Keep | AwaitEarliest | Refresh.
Definition rejected_current source := has source "rejectedToken" &&
  same (get source "rejectedToken") (get (get source "value") "access_token").
Definition before_expiration source := epoch_greater (get (get source "dates") "expires_at") (get source "threshold").
Definition initial_action source :=
  if before_expiration source && negb (rejected_current source) then Keep
  else if negb (is_null (get (get source "value") "earliest_refresh_at")) && negb (has source "rejectedToken")
    then AwaitEarliest else Refresh.
Definition refresh_action_name action := match action with
  | Keep => "keep" | AwaitEarliest => "earliest" | Refresh => "refresh" end.
Definition refresh_initial source := if same_registration source
  then success (JString (refresh_action_name (initial_action source))) else err identity_failure.
Definition reusable source :=
  (before_expiration source && negb (rejected_current source)) ||
  (negb (is_null (get (get source "value") "earliest_refresh_at")) &&
    epoch_greater (get (get source "dates") "earliest_refresh_at") (get source "now_date") &&
    negb (has source "rejectedToken")).
Definition refresh source :=
  if negb (same (get (get source "value") "issuer") (get source "issuer"))
  then err "ChatGPT credential belongs to a different issuer; sign in again"
  else if same_registration source then success (JBool (reusable source)) else err identity_failure.

Fixpoint mantissa_nonzero source := match source with
  | EmptyString => false | String first rest =>
    if Ascii.eqb first "e"%char || Ascii.eqb first "E"%char then false
    else (Nat.leb 49 (nat_of_ascii first) && Nat.leb (nat_of_ascii first) 57) || mantissa_nonzero rest end.
Definition positive_number value := match value with
  | JNumber lexeme => number_lexeme lexeme && negb (starts lexeme "-") && mantissa_nonzero lexeme
  | _ => false end.
Definition token_grant source :=
  let tokens := get source "tokens" in let previous := get source "previous" in
  let audio := is_audio (kind_of source) in
  nonempty (get tokens "access_token") &&
  nonempty (if audio && is_null (get tokens "refresh_token") then get previous "refresh_token" else get tokens "refresh_token") &&
  is_text (get tokens "token_type") && String.eqb (lower_ascii (str tokens "token_type")) "bearer" &&
  (audio || positive_number (get tokens "expires_in")) &&
  (is_object previous || nonempty (get tokens "id_token")) &&
  (audio || scope (default (get tokens "scope") (get previous "scope"))).
Definition claims_valid source :=
  let claims := get source "claims" in
  (is_object (get source "previous") || is_object claims) &&
  (is_null claims || (identity_text (get claims "sub") &&
    (negb (has source "subject") || same (get claims "sub") (get source "subject")) &&
    (negb (has claims "azp") || same (get claims "azp") (get source "clientId")))).
Definition identity_message := "ChatGPT identity verification failed; sign in again".
Definition grant_message := "ChatGPT returned an invalid token grant".
Definition token_subject source :=
  if negb (token_grant source) then err grant_message
  else if claims_valid source then success
    (if is_object (get source "claims") then get (get source "claims") "sub" else get (get source "previous") "subject")
  else err identity_message.
Definition token_times source :=
  if negb (is_object (get source "expires")) then range_error "Invalid time value"
  else if is_null (get (get source "tokens") "earliest_refresh_at") || is_text (get (get source "earliest") "iso")
    then success JNull else err "Invalid ChatGPT token refresh time".
Definition token_expiration source := if is_object (get source "expires")
  then success JNull else range_error "Invalid time value".
Definition identity_field claims previous claim name :=
  if is_object claims then if nonempty (get claims claim) then get claims claim else JNull else get previous name.
Definition token_record source :=
  let tokens := get source "tokens" in let claims := get source "claims" in let previous := get source "previous" in
  JObject [("format",JString (credential_format (kind_of source)));
    ("issuer",get (get source "metadata") "issuer");("client_id",get source "clientId");
    ("subject",if is_object claims then get claims "sub" else get previous "subject");
    ("account_id",get source "identity");("name",identity_field claims previous "name" "name");
    ("email",identity_field claims previous "email" "email");("access_token",get tokens "access_token");
    ("refresh_token",if is_audio (kind_of source) && is_null (get tokens "refresh_token") then get previous "refresh_token" else get tokens "refresh_token");
    ("id_token",default (get tokens "id_token") (get previous "id_token"));
    ("scope",default (get tokens "scope") (get previous "scope"));
    ("expires_at",get (get source "expires") "iso");("earliest_refresh_at",get (get source "earliest") "iso");
    ("last_refresh",get (get source "now_date") "iso")].
Definition token source :=
  if negb (token_grant source) then err grant_message
  else if String.eqb (str source "phase") "grant" then success JNull
  else if negb (claims_valid source) then err identity_message
  else if negb (is_object (get source "expires")) then range_error "Invalid time value"
  else if negb (is_null (get (get source "tokens") "earliest_refresh_at") || is_text (get (get source "earliest") "iso"))
    then err "Invalid ChatGPT token refresh time"
  else credential (JObject [("audio",JBool (is_audio (kind_of source)));("value",token_record source);
    ("identity",get source "identity");("dates",JObject [("expires_at",get source "expires");
      ("last_refresh",get source "now_date");("earliest_refresh_at",get source "earliest")])]).
Definition audio_identity source :=
  let previous := get source "previous" in let claims := get source "claims" in
  let identity := if is_object claims then get (get claims "https://api.openai.com/auth") "chatgpt_account_id"
    else get previous "account_id" in
  if nonempty identity && (negb (is_object previous) || same identity (get previous "account_id")) then success identity
  else err "ChatGPT audio authorization has no matching account identity; sign in again".
Definition audio_connection source := if same (get source "connectionId") (JString "chatgpt-voice")
  then success JNull else err "Unknown ChatGPT audio account".
Definition registration_record source := success (JObject [
  ("format",JString registration_format);("issuer",get source "issuer");
  ("client_id",get source "clientId");("subject",get (get source "registered") "subject")]).
Definition registration_subject source := success
  (set (get source "registered") "subject" (get (get source "saved") "subject")).
Definition authorization_view source :=
  let credential := get source "credential" in
  success (JObject [("account_id",get credential "account_id");("headers",JObject
    ([("authorization",JString ("Bearer " ++ str credential "access_token"))] ++
      optional (is_audio (kind_of source)) "originator" (JString "selvedge_audio"))) ]).
Definition login_result source := let saved := get source "saved" in success (JObject
  [("account_id",get saved "account_id");("filename",get source "filename");
    ("name",get saved "name");("email",get saved "email")]).
