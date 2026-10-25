# Commit independent business changes before scheduling

## Status

Accepted. Extends ADR 0065.

## Context

A task birth, an owned final result or a newly installed request receiver could
be rolled back because unrelated scheduling changed the same candidate later
in the transaction. Local constructor proofs did not establish success through
that entire composition. Requiring every other task and feature to be idle
removed the interference from a theorem rather than from the production path.

No product requirement makes a successful creation or accepted final settlement
atomic with all background work. ADR 0065 already uses the journal and a durable
continuation to separate a manual fork from that work. This is also consistent
with [Temporal's event-history model](https://docs.temporal.io/encyclopedia/event-history),
where recorded commands and events support progress after a worker failure.

## Decision

Reuse the existing durable continuation for finite business transactions whose
result is independent of subsequent scheduling. Keep the actual owner resolver,
constructor, receiver and effect together. Prove their concrete preservation and
authority from business prerequisites and physical observations, and deliver the
actual result within its input and output budgets. Ordinary scheduling follows
through `ContinueScheduling`; it has no authority to undo the preceding commit.

The boundary must preserve event order and task-graph output routing. Creation,
fork receipts and final after-hook settlement do not append assistant output.
A model completion's assistant-output delta is processed before scheduling can
yield. An accepted native fork yields only at the first actual runnable action,
after its argument, capability, before-hook and result-capacity gates. Advancing
that pending invocation, creating its children and installing after-hook result
processing remain one transaction, so replay cannot execute the fork again.
An earlier runnable action is never skipped. A yielded native invocation resumes
before automatic title maintenance; its continuation can then advance titles.

Archived settlement is restricted to the matching final after-hook callback.
It consumes that accepted operation without granting ordinary execution or model
inference to an archived task. Intermediate hooks and stale callbacks retain
their existing admission rules.

Automatic title requests use an independent continuation transaction as well.
Selecting one eligible task, allocating its ticket, installing its receiver and
emitting its request happen together. Pending entries exclude duplicate issuance;
subsequent continuations can process other eligible tasks. This keeps the actual
automatic request, rather than only title configuration, inside the guarantee.

Public feature request entries share the same deferred admission and delivery
pipeline. World validity and cross-step authority remain distinct checks where
other paths still need them. A positive proof derives their successful outcome;
it does not assume that a validator or executor already succeeded. Raw input,
stale correlation, physical observations and actual transport budgets retain
their authoritative runtime boundaries. Native result proofs additionally name
historical invocation authority and the allocator's historical ticket supply.

## Consequences

The business response and its effects may precede context or model scheduling
by another journal transaction. This adds a persistence boundary without adding
a command queue, recovery format or scheduler. Existing journal recovery resumes
an unconsumed continuation; already issued IO keeps its existing outcome rules.
Pure construction and entry theorems cover these transactions. Extraction,
JavaScript bindings, SQLite acknowledgement and physical IO remain separate
validation boundaries.
