# Feature composition

Assembles independent feature state and vocabulary into the harness and binds feature behavior to task creation.

Start with [MODEL.bend](MODEL.bend), [SPEC.bend](SPEC.bend), [CONTRACT.bend](CONTRACT.bend), [CODEC.bend](CODEC.bend).

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.
