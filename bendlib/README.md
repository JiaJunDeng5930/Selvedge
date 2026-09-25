# Bend support definitions

Read the root CONCEPTS, COMMANDS and MODEL entry points before following an
implementation detail into this directory. INVARIANTS and LAWS constrain changes.

`stdlib.bend` is generated from existing Rocq standard-library proof terms, with
provenance and regeneration instructions in `../theory/README.md`. `theory.bend`
instantiates those certificates for append, replay composition and stuttering.
It does not maintain a second recursive algebra development.
`structures.bend` packages first-class semigroups, monoids, homomorphisms, actions, projections,
refinements, discrete dynamical systems, simulations and read-only machines.
`architecture.bend` binds them to the real program below the CONCEPTS entry;
PROOF consumes these values for queue, history, replay, decision and batch laws.
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

Run `npm run check` for the proof gate and `npm test` for native execution and
host integration. Changing a Bend source changes the journal's kernel identity.
