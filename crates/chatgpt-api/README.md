# chatgpt-api

<!-- selvedge-package-readme
package: chatgpt-api
freshness_fingerprint: eacc9d918c20427e31e50f7513d6c3802eda230f
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
`tools` carries the complete function descriptor set. Optional `allowed_tools`
selects a duplicate-free subset by name and is encoded as
`tool_choice.allowed_tools`; an empty subset encodes `tool_choice: "none"`
without deleting the descriptors.
`FunctionCallItem.arguments` is a `JsonObject`: this crate decodes the
provider's string-valued wire field at ingress and encodes it again only when
building a replay request. Arbitrary-precision JSON numbers therefore remain
lossless across provider normalization and replay.

Request encoding follows Codex commit `e269f2164cbb9f499e4f22301c393500e2a831f3`:
`session-id`, `thread-id`, and `x-client-request-id` use the caller's conversation
identity; `client_metadata` includes available session, thread, window,
installation, subagent, parent, and turn metadata. This API currently has one
conversation identity, so its session and thread identifiers are equal.
Reasoning effort and encrypted-content inclusion are independent of summary
support. Unsupported summary and verbosity controls are omitted; output schemas
remain available when verbosity is unsupported. A summary setting of `none`
omits the summary parameter.

Typed replay preserves message `phase`,
`internal_chat_message_metadata_passthrough`, function `encrypted_function_args`,
and input-image URL or file references with their `detail`. Callers must retain
these response items themselves. Unknown item and content types remain opaque;
that preservation does not add tool execution support. The provider-neutral
`selvedge-api` history does not persist phase, reasoning/encrypted metadata, or
the effective turn state, so these replay guarantees apply to direct callers of
this crate, not to the full durable Selvedge conversation path.

Informational SSE events with unknown types are yielded as `Other` and do not
terminate the stream. Explicit `error`, `response.failed`, and
`response.incomplete` events do terminate it; `response.completed` is the success
terminal, and EOF without it remains an error. Failure categories distinguish
current policy, overload, and rate-limit codes while retaining raw provider
details and retry delays. Usage exposes cache-write tokens and preserves
fractional `codex_rollout_budget_units` without rounding.

## Config

This crate reads:

```toml
[llm.providers.chatgpt]
base_url = "https://chatgpt.com/backend-api/codex"
stream_completion_timeout_ms = 1800000
```

`base_url` is the upstream ChatGPT API base URL. `stream_completion_timeout_ms`
caps the total lifetime of a single successful response stream.

The decoder caps one pending SSE frame at 1 MiB and the complete response stream at 4 MiB. Either boundary returns `ChatgptApiEndpointError::ResponseTooLarge`.

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
  SizeError[Return response-too-large endpoint error]

  Start -->|caller provides request| Validate
  Validate -->|model, input, tools, and allowed-tool subset satisfy request rules| ResolveAuth
  Validate -->|required field is empty, inconsistent, or names an unknown allowed tool| ValidationError
  ResolveAuth -->|auth resolution returns credentials| OpenStream
  ResolveAuth -->|auth resolution returns ChatgptAuthError| AuthError
  OpenStream -->|HTTP status is 2xx and body is streamable| Decode
  OpenStream -->|HTTP status is unauthorized and retry has not been used| RetryAfterUnauthorized
  OpenStream -->|HTTP status is non-2xx other than first unauthorized retry path| EndpointError
  OpenStream -->|selvedge-client returns transport status, build, config, or timeout error| TransportError
  RetryAfterUnauthorized -->|forced auth refresh succeeds| OpenStream
  RetryAfterUnauthorized -->|forced auth refresh fails| AuthError
  Decode -->|valid SSE event including informational unknown types and replay metadata maps to response event| YieldEvent
  Decode -->|provider sends response.completed| Complete
  Decode -->|provider sends error, response.failed, or response.incomplete| EndpointError
  Decode -->|overall stream lifetime exceeds configured stream_completion_timeout_ms| TimeoutError
  Decode -->|body chunk read fails| TransportError
  Decode -->|SSE, JSON event payload, or function arguments cannot be decoded| DecodeError
  Decode -->|one frame exceeds 1 MiB or the stream exceeds 4 MiB| SizeError
  YieldEvent -->|caller polls again before terminal event| Decode
```
