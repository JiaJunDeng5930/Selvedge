# Local proof boundaries

The component-local providers `task-storage.bend` and `reasoning-locality.bend`
quantify over unknown surrounding state and effect types. The application
reasoning provider reuses those proof values. `../feature-laws.bend` composes
feature refinement with explicit evidence for task creation, and
`../locality.bend` binds update and preservation guarantees to production dispatch,
storage functions. `feature-frame.bend` supplies board storage evidence.

Task storage's production `update_state` specializes the abstract
`Tasks.update_carrier` computation to the domain model's task observation and
write operation. Its provider proves the complete required update and frame
preservation for arbitrary surrounding state; client proofs use that storage
operation instead of expanding its concrete task list reconstruction. The locality
replacement fixture changes that reconstruction and discharges the same local contract with the imported `app_nil_r` theorem;
all client proofs remain byte-identical. The extension fixture likewise checks
the full proof root with the original global UI, wire and native entry frozen.

The locality, Core and Web contracts group existing obligations by responsibility;
their assembly still requires every group's evidence. Grouping is a reading
boundary, not an optional proof tier. Public clauses quantify whole private
states and use observations and intended updates. Representation-specific
providers may destructure those states to discharge the original equations;
their source paths are explicit owners in `../../components.json`. This does not
make every client proof independent of representation. The source ownership gate
checks private construction and patterns, while the proof gate retains complete
decisions, completion correlation and ordered effects. The `test:locality`
fixtures provide separate evidence through frozen clients and native entry points.

Preservation is scoped to the component operation that owns it. A law quantifying
over all future feature events while freezing their entire state would prevent
legitimate extensions.

`PROOF.bend` only assembles `CONCEPTS.Harness`. Each module here closes one
boundary through the shared `LAWS.bend` or architecture declarations.

[board.bend](board.bend) constructs the production board refinement and callback
evidence declared in [../board-architecture.bend](../board-architecture.bend).
[../../tests-bend/board-proof.test.mjs](../../tests-bend/board-proof.test.mjs)
challenges that production binding using type-correct defects, rather than
treating a successful checker invocation as evidence that the specification
detects those defects.

Provider imports are explicit: Bend rejects using an unfilled law as live proof
evidence. Modules consume sibling laws through their declared interfaces, not
sibling-private helper functions. The complete dependency graph is acyclic.

The trace module proves only the application's tape/fold correspondence and
one-step correspondence. Simulation, partition and invariant lifting come from
the original Stdlib iterator certificates. Imported evidence is rebound through
pointwise application when the checker does not identify two function names;
this does not assume function extensionality.

The association-map deletion proof is generated from the original ExtLib proof,
not maintained as another project induction. Consuming an operation right is a
domain value adapter applied to that theorem. Result routing, error ownership and
which product component changes remain domain obligations: a generic map or
simulation theorem cannot choose those meanings for the application.

`scripts/verify-proof.mjs` requires the pinned compiler's pure-success report.
Unsafe or foreign dependencies, missing evidence and unexpected reports fail
both ordinary checks and cached builds. MAIN alone owns the external IO boundary.
