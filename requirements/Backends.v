From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import ContextSelection.
From Selvedge.Adapters Require Import Common ProviderCatalog BackendRequests Api.
From Selvedge.Programming Require Import AdapterResult.

(** * Requests retain their admitted account and durable response

    Credential rotation must not change the principal of an already selected
    request. Account identity therefore includes the issuer, issued client and
    verified subject; a matching display identity cannot authorize a different
    registration. Registration survives separately from rotating credentials;
    model and audio credentials retain their own grants. Invalid credentials
    cannot authorize a request, while an invalid disposable cache can be dropped.
    Configured account connections are admitted when configuration enters the
    service; the built-in audio connection is constructed from its native
    declaration. Authorization and model materialization reuse those connections.
    Re-admitting their unchanged URL fields adds no evidence about the credential
    read from disk, whose identity and grant still require their own admission.
    [AccountsProofs] binds these refresh, callback and credential rules to the
    public account operations. Refusal contracts retain failure and the actual
    control decision without fixing diagnostic wording. Errors for malformed
    credential text must be independent of the rejected bytes so they cannot
    disclose a credential. Private credential, registration and host-identity
    files must be readable by their owner and deny group and other access.
    Exact owner write and execute bits add no privacy property. Permission
    acceptance checks owner read explicitly because a privileged test process
    can read a file even when its owner cannot.
    Refresh eligibility uses one admitted, locked
    credential; its expiry margin and earliest refresh time are evaluated
    against the same observed time. Callback admission binds the actual HTTP
    request to the login; repeated browser callbacks must not replace its chosen
    code or repeat the authorization exchange and credential publication.
    The login awaits one callback Promise before exchanging the accepted code.
    Single-settlement Promise semantics gives that continuation one outcome; each
    HTTP callback still undergoes its own method, target, origin, state and
    issued-client admission. Signature, nonce and PKCE verification belong to
    the OpenID client. Displaying the SDK's authorization URL introduces no new
    account admission. Issuer admission checks the credential already held by
    the caller without returning another copy of it.
    Environment authentication admits a captured nonempty key before I/O; that
    same captured key supplies Authorization and the compaction consumer scope.
    These credential guards establish acceptance without a successful-payload
    contract: returning another credential adds no authentication evidence.
    Callback response wording or a duplicate-receipt status
    does not establish whether the exchange ran once.
    [BackendProofs] binds frozen-account checks and
    complete-response retention to the public backend operations.
    Discovered profile namespaces derive from the native SHA-256 hex digest of
    the admitted account connection. Construction establishes their format;
    materialization consumes it directly. User-configured names still require
    a matching discovered account connection before they can select credentials.
    The account transport can omit output from its terminal response after
    reporting finalized items separately. Those items must survive until that
    terminal response, in provider index order, including their coordinates.
    A finalized coordinate names one item; conflicting contents cannot authorize
    a completed answer. The stream keeps provider order through every event,
    including a repeated finalized coordinate. Reconstructed terminal output and
    its coordinate list come from that same retained sequence, so translation can consume them
    without revalidating the sequence constructed by the stream.
    External JSON integer fields denote mathematical values:
    decimal or exponent notation does not select another coordinate, token count
    or advertised model budget. Admission retains the declared field ranges.
    The shared exact integer construction supplies canonical naturals before
    internal indexing and budget calculations; host floating-point conversion
    cannot establish those bounds.
    Transient stream items do not acquire durable-output authority merely by
    arriving before a terminal response.
    SSE framing dispatches only complete events and discards unfinished data at
    EOF, as required by the HTML event-stream protocol. Provider completion still
    requires its own terminal response; framing does not invent that completion.
    An HTTP context-limit failure permits automatic recovery only before output;
    replaying a request after visible output would
    execute the same turn twice.

    Audio callers await context delivery and session-stop completion. A boolean
    reporting a local session-map entry adds no separate completion evidence.
    Single-connection admission returns the identity used for authorization;
    display capabilities belong to the advertised connection list. Physical
    audio close only releases its session. The ordered following emission owns
    the closed event, so cleanup does not need another event payload.

    Provider support admits image capability before selecting the echo or
    network transport. Rechecking the unchanged echo history cannot establish
    another capability. Independent compaction uses the common request type's
    absence of tool authority; empty tool lists and sampling placeholders do
    not strengthen that construction. A native replacement's format and a
    changed consumer's boolean already select their continuations, without
    unused action labels. Web invocation owns its request ticket; the history
    projection does not need an unread ticket copy.

    These are requirements on the extracted decisions from supplied observations.
    Issuer signature verification, atomic credential replacement, live account
    eligibility and physical HTTP execution remain host boundaries. *)
