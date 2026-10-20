# ADR 0041: contextual changes as verified history deltas

## Context

ADR 0040 makes committed model history the sole source of task instructions.
Freezing its initial guidance avoids unrecorded prompt changes, but prevents an
existing task from receiving instruction and guidance edits. Repeating complete
snapshots for every edit would spend context on unchanged material and leave
replacement and deletion implicit.

Skill metadata has the same recording requirement once it is introduced to the
model. That does not make arbitrary tool output a tracked instruction source, or
make discovering a skill equivalent to loading its body.

## Decision

Keep the semantic categories distinct and share their change representation.
The first introduction records a value; subsequent revisions record a patch or
withdrawal addressed to the same stable source identity. A content revision is
not part of that identity. Current accepted values are derived from this history.

Observe external sources through a committed effect before requesting a model.
The kernel accepts the completion and commits the changes before emitting the
actual model request. This preserves the existing request/history correspondence
instead of allowing host request preparation to modify a prompt privately.

Use a bounded mature diff implementation to propose ordered Unicode text edits.
The Bend operation checks the base and the result against the observation before
recording the proposal. This keeps the diff algorithm replaceable without
trusting its output as a state transition. Field changes in skill metadata retain
their own typed patch. Models see the same source identity, revision relation and
precise changes; the reconstructed full value is not appended again.

Start skill support with explicit configured file paths and metadata only. This
makes the injected content and observation boundary inspectable without adding a
directory discovery policy or eagerly injecting skill bodies.

## Consequences

The input journal can retain full external observations while model history
contains only the first value and subsequent deltas. Their different purposes do
not require another authoritative prompt store. Summaries remain fallible notes;
they cannot replace the exact baseline and delta chain. Provider continuation
retains its existing prefix and receives the new records as a suffix.

Observation failures do not withdraw content. Instruction changes do not change
workspace, sandbox or tool authority. A read of a file through an ordinary tool
does not by itself introduce a tracked context object.
