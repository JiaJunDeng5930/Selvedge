# 0053: Work shared interactive UI

## Context

An undertaking needs an interface that remains available while its Tasks and
conversations change. Interactive Markdown already supplies the DSL, bounded
evaluation, controls and browser state restoration. Treating a shared interface
as one Task's reply would make its lifetime and identity depend on that Task.

## Decision

Store the authored source in the existing Work registry and update it through
the ordinary committed kernel operation. This keeps source changes, Work
ownership and restart recovery within the same authority instead of adding a
parallel document store. Resolve the caller's Work from Task lineage, so tools
do not accept an independent target that could disagree with the caller.

Use revision-checked patches because several Tasks can edit the same source.
Keep source admission independent of DSL validity, so an agent can inspect and
repair an incomplete interface.

Give the displayed source its own Work document identity, then reuse the
interactive Markdown document engine. This separates its lifetime from reply
history while retaining the same interpretation and local interaction behavior.
Shared authored source does not require sharing browser-local drafts or
command feedback between users or devices.
