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
explicitly excludes audio input and transcription. Keep its inference
authorization separate from the audio grant.

Use Codex's ChatGPT OAuth login parameters directly in Selvedge. Reuse the Host's
OAuth client, PKCE callback, credential persistence and refresh implementation for
both grants. The audio grant has its own client identity and upstream account
identity; the public inference grant retains its existing resource and scope.
The Host supplies audio requests with its own short-lived authorization rather
than exporting another program's credentials. Native capability admission
requires the audio grant rather than the presence of a public SiwC credential.

Authentication is part of Selvedge's account lifecycle. Requiring a separately
installed executable and an account RPC solely to obtain authorization adds
installation and protocol dependencies without providing task execution value.

Use an in-process Chromium-compatible HTTP client for dictation uploads. With
identical authorization, audio bytes and request headers, the deployed gateway
challenged Bun requests while Chromium requests returned transcription text.
Matching the proxy and automatic headers did not remove the failure, and
Chromium still succeeded with HTTP/2 disabled. The native client dependency
addresses this observed transport boundary without a browser process. Keep voice
signaling on its existing transport and share the existing authorization and
token-refresh lifecycle.

## Consequences

Closing voice releases media and control resources while accepted task work
continues under its original workspace, sandbox and approval policy. Playback
interruption, microphone mute and task cancellation remain separate actions.

Restart recovery restores committed text and task inputs. It does not open a
microphone, restore an old media call or resubmit a delegated input as new work.
Raw audio and account secrets stay outside the input journal.

Audio login and media use OpenAI's OAuth and audio services directly. Explicit
voice login keeps opening an authorization page tied to a user action while
ordinary capability discovery remains read-only.

Production proofs cover native admission, history updates and task decisions.
Physical checks cover the account service, media lifetime, protocol delivery and
commit-before-report ordering. The upstream service and audio transcription
quality remain external boundaries.
