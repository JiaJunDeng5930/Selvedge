# Harness execution

Resolves commands, composes task and feature state, and executes bounded transitions.

Start with [MODEL.bend](MODEL.bend), [COMMANDS.bend](COMMANDS.bend), [CONTRACT.bend](CONTRACT.bend), [PROGRAM.bend](PROGRAM.bend).

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../PROOF.bend) assembles the production evidence.
