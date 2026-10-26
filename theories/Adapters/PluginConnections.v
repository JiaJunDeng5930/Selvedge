From Stdlib Require Import String List Bool NArith Ascii.
From Selvedge.Foundation Require Import Json Utf8.
From Selvedge.Kernel Require Codec.
From Selvedge.Adapters Require Import Common Observation.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition keys source allowed := is_object source &&
  forallb (fun entry => existsb (String.eqb (fst entry)) allowed) (object_fields source) &&
  Nat.eqb (List.length (nodup string_dec (map fst (object_fields source)))) (List.length (object_fields source)).
Definition ascii_letter n := ((65 <=? n) && (n <=? 90)) || ((97 <=? n) && (n <=? 122)).
Definition ascii_name n := ascii_letter n || ((48 <=? n) && (n <=? 57)) || (n =? 95).
Definition valid_name name := match Utf8.decode name with Some (first::rest) =>
  ascii_letter first && forallb ascii_name rest && (N.of_nat (List.length rest) <=? 63) | _ => false end.
Definition env_name name := match Utf8.decode name with Some (first::rest) =>
  (ascii_letter first || (first =? 95)) && forallb ascii_name rest | _ => false end.
Definition uint32 value := canonical_natural value && (nat_value value <=? 4294967295).
Definition uint32_text text := uint32 (JNumber text).
Fixpoint unique_values values := match values with
  | [] => true | first::rest => negb (existsb (equal first) rest) && unique_values rest end.
Definition default_sandbox := JObject [("mode",JString "workspace-write");("network_access",JBool false)].
Definition default_value value fallback := match value with JNull => fallback | _ => value end.
Definition connection_settings id source :=
  if negb (keys source ["token_env";"project_ids";"sandbox"]) then err ("Invalid ChatGPT connection " ++ id)
  else if negb (is_text (get source "token_env") && env_name (str source "token_env")) then err "Each ChatGPT connection needs a token_env name"
  else let ids := get source "project_ids" in
    if negb (is_array ids && (N.of_nat (List.length (items ids)) <=? 32) && forallb uint32 (items ids) && unique_values (items ids))
    then err "Invalid ChatGPT project_ids" else
    let sandbox := default_value (get source "sandbox") default_sandbox in
    (* DEFENSE: External connection settings can contain unknown sandbox fields, unsupported modes or a missing Boolean network_access. *)
    match Codec.parse_sandbox sandbox with
    | None => err "A ChatGPT connection requires an explicit restricted sandbox mode and network_access"
    | Some sandbox => success (JObject [("token_env",get source "token_env");("project_ids",ids);("sandbox",Codec.sandbox_json sandbox)]) end.
Fixpoint connection_entries entries := match entries with
  | [] => success (JObject [])
  | (id,settings)::rest => if negb (uint32_text id) then err "Invalid ChatGPT connection ID" else
    let current := connection_settings id settings in
    if negb (boolean_field current "ok") then current else
    let tail := connection_entries rest in if negb (boolean_field tail "ok") then tail else
    success (JObject ((id,get current "value")::object_fields (get tail "value"))) end.
Definition connection_config source :=
  if negb (keys source ["connections"]) then err "Invalid ChatGPT plugin configuration" else
  let connections := get source "connections" in
  if negb (is_object connections && (N.of_nat (List.length (object_fields connections)) <=? 32) && keys connections (map fst (object_fields connections)))
  then err "ChatGPT plugin connections must be an object with at most 32 entries" else
  let result := connection_entries (object_fields connections) in
  if boolean_field result "ok" then success (JObject [("connections",get result "value")]) else result.
Definition connection_grants source :=
  let connections := default_value (get source "connections") (JObject []) in
  if is_object connections then success (JArray (map (fun entry => JObject [
    ("connection_id",JNumber (fst entry));("project_ids",get (snd entry) "project_ids");("sandbox",get (snd entry) "sandbox")]) (object_fields connections)))
  else err "ChatGPT plugin connections must be an object with at most 32 entries".
(** Secret values never enter Gallina: this is a plan for the opaque credential interpreter. *)
Definition credential_plan := JObject [("operation",JString "base64url-bearer");("minimum",number 32);
  ("maximum",number 256);("alphabet",JString "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-");
  ("distinct",JBool true);("prefix",JString "Bearer ")].
Definition client_endpoint_valid source := String.eqb (str source "protocol") "http:" &&
  (String.eqb (str source "hostname") "127.0.0.1" || String.eqb (str source "hostname") "[::1]") &&
  negb (boolean_field source "username_present") && negb (boolean_field source "password_present") &&
  String.eqb (str source "pathname") "/" && String.eqb (str source "search") "" && String.eqb (str source "hash") "".
Definition client_settings source :=
  if negb (client_endpoint_valid source) then err "SELVEDGE_URL must be an HTTP loopback origin using 127.0.0.1 or [::1]"
  else if negb (is_text (get source "connection") && uint32_text (str source "connection")) then err "SELVEDGE_CONNECTION_ID must name a configured connection"
  else success (JObject [("endpoint",get source "origin");("connection",get source "connection");("credential_plan",credential_plan)]).
Definition settings_file source := if negb (boolean_field source "absolute") then err "SELVEDGE_CONNECTION_FILE must be absolute"
  else if String.eqb (str source "phase") "path" then success JNull
  else if String.eqb (str source "phase") "metadata" then
    if boolean_field source "nofollow" && boolean_field source "regular" && canonical_natural (get source "bytes") &&
      (num source "bytes" <=? 4096) && uint32 (get source "mode") && (num source "mode" mod 64 =? 0) &&
      equal (get source "owner_uid") (get source "current_uid") then success JNull
    else err "The connection file must be a private, owned regular file of at most 4096 bytes"
  else if String.eqb (str source "phase") "keys" then
    if boolean_field source "object" && forallb (fun key => existsb (String.eqb (text key))
      ["SELVEDGE_URL";"SELVEDGE_CONNECTION_ID";"SELVEDGE_CONNECTION_TOKEN"]) (items (get source "keys")) then success JNull
    else err "Invalid connection file"
  else err "Invalid connection file".
