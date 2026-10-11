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
