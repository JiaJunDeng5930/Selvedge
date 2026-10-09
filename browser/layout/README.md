# Physical layout

Allocates measured content in physical space and realizes renderer plans and receipts.

Start with [MODEL.bend](MODEL.bend), [PROGRAM.bend](PROGRAM.bend) and
[CONTRACT.bend](CONTRACT.bend). The contract composes the boundaries in
[geometry-contract.bend](geometry-contract.bend),
[allocation-contract.bend](allocation-contract.bend),
[measurement-contract.bend](measurement-contract.bend) and
[render-contract.bend](render-contract.bend).

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
