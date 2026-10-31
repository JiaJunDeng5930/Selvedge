(** * Delegated access and remote transport

    Sharing a Project grants a particular connection access to that Project;
    remote control grants a revocable controller selected operations. Neither
    grant follows merely from a conversation, matching path or live socket. *)

From Selvedge.Features Require SharingProofs.
Export SharingProofs(connection_without_project_grant_cannot_execute,
  accepted_public_exec_emits_frozen_job, recovery_never_replays_running_job).

(** ** Connection work captures an explicit Project grant

    The MCP connection has a lifetime across conversations. Its dedicated local
    credential selects configured Project membership; it does not expose the
    administrative command API or permit arbitrary workspace and sandbox
    overrides. [connection_without_project_grant_cannot_execute] and
    [accepted_public_exec_emits_frozen_job] constrain the actual feature entry.
    The admitted job captures current Project roots and the restricted sandbox
    before process launch. Sharing one Project does not share the whole host.

    Request identities and retained results support retry after a lost response.
    Forgetting a settled receipt does not recycle its operation identity.
    [recovery_never_replays_running_job] marks uncertain work instead of launching
    it again; cancellation requests a physical stop without undoing writes.
    Project connection authority remains distinct from browser, CLI and remote
    controller credentials.

    The standalone package and service use the same credential interpreter and
    filesystem primitives. Secrets, token bytes and tunnel identities remain
    outside semantic inputs and the journal. Installed clients read their owned
    private configuration; environment inheritance is not a portable package
    contract. Local stdio and deployed tunnel packaging choose their actual
    route without embedding credentials or a fabricated registered application
    identity. Real tunnel and filesystem isolation remain physical checks. *)

From Selvedge.Features Require RemoteProofs RemoteEntryProofs.
Export RemoteProofs(check_satisfies_complete_access_contract,
  authorize_satisfies_complete_request_contract,
  revoked_remote_controller_cannot_replay, remote_replay_has_no_effect,
  oversized_remote_reply_rolls_back).
Export RemoteEntryProofs(current_control_grant_executes_actual_remote_stop).

(** ** Revocation precedes retained-result access

    A remote receipt is reusable only under current authority. The independent
    access and request contracts in [RemoteProofs] derive fresh admission and
    replay from grants, componentwise permissions, bounds and stored receipts.
    [revoked_remote_controller_cannot_replay] prevents retained results from
    bypassing revocation. [remote_replay_has_no_effect] avoids repeated execution.
    Oversized complete replies roll back instead of partly committing a result.

    Grant generations are monotone; a later grant cannot authorize an earlier
    ticket. Queries preserve the world and do not apply prepared configuration.
    [current_control_grant_executes_actual_remote_stop] additionally proves a
    positive entry case: with a single running Task, current control permission,
    a fresh request and receipt capacity, the actual packet executor stops that
    Task and retains the reply. The general access contracts and this particular
    execution case have different scopes. Connection jobs and remote commands
    reuse the existing scheduler. *)

From Selvedge.Host Require RemoteTransportProofs
  RemoteConnectorSessionProofs RemoteRelaySessionProofs.
Export RemoteTransportProofs(authorization_retry_decreases,
  rejected_identity_ignores_async_observations,
  retry_observation_before_deadline_does_not_connect).
Export RemoteConnectorSessionProofs(subscription_capture_records_the_current_notice_cutoff,
  delivered_notice_is_queued_and_beyond_the_current_cutoff).
Export RemoteRelaySessionProofs(consumption_removes_ticket,
  stale_generation_cannot_deliver, replaced_hash_cannot_install_pairing).

(** ** The relay and connector speak the same admitted protocol

    The host and relay use the same extracted frame predicates. Controller IDs,
    receipt request IDs, epochs and enrollment credentials have their own
    accepted languages. Only declared bounded envelope integers are materialized
    as JavaScript numbers; opaque command and event JSON retains its numeric
    tokens. An unrelated header limit cannot silently narrow enrollment.

    Closed transport states distinguish probing, negotiation, online operation,
    scheduled retry and rejected identity. Randomness, status and clock values
    are observations, not host permission to reconnect. Authorization checks
    retain their bounded sequence comparison; capture requires equality with
    the current committed sequence in that observation.

    New semantic state is installed before sending or accepting sockets. Ticket
    consumption precedes authorization. After asynchronous hashing, the relay
    rereads the current attachment instead of publishing an earlier snapshot.
    Pending jobs determine connector queue counts and bytes; no independent
    counter can drift after revocation or a delayed completion.

    [subscription_capture_records_the_current_notice_cutoff] and
    [delivered_notice_is_queued_and_beyond_the_current_cutoff] connect snapshot
    subscription and later notices. Transport replacement retains the notice
    sequence. Unsubscribe, resubscribe and delayed queue completion therefore
    share one cursor owner rather than separate JavaScript tests.

    The journal remains command-idempotency authority; the relay does not keep
    another durable command database. Socket handles, cryptography, atomic
    attachment publication and network ordering remain host responsibilities.

    Opening the intended loopback URL establishes an HttpOnly browser session so
    product JavaScript need not handle its secret. Origin and host admission
    remain necessary. CLI Bearer credentials and plugin grants retain their
    separate lifetimes. Build provenance identifies an artifact; persisted
    protocol compatibility identifies replayable work. Only the current
    persisted formats are accepted, without manufacturing authority from older
    attachment or receipt shapes. *)