From Selvedge.Adapters Require Import AccountsProofs BackendProofs.
Export AccountsProofs(public_refresh_identity_binds_each_principal_field,
 public_refresh_cannot_replace_the_request_identity,
 public_refresh_keeps_the_same_request_identity,
 public_valid_callback_authorizes_its_client,
 public_credential_requires_unambiguous_identity,
 public_audio_credential_rejects_another_client,
 public_malformed_encoded_cache_is_disposable,
 public_unparseable_authentication_text_is_sanitized).
Export BackendProofs(public_frozen_account_rejects_another_identity,
 public_matching_account_is_usable,
 public_nonempty_environment_credential_is_admitted,
 public_empty_environment_credential_fails_before_io,
 public_finalized_output_retains_every_item,
 public_stream_step_preserves_provider_order,
 public_conflicting_finalized_output_fails,
 public_completed_response_preserves_durable_output,
 public_completed_response_retains_finalized_output,
 public_nonterminal_events_cannot_release_durable_output,
 public_http_context_limit_recovers_before_output,
 independent_requests_have_no_tool_authority).

(** * Exact retry decisions precede timer conversion

    A Retry-After header specifies a minimum wait. Truncation can violate that
    minimum, while rounding before admission can hide an exact value above a
    configured cap. Backend and evaluator policies consume the same exact
    parser, retain their own attempt and delay limits, and convert an admitted
    delay to its first permissible integral millisecond. Evaluator configuration
    admits its attempt limit once. The request loop checks its current attempt
    before dispatch; response and network stages consume that admitted attempt.
    Rechecking the configuration and cursor at every private stage adds no
    protection against an external retry response.
    [RetryAfterProofs] supplies the common arithmetic; [RetryExecutionProofs]
    binds it to the actual public retry plans. A checked plan does not establish
    when a physical timer or remote server acts. *)
From Selvedge.Adapters Require Import RetryAfterProofs RetryExecutionProofs.
Export RetryAfterProofs(integer_timer_does_not_precede_exact_delay,
 integer_timer_is_the_first_admissible_millisecond,
 integer_timer_preserves_an_exact_integer_cap).
Export RetryExecutionProofs(public_backend_timer_respects_header_and_budget,
 public_evaluator_timer_respects_header_and_fixed_budget).

(** * Argument transport preserves the tool owner's input

    Ordinary host objects would erase repeated members and numeric spellings
    before hooks and final tool admission could inspect them. [CallWire] retains
    argument text derived from the ordered AST. [EncodedObject] admits that text
    with the original logical callback nesting budget; [TextJsonRoundtrip]
    establishes member-preserving serialization for legal values within that
    budget. These constructions keep one argument authority through transport.

    A before-tool hook may repair a call. [HooksProofs] therefore connects its
    rewrite to the same call identity and subsequent final admission, while
    [PluginAuthorityProofs] retains the external MCP server's own schema boundary.
    A media result reserves its correlated RPC identity before materialization
    and settles that reservation once. The public media plan admits every part
    within one byte budget. JavaScript materialization and the physical protocol
    remain separate checks.

    A plugin notification attempts to enqueue one already committed event.
    Admission decides whether capacity remains and the resulting byte total;
    it does not rewrite the event. The host can therefore enqueue that original
    event directly after acceptance, without transporting a second copy inside
    a singleton list. *)
From Selvedge.Foundation Require Import CallWire.
From Selvedge.Programming Require Import EncodedObject.
From Selvedge.Foundation Require Import TextJsonRoundtrip.
Export CallWire(callback_argument_nesting, admit_at, decode_at, encode, external).
Export EncodedObject.Admitted(parsed_members, construct_members).
Export TextJsonRoundtrip(parse_render_members_at).
From Selvedge.Kernel Require Import HooksProofs PluginAuthorityProofs.
Export HooksProofs(a_before_rewrite_preserves_call_identity_and_the_remaining_chain,
 final_invalid_arguments_never_dispatch).
Export PluginAuthorityProofs(mcp_object_arguments_reach_the_server_contract,
 extension_arguments_use_the_declared_fragment, admitted_mcp_calls_dispatch).
From Selvedge.Adapters Require Import ApiProofs RpcProofs.
Export RpcProofs(response_consumes_exactly_its_correlated_identity,
 materialization_reserves_and_removes_its_pending_identity).
Export ApiProofs(public_issued_media_rpc_result_reserves_before_materialization,
 public_reserved_rpc_materialization_resolves_once,
 public_mcp_media_plan_admits_every_part_within_one_byte_budget).

