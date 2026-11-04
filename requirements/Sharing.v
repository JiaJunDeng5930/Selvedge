(** * Delegated access and remote transport

    Sharing a Project grants a particular connection access to that Project;
    remote control grants a revocable controller selected operations. Neither
    grant follows merely from a conversation, matching path or live socket. *)

From Selvedge.Features Require SharingProofs.
Export SharingProofs(connection_without_project_grant_cannot_execute,
  accepted_public_exec_emits_frozen_job, query_cannot_reveal_foreign_operation,
  retained_public_exec_satisfies_retry_contract,
  public_forget_removes_settled_receipt,
  recovery_never_replays_running_job).
From Selvedge.Adapters Require ApiProofs.
Export ApiProofs(public_configured_connection_grants_preserve_authority,
  public_rpc_reservation_matches_available_capacity).

(** ** Connection work captures an explicit Project grant

    The MCP connection has a lifetime across conversations. Its dedicated local
    credential selects configured Project membership; it does not expose the
    administrative command API or permit arbitrary workspace and sandbox
    overrides. [connection_without_project_grant_cannot_execute] and
    [accepted_public_exec_emits_frozen_job] constrain the actual feature entry.
    The admitted job captures current Project roots and the restricted sandbox
    before process launch. Sharing one Project does not share the whole host.

    Request identities and retained results support retry after a lost response.
    A retained request belongs to the connection and request ID used to find it;
    comparing that connection again supplies no additional authority. The
    requested Project and arguments must still match the retained intent.
    [retained_public_exec_satisfies_retry_contract] constrains the actual exec
    entry to return the retained receipt or refuse changed intent, leaving the
    world unchanged and issuing no effects in either case. The current Project
    may have been deleted or its primary root changed after the original job.
    A retry uses that job's frozen receipt and needs no current Project, primary
    root, fresh execution capacity or currently available managed workspace.
    [public_forget_removes_settled_receipt] requires forgetting a settled
    receipt to acknowledge its removal without moving the identity supply
    backward or issuing work. Gaps in that supply do not recycle earlier
    operation identities. The caller already supplies the receipt identity;
    successful forgetting needs only the standard command acknowledgement.
    [recovery_never_replays_running_job] marks uncertain work instead of launching
    it again; cancellation requests a physical stop without undoing writes.
    Project connection authority remains distinct from browser, CLI and remote
    controller credentials.

    [query_cannot_reveal_foreign_operation] requires an ungranted query to fail
    without disclosing private world data. Its diagnostic may depend on the
    public request but is chosen independently of that world; neither an error
    identifier's spelling nor fixed prose is part of the access guarantee.

    Configuration admission already establishes connection identities, project
    membership and sandbox values. Projecting those admitted values into native
    grants preserves that authority without admitting the configuration again;
    [public_configured_connection_grants_preserve_authority] binds this projection
    to the actual adapter entry without requiring grant-list order. The public
    native command still admits independently supplied grant requests.
    Job settlement keeps its completion and scheduling decisions; its host
    caller needs the commit acknowledgement, not another accepted marker.

    The standalone package and service use the same credential interpreter and
    filesystem primitives. Secrets, token bytes and tunnel identities remain
    outside semantic inputs and the journal. Installed clients read their owned
    private configuration; environment inheritance is not a portable package
    contract. Local stdio and deployed tunnel packaging choose their actual
    route without embedding credentials or a fabricated registered application
    identity. The tunnel launcher forwards profile names and tunnel identifiers
    unchanged as arguments to the official client, which owns their validation
    and profile-file selection. A second spelling or length policy here would
    reject values the actual client supports without adding local authority.
    The launcher still owns its supported options and propagates client failure.
    The shared bounded descriptor reader establishes file kind,
    no-follow access and size; plugin admission adds the private file's owner,
    permissions and configuration fields. Each boundary consumes the
    observations already established by its owner. The descriptor supplies
    [fs.Stats.mode] as a filesystem bit field; a connection identity's numerical
    bounds do not protect the credential.
    See https://nodejs.org/api/fs.html#statsmode .
    Published credentials must be owner-readable and deny group/other access.
    Loading does not require owner write permission. Acceptance retains the
    read permission check because a privileged test runner could otherwise
    read an owner-unreadable file and conceal a failed ordinary installation.

    Identity loading preserves safe descriptor failures without assigning
    another diagnostic category. Only a missing identity permits initial
    creation. Parsing failures still need redaction because their diagnostics
    can contain credential bytes; descriptor failures contain no such bytes.

    Client settings retain the admitted authorization header: repeating token
    admission for each request adds no new authority. Setup persists the same
    validated raw credential in the private connection file, while runtime
    requests use the header established when that configuration was loaded.
    Repeating setup must fail while the saved credential remains usable.
    Reporting that refusal needs no separate machine-readable error category.

    Packaging exports an explicit set of shipped files, keeping private
    connection data outside the package. Its output may be a new directory
    within the source tree because that directory cannot enter the fixed input
    set. Exclusive directory creation preserves existing deployments. Explicit
    relative paths use the process working directory, as ordinary filesystem
    paths do. Real tunnel and filesystem isolation remain physical checks. *)

