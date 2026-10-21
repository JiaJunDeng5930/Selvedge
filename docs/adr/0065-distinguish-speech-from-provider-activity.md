# 0065: Distinguish speech from provider activity

Date: 2026-10-21
Status: Accepted

## Context

A provider's activity records and its assistant messages have different meanings.
The original conversation view distinguished them, while the audio adapter used
the role alone. The initial Rocq migration also lost the order of text and image
parts when it appended images after the message text. These discrepancies affect
readers, speech and history consumers of the same stored conversation.

## Decision

Keep the original provider payload for audit and share the assistant-message
classification across its consumers. A role on a reasoning or compaction record
does not turn that record into speech. Keep plain text and Markdown as explicit
projections for their respective uses; the message's Markdown projection retains
the original content-part order. Presentation consumes that projection without
adding a second image sequence.

Advance the single current journal format to `selvedge-rocq-journal-4`. History
queries are also available as native model tools. Their results become recorded
function outputs, so corrected message classification can change a durable
decision even though a direct history query does not mutate the world. History
search consumes the plain-text projection; presentation consumes Markdown.
Reject earlier formats before replay instead of interpreting their receipts under new
semantics or adding a compatibility implementation.

## Limits

The shared classification establishes which stored items represent speech; it
does not establish the truth of model output or the behavior of an audio
provider. Extraction, the journal interpreter and physical media remain their
respective external trust boundaries.
