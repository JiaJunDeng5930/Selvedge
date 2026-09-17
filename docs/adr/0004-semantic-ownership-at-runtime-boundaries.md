# ADR 0004: Semantic ownership at runtime boundaries

Status: Accepted

## Context

Several boundaries represented one decision or resource using independently maintained fields. Reused client command IDs could make an old stream destroy a new session. Hydration rollback retained its start message but lost its completed snapshot. Bash cleanup could consume a completed task twice, and web shutdown did not own accepted connections. Model dispatch reconstructed part of a task's configuration and omitted its reasoning effort.

These failures require ownership and complete contracts, rather than additional checks at every caller. Existing frozen tool contracts and durable task lifecycle decisions remain unchanged.

## Decision

A persisted task's model configuration is one immutable, validated domain value. Database decoding constructs it; runtime dispatch carries the same shared value. Profile registry resolution remains separate: existing tasks select a configured profile rather than freezing a copy of its runtime definition. Only provider adapters map abstract reasoning choices to provider request options. The executable provider enum also determines dispatch, so advertising a provider and selecting its adapter cannot use independent registries.

An attach attempt has a fresh internal session identity, independent of its reusable client command correlation. Messages, completion results and cleanup guards retain that identity. A local operation similarly owns an instance token. Cleanup affects the current resource only when the instance matches. Hydration owns both its phase and any completed result while temporarily hidden by a replacement; restoring a candidate restores the complete state.

A running service or command owns the work it starts. Web shutdown cancels and joins accepted connection handlers. Bash execution owns its child and both output readers in one completion scope; timeout resumes cleanup without consuming completed results again. Runtime database transitions execute through one blocking boundary while the actor retains serial command semantics and its shutdown barrier.

The router's runtime factory remains serial. Its ordinary return value represents completion; effect IDs, pending maps and deferred queues are unnecessary when the router cannot process another command during the call. Infallible construction and conversion return values directly.

## Consequences

Rust's private fields, owned scopes, immutable shared values and exhaustive enum matching enforce the structural parts of these contracts. Dynamic ordering, cancellation and external provider semantics still require behavior tests. Regressions cover reused IDs, hidden hydration results, independently finishing output pipes, shutdown with outstanding connections and non-default reasoning choices.

Internal APIs intentionally change, and obsolete placeholder states and their exclusive tests are removed. This does not add compatibility paths for previous persisted formats. Database schema initialization is atomic, and validation derives the current expected structure from the schema source instead of maintaining another schema description.