(** ** MCP discovery completes within one request deadline

    Discovering a tool catalog is one operation even when the server paginates
    it. A server can keep returning empty pages with different cursors, so tool
    count, catalog bytes and repeated-cursor detection do not bound discovery.
    [host/mcp.mjs] uses the configured RPC timeout for the complete discovery
    and passes the same cancellation signal to every page request. The existing
    [public_rpc_reservation_matches_available_capacity] contract excludes a new
    request after cancellation; an outstanding request uses the shared RPC
    retirement path. Timer delivery and pipe cancellation remain physical
    runtime obligations.

    The MCP pagination protocol gives the server control of page size and makes
    cursors opaque. Only the current cursor is needed to request the next page;
    retaining every earlier cursor adds unbounded state without guaranteeing
    completion. An empty string is a cursor, while an absent cursor ends the
    catalog. The catalog's existing tool count and byte limits remain in force.
    See https://modelcontextprotocol.io/specification/2025-11-25/server/utilities/pagination.

    Several list-changed notifications received before a queued query starts
    require only that one query of the current catalog. The service keeps at
    most one queued refresh action per configured server in a map. It removes
    that action when the query starts, allowing a change during the query to
    schedule one subsequent refresh. This bounds waiting work without losing
    changes that the running query may not have observed. *)

From Selvedge.Features Require RemoteProofs RemoteEntryProofs.
Export RemoteProofs(check_satisfies_complete_access_contract,
  authorize_satisfies_complete_request_contract,
  revoked_remote_controller_cannot_replay, remote_replay_has_no_effect,
  prepared_remote_permissions_are_required, oversized_remote_reply_rolls_back,
  remote_receipt_preserves_authority, remote_query_is_read_only,
  public_grant_replaces_authority_and_clears_old_receipts,
  local_administration_never_reuses_a_generation,
  delegated_remote_administration_is_denied).
Export RemoteEntryProofs(current_control_grant_executes_actual_remote_stop).

(** ** Revocation precedes retained-result access

    A remote receipt is reusable only under current authority. The independent
    access and request contracts in [RemoteProofs] derive fresh admission and
    replay from grants, componentwise permissions, bounds and stored receipts.
    Refusal requires a failed admission condition. Diagnostic identifiers,
    wording and the choice among simultaneous failures do not determine access
    or replay, so these contracts leave them unspecified.
    [delegated_remote_administration_is_denied] additionally requires delegated
    administration to leave the world unchanged and issue no effects. Its
    refusal diagnostic is independent of private world data, without fixing
    the diagnostic's identifier or prose.
    Probe success already admits preparation or capture; an additional admitted
    marker supplies no consumed information. A retained-result probe still
    distinguishes replay and carries the original reply for its caller.
    Admission after asynchronous preparation uses the current world. Within
    that pure transition the request and receipt cannot change; checking the
    prepared command's permissions suffices without admitting that packet again.
    [prepared_remote_permissions_are_required] prevents preparation from using
    permissions absent from the current grant through the actual executor.
    [revoked_remote_controller_cannot_replay] requires the actual local command
    to acknowledge revocation, prevent retained-result access and issue no
    work. Revocation removes future access without undoing accepted work.
    Echoing the controller identity or a second revoked flag adds no information
    to command success. [remote_replay_has_no_effect] avoids repeated execution.
    Oversized complete replies roll back instead of partly committing a result.

    Grant generations are monotone; a later grant cannot authorize an earlier
    ticket. The public grant contract requires the requested authority, a fresh
    epoch, removal of that controller's old receipts and preservation of other
    controllers. Contiguous epoch allocation and grant-list placement do not
    affect authorization and need no separate guarantee.
    [remote_receipt_preserves_authority] keeps each controller's selected grant
    and a nondecreasing epoch supply when a command receipt is recorded.
    Authorization consumes that mapping and fresh identities, independently of
    the grant list's order or gaps in the unused identity supply.
    Queries preserve the world, do not apply prepared configuration and do not
    schedule work. [remote_query_is_read_only] constrains those results at the
    executor entry. That entry separates queries before mutation scheduling;
    repeating the query test in the mutation branch adds no guarantee. Remote
    admission excludes local speech-transcript commands, so mutation scheduling
    needs only successful completion and the deliberate idle-creation exception.
    [current_control_grant_executes_actual_remote_stop] additionally proves a
    positive entry case: with a single running Task, current control permission,
    a fresh request and receipt capacity, the actual packet executor stops that
    Task, acknowledges success and retains the original reply. The controller
    supplied the target Task identity, so echoing that identity adds no required
    result. The general access contracts and this particular execution case
    have different scopes. Connection jobs and remote commands
    reuse the existing scheduler. *)

