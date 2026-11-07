(** * Commit, effect and media lifetimes

    A successful pure transition and a durable commit are different facts. The
    host must publish the former only after observing the latter, and preserve
    uncertainty when the acknowledgement is lost. Physical handles and received
    media have their own lifetimes; they cannot silently replace domain policy. *)

From Stdlib Require Import List NArith.
From Selvedge.Kernel Require PacketProofs.
Export PacketProofs(actual_query_preserves_world_and_emits_no_effect).
Import ListNotations.

(** ** Acknowledgement controls publication

    A journal stores admitted inputs and restores the world by replaying the
    same entry; replay does not publish physical effects. Queries preserve the
    world, emit no effects and require no journal row. A committed row must
    retain the input evaluated by the Worker so recovery reconstructs that
    execution. The submitted frame is also the retained replay input: one
    serialization owner avoids a second representation whose interpretation
    could differ from the committed execution. Replay submits that retained
    frame to the same admission entry.
    [actual_query_preserves_world_and_emits_no_effect] constrains that actual
    packet entry. Public restart tests cover ordered replay and retained state;
    SQLite supplies transaction durability. Exclusive writer ownership and the
    acknowledged transaction establish journal authority. An authenticated
    audit history would require an independent trust anchor and is outside this
    restart contract. Changes to input meaning require a new persistent format
    so restart cannot silently reinterpret prior work.

    The Journal owns serialization through the entire Worker response and
    storage commit, so another input cannot observe an uncommitted world.
    Assessments use that same owner. With one outstanding request and one Worker
    response per request, the pending invocation supplies response correlation.
    Worker message delivery remains a runtime premise; timeout or failure
    retires that Worker before another invocation can use its uncertain world.
    Closing drains the invocation queue and awaits Worker termination.

    Publication and successful completion of durable mutations require
    acknowledgement of the commit. A failure during COMMIT has an unknown outcome. It
    retires the current world, so reopening establishes the durable result;
    neither completion retry nor resource rollback is authorized by uncertainty.
    A failure before COMMIT is a definite rejection.

    These are requirements on the physical transaction, including its storage
    call, returned promise and observers. [tests/journal.test.mjs] checks that
    failed storage cannot publish or launch paid work, and that lost COMMIT
    acknowledgement retires execution while reopening recovers the accepted
    input once. [tests/service.test.mjs] covers successful publication through
    the public service and event stream. *)

From Selvedge.Adapters Require RpcProofs ApiProofs.
Export RpcProofs(correlation_matches_the_pending_numeric_value).
Export ApiProofs(public_unissued_rpc_response_preserves_pending_requests,
  public_issued_plain_rpc_result_resolves_its_pending_request,
  public_issued_media_rpc_result_reserves_before_materialization,
  public_rpc_frame_admission_matches_its_byte_budget,
  public_rpc_write_admission_matches_its_byte_budgets,
  public_rpc_reservation_matches_available_capacity,
  public_rpc_reservation_returns_a_bounded_pending_set).

(** ** RPC responses retain the issued numeric identity

    JSON-RPC correlates a response with the value of the issued identifier.
    Equivalent JSON Number spellings therefore identify the same pending
    request. The existing bounded-integer decoder supplies its exact value;
    strings, fractional values and unrelated identities cannot consume that
    request. The correlation law gives both directions, and the actual API
    contracts connect it to ordinary settlement and media reservation.
    A result retired during asynchronous materialization remains retired.

    External stdout, a slow pipe and concurrent Task calls can otherwise retain
    unbounded frames or pending replies. The frame and write admission contracts
    constrain the actual byte observations supplied by framing and encoding,
    including the outbound queue. Reservation admission also constrains the
    returned pending set together with still-running materialization work.
    A cancelled reply can leave its physical work active, so freeing only the
    reply identity must not free that capacity. These contracts retain usable
    admission within the budgets without prescribing the diagnostic selected
    when several limits fail together.

    Closure withdraws write admission before invoking cancellation, and
    successful completion awaits the admitted physical work. Cancellation
    callbacks can run synchronously before the async close call returns its
    completion Promise. The immediate admission observation therefore cannot
    simply be replaced by that Promise: doing so would defer cancellation or
    require another publication mechanism. The retirement laws concern semantic
    ownership; the transport's synchronous sequencing establishes this physical
    order. The full-service shutdown case in [tests/session-boundaries.test.mjs]
    exercises cancellation of an unanswered extension hook and release of its
    peer. *)