(** * Images retain portable identity and content order

    A mutable workspace path or provider upload identifier cannot identify the
    same image across later requests and replay. Durable content retains image
    references in their original order. [ConversationProofs] owns that ordering;
    [ContextSelectionProofs] retains original images through summary selection.
    [CompactionPlanProofs] selects portable rebuilding when images are present,
    avoiding a provider continuation that could copy transport byte strings back
    into durable history.

    [ProviderCompactionProofs] connects typed input-image classification to
    the account estimate and prevents a text-only fallback for opaque content.
    A reasoning or compaction input item carries its nonempty encrypted
    continuation. Resource semantics belongs to those input positions, not
    similarly named fields anywhere in a JSON tree. The resident discovery tool
    currently presents external tools through deferred parameter declarations;
    classification does not need a guarantee over arbitrary Schema metadata.
    The byte estimate still includes the entire encoded request.
    The estimate supports admission; it is not an exact provider token count.
    Physical preparation admits the complete request's bytes before measurement.
    The request encoder establishes the object's structure, which measurement
    consumes directly instead of admitting that private structure again.
    Measurement therefore selects the account image estimate or provider meter;
    an over-budget request cannot become admissible through a fabricated token
    count. A readable request may use the existing byte bound after an explicit
    unsupported meter-route response.
    Admission depends on the consumer scope and token bound; a label naming
    the measurement source adds no admission or scheduling evidence.
    Vault bytes, digest checks, image decoding, model capabilities and transport
    materialization are physical observations rather than consequences of these
    pure proofs. *)
From Selvedge.Kernel Require Import ConversationProofs ContextSelectionProofs CompactionPlanProofs.
Export ConversationProofs(user_images_keep_their_place_between_the_original_text_parts).
Export ContextSelectionProofs(selecting_a_summary_preserves_each_original_image).
Export CompactionPlanProofs(images_force_portable_rebuilding).
From Selvedge.Adapters Require Import ProviderCompactionProofs.
Export ProviderCompactionProofs(public_account_image_requests_use_the_complete_request_estimate,
 public_other_requests_use_provider_measurement,
 public_image_requests_never_use_textual_fallback,
 public_encrypted_requests_never_use_textual_fallback).

Import ListNotations.
Open Scope string_scope.

(** * Authority follows the shared request construction

    Adding a compatible backend must not give independent title, board,
    approval or compaction requests tool authority. The indexed request type
    and its common encoder already own that guarantee. These requirements
    connect it to the actual [Api.call "backend.request"] entry, including
    preparation and successful admission. No provider registration adds a
    separate authority proof. *)

Lemma removing_another_field_keeps_lookup : forall fields selected removed,
 selected <> removed ->
 Json.lookup selected (Json.remove_field removed fields) = Json.lookup selected fields.
Proof.
 intros fields; induction fields as [|[key value] rest IH]; intros selected removed Different.
 - reflexivity.
 - cbn [Json.remove_field Json.lookup].
   destruct (String.eqb removed key) eqn:Removed.
   + apply String.eqb_eq in Removed; subst key.
     assert (Kept : String.eqb selected removed = false) by (now apply String.eqb_neq).
     rewrite Kept; apply IH; exact Different.
   + cbn [Json.lookup]; destruct (String.eqb selected key); [reflexivity|].
     apply IH; exact Different.
Qed.

Lemma updating_another_field_keeps_value : forall source selected updated value,
 selected <> updated ->
 get (set source updated value) selected = get source selected.
Proof.
 intros source selected updated value Different.
 assert (Kept : String.eqb selected updated = false) by (now apply String.eqb_neq).
 unfold get, set, Json.field, Json.set_field; cbn [Json.lookup].
 rewrite Kept, removing_another_field_keeps_lookup by exact Different.
 destruct source; reflexivity.
Qed.

Lemma preparation_keeps_the_request_kind : forall effect,
 str (BackendRequests.independent_effect effect) "kind" = str effect "kind".
Proof.
 intro effect; unfold BackendRequests.independent_effect.
 destruct (String.eqb (str effect "kind") "context_compaction").
 - unfold str; rewrite updating_another_field_keeps_value by discriminate; reflexivity.
 - destruct (existsb (String.eqb (str effect "kind")) ["task_title"; "board_text"]).
   + unfold BackendRequests.independent_task_text, str.
     repeat rewrite updating_another_field_keeps_value by discriminate; reflexivity.
   + destruct (String.eqb (str effect "kind") "approval"); [|reflexivity].
     unfold str; rewrite updating_another_field_keeps_value by discriminate; reflexivity.
Qed.

Lemma independent_request_preparation_succeeds : forall effect,
 independent_kind (str effect "kind") = true ->
 BackendRequests.prepare_effect effect = Accepted (BackendRequests.independent_effect effect).
