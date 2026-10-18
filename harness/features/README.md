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
queries. Work task creation resolves through the ordinary start operation, then
records membership in the same decision before scheduling. The independent
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

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.
