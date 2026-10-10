# ChatGPT sharing

Owns project sharing grants, requests and outcomes for the ChatGPT feature.

Start with [MODEL.bend](MODEL.bend), [SPEC.bend](SPEC.bend), [PROGRAM.bend](PROGRAM.bend), [CONTRACT.bend](CONTRACT.bend).

For commands, follow `construct_command` in [MODEL.bend](MODEL.bend) to `realize`
in [PROGRAM.bend](PROGRAM.bend). For completion callbacks, follow
`construct_completion` to `realize_completion` in the same entries. These
consumers use the captured component state; `realize_calculation` remains an
implementation and proof primitive.

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.
