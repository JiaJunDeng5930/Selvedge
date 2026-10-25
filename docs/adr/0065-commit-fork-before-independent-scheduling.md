# ADR 0065: Commit fork before independent scheduling

## Context

The earlier exported fork proof enumerated a small family of worlds. Its
postprocessing frame excluded ordinary runnable background work. Proving only
the fork constructor could not justify bypassing admission after arbitrary
scheduler, board and context maintenance steps had changed the candidate.
Conversely, those independent steps could make a valid fork fail admission.
No product requirement makes their completion part of the fork response.

## Decision

Commit an external manual fork as its own durable domain transaction. Reuse the
actual command handler and fork constructor. Admit the selected physical
workspace once, deliver the actual business reply and effects within the output
budget, and request further work through the existing `ContinueScheduling`
effect. The journal commits state before interpreting effects; recovery can
resume tasks whose continuation has not issued IO. Already issued model or tool
work keeps the existing unknown-outcome recovery rules.

This follows the established separation between atomic persistence and
post-persistence effects described by
[Akka's event sourcing documentation](https://doc.akka.io/libraries/akka-core/current/typed/persistence.html).
It introduces no new scheduler or persistence mechanism. Native fork remains
inside its accepted tool invocation so its settlement order is preserved.

Use the general constructor preservation proof for the manual transaction,
including rejection paths. Its successful case quantifies over arbitrary
well-formed worlds and real fork prerequisites. Existing operations, plugins,
archived settlements and unavailable unrelated resources remain in that domain.
The exported positive theorem requires the actual input frame and business
candidate output budget, rather than a successful validator or an error
envelope's budget.

The fork transaction therefore bypasses final whole-world invariant and
cross-step admission. The constructor's exact births, retained fields,
operation certificates, lineage capacity, settings and ticket ownership have
already been proved. The physical workspace observation and delivery budget
remain runtime decisions. Other transactions retain admission for relationships
that later composition has not established statically.

Model requests also use one canonical selection bound to their actual source,
owner and ticket. The request carries the selection witness and one set of
ticket, callable tools and output mode fields. Context capture changes only the
request history; compaction changes only its scope and reserve. Neither can
select another model. Remove the repeated model-selection scan and duplicate
snapshot-phase comparisons, while retaining comparisons against the final
current task. The witnesses are propositions, erased by the standard
[Rocq extraction mechanism](https://github.com/rocq-prover/rocq/blob/master/plugins/extraction/README).

## Consequences

The fork response contains its committed births and a continuation. Context and
model requests may arrive in a later transaction. Pure preservation and positive
execution are Rocq theorems; real continuation dispatch and recovery before IO
are exercised through the public Service and journal. Extraction, JavaScript,
SQLite and physical IO retain their separate trust boundaries.
