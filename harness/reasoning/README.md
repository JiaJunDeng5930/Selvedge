# Reasoning

Selects reasoning policy and context and binds its production updates to independent requirements.

Start with [MODEL.bend](MODEL.bend), [SPEC.bend](SPEC.bend), [PROGRAM.bend](PROGRAM.bend), [CONTRACT.bend](CONTRACT.bend).
Tracked source identities and patches belong to [context](../context/README.md);
`observe_context` and `context_completed` connect that boundary to model requests.

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.
