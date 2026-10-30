From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonObjects TextJson CallWire.
From Selvedge.Kernel Require Import ContextSelection.
From Selvedge.Adapters Require Import Common ProviderCatalog BackendHistory BackendRequests BackendResponses RetryAfter BackendRetry Backends Api.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Theorem public_completed_response_preserves_durable_output : forall source first rest,
  str (get source "event") "type" = "response.completed" ->
  str (get (get source "event") "response") "status" = "completed" ->
  get (get (get source "event") "response") "output" = JArray (first :: rest) ->
  str (get (Api.call "backend.stream_step" source) "value") "action" = "terminal" /\
  get (get (Api.call "backend.stream_step" source) "value") "output" = JArray (first :: rest).
Proof.
 intros source first rest kind completed output.
 change (str (get (BackendResponses.stream_step source) "value") "action" = "terminal" /\
   get (get (BackendResponses.stream_step source) "value") "output" = JArray (first :: rest)).
 unfold BackendResponses.stream_step,step. rewrite kind. cbn.
 rewrite completed,String.eqb_refl. unfold terminal_action. rewrite output. cbn [is_array items].
 destruct (String.eqb (str (get source "effect") "kind") "context_compaction"); split; reflexivity.
Qed.

Theorem public_nonterminal_events_cannot_release_durable_output : forall source,
  str (get source "event") "type" <> "response.completed" ->
  str (get (Api.call "backend.stream_step" source) "value") "action" <> "terminal".
Proof.
 intros source nonterminal.
 change (str (get (BackendResponses.stream_step source) "value") "action" <> "terminal").
 unfold BackendResponses.stream_step,step.
 destruct (String.eqb (str (get source "event") "type") "response.output_text.delta");
   [destruct (is_text (get (get source "event") "delta") &&
      canonical_natural (get (get source "event") "output_index"))|];
   try (destruct (String.eqb (str (get source "effect") "kind") "context_compaction"); discriminate).
 destruct (String.eqb (str (get source "event") "type") "response.output_item.done").
 - destruct (canonical_natural (get (get source "event") "output_index") &&
     is_object (get (get source "event") "item"));
     try (destruct (conflict _ _ _));
     destruct (String.eqb (str (get source "effect") "kind") "context_compaction"); discriminate.
 - apply String.eqb_neq in nonterminal. rewrite nonterminal.
   destruct (existsb (String.eqb (str (get source "event") "type"))
     ["error";"response.failed";"response.incomplete"]);
     destruct (String.eqb (str (get source "effect") "kind") "context_compaction"); discriminate.
Qed.

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
Definition account_function_output arguments namespace := JObject [
  ("profile",JObject [("provider",JString "chatgpt")]);
  ("markdown_observations",JArray [JArray []]);
  ("output",JArray [JObject [("type",JString "function_call");("namespace",JString namespace);
    ("call_id",JString "call-1");("name",JString "read_work");("arguments",JString arguments)]])].
Theorem public_local_function_call_decodes_raw_arguments : forall arguments fields,
  CallWire.parse_arguments CallWire.callback_argument_nesting arguments = Some (JObject fields) ->
  Api.call "backend.output" (account_function_output arguments "selvedge") =
    success (JArray [CallWire.encode_item "call-1" "read_work" (JObject fields)]).
Proof.
  intros arguments fields parsed.
  change (Api.call "backend.output" (account_function_output arguments "selvedge"))
    with (BackendResponses.output (account_function_output arguments "selvedge")).
  cbn -[CallWire.parse_arguments CallWire.callback_argument_nesting].
  rewrite (eq_refl : Utf8.nonblank "call-1" = true),
    (eq_refl : Utf8.nonblank "read_work" = true), parsed. reflexivity.
Qed.
Theorem public_foreign_function_namespace_is_rejected : forall arguments namespace,
  namespace <> local_tool_namespace ->
  Api.call "backend.output" (account_function_output arguments namespace) =
    err "ChatGPT returned a function call outside the local tool namespace".
Proof.
  intros arguments namespace foreign.
  apply String.eqb_neq in foreign.
  change (Api.call "backend.output" (account_function_output arguments namespace))
    with (BackendResponses.output (account_function_output arguments namespace)).
  cbn -[CallWire.parse_arguments]. rewrite foreign. reflexivity.
Qed.
Theorem public_unparseable_function_arguments_are_rejected : forall arguments,
  CallWire.parse_arguments CallWire.callback_argument_nesting arguments = None ->
  Api.call "backend.output" (account_function_output arguments "selvedge") =
    err "Invalid JSON function arguments".
Proof.
  intros arguments malformed.
  change (Api.call "backend.output" (account_function_output arguments "selvedge"))
    with (BackendResponses.output (account_function_output arguments "selvedge")).
  cbn -[CallWire.parse_arguments CallWire.callback_argument_nesting].
  rewrite (eq_refl : Utf8.nonblank "call-1" = true),
    (eq_refl : Utf8.nonblank "read_work" = true), malformed. reflexivity.
Qed.
(** This law covers every construction and provider registration. The true
    index leaves no place for a helper request to carry tool authority. *)
Theorem independent_requests_have_no_tool_authority : forall profile
  (request : BackendRequests.response_request true),
  get (BackendRequests.encode_request profile request) "tools" = JArray [] /\
  get (BackendRequests.encode_request profile request) "tool_choice" = JString "none".
Proof. intros; split; reflexivity. Qed.
