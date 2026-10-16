# Tracked model context

[MODEL.bend](MODEL.bend) defines typed context identities, initial snapshots and
checked text or skill metadata patches. [PROOF.bend](PROOF.bend) binds accepted
observations to the actual reconstruction and append operations in the task
history. Context revisions describe a source's content; source identity does not
include its revision. Text edit offsets count Unicode characters in the same
baseline, in increasing, non-overlapping order.

Instruction, project guidance and skill information remain distinct categories.
Only introduction records contain a full value; amendment records contain the
verified patch. The current bindings are derived by folding the append-only
history. Settings and reasoning configuration retain their existing semantics.
