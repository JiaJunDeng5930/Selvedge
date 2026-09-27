# Bend support definitions

Read the root CONCEPTS, COMMANDS and MODEL entry points before following an
implementation detail into this directory. INVARIANTS and LAWS constrain changes.

`../UI.bend` owns the platform-independent presentation and event semantics.
`wire.bend` decodes that public vocabulary; `protocol.bend` uses the ordinary
command resolver, and `commit.bend` projects the post-scheduling world before
atomic output admission. The surface's read-only observation and command gates
are carried by `architecture.UserSurface` and checked in `proofs/ui.bend`.

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
and deletion-absence proof. `MODEL.Operation()` uses its key/value representation
directly, so `operations.bend` only adapts the domain value returned by lookup.
`relations.bend` is generated from original relational-closure proofs and explicit
theorem applications. `reachability.bend` binds their edges to actual inputs and
complete committed decisions; `CONCEPTS.Composition.protocol` requires preorder,
batch flattening, simulation, safety and exact journal/receipt correspondence.
`proofs/reachability.bend` supplies only the single-step and representation
obligations; arbitrary-path results reuse those checked source proofs.
Batch recovery, task views and branch results use the imported map correspondence;
partition and map-composition results instantiate original library theorems.

`protocol.bend` resolves every input and accepted internal invocation into its
semantic operation. Completion tickets are checked here, not independently in
the host and implementation. Internal calls reuse COMMANDS' resolver and settle
their caller in the resulting world, including self-send and self-archive. Its
full input and invocation refinements extend the public command specification.

`commit.bend` gives the complete command boundary: refusal does not schedule,
accepted work has a bounded scheduler, retired effects are filtered, and validity
or complete-envelope output rejection rolls back state and all effects. LAWS
also fixes the scheduler's zero, quiescent and successor cases. Host commit
ordering is checked separately by integration tests, not assumed proven by Bend.

`execution.bend` owns the finite execution specification. Its action alphabet
separates deciding what work means from realizing it in PROGRAM. Resolution
includes recovery, availability and argument checks; action meaning fixes the
whole decision. The scheduler refinement uses the original imported `nat_ind`
certificate. The specification dependency closure excludes the implementation.

`transcript.bend` independently specifies complete finite decision traces;
`traces.bend` runs the production transition on that carrier. Original
`Nat.iter_swap_gen`, `Nat.iter_add` and `Nat.iter_ind` proofs lift the one-step
correspondence to trace refinement, partition and replay safety. Receipts include
replies and ordered effects. The local tape/fold proof establishes correspondence
with the production journal rather than proving an unused abstract interpreter.

`interface.bend` specifies the pure native packet protocol; `frontend.bend`
implements it, including malformed JSON, failed decoding and durability. Both
are in the proof closure. MAIN only performs IO. The modules in `proofs` consume
declared laws through explicit provider imports; see `proofs/README.md`.

`tasks.bend` implements task collection, history, queue, and recovery operations,
including closing interrupted tool attempts and validating summary completions.
Summary failure consumes no new authority: rejected calls and checkpoints are
not installed. Independently queued user messages are promoted in FIFO order;
an empty queue stops and a frozen queue remains frozen.
`MODEL.context_history` is the authoritative checkpoint projection. Full history
remains append-only; the presentation layer renders whichever history the
authorized effect carries. `INVARIANTS.settled_calls` guards context cuts against
unsettled function calls.
`equality.bend` supplies bounded structural comparisons used by INVARIANTS.
A comparison budget exhaustion returns false; it never certifies unchecked values.
These comparisons establish value relations, not physical pointer sharing.

`json.bend` preserves JSON number spellings and provides bounded decoding and
rendering. `schema.bend` checks the supported command and built-in tool schemas.
`wire.bend` decodes external messages to MODEL inputs. `presentation.bend` renders
model values and decisions. None of these modules performs an operating-system
effect; all external work crosses the host boundary.

Run `npm run check` for the proof gate and `npm test` for compiler/protocol probes,
host components, end-to-end behavior and proof-infrastructure mutations. Internal
semantic examples already covered by proofs are not duplicated as unit tests;
see `../tests-bend/README.md`. Changing a Bend source changes the journal identity.

`operations.bend` owns execution and result-callback rights, running announcements
and non-replayable interrupted outcomes. Task control and operation ownership are a
product: finishing one tool must not overwrite an unrelated pending model request.
A coalescing notification bit retains results that arrive during a model turn.
Summary eligibility excludes live operations; oversized partial context waits,
then summarizes after settlement. Forks inherit context with explicit nonownership
notices, never the parent's rights. `steer` and `cancel_operation` have separate
native command meanings and separately scoped cancellation effects.
