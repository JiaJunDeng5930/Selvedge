# 0015: native extension protocol

Status: accepted, 2026-09-25.

## Context

Putting callbacks in the external executor would miss internal tools, including
fork and task control. Mutating stored original calls would also invalidate the
existing relationship between accepted history and pending operation rights.
JavaScript event classification would create another domain interpretation.

## Decision

`HOOKS.bend` is an ordered authorization protocol ahead of source classification.
Tasks freeze plugin revisions and order. Every callback is a committed ticket;
its result becomes an owner-bound immutable certificate. The current effective
call and remaining chain must reconstruct from the original accepted call and
those certificates. Failure is closed and cancellation/recovery never guesses an
unknown callback outcome. External interpreters execute only fully authorized,
committed tool effects.

Plugins are language-neutral local JSON-RPC processes. MCP and plugins share one
bounded stdio transport, but not protocol vocabularies. A manifest declares new
tools, before-tool capability and typed event subscriptions. Unsupported native
schema features reject registration rather than produce a partial interpretation.

Native event projection observes committed task/history changes and surviving
effects. Child birth is an explicit typed record with unchanged public fork-return
serialization; inherited events are not new occurrences. Observation enriches an
effect envelope without changing state, command receipt or core effects, with a
checked projection certificate. Optional events can be omitted under packet/queue
pressure. Delivery is bounded and best-effort, not an exactly-once event service.

## Consequences

Cross-cutting behavior no longer needs per-tool callbacks. The public conceptual
entry carries extension laws, while transport, executable policies and external
observer side effects remain explicit trust boundaries. No new FFI, universal
untyped runtime, background agent or proof assumption is introduced. New variants
extend the existing closed native types and full-transition proof; journals remain
source-fingerprint bound instead of acquiring an implicit migration path.
