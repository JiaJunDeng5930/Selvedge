# ADR 0007: Caller-owned Responses WebSocket connections

Status: Accepted

## Context

GPT-6 adds asynchronous tool calls, input items that change reasoning effort without replacing the cached prompt prefix, and mid-turn steering. Steering requires commands and multiple response streams to share a WebSocket connection. The existing HTTP entrypoint owns one response stream and cannot express this lifetime.

Moving a socket directly into the provider adapter would bypass Selvedge's transport configuration and certificate handling. Hiding a shared session behind the existing `stream` function would also introduce a second owner for conversation history and pending work.

## Decision

Add WebSocket transport to `selvedge-client` and an explicit, caller-owned WebSocket connection API to `chatgpt-api`. The transport owns framing, TLS, connection settings, and transport errors. The adapter owns ChatGPT authentication, wire commands, typed response events, and connection-level failure handling. Callers retain responsibility for history, response identifiers, pending tool results, and reconnect decisions.

Keep the existing HTTP stream contract. A WebSocket response terminal event ends that response rather than the connection. Steering acceptance, required-input waits, steering failure, and automatic continuation remain observable events. The adapter does not silently replay steering or model requests after transport loss.

Resolve authentication and connection headers for each handshake. Freeze that connection's request context so subsequent creates cannot silently change metadata that already went into the handshake. Expose server-returned turn state for explicit reuse when opening a later connection or HTTP request.

Preserve the distinction between asynchronous and synchronous calls in provider items, including explicit false and omitted flags. Represent reasoning configuration changes as input items, preserving their position and the original request-level reasoning setting. Neither addition implicitly enables tool execution or changes the durable task model.

A misalignment policy error terminates the affected adapter connection and disables subsequent sends. Expose the provider's diagnostic data; do not retry the stopped workflow.

## Consequences

Callers can send steering while receiving model output and can supply required tool results on the same connection. This requires an explicitly managed lifetime, while the HTTP API continues to have a single-response lifetime. There is no global session cache or implicit HTTP fallback.

Protocol tests can verify framing, commands, ordering, continuations, and failures against local peers. Live backend access and feature availability remain separate from those tests. Selvedge's core task scheduler and persistent history must opt into this new API separately.
