# Approval

Resolves operation permission requests and interprets task-bound authorization and callbacks.

Start with [MODEL.bend](MODEL.bend), [HOOKS.bend](HOOKS.bend), [CONTRACT.bend](CONTRACT.bend), [PROOF.bend](PROOF.bend).

For review interpretation, follow `ReviewRequest`, `construct_review` and `meaning`
in [MODEL.bend](MODEL.bend). The request captures the world used to resolve the
current task and operation. Origin checks retain their local responsibility;
`meaning_calculation` is the underlying interpretation primitive.

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.
