From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonObjects.
From Selvedge.Kernel Require Import ContextSelection.
From Selvedge.Adapters Require Import Common ProviderCatalog BackendHistory BackendRequests BackendResponses RetryAfter BackendRetry Backends Api.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Theorem public_frozen_account_rejects_another_identity : forall source,
  text (get (get source "profile") "bound_account_id") <> "" ->
  JsonObjects.equivalent (get (get source "profile") "bound_account_id")
    (get (get source "authorization") "account_id") = false ->
  Api.call "backend.authorization" source = err
    "This task belongs to a different ChatGPT account; restore that account or create a new task".
Proof.
 intros source bound different;change (authorization source = err
    "This task belongs to a different ChatGPT account; restore that account or create a new task").
 unfold authorization;apply String.eqb_neq in bound;now rewrite bound,different.
Qed.
Theorem public_matching_account_is_usable : forall source,
  JsonObjects.equivalent (get (get source "profile") "bound_account_id")
    (get (get source "authorization") "account_id") = true ->
  Api.call "backend.authorization" source = success JNull.
Proof. intros source matching;change (authorization source = success JNull);unfold authorization;
 rewrite matching;cbn;now rewrite andb_false_r. Qed.
Theorem public_nonempty_environment_credential_is_retained : forall source,
  is_text (get source "key") = true -> str source "key" <> "" ->
  Api.call "backend.credentials" source = success (get source "key").
Proof. intros source typed nonempty;change (credentials source = success (get source "key"));
 unfold credentials;apply String.eqb_neq in nonempty;now rewrite typed,nonempty. Qed.
Theorem public_empty_environment_credential_fails_before_io : forall source,
  str source "key" = "" ->
  Api.call "backend.credentials" source = err
    ("Set " ++ display_field (get source "profile") "api_key_env" ++ " to use this provider").
Proof. intros source empty;change (credentials source = err
    ("Set " ++ display_field (get source "profile") "api_key_env" ++ " to use this provider"));
 unfold credentials;rewrite empty;cbn;now rewrite andb_false_r. Qed.
Theorem public_context_limit_recovery_requires_unexposed_output : forall source,
  Api.call "backend.context_limit" source = success (JBool true) ->
  boolean_field source "output_started" = false.
Proof. intros source H;change (context_limit source = success (JBool true)) in H.
 unfold context_limit in H;destruct (boolean_field source "output_started") eqn:E;[|reflexivity];cbn in H;repeat rewrite andb_false_r in H;discriminate. Qed.
Theorem public_aborted_connection_does_not_retry : forall source,
  boolean_field source "error_present" = true -> boolean_field source "aborted" = true ->
  Api.call "backend.retry" source = retry_action "abort" false.
Proof. intros source error aborted;change (retry source = retry_action "abort" false);unfold retry;now rewrite error,aborted. Qed.
Theorem public_exhausted_response_retry_stops : forall source,
  boolean_field source "error_present" = false -> boolean_field source "response_present" = true ->
  attempt_available source = false -> Api.call "backend.retry" source = retry_action "stop" false.
Proof. intros source error response exhausted;change (retry source = retry_action "stop" false);unfold retry;
 rewrite error,response,exhausted;cbn;now rewrite andb_false_r. Qed.
Theorem public_excessive_retry_after_cancels_response : forall source delay,
  boolean_field source "error_present" = false -> boolean_field source "response_present" = true ->
  contains (items (get (get source "policy") "statuses")) (get source "status") = true ->
  attempt_available source = true -> header_delay source = Some delay ->
  delay_exceeds_integer delay (num (get source "policy") "max_retry_after_ms") = true ->
  Api.call "backend.retry" source = retry_failure
    ("Model request failed with HTTP " ++ display_field source "status" ++ "; Retry-After exceeds the retry budget") true false.
Proof. intros source delay error response status available header budget;change (retry source = retry_failure
    ("Model request failed with HTTP " ++ display_field source "status" ++ "; Retry-After exceeds the retry budget") true false);
 unfold retry;now rewrite error,response,status,available,header,budget. Qed.
Theorem public_admitted_retry_keeps_the_header_minimum : forall source delay,
  boolean_field source "error_present" = false -> boolean_field source "response_present" = true ->
  contains (items (get (get source "policy") "statuses")) (get source "status") = true ->
  attempt_available source = true -> header_delay source = Some delay ->
  delay_exceeds_integer delay (num (get source "policy") "max_retry_after_ms") = false ->
  Api.call "backend.retry" source = continue source true (maximum_delay (base_delay source) delay).
Proof. intros source delay error response status available header budget;change (retry source = continue source true (maximum_delay (base_delay source) delay));
 unfold retry,chosen_delay;now rewrite error,response,status,available,header,budget. Qed.
Definition example_account_output arguments namespace := JObject [
  ("profile",JObject [("provider",JString "chatgpt")]);
  ("output",JArray [JObject [("type",JString "function_call");("namespace",JString namespace);
    ("call_id",JString "call-1");("name",JString "read_work");("arguments",JString arguments)]])].
Theorem public_local_function_call_decodes_raw_arguments :
  Api.call "backend.output" (example_account_output "{""work_id"":7}" "selvedge") =
    success (JArray [JObject [("type",JString "call");("id",JString "call-1");
      ("name",JString "read_work");("arguments",JObject [("work_id",JNumber "7")])]]).
Proof. vm_compute;reflexivity. Qed.
Theorem public_foreign_function_namespace_is_rejected :
  Api.call "backend.output" (example_account_output "{}" "foreign") =
    err "ChatGPT returned a function call outside the local tool namespace".
Proof. vm_compute;reflexivity. Qed.
Theorem public_duplicate_function_arguments_are_rejected :
  Api.call "backend.output" (example_account_output "{""x"":1,""x"":2}" "selvedge") =
    err "Invalid JSON function arguments".
Proof. vm_compute;reflexivity. Qed.
Theorem public_helper_request_has_no_tool_authority : forall tools callable,
  let source := JObject [("effect",JObject [("kind",JString "context_compaction");
    ("tools",JArray tools);("callable",JArray callable);("history",JArray []);
    ("model",JObject [("provider",JString "responses");("name",JString "fixture")])]);
    ("profile",JObject [("provider",JString "responses")])] in
  get (Api.call "backend.request" source) "ok" = JBool true /\
  get (get (Api.call "backend.request" source) "value") "tools" = JArray [].
Proof. intros;split;reflexivity. Qed.
