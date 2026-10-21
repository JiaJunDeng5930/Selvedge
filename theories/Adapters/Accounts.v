From Stdlib Require Import String List.
From Selvedge.Foundation Require Import TextJson.
From Selvedge.Adapters Require Import AccountMaterialization AccountOAuth AccountTransport.
Import ListNotations.
Open Scope string_scope.

Definition contract (_ : json) := success AccountContracts.contract.
Definition discovery_failure (_ : json) := err "Invalid ChatGPT OpenID discovery".
Definition grant_failure (_ : json) := err "ChatGPT token grant or identity verification failed; sign in again".
Definition catalog_fetch_failure (_ : json) := success (JString "Could not fetch the ChatGPT model catalog").
Definition catalog_failure source := err ("ChatGPT model discovery failed with HTTP " ++
  match get source "status" with JNumber value => value | _ => "" end).
(* DEFENSE: Externally edited authentication files can contain invalid JSON or duplicate members;
   parser errors must not expose token-bearing text. A parsed scalar or null is
   also a malformed record, not evidence that an optional file is absent. *)
Definition record_decode source := match TextJson.parse_json (str source "text") with
  | Some value => if is_object value then success value else AccountOAuth.record_parse_failure source
  | None => AccountOAuth.record_parse_failure source end.
(* DEFENSE: Malformed disposable model-cache files cause discovery rather than credential failure. *)
Definition cache_decode source := success (match TextJson.parse_json (str source "text") with
  | Some value => value | None => JNull end).

Definition handlers : list (string * (json -> json)) := [
  ("account.record_decode",record_decode);
  ("account.cache_decode",cache_decode);
  ("account.account_namespace",AccountCatalog.account_namespace);
  ("account.account_summary",AccountCatalog.account_summary);
  ("account.audio_connection",AccountIdentity.audio_connection);
  ("account.audio_identity",AccountIdentity.audio_identity);
  ("account.auth_parameters",AccountOAuth.auth_parameters);
  ("account.authorization_view",AccountIdentity.authorization_view);
  ("account.authorize_prompt",AccountOAuth.authorize_prompt);
  ("account.auto_preset",AccountMaterialization.auto_preset);
  ("account.cache",AccountCatalog.cache);
  ("account.cache_error",AccountCatalog.cache_error);
  ("account.cache_fallback",AccountCatalog.cache_fallback);
  ("account.cache_fresh",AccountCatalog.cache_fresh);
  ("account.cache_record",AccountCatalog.cache_record);
  ("account.cache_size",AccountCatalog.cache_size);
  ("account.callback",AccountOAuth.callback);
  ("account.candidate_identity",AccountCatalog.candidate_identity);
  ("account.candidate_paths",AccountMaterialization.candidate_paths);
  ("account.candidate_read",AccountOAuth.candidate_read);
  ("account.candidates",AccountMaterialization.candidates);
  ("account.catalog",AccountCatalog.catalog);
  ("account.catalog_failure",catalog_failure);
  ("account.catalog_fetch_failure",catalog_fetch_failure);
  ("account.catalog_result",AccountCatalog.catalog_result);
  ("account.catalog_selectable",AccountCatalog.catalog_selectable);
  ("account.catalog_transport",AccountTransport.catalog_transport);
  ("account.code_grant_checks",AccountOAuth.code_grant_checks);
  ("account.config_materialized",AccountMaterialization.config_materialized);
  ("account.connection",AccountFields.connection_call);
  ("account.connection_identity",AccountCatalog.connection_identity);
  ("account.contract",contract);
  ("account.credential",AccountIdentity.credential);
  ("account.discovery",AccountOAuth.discovery);
  ("account.discovery_failure",discovery_failure);
  ("account.grant_failure",grant_failure);
  ("account.hash_prefix",AccountCatalog.hash_prefix);
  ("account.host_registration",AccountOAuth.host_registration);
  ("account.host_registration_record",AccountOAuth.host_registration_record);
  ("account.host_saved",AccountOAuth.host_saved);
  ("account.http",AccountOAuth.http);
  ("account.insecure",AccountOAuth.insecure);
  ("account.issuer_admission",AccountIdentity.issuer_admission);
  ("account.login_account",AccountMaterialization.login_account);
  ("account.login_result",AccountIdentity.login_result);
  ("account.materialization_diagnostic",AccountMaterialization.materialization_diagnostic);
  ("account.materialization_failure",AccountMaterialization.materialization_failure);
  ("account.materialize",AccountMaterialization.materialize);
  ("account.model_cache_path",AccountCatalog.model_cache_path);
  ("account.models_url",AccountCatalog.models_url);
  ("account.optional_registration",AccountOAuth.optional_registration);
  ("account.profile_connection",AccountFields.profile_connection);
  ("account.record_parse_failure",AccountOAuth.record_parse_failure);
  ("account.record_read_failure",AccountOAuth.record_read_failure);
  ("account.refresh",AccountIdentity.refresh);
  ("account.refresh_initial",AccountIdentity.refresh_initial);
  ("account.refresh_registration",AccountIdentity.refresh_registration);
  ("account.registration",AccountIdentity.registration);
  ("account.registration_record",AccountIdentity.registration_record);
  ("account.registration_subject",AccountIdentity.registration_subject);
  ("account.sdk_timeout",AccountOAuth.sdk_timeout);
  ("account.token",AccountIdentity.token);
  ("account.token_expiration",AccountIdentity.token_expiration);
  ("account.token_subject",AccountIdentity.token_subject);
  ("account.token_times",AccountIdentity.token_times)
].
Definition call operation source := match find (fun handler => String.eqb operation (fst handler)) handlers with
  | Some (_,handler) => handler source
  | None => err ("Unknown host model operation: " ++ operation) end.
