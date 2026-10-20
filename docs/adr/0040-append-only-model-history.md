# ADR 0040: append-only model history

The context-selection decision is superseded by [ADR 0041](0041-context-compaction.md).
The requirement to retain immutable original history remains in force.

## Context

Task requests assembled assistant instructions, settings and project guidance at
dispatch time, separately from the stored conversation. A configuration or file
change could therefore change what the model received without changing the
task's recorded history. Reading that history could not uniquely explain the
request, and restoring a task could depend on mutable inputs outside its journal.

Context checkpoints and provider compaction introduced another source of
uncertainty: a stored conversation and the prefix selected for a later request
could describe different model contexts. This made inspection and recovery
depend on request preparation rather than on committed task facts.

## Decision

Use committed task history as the sole source of task model messages and
instructions. Capture instructions and contextual changes when appending them
to that history, before dispatch. The existing input and decision journal owns
their persistence; a separate prompt store would create another account of the
same task.

Root initialization owns the snapshot of current defaults and external
guidance. Forking owns inheritance from the parent's recorded history and the
append of explicitly requested overrides. These responsibilities differ because
a new root selects its initial environment, while a fork continues an existing
conversation. Reading current defaults again during a fork would silently
change the meaning of inherited instructions.

Decoders, transport encoders and provider adapters translate recorded values;
they do not supply additional prompt content. Keeping this boundary mechanical
makes provider choice independent of instruction ownership. Context and audit
records retain their respective meanings when encoded, so recording execution
settings does not grant those settings instruction authority.

Select complete, append-only history for task continuation. Summaries add
information to the conversation instead of replacing earlier messages. A
context-limit failure remains an explicit failure: silently retrying with less
history would violate the chosen source of model input. Provider continuation
may reuse a verified recorded prefix, but cannot select a different context.

## Consequences

Recorded history can explain the semantic content of each task request across
configuration changes and restart. Changes become inspectable additions, and
forks preserve the evidence behind the conversation they inherit. Provider
encoding and external dispatch still require integration evidence; persistence
alone does not establish their agreement with the recorded input.

An additive summary does not reduce context consumption. Long conversations
can reach the provider's limit, and the service must report that boundary rather
than claim that a summary has compressed the retained history.

Superseded persisted formats fail current-format validation. No migration or
compatibility decoder is introduced for this change.
