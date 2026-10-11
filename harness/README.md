# Harness execution

Resolves commands, composes task and feature state, and executes bounded transitions.

For the representation-independent execution interface, start with the root
[MODEL.bend](../MODEL.bend). Its production binding is supplied by the root proof.
For concrete harness requirements and implementation, start with [MODEL.bend](MODEL.bend), [COMMANDS.bend](COMMANDS.bend), [CONTRACT.bend](CONTRACT.bend), [PROGRAM.bend](PROGRAM.bend).

For command execution, follow `construct_command` in [COMMANDS.bend](COMMANDS.bend)
to `realize` in [PROGRAM.bend](PROGRAM.bend). For incoming inputs, follow
`construct_input` in [protocol/PROGRAM.bend](protocol/PROGRAM.bend) to
`realize_event` in [PROGRAM.bend](PROGRAM.bend). These consumers use the world
captured by the construction. Calculation helpers remain implementation and
proof entry points.

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../PROOF.bend) assembles the production evidence.
