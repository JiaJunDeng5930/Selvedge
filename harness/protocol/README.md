# Protocol and commitment

Correlates accepted calls and results, schedules their interpretation and commits complete decisions.

Start with [PROGRAM.bend](PROGRAM.bend), [RESULTS.bend](RESULTS.bend), [COMMIT.bend](COMMIT.bend), [PROOF.bend](PROOF.bend).

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.
