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
input closure, write reservations and failure. In particular,
[Bun's exited promise](https://bun.sh/docs/runtime/child-process#exit-handling)
observes process exit; terminal and pipe output have separate lifetimes.

## Decision

Express the fixed cleanup and await sequence directly in the process runner.
Keep remote environment cancellation, process-group and session termination,
input closure and the bounded inherited-output deadline. Await those physical
operations and output draining before reporting completion to the
controller. Remove the two plan types, lists and adapter routes, as
well as the unused standalone status route.

The complete caller trace also establishes startup, exit and completion order:
these events are issued only by the same private execution. The separate
`output_drained` bit has no reader before the completion gate rechecks it; it
duplicates the awaits already required to reach that gate. Remove that bit,
its event and the checks of this fixed event sequence. Once that gate is gone,
the draining phase has the same reads and transitions as running with closed
input. Remove it and the separate shell-exit event: the actual exit continuation
already closes input through the shared cleanup operation. The same input-closed
observation makes repeated exit, cancellation and EOF cleanup idempotent; the
host does not need a second `inputCloseStarted` flag.
Both normal and failed attempts finish through the same terminal observation.

A retained-file candidate exists only after its file sync and close succeed,
so a separate `file_synced: true` field supplies no new observation. The two
directory barriers are also a fixed awaited sequence: use one successful path
publication observation after both return. Retain the actual IO and the model's
requirement that reported persistence needs complete capture and published paths.
The metadata theorem now constrains the actual adapter response.

## Consequences

The controller continues to own process admission, lifecycle observations,
bounded output slicing and publication metadata. Its proofs constrain those
operations. Public process tests exercise the physical cleanup and IO composition;
there is no extra interpreter for an unconditional physical sequence.
