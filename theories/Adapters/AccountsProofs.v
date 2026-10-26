From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import AccountFields AccountIdentity AccountOAuth AccountCatalog AccountMaterialization Accounts Api.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Theorem public_model_credential_rejects_another_identity : forall source,
  boolean_field source "audio" = false ->
  same (get (get source "value") "account_id") (get source "identity") = false ->
  Api.call "account.credential" source = err "Invalid current-format ChatGPT credential; sign in again".
Proof.
 intros source model different.
 assert (credential_checks source = false) as invalid.
 { unfold credential_checks,credential_binding,kind_of;rewrite model;cbn [is_audio];
   rewrite different;now rewrite !andb_false_r. }
 change (credential source = err "Invalid current-format ChatGPT credential; sign in again").
 unfold credential,admit_credential;destruct (decode_complete credential_schema (get source "value"));
   try rewrite invalid;reflexivity.
Qed.
Theorem public_audio_credential_rejects_another_client : forall source,
  boolean_field source "audio" = true ->
  same (get (get source "value") "client_id") (get AccountContracts.audio_contract "client_id") = false ->
  Api.call "account.credential" source = err "Invalid current-format ChatGPT credential; sign in again".
Proof.
 intros source audio different.
 assert (credential_checks source = false) as invalid.
 { unfold credential_checks,credential_binding,kind_of;rewrite audio;cbn [is_audio];
   rewrite different;now rewrite !andb_false_r. }
 change (credential source = err "Invalid current-format ChatGPT credential; sign in again").
 unfold credential,admit_credential;destruct (decode_complete credential_schema (get source "value"));
   try rewrite invalid;reflexivity.
Qed.
Theorem public_registration_rejects_another_issuer : forall source,
  same (get (get source "value") "issuer") (get source "issuer") = false ->
  Api.call "account.registration" source = err "Invalid ChatGPT client registration; sign in again".
Proof.
 intros source different.
 change (registration source = err "Invalid ChatGPT client registration; sign in again").
 unfold registration,admit_registration;destruct (decode_complete registration_schema (get source "value"));auto.
 unfold registration_checks,registration_binding;rewrite different;now rewrite !andb_false_r.
Qed.
Theorem public_refresh_rejects_another_registered_client : forall source,
  same (get (get source "registered") "client_id") (get (get source "value") "client_id") = false ->
  Api.call "account.refresh_registration" source = err identity_failure.
Proof. intros source different;change (refresh_registration source = err identity_failure).
 unfold refresh_registration,refresh_admission,same_registration;now rewrite different. Qed.
Theorem public_refresh_cannot_replace_the_request_identity : forall source,
  same_registration source = true ->
  has source "requestCredential" = true ->
  same_request_identity (get source "requestCredential") (get source "value") = false ->
  Api.call "account.refresh_registration" source = err request_identity_failure /\
  Api.call "account.refresh_initial" source = err request_identity_failure.
Proof.
 intros source registered bound different;split;
 [change (refresh_registration source = err request_identity_failure)
 |change (refresh_initial source = err request_identity_failure)];
 unfold refresh_registration,refresh_initial,refresh_admission,request_identity_retained;
 now rewrite registered,bound,different.
Qed.
Theorem public_refresh_keeps_the_same_request_identity : forall source,
  same_registration source = true ->
  same_request_identity (get source "requestCredential") (get source "value") = true ->
  Api.call "account.refresh_registration" source = success JNull /\
  Api.call "account.refresh_initial" source =
    success (JString (refresh_action_name (initial_action source))).
Proof.
 intros source registered retained;split;
 [change (refresh_registration source = success JNull)
 |change (refresh_initial source = success (JString (refresh_action_name (initial_action source))))];
 unfold refresh_registration,refresh_initial,refresh_admission,request_identity_retained;
 rewrite registered,retained,orb_true_r;reflexivity.
Qed.
Theorem public_refresh_identity_binds_each_principal_field : forall source,
  has source "requestCredential" = true ->
  Api.call "account.refresh_registration" source = success JNull ->
  forall field, In field ["issuer";"client_id";"subject";"account_id"] ->
    same (get (get source "requestCredential") field) (get (get source "value") field) = true.
