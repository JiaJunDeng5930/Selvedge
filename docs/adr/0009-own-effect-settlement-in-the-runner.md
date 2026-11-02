# ADR 0009: Keep effect settlement ownership in its runner

Date: 2026-11-02
Status: Accepted

## Context

The dispatch controller tracked a `settled` bit for each physical effect and
proved that later settlement observations could not acknowledge it again.
The actual runner sends those observations only while awaiting the journal
result. Its first successful acknowledgement returns from settlement; its
finalizer removes the physical handle after the runner returns. Workspace
execution and startup reconciliation follow the same awaited path.

The bit therefore repeated the runner's control flow. Neither cancellation nor
shutdown can create a second settlement invocation: both retain the active
handle until its existing runner finishes. JavaScript's
[Promise and async-function semantics](https://tc39.es/ecma262/2026/multipage/control-abstraction-objects.html#sec-async-functions-abstract-operations)
provide the continuation ownership this path already uses.

## Decision

Remove the duplicate settlement bit, its serialization and the theorem about
repeated settlement after acceptance. An accepted journal callback keeps its
acknowledgement during shutdown without updating a second completion state.

Keep the independent physical handle and reduced-callback state. Concurrent
effects can finish out of order, and size rejection can actually resume the
settlement loop with a smaller failure callback. Provider cancellation and
workspace barriers also continue to depend on the registered running effects.

## Consequences

The dispatch model no longer promises to suppress a repeated successful
settlement invocation that the host cannot issue. Kernel callback tickets still
reject stale external results; that boundary receives independent external
observations and has a different lifetime. Public service, cancellation and
effect-failure tests continue to exercise the real runner and journal boundary.
