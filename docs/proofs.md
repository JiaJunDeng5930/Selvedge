# Local proof boundaries

The component-local providers `../harness/tasks/PROOF.bend` and `../harness/reasoning/PROOF.bend`
quantify over unknown surrounding state and effect types. The application
reasoning provider reuses those proof values. `../harness/features/laws.bend` composes
feature refinement with explicit evidence for task creation, and
`../harness/LOCALITY.bend` binds update and preservation guarantees to production dispatch,
storage functions. `../harness/features/PROOF.bend` supplies board storage evidence.

Task storage's production `update_state` specializes the abstract
`Tasks.update_carrier` computation to the domain model's task observation and
write operation. Its provider proves the complete required update and frame
preservation for arbitrary surrounding state; client proofs use that storage
operation instead of expanding its concrete task list reconstruction. The locality
replacement fixture changes that reconstruction and discharges the same local contract with the imported `app_nil_r` theorem;
all client proofs remain byte-identical. The extension fixture likewise checks
the full proof root with the original global UI, wire and native entry frozen.

The locality, interaction and browser contracts group existing obligations by responsibility;
their assembly still requires every group's evidence. Grouping is a reading
boundary, not an optional proof tier. Public clauses quantify whole private
states and use observations and intended updates. Representation-specific
providers may destructure those states to discharge the original equations;
their source paths are explicit owners in `../components.json`. This does not
make every client proof independent of representation. The source ownership gate
checks private construction and patterns, while the proof gate retains complete
decisions, completion correlation and ordered effects. The `test:locality`
fixtures provide separate evidence through frozen clients and native entry points.

Preservation is scoped to the component operation that owns it. A law quantifying
over all future feature events while freezing their entire state would prevent
legitimate extensions.

The root [PROOF.bend](../PROOF.bend) assembles `CONCEPTS.Harness` and imports all
production providers. Local proof units group complete responsibilities beside
their owning concepts. A concept's `PROOF.bend` retains the aggregate evidence its
clients need; it need not import every local provider if that would create a
backedge. Contract composition still requires each responsibility's evidence.

[Layout](../browser/layout/README.md) separates geometry, allocation, measured
size and source correspondence, and renderer realization.
[Document](../browser/document/README.md) separates source validity, rendered
observations and content presentation.
[Presentation](../interaction/presentation/README.md) separates semantic scenes
from surface composition and interaction. Follow those guides to the executable
contracts and their providers rather than treating file size as a proof boundary.

The public vocabularies in [interaction/TYPES.bend](../interaction/TYPES.bend),
[presentation/MODEL.bend](../interaction/presentation/MODEL.bend) and
[presentation/SURFACE.bend](../interaction/presentation/SURFACE.bend) are independent
of their calculating implementations. Validation used by production remains in
production modules; a caller does not import open laws merely to compute validity.

[PROOF.bend](../features/board/PROOF.bend) constructs the production board refinement and callback
evidence declared in [features/board/CONTRACT.bend](../features/board/CONTRACT.bend).
[../tests-bend/board-proof.test.mjs](../tests-bend/board-proof.test.mjs)
challenges that production binding using type-correct defects, rather than
treating a successful checker invocation as evidence that the specification
detects those defects.

Proof discovery resolves each law's module and declaration identity and requires
one complete, unique provider for that identity. Provider filenames do not define
the binding. Bend rejects using an unfilled law as live proof evidence. Modules
consume sibling laws through their declared interfaces, not sibling-private helper
functions. Imports must preserve the dependency order between those providers.

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
both ordinary checks and cached builds. MAIN owns native external IO.
[Browser PLATFORM.bend](../browser/runtime/PLATFORM.bend) defines the browser effect
boundary. Pure model evidence does not establish the concrete platform
interpreter's behavior; focused boundary and end-to-end checks cover those effects.
