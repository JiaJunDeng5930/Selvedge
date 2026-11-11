From Stdlib Require Import String List Bool NArith Sorting.Permutation.
From Selvedge.Adapters Require Import AccountFields AccountIdentity AccountOAuth AccountCatalog AccountMaterialization Accounts Api.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Theorem public_credential_rejects_another_client : forall source,
  same (get (get source "value") "client_id") AccountContracts.client_id = false ->
  exists message, Api.call "account.credential" source = err message.
Proof.
 intros source different. exists "Invalid current-format ChatGPT credential; sign in again".
 assert (credential_checks source = false) as invalid.
 { unfold credential_checks,credential_binding;rewrite different;now rewrite !andb_false_r. }
 change (AccountIdentity.credential source = err "Invalid current-format ChatGPT credential; sign in again").
 unfold AccountIdentity.credential,admit_credential;destruct (decode_complete credential_schema (get source "value"));
   try rewrite invalid;reflexivity.
Qed.
Theorem public_refresh_cannot_replace_the_request_identity : forall source,
  has source "requestCredential" = true ->
  same_request_identity (get source "requestCredential") (get source "value") = false ->
  exists message, Api.call "account.refresh" source = err message.
Proof.
 intros source bound different. exists request_identity_failure.
 change (refresh source = err request_identity_failure).
 unfold refresh,refresh_admission,request_identity_retained;
 now rewrite bound,different.
Qed.
Theorem public_refresh_keeps_the_same_request_identity : forall source,
  same_request_identity (get source "requestCredential") (get source "value") = true ->
  Api.call "account.refresh" source =
    success (JString (refresh_action_name (refresh_action_for source))).
Proof.
 intros source retained.
 change (refresh source = success (JString (refresh_action_name (refresh_action_for source)))).
 unfold refresh,refresh_admission,request_identity_retained;
 rewrite retained,orb_true_r;reflexivity.
Qed.
Theorem public_refresh_identity_binds_each_principal_field : forall source result,
  has source "requestCredential" = true ->
  Api.call "account.refresh" source = success result ->
  forall field, In field ["issuer";"client_id";"subject";"account_id"] ->
    same (get (get source "requestCredential") field) (get (get source "value") field) = true.
Proof.
 intros source result bound accepted field member.
 change (refresh source = success result) in accepted.
 unfold refresh,refresh_admission in accepted.
 destruct (request_identity_retained source) eqn:retained;try discriminate.
 unfold request_identity_retained in retained;rewrite bound in retained.
 change (same_request_identity (get source "requestCredential") (get source "value") = true) in retained.
 unfold same_request_identity in retained;rewrite forallb_forall in retained;now apply retained.
Qed.
Theorem public_credential_rejects_another_issuer : forall source,
  same (get (get source "value") "issuer") (get source "issuer") = false ->
  exists message, Api.call "account.issuer_admission" source = err message.
Proof. intros source different; exists "ChatGPT credential belongs to a different issuer; sign in again"; change (issuer_admission source = err "ChatGPT credential belongs to a different issuer; sign in again");
 unfold issuer_admission;now rewrite different. Qed.
Theorem public_foreign_callback_state_cannot_authorize : forall source,
  same (first (parameters source "state")) (get source "state") = false ->
  str (get (Api.call "account.callback" source) "value") "action" <> "accept".
Proof.
 intros source different.
 change (str (get (callback source) "value") "action" <> "accept").
 unfold callback,decide_callback.
 destruct (parsed (get source "url"));cbn;try discriminate.
 destruct (same (get (get source "url") "pathname") AccountContracts.callback_path);cbn;try discriminate.
 unfold callback_bound;rewrite different;rewrite !andb_false_r;discriminate.
Qed.
Theorem public_cache_cannot_cross_an_account : forall source,
  same (get (get source "value") "account_id") (get source "account") = false ->
  Api.call "account.cache" source = success JNull.
Proof. intros source different;change (cache source = success JNull);unfold cache;
 rewrite different;now rewrite !andb_false_r. Qed.
Theorem public_cache_cannot_cross_a_connection : forall source,
  same (get (get source "value") "connection") (get source "connection") = false ->
  Api.call "account.cache" source = success JNull.