From Selvedge.Host Require Dispatch DispatchAdapterProofs.
Export Dispatch(launch_installs_handle_before_run,
  completion_only_removes_its_generation,
  uncertain_never_retries, reduced_callback_never_retries,
  terminal_settlement_prevents_new_work,
  shutdown_never_cancels_provider,
  ticket_provider_cancellation_keeps_registered_handle,
  task_provider_cancellation_only_stops_independent_entries).
Export DispatchAdapterProofs(dispatch_step_returns_its_next_state).

(** ** Each physical effect keeps its own generation

    [launch_installs_handle_before_run] requires ownership before interpretation.
    Completion uses a physical generation so an old finalizer can be separated
    from a replacement with the same logical key. The existing
    [completion_only_removes_its_generation] retains exactly the entries from
    other generations. Completing one invocation must leave concurrent work
    registered so later cancellation and cleanup still reach it.
    Recovery uses this same runner, including its original rejecting
    promise, so a failed recovery cannot become successful startup through a
    background error observer.

    A successful journal acknowledgement returns directly from the runner's
    awaited execution, before consulting retirement control. Shutdown cannot
    turn that accepted commit into a failure. That runner owns settlement and
    retains its physical handle until completion. Cancellation and shutdown
    observe the handle without creating another settlement continuation, so
    their state need not mirror the Promise's completed continuation. External
    callback tickets have a different lifetime: independent external results
    can arrive late and still require ticket admission.

    A terminal failure retires dispatch before its settlement promise rejects.
    Other queued continuations can resume before the failure observer runs;
    [terminal_settlement_prevents_new_work] blocks new launches and reductions
    during that interval.
    Size-rejected callbacks may be reduced once; a further rejection retires
    execution instead of retrying indefinitely. The returned state must retain
    that reduction, retirement and generation ownership when the next invocation
    reads it. [dispatch_step_returns_its_next_state] binds the actual control
    response, its effects and its decoded successor to the pure transition;
    an independent codec law would not require the response to include state.

    Closing an observer is different from cancelling a provider invocation.
    [shutdown_never_cancels_provider] preserves remote work for recovery.
    Explicit cancellation retains the registered request owner and ticket,
    including independent approval owners, instead of reducing every stop to
    a Task number. Archive barriers and compensation are controller decisions;
    the host supplies actual resource and path-overlap observations.

    Generated discriminated unions require a physical interpreter for every
    effect. Strict checking includes the real runner and settlement consumer,
    not only a declaration that a handwritten caller might misread. *)

From Selvedge.Host Require ProcessProofs ProcessAdapterProofs.
Export ProcessProofs(reserved_write_is_exclusive, append_tail_is_bounded,
  append_tail_preserves_absolute_cursor, completed_retention_is_bounded,
  completion_retains_exactly_unexpired_entries,
  artifact_metadata_requires_complete_published_capture).
Export ProcessAdapterProofs(registry_completion_returns_its_retained_processes).

(** ** Process progress is bounded without copying its complete buffer

    Successful completion follows actual exit and output drain. The private
    execution's awaited IO establishes that order; [tests/process.test.mjs]
    exercises the physical boundary. Stdin reservations prevent concurrent
    writes, and absolute output cursors survive bounded tail retention.
    [reserved_write_is_exclusive] and [append_tail_preserves_absolute_cursor]
    bind those requirements to the pure controller. The physical scalar buffer
    stays in the host; the model controls counts and slice instructions. Sending the whole tail through
    semantic JSON per chunk adds cost without stronger authority.
    A completed process remains queryable within the retained completion window.
    Completion bounds that window and removes exactly its expired entries,
    preserving all other running and retained processes. Physical handles follow
    the same returned retirement list. The actual completion response must
    carry the retained registry, including the completion queue, into the next
    invocation. [registry_completion_returns_its_retained_processes] connects
    that response and its retirement list to the pure retention operation;
    otherwise dropping the queue at the boundary would defeat the bound.

    PTY execution keeps its fresh terminal session and the admitted command as
    the foreground job so resize and keyboard signals reach it. Pipe execution
    has its own session behavior. Job-control wrapping passes the command as an
    argument rather than evaluating it again. Process groups, sandbox enforcement
    and terminal semantics require physical evidence. Durable output publication
    waits for all selected file and parent barriers.
    [artifact_metadata_requires_complete_published_capture] constrains the
    actual reported metadata from capture and path-publication observations;
    the physical publisher supplies those observations after its awaited IO.
    Bounded readers observe the opened descriptor before and after the bounded read, not a prior path size. *)

