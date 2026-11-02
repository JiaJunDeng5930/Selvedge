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
    execution.
    [actual_query_preserves_world_and_emits_no_effect] constrains that actual
    packet entry. Public restart tests cover ordered replay and retained state;
    SQLite supplies transaction durability.

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

From Selvedge.Host Require Dispatch.
Export Dispatch(launch_installs_handle_before_run,
  completion_only_removes_its_generation,
  uncertain_never_retries, reduced_callback_never_retries,
  terminal_settlement_prevents_new_work,
  shutdown_never_cancels_provider,
  ticket_provider_cancellation_keeps_registered_handle,
  task_provider_cancellation_only_stops_independent_entries).

(** ** Each physical effect keeps its own generation

    [launch_installs_handle_before_run] requires ownership before interpretation.
    Completion uses a physical generation so an old finalizer can be separated
    from a replacement with the same logical key. The existing
    [completion_only_removes_its_generation] establishes the surviving-entry
    direction: every retained entry existed before and differs from the completed
    generation. Recovery uses this same runner, including its original rejecting
    promise, so a failed recovery cannot become successful startup through a
    background error observer.

    A successful journal acknowledgement returns directly from the runner's
    awaited execution, before consulting retirement control. Shutdown cannot
    turn that accepted commit into a failure.

    A terminal failure retires dispatch before its settlement promise rejects.
    Other queued continuations can resume before the failure observer runs;
    [terminal_settlement_prevents_new_work] blocks new launches and reductions
    during that interval.
    Size-rejected callbacks may be reduced once; a further rejection retires
    execution instead of retrying indefinitely.

    Closing an observer is different from cancelling a provider invocation.
    [shutdown_never_cancels_provider] preserves remote work for recovery.
    Explicit cancellation retains the registered request owner and ticket,
    including independent approval owners, instead of reducing every stop to
    a Task number. Archive barriers and compensation are controller decisions;
    the host supplies actual resource and path-overlap observations.

    Generated discriminated unions require a physical interpreter for every
    effect. Strict checking includes the real runner and settlement consumer,
    not only a declaration that a handwritten caller might misread. *)

From Selvedge.Host Require ProcessProofs.
Export ProcessProofs(reserved_write_is_exclusive, append_tail_is_bounded,
  append_tail_preserves_absolute_cursor,
  artifact_metadata_requires_complete_published_capture).

(** ** Process progress is bounded without copying its complete buffer

    Successful completion follows actual exit and output drain. The private
    execution's awaited IO establishes that order; [tests/process.test.mjs]
    exercises the physical boundary. Stdin reservations prevent concurrent
    writes, and absolute output cursors survive bounded tail retention.
    [reserved_write_is_exclusive] and [append_tail_preserves_absolute_cursor]
    bind those requirements to the pure controller. The physical scalar buffer
    stays in the host; the model controls counts and slice instructions. Sending the whole tail through
    semantic JSON per chunk adds cost without stronger authority.

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
    public inference authorization. Media signaling may finish before the control
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
