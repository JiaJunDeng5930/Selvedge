# 0030: Concept-local proof providers

## Context

A separate file for each property and its short proof split local reasoning across
many small files. Readers had to move between a concept's public entries and
narrow proof files even when the evidence had no independent consumers. Discovering
providers from a law file's name also coupled proof organization to filenames:
collecting evidence in the concept provider could leave valid laws undiscovered.

## Decision and reasons

Collect local evidence in each concept's `PROOF.bend`. Resolve proof providers by
the actual law identity, comprising its source module and declaration, and require
complete and unique evidence for that identity. This permits local proof helpers
and their consumers to remain together without making a filename convention part
of the proof contract. Bend's [law and qualified-definition syntax](https://github.com/bendlang/bend/blob/main/guide/GUIDE.md)
binds evidence through module declarations, rather than proof filenames.

Keep independently consumed evidence separate where importing the complete
concept provider would introduce an import cycle. Four existing providers retain
that role: `browser/model-proof.bend`, `browser/runtime/platform-proof.bend`,
`browser/document/presentation-proof.bend`, and `harness/protocol/commit-proof.bend`.
These exceptions follow real cross-concept dependencies rather than property size.

A short file can still express a stable public interface or an independent
semantic boundary. Do not merge files mechanically by line count. Concept entries,
executable contracts and import ownership remain authoritative; documentation
does not duplicate their property catalog. The two-level concept directory limit
and the representation boundaries in [ADR 0028](0028-model-representation-boundaries.md)
and [ADR 0029](0029-shallow-concept-directories.md) remain in force. Moved paths
have no forwarding modules or compatibility layer.

## Tradeoffs and evidence boundaries

Concept providers become larger, while readers can follow local evidence without
reconstructing many file boundaries. Qualified law bindings and local helper
names must remain unambiguous during consolidation. Moving a proof does not
weaken its requirements or change which production computation it establishes.

Provider discovery and the compiler proof gate establish different facts:
discovery must find complete, unique evidence, and the pinned compiler must check
that evidence. Neither establishes the host's effect ordering or browser platform
behavior. Those external boundaries retain their focused integration checks and
end-to-end evidence.
