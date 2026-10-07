# Native transport

Decodes and renders the pure native packet protocol; the root MAIN entry owns IO.

Start with [MODEL.bend](MODEL.bend), [PROGRAM.bend](PROGRAM.bend), [PROOF.bend](PROOF.bend).

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.
