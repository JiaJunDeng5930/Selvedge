# Feature composition

Assembles independent feature state and vocabulary into the harness and binds feature behavior to task creation.

Start with [MODEL.bend](MODEL.bend), [SPEC.bend](SPEC.bend), [CONTRACT.bend](CONTRACT.bend), [CODEC.bend](CODEC.bend).

For command interpretation, follow `construct_command` in
[resolution.bend](resolution.bend) to `realize` in [execution.bend](execution.bend).
For completions, follow `construct_event` in [protocol.bend](protocol.bend) to
`event` in [execution.bend](execution.bend). Assembly captures the current world
at interpretation and consumes the construction immediately. Board launches
use ordinary task creation through this assembly and the core harness.

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.
