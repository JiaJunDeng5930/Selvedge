# Browser runtime

Combines platform observations, native fields and physical browser transitions at the native browser boundary.

For the representation-independent application and display interfaces, start
with the root [MODEL.bend](../../MODEL.bend). The root proof binds them to the
production runtime and its evidence. For concrete runtime details, start with [MODEL.bend](MODEL.bend), [PLATFORM.bend](PLATFORM.bend), [CONTRACT.bend](CONTRACT.bend), [PROOF.bend](PROOF.bend).

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.
