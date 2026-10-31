(** * Commit, effect and media lifetimes

    A successful pure transition and a durable commit are different facts. The
    host must publish the former only after observing the latter, and preserve
    uncertainty when the acknowledgement is lost. Physical handles and received
    media have their own lifetimes; they cannot silently replace domain policy. *)

From Stdlib Require Import List NArith.
From Selvedge.Host Require Import Transaction.
From Selvedge.Kernel Require JournalProofs.
Export JournalProofs(batches_preserve_input_and_receipt_order,
  replay_projects_the_actual_trace,
  every_input_retains_one_complete_receipt,
  extending_a_trace_never_rewrites_prior_receipts).
Export Transaction(publication_requires_commit_ack).
Import ListNotations.

(** ** Acknowledgement controls publication

    The Worker owns the opaque world initialized by the kernel. A journal stores
    admitted inputs and complete receipts and restores it by replaying the same
    entry; replay does not publish physical effects. [JournalProofs] establishes
    input/receipt order and retained earlier receipts, not SQLite durability.

    [publication_requires_commit_ack] is the safety direction. The positive
    requirement below also rules out a controller that never publishes accepted
    work. The expected primitives are stated independently of the transition's
    implementation and concern [Transaction.step], the operation interpreted by
    the host. *)

Theorem acknowledged_commit_publishes_and_resolves : forall generation,
  Transaction.step
    (Transaction.State Transaction.CommitPending generation)
    Transaction.CommitAck =
  (Transaction.State Transaction.Committed generation,
    [Transaction.Publish; Transaction.Resolve]).
Proof. intros; reflexivity. Qed.

(** A failure during COMMIT has an unknown outcome. Retiring the current world
    forces reopening to establish the durable result; neither completion retry
    nor resource rollback is authorized by uncertainty. This differs from a
    definite pre-commit rejection. *)

Theorem uncertain_commit_retires_the_world : forall current generation,
  Transaction.step (Transaction.State current generation) Transaction.CommitUnknown =
  (Transaction.State Transaction.Retired generation,
    [Transaction.RejectUnknown; Transaction.Retire]).
Proof. intros; reflexivity. Qed.

From Selvedge.Host Require Dispatch.
Export Dispatch(launch_installs_handle_before_run,
  completion_only_removes_its_generation,
  uncertain_never_retries, reduced_callback_never_retries,
  shutdown_preserves_an_accepted_callback,
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

    Dispatcher retirement blocks new launches and reductions, but does not undo
    a commit already accepted while shutdown was starting.
    [shutdown_preserves_an_accepted_callback] retains that acknowledgement.
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
Export ProcessProofs(finished_requires_exit_and_drain,
  reserved_write_is_exclusive, append_tail_is_bounded,
  append_tail_preserves_absolute_cursor,
  artifact_publication_requires_all_barriers).

(** ** Process progress is bounded without copying its complete buffer

    A process finishes after exit and output drain. Stdin reservations prevent
    concurrent writes, and absolute output cursors survive bounded tail
    retention. [finished_requires_exit_and_drain], [reserved_write_is_exclusive]
    and [append_tail_preserves_absolute_cursor] bind those requirements to the
    pure controller. The physical scalar buffer stays in the host; the model
    controls counts and slice instructions. Sending the whole tail through
    semantic JSON per chunk adds cost without stronger authority.

    PTY execution keeps its fresh terminal session and the admitted command as
    the foreground job so resize and keyboard signals reach it. Pipe execution
    has its own session behavior. Job-control wrapping passes the command as an
    argument rather than evaluating it again. Process groups, sandbox enforcement
    and terminal semantics require physical evidence. Durable output publication
    waits for all selected file and parent barriers. Bounded readers observe the
    opened descriptor before and after the bounded read, not a prior path size. *)

From Selvedge.Kernel Require SpeechProofs.
From Selvedge.Host Require AudioProofs AudioSession AudioTransport.
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
