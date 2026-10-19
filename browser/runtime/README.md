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
order satisfies the pinned compiler's live-reference checks. Physical browser
behavior and external effects remain separate verification boundaries.

Normal physical receipts continue the production display calculation. A terminal
failure uses the same recovery producer as the initial build, making its reason
available through the existing recovery view. Utility measurement retains its
own bounded fallback.

The physical runtime retains navigation attention alongside its render lifecycle.
Native owner and hover-capability observations enter through `PLATFORM`; the
runtime validates owners against the current semantic navigation. Interest-only
publication uses the current candidate and supporting form. The runtime's
navigation contract binds its transient-state update and the new layout derivation.

`DisplayUpdates.semantic_latest` records the last semantic update in the existing
display revision sequence. Navigation interest alone advances presentation while
preserving this stamp. `display_pending` still schedules and marks every pending
publication; `semantic_pending` disables external actions only while publication
predates the semantic stamp. Both native enabled-state synchronization and action
admission use that same rule, retaining event/mount ownership and service checks.
An attention update cannot clear earlier semantic lag, and publishing an older
active candidate cannot enable an action against newer semantic state.

Native synchronization validates each published field against its complete
current owner, schema and mount occurrence. Text, number and textarea controls
show the shared raw draft; sliders, selections and checkboxes show canonical
values. Updates retain field order and preserve composition. Field ownership
uses the whole surface; external actions also require the current foreground
scope, enabled state, fresh authorized sources and current semantic publication.

Identical commands already awaiting a receipt are sent only once. A second
interactive submission receives failure feedback for its own owner, component
path and ticket, so its button stops waiting without settling the first request.
The pending command, receipt and ticket source remain unchanged; rendering and
focus effects from that feedback still reach the browser.

`commit_refresh_needed` classifies a dequeued watch commit against the current
accepted state. A notice already covered by that namespace and durable sequence
needs no refresh while sources remain fresh, allowed and Connected. A malformed
or out-of-native-range sequence conservatively requests a refresh. Pending
publication does not change this decision. Initial refresh, authentication,
newer commits and subsequent stream notices retain their existing processing;
no last-notice cache is retained.

Normal frame forwarding carries `FRAME.expectations` from the published
allocation into the semantic observation. This projection retains effective
exposure and optional command availability while omitting inert subtrees. It
shares exposure meaning with the utility frame contract; native content,
scrolling and focus remain responsibilities of the normal semantic observer.

Authored Markdown nodes own their delegated native links as content focus.
Observing that focus retains the complete owner and link identity without
requesting the document's initial product focus.

Current-layer inspection reports the foreground interaction owner: attachment
preview, directory picker, settings, a declared modal/menu, then modal navigation.
Nonmodal details do not take that ownership. Inspection combines this current
scope with the published frame, its native ownership and tab order. Document
scope does not require modal target retention; a temporary scope retains its
ownership checks, initial focus and dismissal behavior. Loading a temporary
layer hands focus from its root to the ready initial control only while the
user's focus still belongs to that root.

Font preparation requests Body and both actual activity-role fonts together.
`measurement_plan` and browser receipt acceptance share the same generation-owned
specifications. Candidate construction remains `WaitingFont` until both activity
metrics are retained; the existing font cache supplies the additional observations.
The preferred navigation width, readable navigation minimum and main writing
minimum are inputs to joint allocation, not a guarantee that any candidate fits.
`SHELL.workspace` reserves the simultaneous Task-navigation and main-content
minimum for navigation-capable candidates, independently of whether the user has
collapsed the Task tree. The enclosing global rail occupies its actual allocated
width separately. A hidden tree therefore cannot make a narrow viewport acquire
desktop Work navigation. The same source minimum remains in force when pending
physical measurements resume.

New layout derivations, including explicit remeasurement and navigation attention
changes, begin at the full candidate. Each ready full form compares the preferred
single-line demand of its actual supporting region with that region's allocated
inner width. The compact form is admitted only after actual physical allocation
has reached Ready; it does not use a viewport threshold. Pending receipts resume
their current candidate and engine within the same derivation.

Source changes advance the latest semantic revision. An active measurement keeps
its frozen source and generation while newer changes coalesce. Its receipt may
publish that complete snapshot; the next candidate immediately measures the
latest revision. A reserved status slot marks presentation lag, and native user
buffers retain newer edits. Old generation-bound receipts never belong to a new
candidate. Physical environment changes restart measurement. Namespace switches
and explicit authorization loss invalidate both the active candidate and displayed
content immediately. The font cache, latest application, anchors and attention
remain owned by the runtime.

`BROWSER.snapshot_environment` accepts the store namespace, sequence and world
atomically. A new namespace resets old pending commands and accepts the new
sequence even when it is lower. Foreign namespace command completions are inert;
ordinary completions cannot restore revoked source access. Parser observations
are driven from canonical Bend documents before geometry measurement. Isolated
measurements consume those accepted scenes without subscriptions or effects.

`authenticated_snapshot` checks the request namespace and current authentication
ticket before observing the returned world. A current authentication can settle
after the world advances without installing its older snapshot. Accepted namespace
replacement starts a fresh authentication ticket; a same-namespace snapshot
reconnects only a lost service. Only an owned successful authentication emits the
`SessionReady` effect that starts the physical watch. `network_failed` correlates
ordinary failures with their namespace, sequence and captured connection ticket, and authentication failures
with their current ticket, before observing staleness or explicit revocation and
the corresponding service transition. The complete ordered decisions are bound
in the runtime contract and proofs.

Physical frame, focus, reading and motion observations retain their actual legacy
decision without starting document synchronization. Source-changing inputs still
synchronize canonical documents. This preserves accepted frame realization;
otherwise internal platform commits would reset it to waiting and request the
same frame indefinitely. The public non-rebuild acceptance law preserves the exact
observed state, outer runtime fields and effects, including pending frame requests.

Command deduplication preserves completion ownership. A second interactive intent
for an identical pending command receives explicit failure feedback for its own
button; it neither replaces the original pending request nor sends another one.

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