Proof.
 intros effect Independent; unfold BackendRequests.prepare_effect.
 rewrite preparation_keeps_the_request_kind, Independent; reflexivity.
Qed.

(** The public dispatcher delivers the constructed request whenever its input
    and reasoning admissions succeed. It cannot reject such an admitted request
    merely to preserve the authority requirement. The premises describe the
    existing admission boundaries; this theorem does not establish admission
    for arbitrary external JSON. [tests/title-request-settings.test.mjs] also
    exercises successful admission and completed delivery through the service. *)
Theorem admitted_independent_request_reaches_the_public_output : forall source input reasoning,
 independent_kind (str (get source "effect") "kind") = true ->
 BackendRequests.effect_input ContextSelection.target_messages
   (BackendRequests.independent_effect (get source "effect")) (get source "profile") = Accepted input ->
 BackendRequests.admit_reasoning
   (BackendRequests.independent_effect (get source "effect")) (get source "profile") = Accepted reasoning ->
 Api.call "backend.request" source = success
   (BackendRequests.encode_request (get source "profile")
     (BackendRequests.construct_request
       (BackendRequests.independent_effect (get source "effect")) input reasoning
       (BackendRequests.output_limit (BackendRequests.independent_effect (get source "effect"))))).
Proof.
 intros source input reasoning Independent Input Reasoning.
 change (Api.call "backend.request" source)
   with (BackendRequests.request ContextSelection.target_messages source).
 unfold BackendRequests.request.
 rewrite independent_request_preparation_succeeds by exact Independent.
 cbn [bind]; rewrite Input; cbn [bind]; rewrite Reasoning; reflexivity.
Qed.

Theorem accepted_independent_public_request_has_no_tool_authority : forall source body,
 independent_kind (str (get source "effect") "kind") = true ->
 Api.call "backend.request" source = success body ->
 get body "tools" = JArray [] /\ get body "tool_choice" = JString "none".
Proof.
 intros source body Independent Accepted.
 change (BackendRequests.request ContextSelection.target_messages source = success body) in Accepted.
 unfold BackendRequests.request in Accepted.
 rewrite independent_request_preparation_succeeds in Accepted by exact Independent.
 cbn [bind] in Accepted.
 destruct (BackendRequests.effect_input ContextSelection.target_messages
   (BackendRequests.independent_effect (get source "effect")) (get source "profile"))
   as [input|code message] eqn:Input; cbn [bind render_outcome] in Accepted; [|discriminate].
 destruct (BackendRequests.admit_reasoning
   (BackendRequests.independent_effect (get source "effect")) (get source "profile"))
   as [reasoning|code message] eqn:Reasoning; cbn [bind render_outcome] in Accepted; [|discriminate].
 injection Accepted as Encoded; subst body.
 generalize (BackendRequests.construct_request
   (BackendRequests.independent_effect (get source "effect")) input reasoning
   (BackendRequests.output_limit (BackendRequests.independent_effect (get source "effect")))).
 rewrite preparation_keeps_the_request_kind, Independent.
 intro request; apply BackendProofs.independent_requests_have_no_tool_authority.
Qed.

(** * Retained Web requests and continuation

    Reconnecting an observer may reuse a retained request only when its body
    and connection still agree. A receipt is bound to the actual Task,
    connection and response. Continuing after tools requires the complete,
    uniquely matched result batch; a partial batch cannot stand for completion.
    Detaching an observer leaves retained work available, while explicit
    cancellation has its own state and connection conditions. Cancellation
    selects at most one retained request: the latest for the matching owner and
    ticket. An optional record represents that selection directly;
    resetting a whole session remains a separate operation over its requests.
    Resource admission follows the fields used for settlement and continuation: response identity,
    model, predecessor, status, output and tool-call correlation. Creation time,
    usage estimates and a tool item's separate provider identifier have no role
    in those decisions. They remain in the retained response when supplied, but
    their presence or format cannot block otherwise usable output.

    A Web request consumes the Task's frozen catalog. Configuration admission
    already establishes distinct tool names and object schemas. Native and
    plugin names use the admitted identifier grammar, and MCP names are
    normalized at discovery. The Web encoder preserves those declarations and
    checks its own length limit, because combined MCP server/tool names are
    not otherwise limited to that transport's maximum.

    These contracts constrain the interpreters used by the declared [web.*]
    operations. HTTP delivery and durable store acknowledgements remain host
    observations. *)
From Selvedge.Adapters Require WebProofs.
Export WebProofs(existing_request_reuse_requires_body_and_connection,
  receipt_is_bound_to_actual_task_connection_and_response,
  tool_continuation_requires_complete_unique_result_batch,
  cancelled_request_cannot_reuse_a_different_connection).
