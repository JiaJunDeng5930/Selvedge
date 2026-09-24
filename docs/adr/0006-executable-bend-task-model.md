# Executable task model in Bend 2

## Decision

The migration experiment makes a pure, terminating Bend transition the owner of
task state. The native process executes the same definitions named by the laws.
Node interprets returned effects and owns operating-system integration. It records
each durable input and decision in SQLite before publishing or dispatching effects.

## Reasons

Keeping a second lifecycle implementation in the host would require a separate
refinement argument every time the model changes. Executing the modeled transition
removes that duplicate implementation. A bounded transition also permits structural
termination checking while an external service can run indefinitely.

History append and durable replay use generic list operations. Their algebraic
results can therefore be instantiated directly with the production definitions,
without translating a second simulator into a relationship with the implementation.

Task laws describe the pure decision. They cannot establish whether an operating
system performed a command before a crash. Unknown external outcomes remain
explicit and are not automatically retried. Host integration tests cover this
boundary; they are not represented as Bend proofs.

## Consequences

MODEL, LAWS, and PROGRAM are the primary reading entry points. PROOF contains
proof construction, and the support library contains reusable theory and codecs.
The exploration record stores experiments, discovered limitations, and reasons;
it does not duplicate the lifecycle tables or command vocabulary.

The existing Rust workspace remains as a reference during this experiment. Its
persistent formats are not imported or migrated by the Bend host.

This temporary retention was superseded by
[ADR 0007](0007-admit-certified-bend-transitions.md) when the Bend runtime became
the sole implementation in the checkout.

## Observation boundary

Public queries return only a reply value. The transition supplies the unchanged
world and an empty effect list, and derives persistence and scheduling from one
input-mode classification. This avoids separately proving that each branch of
every query remembers to preserve state. Internal read tools reuse the query but
still record their tool result through the normal durable execution path.
