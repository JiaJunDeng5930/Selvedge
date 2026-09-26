# Local proof boundaries

`PROOF.bend` only assembles `CONCEPTS.Harness`. Each module here closes one
boundary through the shared `LAWS.bend` or architecture declarations:

| Module | Obligation |
| --- | --- |
| `protocol` | Public commands, accepted events and internal-call settlement. |
| `execution` | Resolved action meaning and every finite scheduler budget. |
| `commit` | Complete input refinement, admission and bounded output delivery. |
| `frontend` | Exact pure native input protocol, including malformed packets. |
| `safety` | Initial validity and one committed transition's safety certificate. |
| `traces` | Complete receipt simulation, partitioned execution and journal safety. |
| `reachability` | Input-labelled edges, exact journal/receipt correspondence and premises for imported relational simulation/safety. |
| `tasks` | Lifecycle, fork, interruption, recovery and context correspondences. |
| `observations` | Queries preserve both world and effect silence. |
| `ui` | Native presentation, live command gates and state/effect-preserving projection. |
| `plugins` | Unified gate, call identity, task-owned certificates and observer non-interference. |
| `algebra` | Bind standard structures and imported results to production operations. |

Provider imports are explicit: Bend rejects using an unfilled law as live proof
evidence. Modules consume sibling laws through their declared interfaces, not
sibling-private helper functions. The complete dependency graph is acyclic.

The trace module proves only the application's tape/fold correspondence and
one-step correspondence. Simulation, partition and invariant lifting come from
the original Stdlib iterator certificates. Imported evidence is rebound through
pointwise application when the checker does not identify two function names;
this does not assume function extensionality.

`scripts/verify-proof.mjs` requires the pinned compiler's pure-success report.
Unsafe or foreign dependencies, missing evidence and unexpected reports fail
both ordinary checks and cached builds. MAIN alone owns the external IO boundary.
