# Reasoning

Selects reasoning policy and context and binds its production updates to independent requirements.

Start with [MODEL.bend](MODEL.bend), [SPEC.bend](SPEC.bend), [PROGRAM.bend](PROGRAM.bend), [CONTRACT.bend](CONTRACT.bend).

[view.bend](view.bend) prepares a bounded public preview before encoding an
evaluator effect. It retains the original and recent user requests, recent public
notes and the last six tool calls with their outputs. The host applies the final
tokenizer budgets. The immutable source history and reasoning leases are not
replaced by this transport preview.

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.
