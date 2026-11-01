# Store only the inputs needed for restart

Status: accepted

## Context

Selvedge must restore committed task state after restart and must commit a change
before starting its external effects. The host reconstructs state by passing the
stored inputs to the same extracted kernel entry used during execution.

The journal also stored every complete decision and a SHA-256 chain. These
fields supported tamper detection and exact output comparisons during restart;
they were not used to reconstruct state or serve the public event cursor. The
chain had no independent trusted endpoint and did not protect against someone
who could rewrite the whole database. Exact output comparison also made changed
diagnostic wording or otherwise harmless output changes prevent restart.

## Decision

Persist the ordered inputs in SQLite and publish their decisions only after
COMMIT succeeds. Retain exclusive writer ownership, explicit format selection
and the existing distinction between rejected and uncertain commits. SQLite
transactions and WAL with `synchronous=FULL` provide the physical durability
boundary. Restart replays the inputs without dispatching effects.

Remove the decision copies, hash chain and unused Gallina trace model whose
properties concerned the removed receipt collection. Use the actual packet's
query-purity theorem and transaction controller's publication theorem for their
respective guarantees; public restart and failed-commit tests cover physical
storage and execution.

The current format is version 13. Changes that alter the interpretation of
stored inputs must change that format; older formats are rejected without
migration. No tamper-evident audit journal is part of the product requirement.

## References

- [SQLite atomic commit](https://www.sqlite.org/atomiccommit.html)
- [SQLite write-ahead logging](https://www.sqlite.org/wal.html)
- [Event sourcing persistence](https://eventsourcing.readthedocs.io/en/stable/topics/persistence.html)
