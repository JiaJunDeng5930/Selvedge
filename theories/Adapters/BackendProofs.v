From Stdlib Require Import String List Bool NArith Sorting.Permutation Sorting.Sorted Lia.
From Selvedge.Foundation Require Import Json JsonObjects TextJson CallWire NumbersProofs.
From Selvedge.Kernel Require Import ContextSelection.
From Selvedge.Adapters Require Import Common ProviderCatalog BackendHistory BackendRequests BackendResponses RetryAfter BackendRetry Backends Api.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Lemma admitted_reasoning_retains_the_committed_request_effort : forall effect profile reasoning,
 BackendRequests.admit_reasoning effect profile = AdapterResult.Accepted (Some reasoning) ->
 reasoning = JObject [("effort",BackendRequests.request_effort effect)].
Proof.
 intros effect profile reasoning Admitted.
 unfold BackendRequests.admit_reasoning in Admitted.
 repeat match type of Admitted with
 | context [if ?condition then _ else _] => destruct condition end;
 inversion Admitted; reflexivity.
Qed.

Theorem public_requests_use_the_committed_request_effort : forall source effect input reasoning,
 BackendRequests.prepare_effect (get source "effect") = AdapterResult.Accepted effect ->
 BackendRequests.effect_input ContextSelection.target_messages effect (get source "profile") =
   AdapterResult.Accepted input ->
 BackendRequests.admit_reasoning effect (get source "profile") = AdapterResult.Accepted (Some reasoning) ->
 Api.call "backend.request" source = success
   (BackendRequests.encode_request (get source "profile")
     (BackendRequests.construct_request effect input
       (Some (JObject [("effort",BackendRequests.request_effort effect)]))
       (BackendRequests.output_limit effect))).
Proof.
 intros source effect input reasoning Prepared Input Reasoning.
 apply admitted_reasoning_retains_the_committed_request_effort in Reasoning as Value.
 subst reasoning.
 change (Api.call "backend.request" source)
   with (BackendRequests.request ContextSelection.target_messages source).
 unfold BackendRequests.request; rewrite Prepared; cbn [AdapterResult.bind].
 rewrite Input; cbn [AdapterResult.bind]; rewrite Reasoning; reflexivity.
Qed.

Theorem adaptive_account_requests_require_supported_baseline_and_effort : forall effect profile reasoning,
 account profile = true ->
 is_array (get (get profile "model_info") "supported_reasoning_levels") = true ->
 is_object (get (get effect "model") "adaptive_reasoning") = true ->
 independent_kind (str effect "kind") = false ->
 BackendRequests.admit_reasoning effect profile = AdapterResult.Accepted (Some reasoning) ->
 let levels := map (fun level => get level "effort")
   (items (get (get profile "model_info") "supported_reasoning_levels")) in
 contains levels (BackendRequests.request_effort effect) = true /\
 contains levels (BackendRequests.effective_effort effect) = true.
Proof.
 intros effect profile reasoning Account Levels Adaptive TaskRequest Admitted levels.
 unfold BackendRequests.admit_reasoning in Admitted.
 rewrite Account, Levels, Adaptive, TaskRequest, andb_false_r in Admitted.
 cbn [andb negb orb] in Admitted.
 fold levels in Admitted.
 destruct (contains levels (request_effort effect) && contains levels (effective_effort effect)) eqn:Supported;
   [now apply andb_true_iff in Supported|discriminate].
Qed.

Lemma completed_item_roundtrip : forall item,
 decode_completed (encode_completed item) = item.
Proof.
 intros [index value].
 change (CompletedItem
   (match Numbers.parse_natural (Numbers.show_natural index) with Some value => value | None => 0 end)
   value = CompletedItem index value).
 now rewrite natural_print_parse.
Qed.

Lemma response_stream_roundtrip : forall state,
 decode_stream (encode_stream state) = state.
Proof.
 intros [started values].
 change (ResponseStream started (map decode_completed (map encode_completed values)) =
   ResponseStream started values).
 rewrite map_map; f_equal.
 induction values as [|first rest IH]; cbn [map]; [reflexivity|].
 now rewrite completed_item_roundtrip, IH.
Qed.

