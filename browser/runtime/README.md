# Browser runtime

Combines platform observations, native fields and physical browser transitions at the native browser boundary.

For the representation-independent application and display interfaces, start
with the root [MODEL.bend](../../MODEL.bend). The root proof binds them to the
production runtime and its evidence. For concrete runtime details, start with [MODEL.bend](MODEL.bend), [PLATFORM.bend](PLATFORM.bend), [CONTRACT.bend](CONTRACT.bend), [PROOF.bend](PROOF.bend).

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.

Native recovery construction is supplied by the independent
[utility provider](utility-proof.bend), loaded by `MODEL` before its live source
consumer. Its factory retains membership of the caller's actual request, and
complete constructor correspondence identifies the returned node with that
request's raw recovery calculation. The provider uses
`frontend-utility.source_with_recovery` to replace only the recovery children with
constructed nodes; diagnostic and layout calculations stay shared. Independence
from the assembled runtime avoids an import cycle, while provider-before-consumer
order satisfies the pinned compiler's live-reference checks. Formal acceptance
and focused construction checks completed; their scope is recorded in
[the exploration notes](../../docs/bend2-exploration.md). Physical browser behavior
and external effects remain separate verification boundaries.

Normal physical receipts continue the production display calculation. A terminal
failure uses the same recovery producer as the initial build, making its reason
available through the existing recovery view. Utility measurement retains its
own bounded fallback.

The physical runtime retains navigation attention alongside its render lifecycle.
Native owner and hover-capability observations enter through `PLATFORM`; the
runtime validates owners against the current semantic navigation. Interest-only
publication uses the current candidate and supporting form. The runtime's
navigation contract binds its transient-state update and the new layout derivation.

Normal frame forwarding carries `FRAME.expectations` from the published
allocation into the semantic observation. This projection retains effective
exposure and optional command availability while omitting inert subtrees. It
shares exposure meaning with the utility frame contract; native content,
scrolling and focus remain responsibilities of the normal semantic observer.

Font preparation requests Body and both actual activity-role fonts together.
`measurement_plan` and browser receipt acceptance share the same generation-owned
specifications. Candidate construction remains `WaitingFont` until both activity
metrics are retained; the existing font cache supplies the additional observations.
The preferred navigation width, readable navigation minimum and main writing
minimum are inputs to joint allocation, not a guarantee that any candidate fits.

New layout derivations, including explicit remeasurement and navigation attention
changes, begin at the full candidate. Each ready full form compares the preferred
single-line demand of its actual supporting region with that region's allocated
inner width. The compact form is admitted only after actual physical allocation
has reached Ready; it does not use a viewport threshold. Pending receipts resume
their current candidate and engine within the same derivation.

A new source creates a new snapshot generation and re-observes physical metrics;
old generation-bound physical receipts are not reused. The actual font cache,
application state, anchors, displayed publication and attention remain retained.

`measurement_plan_at` is the production role-font request operation for every
capacity and runtime state. Its contract binds that actual operation to the full
font-cache request protocol and both actual role specifications. The public
`measurement_plan` delegates to the same operation at `NaturalSize.limit()`;
the fixed physical capacity changes neither the cache branches nor the protocol.

Role-metric calibration follows the same production boundary: `calibrated_body_at`
looks up the actual requested-capacity metrics, `calibrated_activity_metrics_at`
passes all three actual metrics to `DESIGN.parameters`, and
`calibrated_parameters_at` authors the actual source at that capacity. Their
public fixed-capacity callers delegate at the unchanged physical limit. Both the
complete successful calibration equation and missing-metric waiting obligation
apply to every physical capacity, candidate index and runtime state.