Proof.
 intros source bound accepted field member.
 change (refresh_registration source = success JNull) in accepted.
 unfold refresh_registration,refresh_admission in accepted.
 destruct (same_registration source);try discriminate.
 unfold request_identity_retained in accepted;rewrite bound in accepted.
 change ((if same_request_identity (get source "requestCredential") (get source "value")
   then success JNull else err request_identity_failure) = success JNull) in accepted.
 destruct (same_request_identity (get source "requestCredential") (get source "value")) eqn:retained;
   try discriminate.
 unfold same_request_identity in retained;rewrite forallb_forall in retained;now apply retained.
Qed.
Theorem public_issuer_is_checked_before_refresh : forall source,
  same (get (get source "value") "issuer") (get source "issuer") = false ->
  Api.call "account.refresh" source = err "ChatGPT credential belongs to a different issuer; sign in again".
Proof. intros source different;change (refresh source = err "ChatGPT credential belongs to a different issuer; sign in again");
 unfold refresh;now rewrite different. Qed.
Theorem public_foreign_callback_state_cannot_authorize : forall source,
  same (first (parameters source "state")) (get source "state") = false ->
  str (get (Api.call "account.callback" source) "value") "action" <> "accept".
Proof.
 intros source different.
 change (str (get (callback source) "value") "action" <> "accept").
 unfold callback,decide_callback.
 destruct (parsed (get source "url"));cbn;try discriminate.
 destruct (same (get (get source "url") "pathname") (JString "/auth/callback"));cbn;try discriminate.
 destruct (boolean_field source "received");cbn;try discriminate.
 unfold callback_bound;rewrite different;rewrite !andb_false_r;discriminate.
Qed.
Theorem public_completed_callback_is_not_consumed_again : forall source,
  parsed (get source "url") = true ->
  same (get (get source "url") "pathname") (JString "/auth/callback") = true ->
  boolean_field source "received" = true ->
  Api.call "account.callback" source = success (encode_callback (IgnoreCallback 409)).
Proof. intros source parsed_url path received;change (callback source = success (encode_callback (IgnoreCallback 409))).
 unfold callback,decide_callback;now rewrite parsed_url,path,received. Qed.
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
Theorem public_unparseable_authentication_text_is_sanitized : forall source,
  TextJson.parse_json (str source "text") = None ->
  Api.call "account.record_decode" source = err "Invalid ChatGPT authentication record; sign in again".
Proof. intros source invalid;change (record_decode source = err "Invalid ChatGPT authentication record; sign in again");
 unfold record_decode;now rewrite invalid. Qed.
Theorem public_unparseable_cache_is_disposable : forall source,
  TextJson.parse_json (str source "text") = None -> Api.call "account.cache_decode" source = success JNull.
Proof. intros source invalid;change (cache_decode source = success JNull);unfold cache_decode;now rewrite invalid. Qed.
Theorem public_login_metadata_excludes_token_fields : forall source,
  map fst (object_fields (get (Api.call "account.login_result" source) "value")) =
    ["account_id";"filename";"name";"email"].
Proof. reflexivity. Qed.

Definition example_credential := JObject [
  ("format",JString "selvedge-chatgpt-2");("issuer",JString "https://auth.openai.com");
  ("client_id",JString "client-1");("subject",JString "subject-1");("account_id",JString "account-1");
  ("access_token",JString "access");("refresh_token",JString "refresh");("id_token",JString "id");
  ("scope",JString "chatgpt.tokens.use.direct");("expires_at",JString "2030-01-01T00:00:00Z");
  ("earliest_refresh_at",JNull);("last_refresh",JString "2029-01-01T00:00:00Z");("name",JNull);("email",JNull)].
Theorem public_valid_credential_is_retained :
  Api.call "account.credential" (JObject [("value",example_credential);("identity",JString "account-1");
    ("dates",JObject [("expires_at",JObject [("iso",JString "2030-01-01T00:00:00Z")]);
      ("last_refresh",JObject [("iso",JString "2029-01-01T00:00:00Z")])])]) = success example_credential.