Proof. intros source different;change (cache source = success JNull);unfold cache;
 rewrite different;now rewrite !andb_false_r. Qed.
Theorem public_forced_discovery_does_not_use_stale_fallback : forall source,
  boolean_field source "force" = true -> Api.call "account.cache_fallback" source = success (JBool false).
Proof. intros source forced;change (cache_fallback source = success (JBool false));unfold cache_fallback;now rewrite forced. Qed.
Theorem public_unparseable_authentication_text_is_sanitized : exists message, forall source,
  TextJson.parse_json (str source "text") = None ->
  Api.call "account.record_decode" source = err message.
Proof. exists "Invalid ChatGPT authentication record; sign in again"; intros source invalid; change (record_decode source = err "Invalid ChatGPT authentication record; sign in again");
 unfold record_decode;now rewrite invalid. Qed.
Theorem public_unparseable_cache_is_disposable : forall source,
  TextJson.parse_json (str source "text") = None -> Api.call "account.cache_decode" source = success JNull.
Proof. intros source invalid;change (cache_decode source = success JNull);unfold cache_decode;now rewrite invalid. Qed.
Theorem public_login_metadata_excludes_token_fields : forall source,
  Forall (fun name => In name ["account_id";"filename";"name";"email"])
    (map fst (object_fields (get (Api.call "account.login_result" source) "value"))).
Proof. intros; repeat constructor; cbn; tauto. Qed.

Definition example_credential := JObject [
  ("format",JString credential_format);("issuer",JString "https://auth.openai.com");
  ("client_id",AccountContracts.client_id);("subject",JString "subject-1");("account_id",JString "account-1");
  ("access_token",JString "access");("refresh_token",JString "refresh");
  ("scope",JNull);("expires_at",JString "2030-01-01T00:00:00Z");
  ("earliest_refresh_at",JNull);("name",JNull);("email",JNull)].
Theorem public_valid_credential_is_retained :
  Api.call "account.credential" (JObject [("value",example_credential);
    ("dates",JObject [("expires_at",JObject [("iso",JString "2030-01-01T00:00:00Z")])])]) = success example_credential.
Proof. vm_compute;reflexivity. Qed.

(* Callback admission binds the browser request to this login. Token signature,
   nonce and PKCE verification remain obligations of the OpenID client. *)
Theorem public_valid_callback_authorizes_its_client : forall source code state,
  parsed (get source "url") = true ->
  get (get source "url") "pathname" = AccountContracts.callback_path ->
  get (get source "request") "method" = JString "GET" ->
  same (get (get source "request") "host") (get (get source "redirect") "host") = true ->
  same (get (get source "url") "origin") (get (get source "redirect") "origin") = true ->
  parameters source "code" = [code] -> nonempty code = true ->
  parameters source "state" = [state] -> same state (get source "state") = true ->
  parameters source "client_id" = [] ->
  parameters source "error" = [] ->
  Api.call "account.callback" source = success (encode_callback (AcceptCallback AccountContracts.client_id)).
Proof.
 intros source code state parsed_url path method host origin codes code_present
   states state_matches clients errors.
 assert (callback_bound source = true) as bound.
 { unfold callback_bound. rewrite method,host,origin.
   cbn [forallb]. rewrite codes,states,clients,errors.
   change (same state (get source "state") = true). exact state_matches. }
 change (callback source = success (encode_callback (AcceptCallback AccountContracts.client_id))).
 unfold callback,decide_callback. rewrite parsed_url,path,bound.
 rewrite errors,clients,codes. cbn [first default is_null List.length Nat.eqb hd].
 rewrite code_present. reflexivity.
Qed.
Theorem public_accepted_callback_binds_the_login_request : forall source id,
  Api.call "account.callback" source = success (encode_callback (AcceptCallback id)) ->
  same (get (get source "request") "method") (JString "GET") = true /\
  same (get (get source "request") "host") (get (get source "redirect") "host") = true /\
  same (get (get source "url") "origin") (get (get source "redirect") "origin") = true /\
  same (first (parameters source "state")) (get source "state") = true.
