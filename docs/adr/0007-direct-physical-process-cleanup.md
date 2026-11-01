# ADR 0007: Keep fixed process cleanup in its physical owner

Date: 2026-11-01
Status: Accepted

## Context

Process cleanup and output draining used two fixed Gallina lists. Neither list
depended on an observation or participated in a proof. An adapter serialized the
steps to JSON, and the host immediately switched over those names to recover the
same physical call sequence. This representation added no choice, ownership or
assurance to the process runner.

The process controller still has real asynchronous facts to retain: startup,
exit, output drain, input closure, write reservations and failure. In particular,
[Bun's exited promise](https://bun.sh/docs/runtime/child-process#exit-handling)
observes process exit; terminal and pipe output have separate lifetimes.

## Decision

Express the fixed cleanup and await sequence directly in the process runner.
Keep remote environment cancellation, process-group and session termination,
input closure and the bounded inherited-output deadline. Await those physical
operations and output draining before reporting the drain observation to the
existing controller. Remove the two plan types, lists and adapter routes, as
well as the unused standalone status route.

## Consequences

The controller continues to own process admission, lifecycle observations,
bounded output slicing and publication decisions. Its proofs constrain those
operations. Public process tests exercise the physical cleanup and IO composition;
there is no extra interpreter for an unconditional physical sequence.