Lemma fresh_completed_item_has_no_conflict : forall values item,
 Forall (fun previous => completed_index previous <> completed_index item) values ->
 conflict values (completed_index item) (completed_value item) = false.
Proof.
 intros values item Fresh; unfold conflict.
 induction Fresh as [|first rest Different Fresh IH]; cbn [existsb]; [reflexivity|].
 apply N.eqb_neq in Different; now rewrite Different, IH.
Qed.

Lemma insert_fresh_completed_item_keeps_all_outputs : forall values item,
 Forall (fun previous => completed_index previous <> completed_index item) values ->
 Permutation (insert_completed item values) (item :: values).
Proof.
 intros values item Fresh; induction Fresh as [|first rest Different Fresh IH]; cbn [insert_completed].
 - reflexivity.
 - destruct (completed_index item <? completed_index first); [reflexivity|].
   assert (Equal : N.eqb (completed_index item) (completed_index first) = false)
     by (apply N.eqb_neq; congruence).
   rewrite Equal. eapply Permutation_trans; [apply perm_skip; exact IH|apply perm_swap].
Qed.

Lemma insert_completed_preserves_forall : forall (property : completed_item -> Prop) values item,
 property item -> Forall property values -> Forall property (insert_completed item values).
Proof.
 intros property values item Item Values; induction Values as [|first rest First Rest IH]; cbn [insert_completed].
 - now constructor.
 - destruct (completed_index item <? completed_index first); [now repeat constructor|].
   destruct (N.eqb (completed_index item) (completed_index first)); now constructor.
Qed.

Lemma insert_completed_item_keeps_provider_order : forall values item,
 StronglySorted (fun left right => completed_index left < completed_index right) values ->
 StronglySorted (fun left right => completed_index left < completed_index right)
   (insert_completed item values).
Proof.
 intros values item Ordered; induction Ordered as [|first rest Ordered IH Above].
 - cbn [insert_completed]; repeat constructor.
 - cbn [insert_completed].
   destruct (completed_index item <? completed_index first) eqn:Before.
   + apply N.ltb_lt in Before. constructor.
     * now constructor.
     * constructor; [exact Before|]. eapply Forall_impl; [|exact Above].
       intros value Later; cbn in *; lia.
   + destruct (N.eqb (completed_index item) (completed_index first)) eqn:Equal.
     * apply N.eqb_eq in Equal. constructor; [exact Ordered|].
       eapply Forall_impl; [|exact Above]. intros value Later; cbn in *; lia.
     * constructor; [exact IH|]. apply insert_completed_preserves_forall; [|exact Above].
       apply N.ltb_ge in Before; apply N.eqb_neq in Equal; lia.
Qed.

Lemma response_step_preserves_provider_order : forall event state,
 StronglySorted (fun left right => completed_index left < completed_index right) (completed_items state) ->
 StronglySorted (fun left right => completed_index left < completed_index right)
   (completed_items (fst (step event state))).
Proof.
 intros event state Ordered; unfold step; cbn [exposed completed_items].
 destruct (String.eqb (str event "type") "response.output_text.delta"); [exact Ordered|].
 destruct (String.eqb (str event "type") "response.output_item.done").
 - destruct (wire_natural (get event "output_index")) as [index|]; destruct (is_object (get event "item"));
     cbn [fst completed_items]; try exact Ordered.
   destruct (conflict (completed_items state) index (get event "item")); cbn [fst completed_items];
     [exact Ordered|now apply insert_completed_item_keeps_provider_order].
 - destruct (String.eqb (str event "type") "response.completed"); [exact Ordered|].
   destruct (existsb (String.eqb (str event "type")) ["error";"response.failed";"response.incomplete"]); exact Ordered.
Qed.

Theorem public_stream_step_preserves_provider_order : forall source,
 StronglySorted (fun left right => completed_index left < completed_index right)
   (completed_items (decode_stream (get source "state"))) ->
 StronglySorted (fun left right => completed_index left < completed_index right)
   (completed_items (decode_stream (get (get (Api.call "backend.stream_step" source) "value") "state"))).
