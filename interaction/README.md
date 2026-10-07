# Platform-independent interaction

Combines application interaction state, user inputs and observable scenes independently of browser geometry.

Start with [MODEL.bend](MODEL.bend), [STATE.bend](STATE.bend), [CONTRACT.bend](CONTRACT.bend), [PROOF.bend](PROOF.bend).

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../PROOF.bend) assembles the production evidence.
