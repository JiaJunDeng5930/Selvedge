# Capture context history revisions before model preparation

## Status

Accepted.

## Context

Context source IO reads snapshots against the committed history at dispatch.
Tool completions and speech input can extend that history while the read is in
flight. A ticket establishes request ownership but does not establish that a
returned patch still belongs to the current source baseline. Applying such a
patch to the extended history can discard a newer source observation.

The original product retried stale observations and suspended generation when a
task froze or stopped. A manual summary has a different continuation: it must be
cancelled rather than turned into a model generation after resumption.

## Decision

Capture the history length alongside the context observation ticket. Share the
capture and request operation between normal scheduling, manual compaction, and
stale retries. A matching completion applies observations only to its captured
revision; an active task retries a stale read with a new ticket and current
history. Side-task history rebasing updates both the dispatched prefix and its
captured revision before physical IO.

A frozen or stopped generation waits for a new observation after resumption and
emits no IO. Manual compaction continues to own its purpose through the existing
maintenance job, so its suspended callback cancels that job, returns to idle,
and retains the original diagnostic. No second purpose field is added to the
kernel activity.

## Consequences

Late callbacks remain protected by ticket identity. History changes during a
read cannot make an old source patch current, and resumption cannot skip the
required source observation. The current derived snapshot codec follows the
activity datatype without a compatibility format.

Per-source observation admission remains independent: one rejected source does
not discard accepted changes from other sources. These lifecycle rules are
proved against the actual scheduler, callback, and manual compaction operations.
