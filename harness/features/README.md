# Feature composition

Assembles independent feature state and vocabulary into the harness and binds feature behavior to task creation.

Start with [MODEL.bend](MODEL.bend), [SPEC.bend](SPEC.bend), [CONTRACT.bend](CONTRACT.bend), [CODEC.bend](CODEC.bend).

For command interpretation, follow `construct_command` in
[resolution.bend](resolution.bend) to `realize` in [execution.bend](execution.bend).
For completions, follow `construct_event` in [protocol.bend](protocol.bend) to
`event` in [execution.bend](execution.bend). Assembly captures the current world
at interpretation and consumes the construction immediately. Board launches
use ordinary task creation through this assembly and the core harness.

Task graph installation and reply reactions are assembled in
[graph-execution.bend](graph-execution.bend), against the independent requirements
in [graph-spec.bend](graph-spec.bend). [graph-proof.bend](graph-proof.bend) binds
the complete decisions to ordinary task creation and message delivery.
[graph-state.bend](graph-state.bend) owns the graph-to-task reference checks and
the graph registry's position in the assembled world.

Managed task worktrees are assembled in [worktree-execution.bend](worktree-execution.bend)
against the independent complete decisions in [worktree-spec.bend](worktree-spec.bend).
[worktree-state.bend](worktree-state.bend) owns task references, completion correlation,
Git effect authority and the single pending workspace initialization coordinate.
[worktree-proof.bend](worktree-proof.bend) and
[worktree-storage-proof.bend](worktree-storage-proof.bend) bind those requirements and
unrelated-state guarantees to production. The component's wire vocabulary and registry
are described by [the worktree feature](../../features/worktree/README.md).

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.

Remote grants and receipts enter through [remote.bend](remote.bend), backed by
[the independent remote component](../../features/remote/README.md). Native
transport classifies a remote request as an observation or mutation; the commit
boundary composes ordinary command execution with receipt retention.
[remote-proof.bend](remote-proof.bend) binds storage preservation and complete
replay and receipt decisions to those production functions.