Proof.
 intros source Ordered.
 pose proof (response_step_preserves_provider_order (get source "event")
   (decode_stream (get source "state")) Ordered) as Preserved.
 change (Api.call "backend.stream_step" source) with (stream_step source).
 unfold stream_step.
 destruct (step (get source "event") (decode_stream (get source "state"))) as [next action]; cbn [fst] in Preserved.
 destruct (String.eqb (str (get source "effect") "kind") "context_compaction"); destruct action;
   change (StronglySorted (fun left right => completed_index left < completed_index right)
     (completed_items (decode_stream (encode_stream next))));
   now rewrite response_stream_roundtrip.
Qed.

Theorem public_finalized_output_retains_every_item : forall source index,
 str (get source "event") "type" = "response.output_item.done" ->
 wire_natural (get (get source "event") "output_index") = Some index ->
 is_object (get (get source "event") "item") = true ->
 StronglySorted (fun left right => completed_index left < completed_index right)
   (completed_items (decode_stream (get source "state"))) ->
 Forall (fun previous => completed_index previous <> index)
   (completed_items (decode_stream (get source "state"))) ->
 exists retained,
 decode_stream (get (get (Api.call "backend.stream_step" source) "value") "state") =
   ResponseStream true retained /\
 str (get (Api.call "backend.stream_step" source) "value") "action" = "continue" /\
 Permutation retained (CompletedItem index
   (get (get source "event") "item") :: completed_items (decode_stream (get source "state"))) /\
 StronglySorted (fun left right => completed_index left < completed_index right) retained.
Proof.
 intros source index Kind Index Item Ordered Fresh.
 set (incoming := CompletedItem index (get (get source "event") "item")).
 set (retained := insert_completed incoming (completed_items (decode_stream (get source "state")))).
 assert (NoConflict : conflict (completed_items (decode_stream (get source "state")))
   index (get (get source "event") "item") = false)
   by (apply (fresh_completed_item_has_no_conflict _ incoming); exact Fresh).
 assert (Step : Api.call "backend.stream_step" source = encode_action (ResponseStream true retained) Continue).
 { change (stream_step source = encode_action (ResponseStream true retained) Continue).
   unfold stream_step, step; rewrite Kind; cbn -[wire_natural].
   rewrite Index, Item; cbn [andb exposed completed_items conflict decode_stream].
   unfold conflict, decode_stream in NoConflict; cbn [completed_items] in NoConflict; rewrite NoConflict.
   destruct (String.eqb (str (get source "effect") "kind") "context_compaction"); reflexivity. }
 exists retained; rewrite Step; split.
 - change (decode_stream (encode_stream (ResponseStream true retained)) = ResponseStream true retained).
   apply response_stream_roundtrip.
 - split; [reflexivity|]. split.
   + apply insert_fresh_completed_item_keeps_all_outputs; exact Fresh.
   + now apply insert_completed_item_keeps_provider_order.
Qed.

Theorem public_conflicting_finalized_output_fails : forall source previous index,
 str (get source "event") "type" = "response.output_item.done" ->
 wire_natural (get (get source "event") "output_index") = Some index ->
 is_object (get (get source "event") "item") = true ->
 In previous (completed_items (decode_stream (get source "state"))) ->
 completed_index previous = index ->
 JsonObjects.equivalent (completed_value previous) (get (get source "event") "item") = false ->
 str (get (Api.call "backend.stream_step" source) "value") "action" = "failure" /\
 get (get (Api.call "backend.stream_step" source) "value") "recoverable" = JBool false.
Proof.
 intros source previous index Kind Index Item Member Coordinate Different.
 assert (Conflict : conflict (completed_items (decode_stream (get source "state")))
   index (get (get source "event") "item") = true).
 { unfold conflict; apply existsb_exists; exists previous; split; [exact Member|].
   now rewrite Coordinate, N.eqb_refl, Different. }
 change (Api.call "backend.stream_step" source) with (stream_step source).
 unfold stream_step, step; rewrite Kind; cbn -[wire_natural].
 rewrite Index, Item; cbn [andb exposed completed_items conflict decode_stream].
 unfold conflict, decode_stream in Conflict; cbn [completed_items] in Conflict; rewrite Conflict.
 destruct (String.eqb (str (get source "effect") "kind") "context_compaction"); split; reflexivity.