From Selvedge.Adapters Require AudioProofs.
Export Selvedge.Adapters.AudioProofs(audio_capability_matches_account_authority,
  initial_context_constructs_protocol_messages).
From Selvedge.Kernel Require SpeechProofs.
From Selvedge.Host Require AudioProofs AudioSession AudioTransport AudioConnection.
Export SpeechProofs(a_new_transcript_changes_only_the_task_history,
  transcript_commands_never_request_scheduling,
  a_matching_delegation_receipt_is_not_delivered_twice,
  a_fresh_voice_delegation_records_ordinary_input_and_its_receipt).
Export AudioProofs(closing_stream_flushes_at_most_once,
  final_transcript_requires_journal).
Export AudioSession(stale_session_is_inert,
  pending_progress_does_not_issue_another_read,
  delivering_progress_does_not_deliver_a_page_twice).
Export AudioTransport(stale_ack_is_inert, begin_has_one_owner,
  draining_transport_rejects_new_arrivals).
Export AudioConnection(step).

(** ** Voice does not collapse speech into task execution

    Dictation edits an owned draft. Completed speech appends ordinary conversation
    history without scheduling inference; [transcript_commands_never_request_scheduling]
    makes that distinction executable. A delegated work input instead records
    ordinary Task input and its session/delegation receipt together. Receipt
    ownership includes the Task, so inherited history cannot acknowledge a
    child's new request. An empty voice conversation uses the existing idle Task
    state, while ordinary creation keeps its initial-message requirement.

    Account audio capability is distinct from the Task's model profile and from
    public inference authorization. [audio_capability_matches_account_authority]
    constrains the selected connection's actual admission. The host then awaits
    account authorization before sending media; copying a constant authorization
    flag into a later body builder would add no authority. Discovery and sign-in
    belong to the installation's audio account. Stateless transcription authorizes
    its selected connection for one request and has no host browser owner. These
    operations need no browser identity; local HTTP authentication still guards
    them. Browser ownership begins when a voice session is created.

    The Service admits the Task and creates the session identity before building
    its request. [initial_context_constructs_protocol_messages] guarantees that
    its committed history projection constructs valid voice messages. The request
    retains those constructed values directly instead of revalidating them or
    silently substituting empty history. The externally supplied SDP still needs
    admission. Media signaling may finish before the control
    connection is ready; microphone admission waits for both connections and
    initialization. Raw audio and secrets never become journal inputs.

    A control connection can observe HTTP 404 while the accepted media call is
    activating. [AudioConnection.step] owns that bounded retry window and each
    socket attempt's identity; an old close cannot terminate a replacement
    attempt. [tests/audio-sessions.test.mjs] checks activation and exhaustion
    through the service, retaining the finite outcome rather than a particular
    retry count as the user requirement.

    The stream owns turns, partial transcript tails and unresolved delegation
    references. The session owns browser generation and pending journal receipts.
    [stale_session_is_inert], [closing_stream_flushes_at_most_once] and
    [final_transcript_requires_journal] constrain their actual steps. Publication
    of final speech and accepted-work context requires successful commit
    acknowledgement. A failed emission retires its semantic suffix rather than
    inventing acceptance or repeating an uncertain write.

    Arrivals enter the combined controller when received. Its FIFO reserves one
    emission token until acknowledgement; graceful stop seals new arrivals,
    drains that accepted prefix and tail, then closes transport. Progress reads
    use a separate reservation containing the issued cursor and delegation IDs.
    Matching pages advance it once; delayed acknowledgements cannot deliver it
    again. Neither reservation waits while holding the other.

    Voice stop, playback interruption, microphone mute and Task cancellation have
    different effects. Closing voice leaves accepted work running; restart
    restores committed text without reopening a microphone or replaying work.
    WebRTC, sockets, journal execution, timers, transcription and provider behavior
    remain physical boundaries, including the separately observed live-account
    authorization and transport requirements. *)
