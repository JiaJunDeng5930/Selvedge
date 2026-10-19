# Interactive Markdown

When a Task and its side conversation are visible together, both document sets
remain active under their independent viewing Task identities. Dismissing the
side window removes that viewing Task from active exposure while retaining its
ordinary saved conversation and local document state.

Owns the bounded declaration language, local input, incremental syntax, expression
evaluation and event admission for explicit `selvedge-ui` Markdown fences. The full
design is [DESIGN.md](DESIGN.md). Executable contracts state the required behavior
of the actual parser, reducer, document lifecycle and source observations.

Start with [TYPES.bend](TYPES.bend) for the independent vocabulary and
[MODEL.bend](MODEL.bend) for production operations. `PARSER` consumes only the
code text reported by the existing Markdown parser. `EXPRESSION` and `DECIMAL`
interpret pure bounded values. `STATE` owns local values and correlated actions;
`REGISTRY` validates ordered declarations and the accepted syntax prefix; `EXPAND`
produces the evaluated component tree with stable identities. `SCENE` and `SOURCES` adapt these public
observations to the application and authored controls without putting World or
DOM operations into the language core.

Contracts and their production evidence live beside these operations. External
Markdown, JSON, storage, native input and measured publication boundaries retain
focused integration and real browser evidence; pure proofs do not establish
those physical assumptions.
Document ownership, prefix admission and freshness are specified in
[documents-contract.bend](documents-contract.bend); canonical persistence is
specified in [snapshot-contract.bend](snapshot-contract.bend). Their adjacent
proof files bind those requirements to the actual operations.

The public operations are `MODEL.initial`, `MODEL.step`, `MODEL.observe`,
`MODEL.source_requests`, and `MODEL.eligible_fence`. `DOCUMENTS` owns the outer
Markdown origin, parser observation and interrupted-output lifecycle. A core
`Owner` is supplied by that layer; it never derives identity from source text or
DOM position. Each event is checked against the current expanded node and mount
occurrence before local state or an external effect can change.

Command feedback is a separate transaction. Only the first still-pending item
with the captured owner, epoch, component path and ticket may settle. It changes
that feedback and the visible revision, preserving values, drafts, definitions,
views, mounts and the next ticket. It emits no action or storage effect and does
not interpret the definition again. The public reducer contracts cover complete
decisions for this correlation and for unowned or currently invisible events.
Successful field and action contracts also bind the public reducer to complete
owned transactions: declared canonical/raw/validation changes, current expansion,
stable or fresh mount generations, bounded snapshots and ordered capability
intents. Unrelated blocks are preserved. Occurrence allocation is constrained by
freshness and continuity rather than a fixed traversal's counter increments.

Controls bound to one root state share its raw editing text and validation.
Text, textarea and number editors retain that draft; sliders, checkboxes and
selections display the last valid canonical value. Each native editing session
still belongs to its exact component and mount occurrence. Invalid drafts do
not change calculations and are not saved in snapshots.
Numeric initial values, edits, assignments and restores must also match the
exact step grid anchored at `min`, or zero if no minimum is declared. Rejected
values are never silently clamped. Integer step defaults to 1 and number step
to 0.01; an explicit `step={0.000001}` admits all six-place decimal values.

Syntax failure preserves the accepted tree. Fatal declaration and structural
failures cut acceptance at the first offending component, including later dataset
rows. Invalid dataset rows produce a local diagnostic and are skipped; later
valid rows continue to be accepted.
Local expression failures remain visible and propagate to dependent components.
The expression evaluator shares one step budget across value validation,
comparison, declaration evaluation and expansion. Decimal arithmetic has six
fractional places, rounds ties away from zero, and rejects overflow and zero
divisors.

Snapshots contain only local canonical values with their complete schemas and
bounded graph/table view values. Restore validates the whole entry, constructs a
pure trial with the restored root values, checks view ownership, then commits it
once. It cannot execute an authored action, replace newer edits, restore source
facts, or reintroduce a pending command.
Conditionally hidden views keep their typed local state. A dynamic view is
discarded when its observed parent explicitly removes the item; an unavailable
or hidden parent does not establish removal. Restoring a dormant view grants no
mount identity or action permission.
Save and restore share a 262144-scalar encoded-payload limit. Larger local state
remains usable in memory, shows an unsaved notice, and emits no storage write;
reducing it below the limit allows saving again.

Streaming work is scheduled in turns of at most 256 complete DSL tokens, with an
8192-scalar token limit and a shared 100000-step definition/evaluation budget.
The independent raw-input limit is 16384 scalars. Oversized input keeps its prior
bounded buffer and value, emits a typed rollback for that exact mounted field,
and reports validation without saving the rejected text.
