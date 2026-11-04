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
Export ApiProofs(public_configured_connection_grants_preserve_authority).

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
    world unchanged and issuing no effects in either case. A retry needs no
    fresh execution capacity or currently available managed workspace.
    [public_forget_removes_settled_receipt] requires forgetting a settled
    receipt to remove it without moving the identity supply backward. Gaps in
    that supply do not recycle earlier operation identities.
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
    observations already established by its owner.
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

From Selvedge.Features Require RemoteProofs RemoteEntryProofs.
Export RemoteProofs(check_satisfies_complete_access_contract,
  authorize_satisfies_complete_request_contract,
  revoked_remote_controller_cannot_replay, remote_replay_has_no_effect,
  prepared_remote_permissions_are_required, oversized_remote_reply_rolls_back,
  remote_receipt_preserves_authority,
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
    [revoked_remote_controller_cannot_replay] prevents retained results from
    bypassing revocation. [remote_replay_has_no_effect] avoids repeated execution.
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
    Queries preserve the world and do not apply prepared configuration.
    [current_control_grant_executes_actual_remote_stop] additionally proves a
    positive entry case: with a single running Task, current control permission,
    a fresh request and receipt capacity, the actual packet executor stops that
    Task and retains the reply. The general access contracts and this particular
    execution case have different scopes. Connection jobs and remote commands
    reuse the existing scheduler. *)

From Selvedge.Host Require RemoteTransportProofs
  RemoteConnectorSessionProofs RemoteRelaySessionProofs.
Export RemoteConnectorSession(retirement_discards_session_and_preserves_notice_cursor).
Export RemoteTransportProofs(authorization_retry_decreases,
  rejected_identity_ignores_async_observations,
  retry_observation_before_deadline_does_not_connect).
Export RemoteConnectorSessionProofs(subscription_capture_records_the_current_notice_cutoff,
  delivered_notice_is_queued_and_beyond_the_current_cutoff,
  every_observed_notice_advances_the_cursor,
  frame_observation_emits_only_frame_actions,
  capture_observations_emit_only_capture_actions,
  delivery_observation_emits_only_delivery_actions,
  enqueue_observation_emits_only_queue_actions).
Export RemoteRelaySessionProofs(successful_consumption_removes_ticket,
  host_frame_admission_matches_negotiation,
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

    Owners need the current connection status to diagnose availability.
    Recovery depends on actual probes, socket traffic and cessation after
    rejected authentication; a separate history of intermediate status
    notifications adds no delivery or recovery guarantee. Relay refusal retains
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
    work and pairing code by entering the offline phase, while preserving the
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
    subscription and later notices. Transport replacement retains the notice
    sequence. Unsubscribe, resubscribe and delayed queue completion therefore
    share one cursor owner rather than separate JavaScript tests.
    The cursor orders notices relative to a subscription cutoff; it is not a
    count of delivered messages. Strict advancement is sufficient without
    requiring adjacent cursor values.

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
