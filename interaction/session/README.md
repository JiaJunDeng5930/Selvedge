# Interaction sessions

Owns application and session observations, navigation and interaction transitions.

Start with [MODEL.bend](MODEL.bend), [PROGRAM.bend](PROGRAM.bend), [CONTRACT.bend](CONTRACT.bend), [PROOF.bend](PROOF.bend).

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.

Submission admission calls the experience `can_prepare` operation on the same
draft body, pending state and world used by presentation. A refused admission
returns the first assessment obstruction, preserves the complete application and
emits no directory observation. Accepted preparation keeps the immutable draft
snapshot and the command resolver as the authoritative execution boundary.
`submission_requirements_gate` and `invalid_preparation_complete_refusal` bind
these guarantees to the production admission and refusal operations.
