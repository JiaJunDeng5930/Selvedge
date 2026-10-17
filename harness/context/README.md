# Tracked model context

[MODEL.bend](MODEL.bend) provides the definition language and its shared
interpreters. [KINDS.bend](KINDS.bend) assembles the concrete definitions; start
there when adding a kind. The instruction, project guidance and skill modules
contain the existing definitions and their business-specific projections.
[CONTRACT.bend](CONTRACT.bend) and [PROOF.bend](PROOF.bend) bind the construction
families to actual snapshot admission, patch application and history operations.
Adding a definition reuses those properties rather than adding another proof.

The definition controls which source is observed, which fields may change and
which fields must agree with source identity. Internal revisions reject patches
against an obsolete baseline. Models receive the source identity and concrete
edits; the initial introduction supplies the meaning needed to use the content.
Text offsets count Unicode characters in the same baseline, in increasing,
non-overlapping order. Only introductions contain complete values.

[ADR 0042](../../docs/adr/0042-context-definition-construction.md) explains why
the definition language is shared across observation and history. The extension
fixture in [context-definitions.test.mjs](../../tests-bend/context-definitions.test.mjs)
adds kinds while freezing the generic implementation, proofs and host consumers.

## Endpoint input selection

Separates the immutable task history from the input selected for a concrete
endpoint and account scope. Start with [selection.bend](selection.bend),
[PROGRAM.bend](PROGRAM.bend), and [selection-proof.bend](selection-proof.bend).

The original history remains the recovery source. A replacement event records a
complete returned window and the captured source length. Selection preserves
fixed task context and appends only records after that captured source. Native
items require their actual consumption scope; portable rebuilding uses the
readable original records, never a previous opaque replacement.

Tracked context introductions and their subsequent edits remain together when
selecting a compressed input. A summary replaces conversational records while
their tracked context history supplies every required edit baseline.
