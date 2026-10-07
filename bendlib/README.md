# Bend support definitions

Read the root CONCEPTS, COMMANDS and MODEL entry points before following an
implementation detail into this directory. INVARIANTS and LAWS constrain changes.

`domain.bend` owns the task types, shared task/project resources and initial core
state. `component.bend` combines a local state with an opaque remainder and retains
complete replies and ordered effects. `effects.bend` leaves feature payloads as a
type parameter. Task, approval, hook, result and reasoning implementation modules
belong to the closed core import boundary declared in `../components.json`.

Read state observations and intended updates in the owning model before following
its representation. For example, `domain.bend` exposes `state_tasks` and
`with_state_tasks`; clients use these operations without opening `State`.
Transparent task, command and view values remain public vocabulary. The
`model_representations` policy in `../components.json` separately declares private
constructors and their implementation and representation-proof owners; it does
not change the closed core import boundary.

`../FEATURES.bend` selects concrete feature state and vocabularies; `../MODEL.bend`
composes them with the task component. The `feature-*` modules connect private
commands, resolved operations, completion correlation, codecs, resource checks
and UI updates to the application. `feature-spec.bend` receives the independent
task-creation specification; `feature-execution.bend` receives its implementation;
`feature-laws.bend` requires their complete-decision correspondence when composing
the proof. `feature-architecture.bend` collects the feature guarantees.

The semantic interface is in [../UI.bend](../UI.bend) and
[../core/interface.bend](../core/interface.bend). Feature command encoding is in
[feature-codec.bend](feature-codec.bend).

`tasks.bend` performs task storage through `update_carrier`, parameterized by an
unknown carrier and its task read/write operations. Production `update_state`
specializes it to `domain.State`, `state_tasks` and `with_state_tasks`;
`update_world` applies the existing component frame operation.
`proofs/task-storage.bend` and `proofs/reasoning-locality.bend` prove actual
task-component behavior for arbitrary surrounding types.
`proofs/feature-frame.bend` supplies board storage evidence. `locality.bend`
requires these providers through its task storage, reasoning and board storage
groups. The grouped contracts in `../core/contract.bend` and `../webui/laws.bend`
likewise retain mandatory evidence at their production assembly points. Pure
execution modules do not import their proof providers, so mutation tests can independently
check that an erroneous implementation remains type-correct.

Board requirements are in `../BOARD.bend` and `board-resolution.bend`.
`board-spec.bend` specifies complete mutations and drafting settlement;
`board-scheduling-spec.bend` specifies the use of ordinary task execution.
See [../core/ui-world.bend](../core/ui-world.bend) for page observations and
[../core/interface.bend](../core/interface.bend) for the semantic interface.
Ordered cards reuse the existing finite map and
standard list operations; there is no browser-side board state machine.

`../UI.bend` owns the platform-independent presentation and event semantics.
`wire.bend` decodes that public vocabulary; `protocol.bend` uses the ordinary
command resolver, and `commit.bend` projects the post-scheduling world before
atomic output admission. The surface's read-only observation and command gates
are carried by `architecture.UserSurface` and checked in `proofs/ui.bend`.
`conversation.bend` owns request titles and shared provider-text decoding.
`conversation-spec.bend` independently observes ordered speech, original audit
records, result values/errors and composer intents. `proofs/conversation.bend`
binds those observations to the production UI helpers; `UserSurface` requires
their evidence. These laws do not assert browser geometry or provider quality.

`../APPROVALS.bend` independently resolves one-operation permission requests and
their human or model decisions. `approval-architecture.bend` binds the executing
request, review and grant boundaries to evidence in `proofs/approvals.bend`.
The shared review refinement is the public `LAWS.review_semantics` obligation,
provided by `proofs/protocol.bend`, not a sibling-private proof helper.

`../HOOKS.bend` owns ordered task-bound authorization and result interpretation.
`results.bend` consumes execution receipts, advances after callbacks and settles
processed results. `architecture.ResultBoundary` binds every pipeline entry and
exit as well as value/error/call correspondence; `proofs/results.bend` supplies
that evidence. `notifications.bend` projects
typed post-commit occurrences and frozen recipients; it cannot change the core
state, reply or effect projection. `architecture.PluginBoundary` binds both to the
conceptual entry through public laws and `proofs/plugins.bend`. Transport-specific
plugin logic belongs to the host, not a second task model. The explicit child-birth
record preserves public fork output while distinguishing inherited from new events.

`stdlib.bend` is generated from existing Rocq standard-library proof terms, with
provenance and regeneration instructions in `../theory/README.md`. `theory.bend`
instantiates those certificates for append, replay composition and stuttering.
It does not maintain a second recursive algebra development.
`architecture.bend` stores domain correspondence and theorem-premise evidence
below the CONCEPTS entry. Consumers use existing list/map/iterator theorems
directly; there is no project-owned general algebra or simulation hierarchy.
`association-map.bend` imports the original ExtLib association-list definitions
and deletion-absence proof. `domain.Operation()` uses its key/value representation
directly, so `operations.bend` only adapts the domain value returned by lookup.
`relations.bend` is generated from original relational-closure proofs and explicit
theorem applications. `reachability.bend` binds their edges to actual inputs and
complete committed decisions; `CONCEPTS.Composition.protocol` requires preorder,
batch flattening, simulation, safety and exact journal/receipt correspondence.
`proofs/reachability.bend` supplies only the single-step and representation
obligations; arbitrary-path results reuse those checked source proofs.
Batch recovery, task views and branch results use the imported map correspondence;
partition and map-composition results instantiate original library theorems.

`interface.bend` specifies the pure native packet protocol; `frontend.bend`
implements it, including malformed JSON, failed decoding and durability. Both
are in the proof closure. MAIN only performs IO. The modules in `proofs` consume
declared laws through explicit provider imports; see `proofs/README.md`.

[domain.bend](domain.bend) contains `context_history`;
[../INVARIANTS.bend](../INVARIANTS.bend) contains `settled_calls`.

`json.bend` preserves JSON number spellings and provides bounded decoding and
rendering. `schema.bend` checks the supported command and built-in tool schemas.
`wire.bend` decodes external messages to MODEL inputs. `presentation.bend` renders
model values and decisions. None of these modules performs an operating-system
effect; all external work crosses the host boundary.

Run `npm run check` for the proof gate and `npm test` for compiler/protocol probes,
host components, end-to-end behavior and proof-infrastructure mutations. Internal
semantic examples already covered by proofs are not duplicated as unit tests;
see `../tests-bend/README.md`. Changing a Bend source changes the journal identity.
