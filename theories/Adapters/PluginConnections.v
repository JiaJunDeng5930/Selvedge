From Stdlib Require Import String List Bool NArith Ascii.
From Selvedge.Foundation Require Import Json Utf8.
From Selvedge.Foundation Require ArgumentDeclaration DeclarationFields KeyedCollection.
From Selvedge.Kernel Require Codec Domain ChatgptArguments.
From Selvedge.Features Require ConnectionGrants.
From Selvedge.Adapters Require ProviderCatalog.
From Selvedge.Adapters Require Import Common Observation.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module D := ArgumentDeclaration.
Module F := DeclarationFields.
Module G := ConnectionGrants.
Module P := ProviderCatalog.

Definition keys source allowed := is_object source &&
  forallb (fun entry => existsb (String.eqb (fst entry)) allowed) (object_fields source) &&
  Nat.eqb (List.length (nodup string_dec (map fst (object_fields source)))) (List.length (object_fields source)).
Definition ascii_letter n := ((65 <=? n) && (n <=? 90)) || ((97 <=? n) && (n <=? 122)).
Definition ascii_name n := ascii_letter n || ((48 <=? n) && (n <=? 57)) || (n =? 95).
Definition valid_name name := match Utf8.decode name with Some (first::rest) =>
  ascii_letter first && forallb ascii_name rest && (N.of_nat (List.length rest) <=? 63) | _ => false end.
Definition env_name name := match Utf8.decode name with Some (first::rest) =>
  (ascii_letter first || (first =? 95)) && forallb ascii_name rest | _ => false end.
Definition uint32 := D.check G.identity_declaration.
Definition identity_format := D.NaturalSpelling 0 (Some ChatgptArguments.identity_maximum).
Fixpoint unique_values values := match values with
  | [] => true | first::rest => negb (existsb (equal first) rest) && unique_values rest end.
Definition default_sandbox := Domain.Sandbox Domain.WorkspaceWrite false.
Definition default_value value fallback := match value with JNull => fallback | _ => value end.
Definition connection_fields := [F.required "token_env" (D.Value Schema.KText);
 F.required "project_ids" G.project_ids_declaration;F.optional "sandbox" (D.nullable Codec.sandbox_declaration)].
Record configured_connection := ConfiguredConnection {
 credential_environment : D.checked env_name; connection_grant : G.grant
}.
Module ConnectionEntries.
 Definition t := configured_connection.
 Definition key := N.
 Definition key_of value := G.identity (connection_grant value).
 Definition key_eq_dec := N.eq_dec.
End ConnectionEntries.
Module Connections := KeyedCollection.Make ConnectionEntries.
Definition configured_sandbox (value : option (D.denote (D.nullable Codec.sandbox_declaration))) := match value with
 | Some (inl fields) => Codec.sandbox_of_values fields
 | None | Some (inr (inl _)) => default_sandbox
 | Some (inr (inr impossible)) => match impossible with end end.
Definition connection_entry (entry : string * json) : P.outcome configured_connection :=
 let '(name,source) := entry in
 match D.decode_text identity_format name,F.decode connection_fields source with
 | Some identity,Some (environment,(projects,(sandbox,_))) =>
   match D.admit env_name environment,G.projects_of_values projects with
   | Some environment,Some projects =>
     P.Accepted (ConfiguredConnection environment (G.Grant identity projects (configured_sandbox sandbox)))
   | None,_ => P.reject "Each ChatGPT connection needs a token_env name"
   | _,None => P.reject "Invalid ChatGPT project_ids" end
 | _,_ => P.reject ("Invalid ChatGPT connection " ++ name) end.
Definition grant_json grant := JObject [("connection_id",number (G.identity grant));
 ("project_ids",G.projects_json (G.grant_projects grant));("sandbox",Codec.sandbox_json (G.grant_sandbox grant))].
Definition connection_json value := let grant := connection_grant value in
 (decimal (G.identity grant),JObject [("token_env",JString (proj1_sig (credential_environment value)));
  ("project_ids",G.projects_json (G.grant_projects grant));("sandbox",Codec.sandbox_json (G.grant_sandbox grant))]).
Definition configuration_json values := JObject [("connections",JObject (map connection_json (Connections.values values)))].
Definition admit_configuration source : P.outcome Connections.t :=
 match F.decode [F.required "connections" D.RawObject] source with
 | Some (entries,_) => match D.admit (fun entries : list (string * json) =>
     N.of_nat (List.length entries) <=? G.maximum_connections) entries with
   | Some entries => P.bind (P.traverse connection_entry (proj1_sig entries)) (fun values =>
     match Connections.admit values with Some values => P.Accepted values
     | None => P.reject "ChatGPT connection identities must be distinct" end)
   | None => P.reject "ChatGPT plugin connections must be an object with at most 32 entries" end
 | None => P.reject "Invalid ChatGPT plugin configuration" end.
Definition connection_config source := P.render_outcome configuration_json (admit_configuration source).
Definition connection_grants source := P.render_outcome (fun values =>
 JArray (map (fun value => grant_json (connection_grant value)) (Connections.values values))) (admit_configuration source).
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
 else match get source "connection" with
 | JString name => match D.decode_text identity_format name with
   | Some identity => success (JObject [("endpoint",get source "origin");("connection",JString (decimal (proj1_sig identity)));("credential_plan",credential_plan)])
   | None => err "SELVEDGE_CONNECTION_ID must name a configured connection" end
 | _ => err "SELVEDGE_CONNECTION_ID must name a configured connection" end.
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
