# chatgpt-api

<!-- selvedge-package-readme
package: chatgpt-api
freshness_commit: 592f95539c225023a2f2d66f8096a3f85ac304ee
-->

## This crate is for

This crate implements ChatGPT `/responses` streaming calls for Selvedge.

Use it to:

- validate ChatGPT response-stream requests
- resolve ChatGPT auth fresh for each call
- open the `/responses` HTTP stream with bounded pre-stream retries
- decode SSE events into typed response events

## This crate is not for

This crate is not for:

- exposing a reusable client object
- caching config, auth, transcript, or turn state across calls
- persisting caller-visible state between requests
- hiding endpoint or transport failures behind fallback behavior

## Public API

Callers build a `ChatgptResponsesRequest` and pass it to `stream(...)`.

The returned `ChatgptResponseStream` yields `Result<ChatgptResponseEvent, ChatgptApiError>`.
Callers are responsible for preserving the full `input` history and the
`effective_turn_state()` value they want to replay on the next call.

## Config

This crate reads:

```toml
[llm.providers.chatgpt]
base_url = "https://chatgpt.com/backend-api/codex"
stream_completion_timeout_ms = 1800000
```

`base_url` is the upstream ChatGPT API base URL. `stream_completion_timeout_ms`
caps the total lifetime of a single successful response stream.

## Timeout Semantics

This crate enforces two independent timeout layers:

- `network.stream_idle_timeout_ms` belongs to `selvedge-client` and limits how
  long one body-chunk wait may stay idle.
- `llm.providers.chatgpt.stream_completion_timeout_ms` belongs to this crate
  and limits the total lifetime of one `/responses` stream.

These settings are intentionally separate and are not merged into one budget.
Both constraints apply to the same request at the same time.

Failure precedence is simple:

- if the transport layer waits too long for the next body bytes,
  `selvedge-client` returns `HttpError::Timeout`
- if the overall `/responses` stream lives too long,
  this crate returns `ChatgptApiLowerLayerError::StreamCompletionTimeout`

Whichever timeout fires first ends the stream first. Callers should therefore
treat the client-layer timeout and the API-layer completion timeout as distinct
failure modes rather than aliases.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([stream request])
  Validate[Validate ChatgptResponsesRequest]
  ResolveAuth[Resolve auth for request]
  OpenStream[Open responses HTTP stream]
  RetryAfterUnauthorized[Refresh auth after unauthorized]
  Decode[Decode SSE events]
  YieldEvent[Yield typed ChatgptResponseEvent]
  Complete[Stream completed]
  ValidationError[Return RequestValidation error]
  AuthError[Return auth lower-layer error]
  EndpointError[Return endpoint error]
  TransportError[Return transport lower-layer error]
  TimeoutError[Return stream completion timeout]
  DecodeError[Return event decode error]

  Start -->|caller provides request| Validate
  Validate -->|model and input fields satisfy request rules| ResolveAuth
  Validate -->|required field is empty or inconsistent| ValidationError
  ResolveAuth -->|auth resolution returns credentials| OpenStream
  ResolveAuth -->|auth resolution returns ChatgptAuthError| AuthError
  OpenStream -->|HTTP status is 2xx and body is streamable| Decode
  OpenStream -->|HTTP status is unauthorized and retry has not been used| RetryAfterUnauthorized
  OpenStream -->|HTTP status is non-2xx other than first unauthorized retry path| EndpointError
  OpenStream -->|selvedge-client returns transport status, build, config, or timeout error| TransportError
  RetryAfterUnauthorized -->|forced auth refresh succeeds| OpenStream
  RetryAfterUnauthorized -->|forced auth refresh fails| AuthError
  Decode -->|valid SSE event maps to response event| YieldEvent
  Decode -->|provider sends terminal completion event| Complete
  Decode -->|overall stream lifetime exceeds configured stream_completion_timeout_ms| TimeoutError
  Decode -->|body chunk read fails| TransportError
  Decode -->|SSE or JSON event payload cannot be decoded| DecodeError
  YieldEvent -->|caller polls again before terminal event| Decode
```
