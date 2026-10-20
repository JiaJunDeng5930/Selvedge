# Preserve history while replacing model context

The additive checkpoint path retained the full original input in later model
requests. It preserved recovery material but did not reduce the context window.
Appending a summarization instruction as a user message also mixed maintenance
with the conversation being summarized. Native opaque output introduced a second
constraint: its use depends on the actual consuming endpoint/account scope.

We retain the immutable original history and record a complete replacement
window together with the source span captured by its committed operation.
Target-context selection consumes a compatible replacement and exactly the
original records appended after that span. The original public records remain
the rebuilding source when an endpoint cannot consume an opaque replacement.
Keeping the source and the selected representation separate avoids binding task
recovery to the lifetime or compatibility of a particular native artifact.

The Web adapter binds root-reset authorization to the captured replacement source
span in its existing invocation identity. This permits a new root for an explicit
replacement while retaining unknown-outcome requests from that same root.

Automatic compaction owns independent feature state rather than taking over the
ordinary task phase. This permits early work alongside inference, while the
hard threshold can wait for the same correlated operation. The native model
receives complete request measurements and clock observations and decides when
to start, wait, continue or adopt. The host interprets committed effects only.
Every individual compaction call has a fresh ticket; a whole operation is not
mistaken for one request. Its captured useful-work revision prevents idle work
from covering later additions or repeatedly rearming itself.

The client method processes bounded fragments and a bounded carry from retained
readable history. It has no requirement that the entire source fit a larger
model. Native compaction and client compaction both return whole replacement
windows. Measuring the complete target encoding before dispatch and adoption
keeps producer accounting separate from consumer accounting. Transport admission
also measures the encoded plan before it leaves Bend: a model token window does
not bound JSON bytes. Chunk sizing reserves the actual carry and metadata, then
checks the final encoding, so large Unicode sources remain dispatchable.

The implementation does not introduce missing-original-history, no-configured-
method or permanently unshrinkable-tail business states. Original retention,
legal enabled-target budgets and a configured client method are requirements of
the normal system. Transport errors remain ordinary correlated invocation
errors. No compatibility shims or obsolete checkpoint lifecycle are retained.

Remote summary fidelity and provider accounting remain external contracts.
Production Bend requirements and proofs carry the internal selection, cursor,
correlation and adoption rules; HTTP, journal and restart tests cover their
physical boundaries. This decision records the reasons for the organization,
not a second authoritative lifecycle specification.
