# Feature composition

Assembles independent feature state and vocabulary into the harness and binds feature behavior to task creation.

Start with [MODEL.bend](MODEL.bend), [SPEC.bend](SPEC.bend), [CONTRACT.bend](CONTRACT.bend), [CODEC.bend](CODEC.bend).

For command interpretation, follow `construct_command` in
[resolution.bend](resolution.bend) to `realize` in [execution.bend](execution.bend).
For completions, follow `construct_event` in [protocol.bend](protocol.bend) to
`event` in [execution.bend](execution.bend). Assembly captures the current world
at interpretation and consumes the construction immediately. Board launches
use ordinary task creation through this assembly and the core harness.

[Work](../../features/work/README.md) owns organizational membership independently
of Projects and execution settings. [work-state.bend](work-state.bend) reads a
Task's immutable root association through its fork lineage and assembles Work
queries. Work task creation resolves through the ordinary start operation or,
when `create_worktree` is true, the managed-worktree start operation. Both record
membership in the same decision before scheduling; a rejected creation retains
the original world without effects. The independent
meaning in [SPEC.bend](SPEC.bend) and the production calculation in
[execution.bend](execution.bend) are connected by
[work-proof.bend](work-proof.bend) and [laws.bend](laws.bend).

The native catalog in [MODEL.bend](MODEL.bend) authors `read_current_task` with
the existing `Native.Caller` query argument. The kernel binds the calling Task
and returns its ordinary Task summary, including `work_id`; `read_work` then
provides that Work's graph IDs.

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

The assembled state coordinates are Board, ChatGPT, Task graph, Compaction,
Worktree, Remote and Work, followed by the identity remainder. Every storage
boundary preserves the unrelated coordinates, including Work ownership during
Remote administration and worktree completion.

`workspace_observation` projects public command kinds into stable directory
observation categories for the host adapters. Feature command cases remain in
this assembly; external consumers interpret only the returned categories.