Proof.
 intros source id accepted.
 change (callback source = success (encode_callback (AcceptCallback id))) in accepted.
 unfold callback,decide_callback in accepted.
 destruct (parsed (get source "url")); cbn in accepted; [|discriminate].
 destruct (same (get (get source "url") "pathname") AccountContracts.callback_path);
   cbn in accepted; [|discriminate].
 destruct (callback_bound source) eqn:bound; cbn in accepted; [|discriminate].
 unfold callback_bound in bound. repeat rewrite andb_true_iff in bound. tauto.
Qed.
Definition automatic_candidate := JObject [("slug",JString "gpt-6-astra");
  ("visibility",JString "list");("supported_reasoning_levels",JArray [JObject [("effort",JString "low")]])].
Theorem public_automatic_transport_follows_advertised_capability : forall supported : option bool,
 let model := match supported with
   | Some supported => set automatic_candidate "supports_reasoning_effort_updates" (JBool supported)
   | None => automatic_candidate end in
 let response := Api.call "account.materialize" (JObject [
   ("namespace",JString "chatgpt/0123456789abcdef");("connection",AccountContracts.defaults);
   ("config",JObject [("profiles",JObject [])]);
   ("result",JObject [("account_id",JString "account-1");("models",JArray [model])])]) in
 get (get (get (get (get response "value") "profiles")
   "chatgpt/0123456789abcdef/gpt-6-astra/~auto") "adaptive_reasoning") "transport" =
 JString (match supported with Some true => "configuration_update" | _ => "request_effort" end).
Proof. intros [[|]|]; vm_compute; reflexivity. Qed.
Definition advertised_auto_suffix := JObject [("slug",JString "gpt-6-astra-auto");
  ("visibility",JString "list")].
Theorem public_advertised_auto_suffix_and_derived_variant_coexist :
  Permutation (map fst (object_fields (get (get (Api.call "account.materialize" (JObject [
    ("namespace",JString "chatgpt/0123456789abcdef");("connection",AccountContracts.defaults);
    ("config",JObject [("profiles",JObject [])]);
    ("result",JObject [("account_id",JString "account-1");("models",JArray [automatic_candidate;advertised_auto_suffix])])])) "value") "profiles")))
  ["chatgpt/0123456789abcdef/gpt-6-astra";"chatgpt/0123456789abcdef/gpt-6-astra/~auto";
    "chatgpt/0123456789abcdef/gpt-6-astra-auto"].
Proof. vm_compute;apply Permutation_refl. Qed.

Theorem public_authentication_text_requires_a_record : forall source value,
  Api.call "account.record_decode" source = success value -> is_object value = true.
Proof.
  intros source value accepted. change (record_decode source = success value) in accepted.
  unfold record_decode in accepted.
  destruct (TextJson.parse_json (str source "text")) as [parsed|]; [|discriminate].
  destruct (is_object parsed) eqn:object; [|discriminate].
  now inversion accepted; subst.
Qed.

Theorem public_credential_requires_unambiguous_identity : forall source value,
  Api.call "account.credential" source = success value ->
  forall name, In name ["issuer";"client_id";"subject";"account_id"] ->
    Utf8.no_nul (str (get source "value") name) = true.
Proof.
  intros source value accepted name member.
  change (AccountIdentity.credential source = success value) in accepted.
  unfold AccountIdentity.credential, admit_credential in accepted.
  destruct (decode_complete credential_schema (get source "value")) as [decoded|]; [|discriminate].
  destruct (credential_checks source) eqn:checks; [|discriminate].
  unfold credential_checks, credential_binding, identity_text in checks.
  repeat rewrite Bool.andb_true_iff in checks.
  cbn in member. destruct member as [<-|[<-|[<-|[<-|[]]]]]; unfold str; tauto.
Qed.

Theorem public_malformed_encoded_cache_is_disposable : forall source,
  get source "code" = JString "ERR_ENCODING_INVALID_ENCODED_DATA" ->
  Api.call "account.cache_error" source = success JNull.
Proof.
  intros source invalid. change (cache_error source = success JNull).
  unfold cache_error. rewrite invalid. reflexivity.
Qed.
