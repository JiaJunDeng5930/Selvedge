From Stdlib Require Import String List Bool NArith Ascii.
From Selvedge.Foundation Require Import BoundedInteger TextJson.
From Selvedge.Adapters Require Import AccountFields RetryAfter.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

(* The issuer comes from the admitted ChatGPT connection. These paths belong
   to Codex device authorization; the peer does not supply them. *)
Definition verification_path := "/codex/device".
Definition device_endpoint source path := JString (str source "issuer" ++ path).
Definition device_token_url source := success (device_endpoint source "/oauth/token").
Definition device_request source := success (JObject [
  ("url",device_endpoint source "/api/accounts/deviceauth/usercode");
  ("body",JObject [("client_id",AccountContracts.client_id)])]).
Definition device_poll_request source := success (JObject [
  ("url",device_endpoint source "/api/accounts/deviceauth/token");
  ("body",project (get source "challenge") ["device_auth_id";"user_code"]);
  ("redirectUri",device_endpoint source "/deviceauth/callback")]).

Definition device_pending_status (status : N) := (status =? 403) || (status =? 404).
Definition device_status source :=
  let status := num source "status" in
  if boolean_field source "poll" && device_pending_status status then success (JBool true)
  else if (200 <=? status) && (status <? 300) then success (JBool false)
  (* DEFENSE: Status outside the successful and pending classes terminates the
     request. Peer-controlled response text never enters the error. *)
  else if status =? 404 then err "ChatGPT device authorization is unavailable (HTTP 404)"
  else err ("ChatGPT device authorization failed with HTTP " ++ decimal status).

Definition device_interval_string source :=
  let digits := match RetryAfter.trim source with String "+" rest => rest | digits => digits end in
  match required_decimal_digits digits with
  | Some (unsigned, EmptyString) =>
      let significant := Decimal.nzhead unsigned in
      (* DEFENSE: An interval string can exceed the unsigned 64-bit range.
         Bound its digit count before conversion to a binary integer. *)
      if Nat.leb (decimal_width significant) 20 then Some (N.of_uint significant) else None
  | _ => None
  end.
Definition device_interval (value : json) : option N :=
  let seconds := match value with
    | JString source => device_interval_string source
    | JNumber source => BoundedInteger.decode_natural 20 source
    | _ => None
    end in
  match seconds with
  (* DEFENSE: An omitted or zero interval can otherwise trigger continuous
     requests while authorization is pending. Wait at least one second. *)
  | Some value => if value <=? 18446744073709551615
    then Some (N.min (N.max 1000 (1000 * value)) AccountContracts.device_login_timeout_ms) else None
  | None => None
  end.

Definition device_user_code value :=
  match field "user_code" value, field "usercode" value with
  | Some code, None | None, Some code => code
  | _, _ => JNull
  end.
Definition device_challenge source :=
  let invalid := err "Invalid ChatGPT device code response" in
  (* DEFENSE: The issuer can omit the required identifiers or return malformed
     JSON. Only the fields of an admitted challenge reach the poll request. *)
  match TextJson.parse_json (str source "text") with
  | Some value =>
      let device_auth_id := get value "device_auth_id" in
      let user_code := device_user_code value in
      match device_interval (supplied value "interval" (number 0)) with
      | Some interval => if nonempty device_auth_id && nonempty user_code then
          success (JObject [("device_auth_id",device_auth_id);("user_code",user_code);
            ("interval_ms",number interval);("verification_url",device_endpoint source verification_path)])
        else invalid
      | None => invalid
      end
  | None => invalid
  end.

Definition device_authorization source :=
  let invalid := err "Invalid ChatGPT device authorization response" in
  (* DEFENSE: A successful HTTP status can carry a malformed approval. The
     exchange requires the authorization code and both of the peer's PKCE fields. *)
  match TextJson.parse_json (str source "text") with
  | Some value =>
      if forallb (fun name => nonempty (get value name))
        ["authorization_code";"code_challenge";"code_verifier"] then
        success (JObject [("code",get value "authorization_code");("verifier",get value "code_verifier")])
      else invalid
  | None => invalid
  end.