Qed.

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

Theorem public_completed_response_retains_finalized_output : forall source first rest,
 str (get source "event") "type" = "response.completed" ->
 str (get (get source "event") "response") "status" = "completed" ->
 (get (get (get source "event") "response") "output" = JNull \/
  get (get (get source "event") "response") "output" = JArray []) ->
 completed_items (decode_stream (get source "state")) = first :: rest ->
 str (get (Api.call "backend.stream_step" source) "value") "action" = "terminal" /\
 get (get (Api.call "backend.stream_step" source) "value") "output" =
   JArray (map completed_value (first :: rest)) /\
 get (get (Api.call "backend.stream_step" source) "value") "output_indices" =
   JArray (map (fun item => number (completed_index item)) (first :: rest)).
Proof.
 intros source first rest Kind Completed Output Retained.
 change (Api.call "backend.stream_step" source) with (stream_step source).
 unfold stream_step, step; rewrite Kind; cbn.
 rewrite Completed, String.eqb_refl. unfold terminal_action.
 destruct Output as [Output|Output]; rewrite Output; cbn [is_array items length Nat.eqb negb andb exposed completed_items];
   rewrite Retained; destruct (String.eqb (str (get source "effect") "kind") "context_compaction");
   repeat split; reflexivity.
Qed.

Theorem public_nonterminal_events_cannot_release_durable_output : forall source,
  str (get source "event") "type" <> "response.completed" ->
  str (get (Api.call "backend.stream_step" source) "value") "action" <> "terminal".
Proof.
 intros source nonterminal.
 change (str (get (BackendResponses.stream_step source) "value") "action" <> "terminal").
 unfold BackendResponses.stream_step,step.
 destruct (String.eqb (str (get source "event") "type") "response.output_text.delta");
   [destruct (wire_natural (get (get source "event") "output_index"));
    destruct (is_text (get (get source "event") "delta"))|];
   try (destruct (String.eqb (str (get source "effect") "kind") "context_compaction"); discriminate).
 destruct (String.eqb (str (get source "event") "type") "response.output_item.done").
 - destruct (wire_natural (get (get source "event") "output_index"));
     destruct (is_object (get (get source "event") "item"));
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
  exists message, Api.call "backend.authorization" source = err message.
Proof.
 intros source bound different; exists "This task belongs to a different ChatGPT account; restore that account or create a new task"; change (authorization source = err
    "This task belongs to a different ChatGPT account; restore that account or create a new task").
 unfold authorization;apply String.eqb_neq in bound;now rewrite bound,different.
Qed.
Theorem public_matching_account_is_usable : forall source,
  JsonObjects.equivalent (get (get source "profile") "bound_account_id")
    (get (get source "authorization") "account_id") = true ->
  exists accepted, Api.call "backend.authorization" source = success accepted.
Proof. intros source matching;exists JNull;change (authorization source = success JNull);unfold authorization;
 rewrite matching;cbn;now rewrite andb_false_r. Qed.
Theorem public_nonempty_environment_credential_is_admitted : forall source,
  is_text (get source "key") = true -> str source "key" <> "" ->
  exists accepted, Api.call "backend.credentials" source = success accepted.
Proof. intros source typed nonempty;exists JNull;change (credentials source = success JNull);
 unfold credentials;apply String.eqb_neq in nonempty;now rewrite typed,nonempty. Qed.
Theorem public_empty_environment_credential_fails_before_io : forall source,
  str source "key" = "" ->
  exists message, Api.call "backend.credentials" source = err message.
Proof. intros source empty; exists ("Set " ++ display_field (get source "profile") "api_key_env" ++ " to use this provider"); change (credentials source = err
    ("Set " ++ display_field (get source "profile") "api_key_env" ++ " to use this provider"));
 unfold credentials;rewrite empty;cbn;now rewrite andb_false_r. Qed.
Theorem public_http_context_limit_recovers_before_output : forall source,
 get (get (Api.call "backend.http_failure" source) "value") "recoverable" = JBool true <->
 JsonObjects.equivalent (get source "status") (number 400) = true /\
 str source "code" = "context_length_exceeded" /\ boolean_field source "output_started" = false.
