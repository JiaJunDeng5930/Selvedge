# Execution

Interprets resolved task operations and projects committed occurrences for external consumers.

Start with [OPERATIONS.bend](OPERATIONS.bend), [PROGRAM.bend](PROGRAM.bend), [PROOF.bend](PROOF.bend).

For task work, follow `construct_work` and `meaning` in [PROGRAM.bend](PROGRAM.bend),
or its `work` wrapper. Construction resolves the task and operation from the
captured world. Grant availability remains a local property; `work_calculation`
and `meaning_calculation` serve implementation and proof consumers.

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.
