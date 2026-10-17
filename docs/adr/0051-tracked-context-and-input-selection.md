# ADR 0051: separate tracked context definitions from input selection

## Context

The tracked-context work and automatic compaction independently introduced
`harness/context/MODEL.bend`. They describe different operations: one admits
source values and applicable deltas, while the other chooses an endpoint's input
from retained task history. Combining their imports would introduce a cycle:
task values depend on the tracked schema, and input selection depends on tasks.

## Decision

Keep the tracked definition language in `MODEL.bend` and place the input-selection
specification in `selection.bend`, with its evidence in `selection-proof.bend`.
The selection implementation retains its existing `PROGRAM.bend` entry. Assemble
both proof providers at the production root rather than importing selection into
the tracked schema.

Preserve source observation before model dispatch and manual compaction. This
lets compaction select from committed context changes instead of allowing host
request preparation to refresh instructions privately. Selection retains fixed
context events, including the introduction and amendments needed to interpret
each tracked source, while ordinary conversation can use the committed compacted
window.

Use a new current journal format, `selvedge-bend-journal-6`, for the combined
tracked-context, task-graph and compaction commit semantics. Earlier formats are
rejected explicitly; no replay adapter or migration is introduced.

## Consequences

New tracked kinds continue to use the same definition constructors and generic
evidence. Endpoint selection can evolve against task history without entering
the schema's import closure. The integrated production proof and external
boundary tests must cover observation, replacement selection and dispatch in
their actual committed order.