From Selvedge.Host Require RemoteTransportProofs
  RemoteConnectorSessionProofs RemoteRelaySessionProofs.
Export RemoteConnectorSession(retirement_discards_session_without_rewinding_notice_cursor).
Export RemoteTransportProofs(authorization_retry_decreases,
  rejected_identity_ignores_async_observations,
  current_retry_rearms_or_connects).
Export RemoteConnectorSessionProofs(subscription_capture_records_the_current_notice_cutoff,
  delivered_notice_is_queued_and_beyond_the_current_cutoff,
  every_observed_notice_advances_the_cursor,
  frame_observation_emits_only_frame_actions,
  capture_observations_emit_only_capture_actions,
  delivery_observation_emits_only_delivery_actions,
  enqueue_observation_emits_only_queue_actions).
Export RemoteRelaySessionProofs(successful_consumption_removes_ticket,
  host_frame_admission_matches_negotiation,
  retirement_notifies_exactly_the_current_controller_host,
  delivery_admits_exactly_current_authority,
  ticket_issuance_admits_exactly_current_bounded_authority,
  issued_tickets_respect_capacity,
  ticket_consumption_admits_exactly_current_bounded_authority,
  replaced_hash_cannot_install_pairing).

(** ** The relay and connector speak the same admitted protocol

    The host and relay use the same extracted frame predicates. Controller IDs,
    receipt request IDs, epochs and enrollment credentials have their own
    accepted languages. Only declared bounded envelope integers are materialized
    as JavaScript numbers; opaque command and event JSON retains its numeric
    tokens. An unrelated header limit cannot silently narrow enrollment.
    The relay does not consume the command's [op] field. Native command
    admission already checks the full command before file observations, so an
    additional transport rule for that field adds no execution authority.

    Session transitions own admission of their actual frames. An HTTP request
    is admitted from its supplied observation; facts needed across socket
    hibernation instead remain in the session attachment. This distinction
    keeps retained state tied to a real lifetime.
    Admitted wire values already have their shared declaration's type;
    projecting and reconstructing the same value supplies no new admission.
    Host-frame admission is a query over the negotiated session. Before hello,
    only the versioned hello frame is eligible; afterward the admitted host
    frames may proceed. [host_frame_admission_matches_negotiation] constrains
    the predicate used by that query, which needs no state-transition wrapper.

    Closed transport states distinguish probing, negotiation, online operation,
    scheduled retry and rejected identity. Randomness, status and clock values
    are observations, not host permission to reconnect. Authorization checks
    retain their bounded sequence comparison; capture requires equality with
    the current committed sequence in that observation.

    A current retry must keep a future check scheduled until its deadline, then
    start a connection with a fresh generation. The host's one-shot timer clears
    its handle before reading [Date.now], whose wall clock can move backward
    after system clock adjustment. Requiring no actions before the deadline
    would lose that retry. [current_retry_rearms_or_connects] instead constrains
    the existing timer or connection action, without fixing the whole internal
    state. Clock behavior: https://www.w3.org/TR/hr-time-3/#clocks .

    Owners need the current connection status to diagnose availability.
    The query uses the installed transport phase and its socket's current
    controllers. Keeping another status record would require separate updates
    after negotiation, replacement and controller closure without adding an
    observation. Phase-marking actions that only update that copy are likewise
    unnecessary. Rejected authentication still removes the notice listener;
    that action releases a physical subscription.
    Recovery depends on actual probes, socket traffic and cessation after
    rejected authentication; a separate history of intermediate status
    notifications adds no delivery or recovery guarantee. The native WebSocket
    client's error event is followed by close, which already reports that
    failure; an empty error listener adds no observation or recovery action.
    See https://websockets.spec.whatwg.org/#feedback-from-the-protocol .
    Relay refusal retains
    the protocol's HTTP and WebSocket status semantics, without fixing an
    application diagnostic's spelling when no client consumes it.
    Rejected authentication remains quiescent under background observations;
    only an explicit owner action can resume it. Its generation must stay
    nondecreasing so a future session cannot reuse a retired identity, but no
    pending physical work requires that private counter to remain fixed.

    Each capture attempt retains only its pending check stage across native
    observations. Capture, denial and disconnection end the awaited invocation;
    they do not create a retained authorization state. A required disconnection
    constrains the action that retires the transport, not the abandoned check
    stage or intermediate session that its consumer immediately discards.
    Local pairing starts with an explicit deadline and clearing ends it
    unconditionally. Only observing, receiving or consuming a pending request
    needs a clock reading to decide whether that deadline has passed.

    New semantic state is installed before sending or accepting sockets. A
    successfully consumed ticket is removed before accepting its connection,
    so the credential cannot authorize another one. Failed admission issues no
    authority and need not spend an otherwise valid ticket. Issuance already
    removes expired tickets; grant updates remove revoked tickets.
    Credential admission returns an admitted credential or the existing
    rejection action; another accepted flag carries no additional result.
    After asynchronous hashing, the relay rereads the current attachment
    instead of publishing an earlier snapshot.
    Pending jobs determine connector queue counts and bytes; no independent
    counter can drift after revocation or a delayed completion.
    A grant observation filters the connector's live connections directly;
    retaining that entire snapshot supplies no later decision. Native commands
    and captures still check current journal authority, while the relay keeps
    the grants it actually uses for tickets and forwarding. The installed
    connector phase also supplies readiness to its physical interpreter;
    a second socket readiness flag would duplicate that state.
    The connector synchronously clears its physical socket owner before closing
    that socket. Object identity therefore excludes old physical callbacks,
    including pairing callbacks, without a second native generation query.
    Native clock, probe and queue observations still carry their generations
    for semantic admission. Connector start, pair and close request their
    physical effects synchronously; their return does not promise delivery.

    The connector interprets each observation's possible actions. The actual
    transition's frame, capture, delivery and enqueue contracts establish these
    ranges; the native consumers narrow the generated union accordingly.
    Impossible internal action categories need no second runtime refusal.
    Actions request work from their interpreter; state-only updates need no
    separate acknowledgement. Retirement removes the live session, its queued
    work and pairing code by entering the offline phase, without rewinding the
    notice cursor across a later connection. Its caller consumes the updated
    state without a retirement acknowledgement or prescribed retired generation.
    Repeating already installed authority in a
    request action adds no authorization check. Immediate transport effects
    likewise use the installed session, while asynchronous callbacks retain
    their generation so replacement can invalidate them.
    Relay liveness and delivery are queries over the current attachment, not
    events that change it. [delivery_admits_exactly_current_authority] constrains
    the actual delivery predicate: an available host, its current generation
    and an exact current grant are all necessary and sufficient.
    That predicate also selects the controller attachment constructor; repeating
    its role test in the host supplies no additional authority.
    [retirement_notifies_exactly_the_current_controller_host] connects controller
    retirement to its current host and exact connection identity. The relay
    retains the host observed by that synchronous transition for notification;
    no asynchronous operation can replace it before the send. Repeating the host
    lookup and silently skipping the required notification supplies no new
    admission. A physical send failure still retires that failed transport.
    Durable Objects block new events during synchronous JavaScript execution:
    https://developers.cloudflare.com/durable-objects/best-practices/rules-of-durable-objects/ .
    Ticket issuance and consumption also require a current grant and unexpired
    credential. A successful consumption carries the selected ticket's authority
    to connection installation. The digest and expiry have completed their
    admission role and need not cross that boundary again. Failure reasons
    belong only to rejected results. Their
    complete admission contracts preserve successful access
    within the attachment and live-connection limits, while
    [issued_tickets_respect_capacity] bounds the actual retained ticket list.

    [subscription_capture_records_the_current_notice_cutoff] and
    [delivered_notice_is_queued_and_beyond_the_current_cutoff] connect snapshot
    subscription and later notices. Unsubscribe, resubscribe and delayed queue completion
    share one cursor owner rather than separate JavaScript tests.
    The cursor orders notices relative to a subscription cutoff; it is not a
    count of delivered messages. Strict advancement is sufficient without
    requiring adjacent cursor values or an unchanged cursor during retirement.

    The journal remains command-idempotency authority; the relay does not keep
    another durable command database. Socket handles, cryptography, atomic
    attachment publication and network ordering remain host responsibilities.
    The deployed Workers compatibility contract already answers peer close
    frames. Closing again adds no transport guarantee and only creates a need
    to normalize reserved close-event codes. The relay still retires its
    attachment and notifies or closes affected peers. This runtime contract is
    enabled by default for compatibility dates from 2026-04-07:
    https://developers.cloudflare.com/durable-objects/best-practices/websockets/ .

    Opening the intended loopback URL establishes an HttpOnly browser session so
    product JavaScript need not handle its secret. Origin and host admission
    remain necessary. The host compares credentials as byte buffers and reports
    that authorization result; credential shape metadata adds no independent
    authority. The expected Host comes from the actual listening address.
    CLI Bearer credentials and plugin grants retain their
    separate lifetimes. Persisted protocol compatibility identifies replayable
    work. Only the current persisted formats are accepted, without manufacturing
    authority from older attachment or receipt shapes. *)