Proof. vm_compute;reflexivity. Qed.

Lemma admitted_model_has_a_fresh_name : forall seen source value,
  admit_model seen source = Some value -> ~ In value.(model_slug) seen.
Proof.
 intros seen source value accepted;unfold admit_model in accepted.
 repeat match type of accepted with
 | context [match ?choice with Some _ => _ | None => _ end] => destruct choice eqn:?;try discriminate
 end.
 destruct (is_object source && bounded_text (JString s) && bounded_text (JString s0) && slug s &&
   negb (existsb (String.eqb s) seen)) eqn:valid;try discriminate.
 inversion accepted;subst;cbn.
 apply andb_true_iff in valid as [_ fresh];apply negb_true_iff in fresh.
 intro present;assert (existsb (String.eqb s) seen = true) as found.
 { apply existsb_exists;exists s;split;auto;apply String.eqb_refl. }
 congruence.
Qed.

Lemma admitted_models_have_unique_fresh_names : forall source seen values,
  admit_models seen source = Accepted values ->
  NoDup (map model_slug values) /\
  (forall value, In value values -> ~ In value.(model_slug) seen).
Proof.
 induction source as [|head rest IH];intros seen values accepted.
 - cbn [admit_models] in accepted;inversion accepted;subst;split.
   + cbn;constructor.
   + intros value present;contradiction.
 - cbn [admit_models] in accepted.
   destruct (admit_model seen head) as [value|] eqn:admitted;try discriminate.
   destruct (admit_models (model_slug value :: seen) rest) as [tail|code message] eqn:decoded;try discriminate.
   cbn [bind] in accepted;inversion accepted;subst.
   destruct (IH _ _ decoded) as [unique avoid].
   split.
   + cbn;constructor;auto.
     intro repeated;apply in_map_iff in repeated as [item [same_name present]].
     apply (avoid item present);cbn;left;congruence.
   + intros item present;destruct present as [<-|present].
     * now apply (admitted_model_has_a_fresh_name _ _ _ admitted).
     * intro old;apply (avoid item present);now right.
Qed.

Theorem public_successful_catalog_has_distinct_model_names : forall source values,
  Api.call "account.catalog" source = success (JArray values) ->
  NoDup (map (fun model => str model "slug") values).
Proof.
 intros source values accepted;change (catalog source = success (JArray values)) in accepted.
 unfold catalog in accepted.
 destruct (is_object (get source "value") && is_array (get (get source "value") "models") &&
   Nat.leb (List.length (items (get (get source "value") "models"))) 512);try discriminate.
 destruct (admit_models [] (items (get (get source "value") "models"))) as [models|code message] eqn:decoded;try discriminate.
 cbn [render_outcome] in accepted;inversion accepted;subst.
 rewrite map_map;change (NoDup (map model_slug models)).
 exact (proj1 (admitted_models_have_unique_fresh_names _ _ _ decoded)).
Qed.
(* Callback admission binds the browser request to this login. Token signature,
   nonce and PKCE verification remain obligations of the OpenID client. *)
Theorem public_valid_callback_authorizes_its_client : forall source code state id,
  parsed (get source "url") = true ->
  get (get source "url") "pathname" = JString "/auth/callback" ->
  boolean_field source "received" = false ->
  get (get source "request") "method" = JString "GET" ->
  same (get (get source "request") "host") (get (get source "redirect") "host") = true ->
  same (get (get source "url") "origin") (get (get source "redirect") "origin") = true ->
  parameters source "code" = [code] -> nonempty code = true ->
  parameters source "state" = [state] -> same state (get source "state") = true ->
  parameters source "client_id" = [id] -> client id = true ->
  parameters source "error" = [] ->
  (is_object (get source "registered") = false \/
    same id (get (get source "registered") "client_id") = true) ->
  Api.call "account.callback" source = success (encode_callback (AcceptCallback id)).
