# Physical layout

Allocates measured content in physical space and realizes renderer plans and receipts.

Start with [MODEL.bend](MODEL.bend), [PROGRAM.bend](PROGRAM.bend) and
[CONTRACT.bend](CONTRACT.bend). The contract composes the boundaries in
[geometry-contract.bend](geometry-contract.bend),
[allocation-contract.bend](allocation-contract.bend),
[measurement-contract.bend](measurement-contract.bend) and
[render-contract.bend](render-contract.bend).

[HIERARCHY.bend](HIERARCHY.bend) constructs frames for members, headings and
separate groups. Its production geometry evidence is part of
[geometry-proof.bend](geometry-proof.bend).
Its flat member frame keeps same-level member spacing without adding physical
indentation; the nested member frame retains the owning hierarchy's inset.

[ADAPTATION.bend](ADAPTATION.bend) observes the actual allocated inner width of
identified regions; [adaptation-proof.bend](adaptation-proof.bend) binds its
complete traversal and attribute membership equations to production. Inert
regions remain in this geometry query because disabling interaction does not
remove their allocated space. Opening a foreground dialog must therefore retain
the background supporting region's width observation and presentation form.

[ACTIVITY.bend](ACTIVITY.bend) owns the independent positive motor-target minimum, initial writing-line count
and shared composer clearance. [activity-contract.bend](activity-contract.bend)
binds these relations to the actual property geometry, message normalization and
action frame. The input producer encodes the writing-line count in its native
field policy; `SOURCE.field_natural_height_at` multiplies that count by the
actual resolved line height and combines it with bounded measured growth.
[field-dimensions.bend](field-dimensions.bend) owns that sizing policy;
typography supplies the resolved line height.
Message normalization retains complete style correspondence for every capacity, with the production message-input selection bound to that operation; [activity-proof.bend](activity-proof.bend) supplies the evidence in
the owning layout requirements.

Evidence follows complete responsibilities: [geometry-proof.bend](geometry-proof.bend)
for geometry, [allocation-proof.bend](allocation-proof.bend) for packing and
allocation, [sizing-proof.bend](sizing-proof.bend) for measured dimensions and their
source correspondence, and [render-proof.bend](render-proof.bend) for renderer
realization. [PROOF.bend](PROOF.bend) assembles the receipt and lifecycle evidence
needed by its clients. The repository [PROOF.bend](../../PROOF.bend) imports all
production providers.

Measurement receipt validation belongs to
[physical-content-measurement.bend](physical-content-measurement.bend), beside the
production computation that consumes it. The executable contracts remain the
authority for the obligations, independently of proof-file organization.

A viewport receipt belongs to the request's generation, owner, exact target key
and measurement purpose. Lookup returns the first complete valid receipt,
including its original bounds and payload. An invalid observation cannot supply
part of a later receipt.

`ACTIVITY.bend` supplies common role dimensions and bounded natural-width
policies. Its reference advances are supplied by callers from the actual
activity font observations; it neither approximates them from line height nor
stores another calibration cache. The activity contracts bind these policies
to the production operations.

`RENDERER.owned_nodes` returns the complete owner-matching document nodes in
input order, including repeated owners and all native payloads. The requirement
is the stable owner filter used by the actual renderer.

Primitive receipts must satisfy generation, key, purpose, shape and the requested
node's dimension rules. Width-specific heights match both key and width; a
permitted zero height is a present measurement. Empty interactive content may
admit zero natural height only for its own actual UI target. Foreign targets,
rootless content and width-constrained measurements do not gain that exception.
Missing measurements produce the actual pending requests; invalid dimensions
produce an error; fully admitted receipts produce the prepared allocation.
These admission and preparation requirements are stated independently in
[measurement-requirements.bend](measurement-requirements.bend) and bound to the
production operations by [measurement-proof.bend](measurement-proof.bend).
