# ADR 0052: bind ChatGPT audio to existing conversations and task execution

## Context

Dictation and a live voice conversation both consume microphone input, but have
different effects. Dictation edits a draft. A live conversation produces its own
spoken history and can delegate work while the user continues talking. Treating
every recognized sentence as a normal task submission would run the task model
for conversational speech and lose the distinction between speech and work.

The existing task scheduler batches queued messages. Its journal sequence orders
commits but does not identify a retried request. The ordinary creation command
also starts work immediately, which is inappropriate when opening an empty voice
conversation.

## Decision

Keep draft editing, completed speech records and accepted work as separate
operations. Dictation uses the existing editor identity, revision and selection.
Completed speech extends the ordinary conversation history through an update
that does not schedule the task model. Live partial text and media resources are
temporary observations.

Create an empty conversation with the existing Active/Idle task representation.
The first actual work input uses the ordinary receive operation. Preserve the
existing creation command's initial-message requirement.

Bind each delegated input to its voice session and upstream delegation identity,
and commit its receipt with the accepted task input. Receipt ownership includes
the task identity so an inherited fork history cannot stand for acceptance by
the child. Report committed task progress using the existing task observations;
the receipt does not introduce a separate execution turn or scheduler.

Use browser WebRTC for audio and a Host control connection for protocol events.
The Host retains account authorization, validates protocol observations through
the native adapters and submits accepted operations through the original kernel.
Return the media answer before waiting for control readiness: the upstream call
may require browser ICE activation before accepting its control connection.
Microphone admission still waits for both connections and session initialization.
Use a voice compatible with GPT-Live's Codex catalog. The initial public Realtime
voice default returned SDP without activating the call; the compatible voice
passed the real connection gate.
Audio authorization is a capability of the selected ChatGPT connection,
independent of the task's model profile. An identity login or another provider's
model credential is not an audio capability.

The public third-party Sign in with ChatGPT flow supports Responses and
explicitly excludes audio input and transcription. A real transcription probe
with that grant returned HTTP 403. Keep its inference authorization separate
from the audio authority.

Reuse the official Codex authentication component in a Selvedge-owned home for
audio login, credential storage and refresh. Its public account RPC supplies
short-lived authorization to the Host in memory. This component owns no Selvedge
Task and receives no execution commands. Keep the deprecated token-export RPC
behind one adapter; an unsupported component reports an explicit error. Native
capability admission requires this ChatGPT audio authority rather than the
presence of a public SiwC credential.

The component's public realtime RPC still routes incoming delegations into its
own execution even with `clientManagedHandoffs` enabled; that option suppresses
automatic output forwarding. Keep control transport separate so one accepted
request cannot execute in both Codex and Selvedge.

## Consequences

Closing voice releases media and control resources while accepted task work
continues under its original workspace, sandbox and approval policy. Playback
interruption, microphone mute and task cancellation remain separate actions.

Restart recovery restores committed text and task inputs. It does not open a
microphone, restore an old media call or resubmit a delegated input as new work.
Raw audio and account secrets stay outside the input journal.

Audio requires an installed official Codex component. Its authentication protocol
and the upstream audio service are external dependencies. Explicit voice login
keeps opening an authorization page tied to a user action while ordinary
capability discovery remains read-only.

Production proofs cover native admission, history updates and task decisions.
Physical checks cover the account service, media lifetime, protocol delivery and
commit-before-report ordering. The upstream service and audio transcription
quality remain external boundaries.
