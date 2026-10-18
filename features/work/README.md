# Work

A Work names the continuing undertaking that owns root Tasks and Task graphs.
It is independent of Project and of the Task execution graph. Tasks may have no
Work. A root's recorded owner cannot be transferred; a derived Task observes its
root's owner through the existing Task lineage, without another membership write.

An Agent can discover "this Work" by calling `read_current_task` with no arguments.
Its Task summary includes its ID and nullable `work_id`. Calling `read_work` with
that Work ID provides the graph IDs to inspect and edit.

Start with [MODEL.bend](MODEL.bend) for ownership observations and command
resolution, [SPEC.bend](SPEC.bend) for complete decisions, and
[PROGRAM.bend](PROGRAM.bend) for the independent implementation.
[CONTRACT.bend](CONTRACT.bend) and [PROOF.bend](PROOF.bend) bind refinement,
intended writes and ownership preservation to production functions.
[CODEC.bend](CODEC.bend) owns the JSON command and query vocabulary.

The registry uses the existing finite association map for Work records, explicit
root ownership and graph ownership. Root and graph references are checked against
their actual registries by [feature assembly](../../harness/features/README.md).
The `create_work_task` command accepts the optional boolean `create_worktree`,
which defaults to false. The assembly uses the ordinary Task operation or the
managed-worktree Task operation and records the new root in the same complete
decision. Worktree rejection leaves the original world and emits no effects.
It also derives query Task IDs
from each Task's identity and lineage. This module has no Task execution or host
effects.