Proof.
 intro source.
 change (get (get (Api.call "backend.http_failure" source) "value") "recoverable") with
   (JBool (JsonObjects.equivalent (get source "status") (number 400) &&
   String.eqb (str source "code") "context_length_exceeded" &&
   negb (boolean_field source "output_started"))).
 split.
 - intro Equal; injection Equal as Equal.
   apply andb_true_iff in Equal as [Failure Started].
   apply andb_true_iff in Failure as [Status Code].
   apply String.eqb_eq in Code; apply negb_true_iff in Started; auto.
 - intros [Status [Code Started]]. apply String.eqb_eq in Code.
   now rewrite Status, Code, Started.
Qed.
Theorem public_aborted_connection_does_not_retry : forall source,
  boolean_field source "error_present" = true -> boolean_field source "aborted" = true ->
  Api.call "backend.retry" source = retry_action "abort" false.
Proof. intros source error aborted;change (retry source = retry_action "abort" false);unfold retry;now rewrite error,aborted. Qed.
Theorem public_exhausted_response_retry_stops : forall source,
  boolean_field source "error_present" = false ->
  attempt_available source = false -> Api.call "backend.retry" source = retry_action "stop" false.
Proof. intros source error exhausted;change (retry source = retry_action "stop" false);unfold retry;
 rewrite error,exhausted;cbn;now rewrite andb_false_r. Qed.
Theorem public_excessive_retry_after_cancels_response : forall source delay,
  boolean_field source "error_present" = false ->
  contains (items (get (get source "policy") "statuses")) (get source "status") = true ->
  attempt_available source = true -> header_delay source = Some delay ->
  delay_exceeds_integer delay (num (get source "policy") "max_retry_after_ms") = true ->
  exists message, Api.call "backend.retry" source = retry_failure message true false.
Proof. intros source delay error status available header budget; exists ("Model request failed with HTTP " ++ display_field source "status" ++ "; Retry-After exceeds the retry budget"); change (retry source = retry_failure
    ("Model request failed with HTTP " ++ display_field source "status" ++ "; Retry-After exceeds the retry budget") true false);
 unfold retry;now rewrite error,status,available,header,budget. Qed.
Theorem public_admitted_retry_keeps_the_header_minimum : forall source delay,
  boolean_field source "error_present" = false ->
  contains (items (get (get source "policy") "statuses")) (get source "status") = true ->
  attempt_available source = true -> header_delay source = Some delay ->
  delay_exceeds_integer delay (num (get source "policy") "max_retry_after_ms") = false ->
  Api.call "backend.retry" source = continue source true (maximum_delay (base_delay source) delay).
Proof. intros source delay error status available header budget;change (retry source = continue source true (maximum_delay (base_delay source) delay));
 unfold retry,chosen_delay;now rewrite error,status,available,header,budget. Qed.
Definition account_function_output arguments namespace := JObject [
  ("profile",JObject [("provider",JString "chatgpt")]);
  ("markdown_observations",JArray [JArray []]);
  ("output",JArray [JObject [("type",JString "function_call");("namespace",JString namespace);
    ("call_id",JString "call-1");("name",JString "read_work");("arguments",JString arguments)]])].
Theorem public_foreign_function_namespace_is_rejected : forall arguments namespace,
  namespace <> local_tool_namespace ->
  exists message, Api.call "backend.output" (account_function_output arguments namespace) = err message.
Proof.
  intros arguments namespace foreign. eexists.
  apply String.eqb_neq in foreign.
  change (Api.call "backend.output" (account_function_output arguments namespace))
    with (BackendResponses.output (account_function_output arguments namespace)).
  cbn -[CallWire.parse_arguments]. rewrite foreign. reflexivity.
Qed.
(** This law covers every construction and provider registration. The true
    index leaves no place for a helper request to carry tool authority. *)
Theorem independent_requests_have_no_tool_authority : forall profile
  (request : BackendRequests.response_request true),
  get (BackendRequests.encode_request profile request) "tools" = JArray [] /\
  get (BackendRequests.encode_request profile request) "tool_choice" = JString "none".
Proof. intros; split; reflexivity. Qed.
