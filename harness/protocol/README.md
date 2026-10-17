# Protocol and commitment

Correlates accepted calls and results, schedules their interpretation and commits complete decisions.

Start with [PROGRAM.bend](PROGRAM.bend), [RESULTS.bend](RESULTS.bend), [COMMIT.bend](COMMIT.bend), [PROOF.bend](PROOF.bend).

`COMMIT.Committed` retains the actual decision and its state/effect-authority or
unchanged-world certificate through output admission. `PROGRAM.construct_transition`
is the production constructor; the public transition projects its decision and
the root safety proof projects that same construction's evidence.

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.