Proof.
 intros source code state id parsed_url path fresh method host origin codes code_present
   states state_matches clients valid_client errors registered.
 assert (exists issued, id = JString issued) as [issued ->].
 { unfold client,identity_text,nonempty in valid_client.
   destruct id; cbn in valid_client; try discriminate; eauto. }
 assert (callback_bound source = true) as bound.
 { unfold callback_bound. rewrite method,host,origin.
   cbn [forallb]. rewrite codes,states,clients,errors.
   change (same state (get source "state") = true). exact state_matches. }
 change (callback source = success (encode_callback (AcceptCallback (JString issued)))).
 unfold callback,decide_callback. rewrite parsed_url,path,fresh,bound.
 rewrite errors,clients,codes. cbn [first default is_null List.length Nat.eqb hd].
 rewrite code_present,valid_client.
 destruct registered as [absent|matching]; rewrite absent || rewrite matching;
   now destruct (is_object (get source "registered")).
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
 destruct (same (get (get source "url") "pathname") (JString "/auth/callback"));
   cbn in accepted; [|discriminate].
 destruct (boolean_field source "received"); cbn in accepted; [discriminate|].
 destruct (callback_bound source) eqn:bound; cbn in accepted; [|discriminate].
 unfold callback_bound in bound. repeat rewrite andb_true_iff in bound. tauto.
Qed.
Definition example_model := JObject [("slug",JString "model-1");("display_name",JString "Model 1");("visibility",JString "list")].
Theorem public_valid_model_is_selectable :
  Api.call "account.catalog" (JObject [("value",JObject [("models",JArray [example_model])])]) = success (JArray [example_model]).
Proof. vm_compute;reflexivity. Qed.
Theorem public_duplicate_model_identity_is_rejected :
  Api.call "account.catalog" (JObject [("value",JObject [("models",JArray [example_model;example_model])])]) =
    err "ChatGPT returned an invalid model descriptor".
Proof. vm_compute;reflexivity. Qed.

Definition automatic_candidate := JObject [("slug",JString "gpt-6-astra");("display_name",JString "Astra");
  ("visibility",JString "list");("supported_reasoning_levels",JArray [JObject [("effort",JString "low")]])].
Definition advertised_auto_suffix := JObject [("slug",JString "gpt-6-astra-auto");
  ("display_name",JString "Independent external model");("visibility",JString "list")].
Theorem public_advertised_auto_suffix_and_derived_variant_coexist :
  map fst (object_fields (get (Api.call "account.materialize" (JObject [
    ("namespace",JString "chatgpt/0123456789abcdef");("connection",AccountContracts.defaults);
    ("config",JObject [("profiles",JObject [])]);
    ("result",JObject [("account_id",JString "account-1");("models",JArray [automatic_candidate;advertised_auto_suffix])])])) "value")) =
  ["chatgpt/0123456789abcdef/gpt-6-astra";"chatgpt/0123456789abcdef/gpt-6-astra/~auto";
    "chatgpt/0123456789abcdef/gpt-6-astra-auto"].
Proof. vm_compute;reflexivity. Qed.

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
  forall name, In name ["issuer";"client_id";"subject"] ->
    Utf8.no_nul (str (get source "value") name) = true.
Proof.
  intros source value accepted name member.
  change (credential source = success value) in accepted.
  unfold credential, admit_credential in accepted.
  destruct (decode_complete credential_schema (get source "value")) as [decoded|]; [|discriminate].
  destruct (credential_checks source) eqn:checks; [|discriminate].
  unfold credential_checks, credential_binding, client, identity_text in checks.
  repeat rewrite Bool.andb_true_iff in checks.
  cbn in member. destruct member as [<-|[<-|[<-|[]]]]; unfold str; tauto.
Qed.

Theorem public_malformed_encoded_cache_is_disposable : forall source,
  get source "code" = JString "ERR_ENCODING_INVALID_ENCODED_DATA" ->
  Api.call "account.cache_error" source = success JNull.
Proof.
  intros source invalid. change (cache_error source = success JNull).
  unfold cache_error. rewrite invalid. reflexivity.
Qed.
