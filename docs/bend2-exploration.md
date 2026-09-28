# Bend 2 migration: exploration record

This record collects findings from implementing the executable model. The current
requirements themselves live in `LAWS.bend`, the domain in `MODEL.bend`, and the
executed transition in `PROGRAM.bend`. Dates describe observations on this branch,
not claims about all Bend versions.

## Task-board integration

The first browser pass exposed a mismatch hidden by the pure type check:
successful creation opened a detail dialog, whereas the reference closes it
unless continuous creation is selected. The intended create/edit transitions
are now fields of the assembled `BoardBoundary`, challenged by semantic mutations.

Column-only drag was also insufficient. Manual order now uses the finite map's
existing association-list order, with positional insertion specified separately
from the production helper. Stable priority/pin grouping uses Base list filtering.
The pinned compiler requires `List.filter`'s predicate template to be closed;
priority grouping therefore specializes the finite priority cases rather than
capturing a runtime rank in a compile-time template. No general sorting theory
was reintroduced for this feature.

Browser fixtures wait for the native mode/form to arrive before typing into it;
DOM presence from the preceding dialog is not an acknowledgement of navigation.
Full OS-boundary tests must run where the platform can create its own sandbox.
An outer-sandbox denial is recorded separately from product test results.

## 2026-09-24: establish the existing implementation

The starting worktree already contained a native Bend kernel, a Node host, and
twelve passing kernel/journal tests. Bend 2.0.27 checked `PROOF.bend` and compiled
`MAIN.bend`. This established an executable baseline, not full service validation:
there were no tests yet for the HTTP, provider, process, or MCP integrations.

### A theorem needs the same program entity as the running implementation

The replay composition law instantiates a generic transition-system theorem with
`PROGRAM.next`. History and queue laws instantiate the list monoid laws with the
actual append operation. This is stronger than proving properties of an independent
model and testing that an implementation resembles it. The remaining trust boundary
includes Bend's checker, native compiler, runtime, C token transport, and host.

Several existing laws deliberately name local operations: preserving a contract
when changing a phase, refusing an archived task's input, or rejecting a stale
result before scheduling. They are not yet global invariants of every reachable
world. The scope of each theorem must remain visible in its statement; counting
proved helpers cannot establish a whole-program preservation theorem.

### Termination describes a transition, not the life of a service

The checked program consumes explicit scheduling and rendering budgets. Remaining
work becomes a `ContinueScheduling` effect. The external stdin loop in `MAIN.bend`
uses unchecked recursion and constructs no proof. This provides a useful place to
separate a total mathematical operation from an indefinitely available service;
it does not prove fairness or eventual completion of a task.

### Output admission belongs inside the modeled transition

The host cannot roll back a pure kernel that has already advanced after discovering
that its output cannot be transported. `PROGRAM.deliver` checks the complete output
before admitting the new world or effects. Its rejection laws refer to that actual
admission function. Serialization and transport bounds are consequently part of
the transition's meaning, rather than a host-only optimization.

### External effects require an explicit knowledge state

A journal proves neither that an external command ran nor that it did not run
before a crash. Recovery distinguishes retry-safe internal operations from unknown
external outcomes. The existing SQLite tests exercise commit failure and replay;
the pure recovery laws only constrain the decisions made after that observation.

### Reproducible entry points matter to the experiment

`npm run check` now checks host syntax and all imported proof obligations, including
when a compiled kernel is cached. `npm test` builds the native kernel and runs the
integration suite. The root README points readers to the three executable entry
files rather than presenting the earlier Rust runtime as the experiment's entry.

## 2026-09-24: make observation a program entity

The initial implementation represented read, list, and describe as ordinary
commands. Persistence and scheduling each enumerated them, and read-only proofs
followed the error branches of individual query implementations. This duplicated
the conceptual claim that these commands merely observe the world.

`MODEL.Query` now represents that concept. Its interpreter returns only JSON;
it cannot return a new world or dispatchable effects. `InputMode` supplies the
shared classification used by persistence and scheduling. A tool that reads a
task reuses the same interpreter, but its result is still a durable history event.
Identical data access does not imply identical operational meaning.

The checked laws now quantify over every query and every world, including failed
queries and output admission failures. They establish unchanged world, no effects,
and no durable journal input. A generic transition-system theorem proves that
inserting an identity step anywhere in a trace preserves the final state. The
domain proof instantiates it with `PROGRAM.next` and the query preservation law.
This is a concrete use of stuttering in transition systems. It does not claim that
the observed reply stream is unchanged, or that scheduler fairness is proved.

This refactoring reduces proof dependence on query implementation details: a new
query case inherits the observation laws through the result type and wrapper.
The domain fact and reusable induction are separate, so the generic proof never
unfolds the entire server or serializer.

Bend 2.0.27 requires a match scrutinee to be a parameter or field; matching a
computed classification needs a helper definition. This affects how the executable
model is factored, rather than the classification itself. The installed guide's
explicit equality motives also proved useful for keeping generic replay induction
independent of the concrete task transition.

## 2026-09-24: exercise the effect boundary

The local service tests now run HTTP and event delivery, CLI command discovery,
an offline task, a streaming model fixture, a real stdio MCP process, and a real
Bash process. Both tool fixtures open SQLite themselves and assert that their
effect intent is already committed before producing output. Restart reconstructs
the same conversation without a second model request or repeated tool execution.
Separate process tests exercise bounded stdout/stderr retention, timeout, and
cancellation. These are observations of the host implementation, not new theorems
about the operating system or remote providers.

This exposes a practical division of evidence. The query laws quantify over all
modeled states and inputs. The integration tests check that this particular host
uses the kernel's decision in the intended order. Neither form of evidence should
be used to imply the other. The transcript-replay law also concerns kernel state;
replaying already committed inputs must not interpret their historical effects.

A negative compiler test checks both an open law and a false equality proof.
Bend 2.0.27 rejects both, including under `--check-only`. This tests the actual
build gate used here; it does not prove the checker itself sound. Repository hooks
now include this branch's proof/syntax check and native integration suite.

## 2026-09-24: close the world-invariant proof

The earlier local laws did not establish that a complete scheduler decision left
an admissible task forest. INVARIANTS now defines two executable predicates:
`world` describes a valid state, and `decision(previous, candidate)` describes the
permitted relationship between successive states and their effect intents.
Their definitions are imported by the real transition, rather than copied into
a test simulator or maintained as a separate validation specification.

The world predicate covers canonical task identities, ordered ancestry with
existing parents, inherited frozen contracts, ancestor descendant quotas,
well-formed pending calls, and globally distinct outstanding tickets. The
transition predicate retains existing identities, contracts, ancestry, and history
prefixes; keeps already archived tasks terminal; and checks that every emitted
model/tool intent matches its final task phase, frozen contract, and fresh ticket.
Comparison of structured payloads has an explicit budget and rejects exhaustion.

LAWS now states `transition_admitted` about `PROGRAM.transition` itself. Its
certificate has two alternatives: unchanged world and no effects, or satisfied
world and transition predicates. The certificate survives both invariant checking
and output-size admission. Public observations receive the unchanged alternative
without running a second mutable path. This yields `transition_preserves_world`;
the domain-independent `replay_invariant` theorem then proves
`replay_preserves_world` for every finite input list and any valid starting world.
`initial_world_valid` independently checks the actual initial state.

This construction establishes safety by Boolean reflection at the admission
boundary. It does not establish that the candidate producer always succeeds.
For example, an identity transition could satisfy an invariant-preservation law
while implementing none of the useful commands. Positive operation laws and
functional integration evidence therefore remain necessary. A resource-bound
rejection is also compatible with safety. Making these quantifiers and alternatives
explicit is essential to keeping the formal entry point an honest requirements
model rather than a collection of reassuring theorem names.

A negative test copies the production proof closure, verifies it, then replaces
`PROGRAM.admitted` with unconditional acceptance. The same proof fails at
`admitted_certificate`. Together with the missing/false-proof tests, this checks
that the build gate is actually tied to the implementation being shipped. It does
not prove the compiler sound or establish that the chosen predicates express every
human expectation.

## 2026-09-24: the commit is the unit of effect authority

One scheduler transition can execute several internal tools before returning a
single durable decision. A task can send a message to an idle peer, causing a model
intent to be accumulated, and subsequently archive that peer in the same commit.
The final state has no pending model request for the archived task. Dispatching
the earlier intent and then sending a cancellation would expose an intermediate
state that was never independently committed.

`live_decision` withdraws those superseded intents before the final predicates are
checked. A native test performs the send-and-archive sequence and observes the
archived task, retained input, cancellation intent, and absence of a model request
for it. The finding is that an invariant over emitted effects must relate them
to the committed final state, not merely to the intermediate state where each
effect was initially constructed.

## 2026-09-24: proof factoring has an operational cost

Bend 2.0.27 checked the general trace-invariant development, including separate
initial-state validity, in approximately 0.20 seconds in an isolated probe.
Adding a redundant corollary specialized to `replay(events, initial())` exceeded
a five-second timeout; directly instantiating the generic induction in that
corollary also exceeded the timeout. The initial-state proof alone took about
0.17 seconds. These are observed differences in this pinned checker, not a claim
about the exact internal reduction responsible or all future Bend versions.

The retained development uses the stronger general theorem and the separately
checked initial-state fact. The complete strengthened certificate development
subsequently checked in 0.164 seconds. Keeping a large concrete program out of
unnecessary theorem specialization is therefore an engineering concern even when
the mathematical argument is a straightforward instance of induction.

Two other factoring details mattered. The reusable induction parameter expects
an affine function type; an otherwise identical theorem declared with reusable
parameters does not match that signature. An auxiliary reusable implementation
behind the affine theorem boundary resolves this without changing the statement.
Also, a residual match case excluding an observed command did not reduce far
enough to check the transition proof. Enumerating the command constructors at that
proof boundary made the required reductions explicit. Neither case was addressed
by adding axioms, bypassing termination, or weakening a law.

## 2026-09-24: test the interpreter where the proof ends

The integration suite now contains 26 passing tests. New evidence includes a real
HTTP request interrupted by service shutdown, restart-driven retry of that model
request, a truncated SSE response settled as a failure, and a subsequent successful
request whose history survives another restart without an extra call. Real stdio
MCP notifications remove a route while existing task manifests remain frozen;
shutdown also completes while a catalog discovery is waiting for a response.

A loopback issuer exercises the complete device-code grant, private credential
persistence, concurrent refresh serialization, and rejection of account changes.
A malformed-credential test exposed a host leak: the JSON parser could include
credential text in an exception that the service would place in task history.
The reader now replaces parse diagnostics with a non-secret credential error.
This illustrates an important limit of moving domain invariants into Bend: host
error translation is still an information-flow boundary and needs its own evidence.

An isolated Chrome profile drove the actual local web server through task creation,
echo completion, freezing, queued input, unfreezing, the schema-derived fork form,
child selection, and archival. All eight checks passed with no JavaScript
exceptions or displayed error. The generated screenshot was inspected; the child
retained its inherited history and branch output, and archival disabled its input.
These are local observations, not formal UI or usability theorems.

## 2026-09-24: measure trace and history costs

`scripts/benchmark.mjs` builds a breadth-first four-child task tree after 32 user
turns, each containing 1,024 ASCII bytes. It drives the actual native kernel through
SQLite commits, settles each model intent with deterministic fixture output, and
reopens the journal to verify identical state. There are no remote model calls.
The following run used Node v26.5.0 and Bend 2.0.27 on darwin-arm64. Native peak RSS
was obtained with macOS `/usr/bin/time -l` around the kernel process, excluding
Node. Replay includes native startup and exact decision verification.

| Tasks | Committed inputs | Median transition | P95 transition | Maximum transition | Replay | Journal | Native peak RSS | Replay peak RSS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 17 | 89 | 7.36 ms | 35.90 ms | 192.08 ms | 1.56 s | 1.43 MiB | 10.73 MiB | 10.75 MiB |
| 65 | 161 | 28.86 ms | 225.90 ms | 315.70 ms | 8.19 s | 3.62 MiB | 10.84 MiB | 10.84 MiB |

Measured at `2026-09-24T18:03:12.136Z` with kernel fingerprint `050b42e5d4e028e73c09d7dfcfc0fb34f174afc95eeea0bd8ef5719f962dc4d0`.

The modest RSS change in this workload is an observation about the compiled
runtime, not a proof of pointer sharing or asymptotic space usage. A history-prefix
law relates values; it cannot establish allocator or representation behavior.
Likewise, shared history inside the modeled world does not eliminate copies in
serialized model requests and journal decisions.

Whole-world checks and exact replay have visible costs: the 65-task run takes
about eight seconds to reopen, and its slowest committed transition takes about
316 milliseconds. This implementation accepts those measured costs; it does not
claim indexed validation, snapshot-based recovery, or a throughput result for
unbounded conversations. An incremental validator would need a new preservation
argument tying its cached evidence to each change. A snapshot would similarly
need an explicit reconstruction contract. Neither optimization is silently
assumed by the current theorem.

## Completed migration and evidence boundary

The branch now has one task runtime. The earlier Rust implementation and its
Cargo-based maintenance machinery have been retired from the checkout; history
remains in Git. The fixed Bend release is checksum-verified in a worktree-local
installation, and bootstrap, npm/Just commands, Codex actions, hooks, and the
macOS/Linux CI configuration all target the checked native implementation.
The pinned macOS installer and local gates were executed; the remote CI jobs
have been configured but were not run as part of this local task.

The three exploration goals are realized at their relevant boundaries. Requirements,
model predicates, and operational definitions inhabit the same Bend program used
by the service. List-monoid laws, transition induction, replay composition, and
observation stuttering are instantiated directly on that program. MODEL,
INVARIANTS, LAWS, and PROGRAM provide the top-level reading path, with PROOF holding
proof construction; client command descriptions and controls derive from model
values instead of a second handwritten protocol specification.

The resulting guarantee is deliberately precise. Formalization does not certify
that the predicates capture all informal intent, make runtime rejection impossible,
prove progress or scheduler fairness, or verify a remote system. Live vendor
credentials were not used: authentication and MCP behavior were exercised against
controlled endpoints and real local processes. The Bend checker/compiler, C ABI,
Node, SQLite, operating system, and remote services remain trusted boundaries.
Those limits, the positive functional evidence, and the measured costs are part of
the outcome of this experiment, rather than hidden assumptions of the safety proof.

## 2026-09-24: extend the migrated runtime into a coding harness

This development round began from the migrated runtime with 26 passing tests.
Reference identities and the selected source files are pinned in ADR 0008:
`earendil-works/pi` at `19a0361be89bf78ccf9bbaed9a496d6484759f67`, and
`shpz/UnrealHarness` at `af72d7e53a096bc97bbc3a6fd50e8e4bda183a8c`.
The latter is a UE build/skills/benchmark suite, not an alternative implementation
of a general agent scheduler. The useful comparison was bounded file/tool
interaction, context management, and independently observable build/test results,
not plugins or a claimed benchmark uplift from copying an entire harness.

### A new primitive must join the existing interpretation, not start another model

Adding file operations exposed a distinction that the previous Bash/MCP-only
boundary did not need: an external observation can be repeated without repeating
a mutation. `MODEL.Execution` now supplies the classification used by both
production dispatch and recovery permission. The new read/write/edit recovery
laws reduce that same classification; there is no separately maintained recovery
table in Node.

Repeatable is not the same as deterministic. Repeating a file read after a crash
can return a newer revision. The guarantee is permission to observe again, not
equality to the lost result. The file primitive returns revision evidence so the
next mutation can detect that distinction. By contrast, an interrupted mutation
is still an unknown outcome and cannot be reissued merely because its result was
not recorded. This is a concrete example of why the relevant mathematical
structure must describe the intended observation/effect relation rather than
simply labeling all retries “idempotent.”

### Closing a task phase is not undoing a physical effect

The original `stop` intentionally settles accepted tool calls. Treating it as
“kill current work” would silently change that contract. `interrupt` instead
closes the current logical phase, appends explicit results for every outstanding
call, preserves queued input, and emits cancellation. Dispatched calls receive
an unknown-outcome result; undispatched initial attempts receive a cancellation
result. Late completions then fail the existing ticket/phase correlation check.

The interruption lemmas establish phase settlement, preservation of the frozen
contract and queue, and idempotence on the actual `tasks.interrupt` operation.
The global finite-trace result continues to be an instance of the existing
generic transition invariant theorem. No second replay or cancellation theory
was introduced for this feature. Physical process termination still needs host
evidence: the integration test waits for a real Bash process, interrupts its
task, observes that the process is gone, and resumes the unarchived task.

The new stopped-idle-with-queued-input case also exposed a FIFO issue that was
previously unreachable in the ordinary workflow. Appending a new input directly
would place it ahead of retained queued messages. The implementation now uses
the same `queue_message` followed by `drain` operation for idle reception, rather
than adding another special queue rule. This is an instance where a new modeled
state reveals a missing correspondence to the already chosen list/FIFO model.

### Context compaction is an idempotent view, not a theorem about summarization

`History` remains the append-only record used by replay, audit, task branching,
and `read_task`. `context_history` selects the latest checkpoint plus its suffix
for a model request. Its idempotence and checkpoint-cut equations are checked
against that executable projection. A repeated summary replaces the context
view again without erasing any previous summary or original message from history.

This separates two different proof obligations. Structural safety can be checked:
the summary request has no tool manifest, the cut has only settled function calls,
the returned note must be bounded and nonempty, tool-bearing replies are rejected,
and only a matching live ticket can install a checkpoint. The existing effect
admission certificate now checks the settled-call precondition as part of
`INVARIANTS.summary_effect`. The same precondition guards an explicitly supplied
checkpoint. There is no independent host-side cutoff decision.

Semantic fidelity is different: a model's note need not preserve every relevant
fact. `ContextCheckpoint` therefore contains data, not a proof of conversational
equivalence, and the provider receives it without promotion to system authority.
Original details remain recoverable through the ordinary history tool. Claiming
lossless semantic compression from the projection theorem would cross an
unjustified abstraction boundary.

A provider may reject a context before the byte threshold predicts overflow, or
may be unavailable when a summary is needed. The explicit `compact --summary`
path supplies a bounded checkpoint without invoking that provider. This keeps
recovery expressible in the same native command model instead of requiring an
operator to edit the journal. Automatic thresholds are serialized UTF-8 byte
budgets, not token counts; journal storage, history traversal, and replay still
grow with the complete record.

### An effect interpreter has semantic parameters outside the pure world

Before this change, reopening the same source fingerprint under a different
working directory could replay an identical pure state while interpreting the
next relative file or Bash path in another project. A trace-equality theorem
alone cannot exclude that change in meaning.

The journal now binds the canonical workspace as part of its checked identity,
before kernel reconstruction and recovery. The host uses that same canonical
directory for its effects. This is a concrete interpretation precondition, not
another task-state model. It also makes an important limit visible: two task
branches share a workspace; history branching does not imply filesystem
isolation. Canonical path identity does not establish a snapshot of the directory
contents, which may legitimately change between operations.

### Model-level authorization and OS-level refinement require different evidence

The file primitives use expected SHA-256 revisions, unique literal matches,
per-canonical-path mutation serialization, and same-directory atomic publication.
Tests cover stale readers, overlapping matches, symlink aliases, concurrent
creation, cancellation, executable modes, BOM/CRLF preservation, invalid UTF-8,
binary data, and bounded pages. These observations exercise the bridge from an
authorized file effect to its Node/OS interpretation.

They do not turn a revision check plus `rename` into a global compare-and-swap:
an independent editor, Bash process, or another host can race the final check.
Neither the pure recovery theorem nor atomic replacement proves cross-process
isolation. Multiply-linked mutation is refused rather than pretending replacement
preserves all aliases. Keeping these premises explicit is more useful than adding
a local “safe edit” proposition whose statement omits the physical actors.

Output truncation has a similar boundary. A bounded preview is useful only when
the model knows what was omitted and how to inspect retained evidence. Bash now
returns revision-addressed artifacts for truncated streams, counts bytes beyond
the artifact cap, and avoids splitting valid UTF-8 prefixes. A nonzero exit is a
tool error. Artifact retention remains bounded per stream and cumulative across
commands; it is not an unbounded transcript or automatic storage compactor.

### Evidence from this round

On Node v26.5.0, Bend 2.0.27, darwin-arm64, the current source passed the proof
gate and all 51 automated tests. The negative proof mutations still reject
missing/false obligations and removal of production admission. The new coding
integration runs real reads, file creation, an exact edit, and a Node assertion
through committed native effects; then it compacts, reopens the journal, and
checks that the successful command was not rerun. Other tests cover automatic
and supplied checkpoints, settled tool boundaries, stale/cancelled summaries,
retry exhaustion and cancellation, live process interruption, and workspace
mismatch rejection.

The loopback provider specifies test decisions; it is not evidence that a live
model will choose correct edits or produce faithful summaries. No real provider
credentials or subordinate agents were used. After obtaining permission to launch
an isolated local Chrome process, the browser smoke check passed creation, echo,
freeze, queued input, unfreeze, interrupt, the schema-derived supplied-checkpoint
form, resumption, and archival. It observed twelve command schemas, one task,
no JavaScript exceptions, and no displayed error; its screenshot was inspected.
This checks the local interaction, not model intelligence or general usability.
The earlier performance table records its earlier fingerprint, not measurements
of this larger tool catalog and context-management implementation.
## 2026-09-24: functional meaning, not merely safe admission

The previous admission theorem allowed a safe program to refuse every request.
It also allowed some acknowledged no-ops. Adding another invariant would not
have addressed this: the absent object was the meaning of a command.

The new boundary is a resolved operation algebra. Preconditions select an
operation exactly once; a total semantic function fixes its post-world, reply,
and effects. PROGRAM must refine that entire value, and the committed-command
theorem includes scheduling, effect retirement, validity, output admission and
rollback. Scheduling has explicit zero, quiescent and successor equations;
successful asynchronous dispatch and settlement are positive obligations too.

This exposed a real distinction that the old safety model did not force us to
state. A rejected public fork had already written a synthetic function call and
consumed a ticket. Rejection of a new command and failure of an already accepted
tool are not interchangeable. The former is now inert on the task world; the
latter still records its output. Similarly, a rejected command no longer drains
another task's ready queue. A stale completion may still be a scheduler tick,
without accepting its stale payload; that is a different input class.

At the semantic checkpoint, all 69 tests passed. Eleven additional mutants were
first checked as valid Bend programs, then rejected by the production proof:
always-refused creation, acknowledged but undelivered input, a wrong task identity,
omitted cancellation, omitted model/tool requests, a disabled scheduler, a lost
continuation, arbitrary admission rejection, oversized publication and missing
tool settlement. This checks a different property from simply asking whether a
deliberately false standalone theorem fails. It still does not prove that the
formal requirement is what a human intended; reviewed semantic clauses and
independent native scenarios remain necessary.

## 2026-09-24: reuse the original proof, not its theorem name

The local list theory was previously re-proved with recursive Bend definitions.
Replacing those definitions with calls to renamed local lemmas would not remove
the duplicated theoretical development. We instead quoted the existing opaque
proof bodies of `List.app_nil_r`, `List.app_assoc` and `List.fold_left_app`, plus
the list induction principle, using MetaRocq. The saved bundle records source
versions and digests; an untrusted translator emits proofs that Bend rechecks.
The three source algebra theorems are closed under the global context.

The correspondence is small and explicit: source lists, append, fold-left and
equality map to Bend Base. History extension and actual input replay now use
Base's fold directly. Their composition proofs are instances of the imported
fold theorem. The trace-invariant argument instantiates the imported induction
principle with the actual validity predicate and supplied one-step obligation;
it does not introduce a new recursive standard-theory proof. Unknown constants,
unmapped inductives and unsupported syntax fail closed. A test replaces an
original certificate with a reflexivity term while retaining its statement;
Bend rejects it. A digest or a source label is not a proof oracle.

An affine-language wrinkle matters here. The first generated proof called the
imported eliminator through templates and checked while uninstantiated, but some
real clients captured local list values that cannot be closed template arguments.
The converter now specializes the *imported* eliminator, threading its environment
and retaining the original nil/cons proof terms. It does not discover a fresh
induction proof. Client instantiation, not just checking a generic library file,
must therefore be part of the proof-import gate.

## 2026-09-24: the concept is a value with obligations

Named structures in CONCEPTS bind carriers and actual operations to proof-carrying
types: monoids, right actions, exact refinements, read-only machines and idempotent
projections. Queue, history and replay proofs consume the corresponding values.
An operation is not classified by a comment saying "monoid"; a value of that type
cannot be constructed without the relevant laws.

Choosing the right standard structure also revealed a modeling error to avoid.
Decision combination preserves the first reply, takes the last world and appends
effects. It is associative, but has no global identity decision. Treating the
whole thing as a monoid would add a false requirement. It is a semigroup whose
application-specific correspondence reduces associativity to the imported
effect-list theorem. Conversely, context cutting, phase recovery and interruption
are all projections, despite having very different meanings. Their idempotence
does not establish summary fidelity, replay safety for arbitrary external writes,
or reversal of an interrupted process.

Complete equations can also make proof checking expensive in ways that ordinary
code factoring does not predict. Comparing two independently expanded concrete
query implementations, including the large `describe` value, exceeded a four-
second probe. Sharing the authoritative pure query meaning and checking its
realization at an abstract boundary brought the complete strengthened proof back
under a second locally. The query semantics was not weakened. This is a reason
to keep meaning, realization, and their correspondence separately identifiable
even when they inhabit one formal program.

## 2026-09-25: the specification needs the entire interaction alphabet

A command-wide refinement still left two ways to remain safe but fail useful
work: ignore every asynchronous completion, or execute an internal command
without recording the result in its caller. Public commands alone are not the
input alphabet of an agent harness. Correlated completions, configuration,
recovery and scheduling ticks have their own meaning too.

`protocol.Event` now represents resolved input meaning and `protocol.Invocation`
represents an already accepted internal call. The former settles only the current
ticket and phase; the latter reuses the public resolver but completes its caller
in the *resulting* world. This last choice matters for self-send and self-archive:
using the pre-command caller would silently overwrite the very change being
specified. Internal fork also has different obligations from a manual idle-task
fork: remaining accepted calls must be inherited with their recovery authority.

The input-wide and invocation refinements compare complete decisions. They are
not extra safety predicates and are not proofs about an unused reference loop.
Mutants that discard all input, acknowledge ignored results, skip recovery, omit
caller settlement, or drop the remaining calls of an internal fork are well-typed
but rejected by the same production proof. Changing the authoritative resolver
is a requirements change, not something refinement alone can label incorrect.
Positive native scenarios and review of those semantic clauses remain necessary.

## 2026-09-25: a standard structure must constrain the actual representation

Batch recovery, task views and branch-result identities are now concrete monoid
homomorphisms. Their split-batch and composed-map laws consume original
`List.map_app` and `List.map_map` proofs. `List.map_id` is imported as well; none
of these standard proofs was reconstructed with project-specific induction.
The project supplies operation binding and genuinely domain-specific behavior.

The apparent obvious mapping to Bend's `List.map` was wrong: that primitive takes
affine lists, while the state contains duplicable lists. The same mathematical
name does not establish a representation correspondence. The bridge represents
source map with Base.foldr at the correct multiplicity. Original proof terms are
checked against that representation; source equality elimination is lowered to
Bend's equality rewrite rule. No new equality axiom is introduced.

There is another distinction between stating an algebra law and importing its
proof. An always-empty mapping preserves concatenation, so the homomorphism
statement alone does not identify the intended map. Our mutation of the mapping
to discard every element is rejected by the original map certificate, whose
proof depends on the actual cons equation; map identity separately states the
non-degenerate behavior. Source statements, proof terms, representation choices
and real client instantiations all belong in the import audit.

Finally, a generic mapping factory and a named domain function can be pointwise
equal without being interchangeable as indices of a proof-carrying record.
Bend rejected the direct substitution of the factory's function name for
`protocol.recovery`. The domain structure is therefore constructed at the actual
function index, with pointwise obligations discharged by imported proofs. This
is correspondence work, not a reason to re-prove the algebra or assume function
extensionality. Factoring ordinary code and factoring dependent proof objects
have different constraints.

## 2026-09-25: the conceptual entry can be an assembled program object

`CONCEPTS.Harness` collects the required correspondences in one type. Constructing
it requires the actual command and interaction refinements, invariant-preserving
machine, journal action, read-only observation, batch recovery, associative
decisions, context projection and interruption. A reader can begin with this
object and follow a named structure, rather than discovering concepts by walking
the implementation. Proof construction stays in PROOF; JSON handling and concrete
lifecycle branches remain outside this entry.

This does not make a human request automatically formal. It makes the accepted
formal interpretation and its links to code explicit and checkable. Nor should
every function receive a decorative mathematical label: a useful correspondence
must remove a real proof obligation through a standard theorem or express a
constraint that would otherwise be implicit.

## 2026-09-25: terminating failed work is not abandoning new work

A new native regression exposed two branches where failed compaction left queued
user messages in an active idle task indefinitely: transport failure and invalid
tool-bearing summaries. Context-limit failure already promoted its queue. Safety
did not distinguish these cases, and the earlier local requirement that every
invalid summary ends in Idle actually preserved the defect.

The refined requirement fixes the whole rejected-summary result: retain original
history, record only a failure, reject all proposed calls/checkpoints, then promote
independently queued input. Separate exact laws establish FIFO promotion for an
active nonempty queue and stopping for an empty queue. Frozen input is not
dispatched. This is a deliberate functional-requirement correction, not weakening
a proof until the code passes. The regression failed before the change and passes
after it; reverting promotion is also required to fail the formal proof gate.

The distinction is broader than this particular bug. A phase-only postcondition
can conflate the lifetime of one attempted operation with the obligations owed
to other requests. Complete semantics must account for both, especially when a
background summary and newly submitted instructions share a task.

## 2026-09-25: context recovery must leave evidence in the modeled state

The reference review used pi commit
`19a0361be89bf78ccf9bbaed9a496d6484759f67`, particularly
`packages/coding-agent/src/core/agent-session.ts`, and UnrealHarness commit
`af72d7e53a096bc97bbc3a6fd50e8e4bda183a8c`, particularly the `ue-build` skill and
its executable build feedback. The useful ideas here are bounded recovery,
queue handling and a real tool/result verification loop, not importing a UI or
Unreal-specific integrations. Sources are the `earendil-works/pi` and
`shpz/UnrealHarness` GitHub repositories; the local clones are research material,
not shipped dependencies.

Pi's recovery guard is session bookkeeping. Here an explicit pre-output provider
overflow becomes a typed journal input. The state machine requests a tool-free
summary, commits a checkpoint, then issues a fresh model ticket. A checkpoint
with no new work has consumed the compaction opportunity. Persistent overflow
therefore stops instead of triggering an invisible retry cycle. This survives
reconstruction without trusting a host-local attempt counter. Failed summaries
retain the full record; when even the summary request cannot fit, an explicit
supplied checkpoint is the recovery route, not silent truncation or a claimed
successful summary. No theorem asserts that a model's summary is faithful.

The HTTP/native/SQLite fixture performs a file mutation, encounters overflow,
installs a checkpoint and continues. It checks that the overflow and summary
intent are durable before dispatch and that restart repeats neither the model
turns nor the completed mutation. Separate fixtures reject diagnostic substring
matches, incomplete streams and overflow reported after exposed output as
permission for automatic replay. Only explicit pre-output codes qualify.

Root project instructions exposed a related boundary. Reading AGENTS.md afresh
inside the provider would allow identical replayed effects to acquire different
meaning after a file edit. Instead, startup observes a bounded, revisioned
snapshot and commits it; creation freezes that value into the task contract.
Old tasks and forks retain it, while new tasks after restart can adopt a new
snapshot. Live file contents remain separately observable. Repository guidance
is task data, not a privileged instruction injected by the transport adapter.

## 2026-09-25: proof closure is not deployment closure

Removing obsolete PROGRAM parsing helpers passed the proof root but initially
broke the wire decoder: that module was not in the proof dependency closure.
The decoder now uses the shared protocol parsing helpers, and `npm run check`
checks MAIN as well as PROOF. A theorem about the actual transition does not
establish that every adapter importing it still builds or implements its wire
contract. Native execution, error-path fixtures and durable-effect ordering
remain separate verification obligations, rather than evidence silently folded
into the theorem's claim.

### Validation checkpoint

The completed continuation passed `npm run check`, all 97 tests in `npm test`,
and the tracked-file index check. Seventeen production mutations first passed
ordinary type checking and then failed the formal proof gate. The source proof
bundle was refreshed through the installed Rocq/MetaRocq exporter and reproduced
the checked Bend certificates. MAIN's foreign input and indefinite service loop
remain explicitly reported boundaries; PROOF does not depend on those definitions.

The separate isolated Chrome check passed creation, echo, freeze, FIFO input,
unfreeze, interruption, schema-derived supplied checkpoint, resumption and
archival. It observed twelve command schemas, one task, disabled archived input,
no displayed error and no JavaScript exceptions; its screenshot was inspected.
The smoke script was corrected to wait for actionable controls across asynchronous
refresh, rather than treating a temporarily removed button as a program failure.
This uses the offline profile. Provider protocol tests use local HTTP fixtures,
not a paid model, real account or an evaluation of model intelligence.

A single developer-machine benchmark on 2026-09-25 used darwin-arm64, Node
26.5.0, Bend 2.0.27 and kernel fingerprint `4a3383e4a1c2`. Each case forks after
32 history turns with 1,024-byte messages:

| Tasks | Committed inputs | Median transition | p95 transition | Replay | Native peak RSS |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 17 | 89 | 10.71 ms | 75.12 ms | 2.53 s | 11.69 MiB |
| 65 | 161 | 41.19 ms | 384.38 ms | 11.97 s | 11.80 MiB |

This measures SQLite commit plus native transition latency and reconstruction,
not provider latency or a comparison with another harness. RSS excludes Node;
it does not prove physical history sharing or asymptotic bounds. Resource
accounting required permission for macOS `time -l` outside the command sandbox;
the initial sandbox-only run could not read its clock information. Timing is
observational, not a CI pass threshold or a guarantee of performance under load.

## 2026-09-25: semantic independence must include higher-order parameters

The complete command equation still accepted PROGRAM's scheduler as a parameter.
This is a specification dependency even without a direct import in the commit
module: changing scheduling could change both sides together. A theorem's
quantifiers and supplied higher-order operations therefore belong in its
dependency audit, not just its import graph. Execution now has an independent
action alphabet, action meaning and finite-run meaning. Correspondence proofs
compose command/protocol interpretation, action execution, scheduling, admission
and output delivery. A structural test rejects an implementation dependency in
the specification closure and a production-scheduler binding at the entry.

The imported natural-number eliminator makes the proof boundary tangible: the
project supplies a zero-budget case and a successor correspondence, while the
existing Corelib term performs induction. Adding a source entity also required
refreshing the manifest's format and source fingerprints; changing only the
translator correctly failed the reproducibility gate. The bundle was regenerated
from installed Rocq/MetaRocq rather than repairing the digest by hand. Proof and
native gates then passed, with 102 tests including the corrupted eliminator.

The reference audit also found a name-resolution error in previous exploration:
the local `shpz/UnrealHarness` clone is an Unreal Engine integration, not the
async-first coding harness discussed with the user. The relevant reference is
`unreallabsai/unreal-agent`. Earlier observations about the former must not be
treated as evidence about the latter. Subsequent capability work uses the
correct source, with inspected paths and revisions recorded below.

## 2026-09-25: existing iteration theory becomes the composition mechanism

Importing an eliminator alone still leaves a project-owned proof of a standard
global theorem. The installed Stdlib already supplies `Nat.iter_swap_gen`,
`Nat.iter_add` and `Nat.iter_ind`: a commuting square lifts to finite iteration,
iterations split into consecutive runs, and a preserved predicate holds through
iteration. The bridge now quotes these original terms and checks their translated
statements and bodies. No replacement tactics or local versions of those three
theorems were written. The former local replay-invariant induction was removed.

The engineering work is the representation: an input tape carries the remaining
inputs, current world and complete decision receipts. Its single step is the
actual committed transition. The project proves this step corresponds to the
independent input meaning, and that consuming the tape has the same world as the
production fold-based journal. Those are genuine application obligations. The
imported theorems then provide simulation, partition and safety. Retaining whole
receipts matters: final-state equality alone could accept a program that lost a
reply, duplicated an effect or changed effect order.

Naming a structure is insufficient if its indices name an unused interpreter.
Dynamics and Simulation therefore index both step and run operations. Bend does
not automatically identify a named run wrapper with its partially applied
iterator. The imported proof record is destructured as a parameter and rebuilt
by applying its evidence pointwise. This is a binding proof, not a fresh global
theorem or a function-extensionality assumption. It also exposed a language
constraint: computed values cannot directly be match scrutinees, so the rebinding
boundary needs its own small definition.

The original `iter_ind` proof contains a delta-reduced iterator. A proof translator
must not recognize this by a convenient local name or expected result. Its exact
zero/seed and successor/recursive-application syntax is checked before translating
it. Unknown recursive bodies fail closed. Template parameter reordering must
preserve both declarations and applications, including recursive calls.

## 2026-09-25: proof dependencies become module boundaries

CONCEPTS now consists of proof-carrying meaning, composition, recovery and
observation records. Concrete function indices and constructors moved beneath
that entry. The native packet protocol also acquired an independent meaning and
refinement, so MAIN contains only IO. An architectural test checks that every
pure runtime import belongs to the proof closure; checking a separate transition
root is no longer mistaken for checking its deployed pure frontend.

Splitting the proof root exposed another important dependency: importing a law's
declaration does not import its evidence. Bend rejects using an unfilled law as
live proof. Provider imports now explicitly follow command/protocol, execution,
commit, frontend, trace, safety, task and observation boundaries. The algebra
assembly consumes these interfaces rather than private proof helpers. The graph
is acyclic and checked, making local proof composition an architectural contract
instead of relying on the order of one large proof file.

Negative tests must preserve project identity. Compiling a nested module as a
different root produced an import-namespace error, which is not evidence that a
semantic mutation was caught. The tests now compile a root wrapper importing the
mutated module before requiring the actual proof to fail. Cases include dropping
receipts, ignoring input, making malformed JSON durable and replacing replay by
the identity. Likewise, a successful compiler exit is not enough for the proof
gate: unsafe/foreign dependency reports must fail even when an executable is
cached. MAIN's foreign input and unbounded service lifetime remain separately
reported, rather than being accepted as proof evidence.

This checkpoint passed the pure proof gate, separate native-entry check and all
108 tests. The observed success includes original iterator-certificate mutation
tests and whole-program receipt/input mutations; it is not evidence about remote
model quality or operating-system isolation.

## 2026-09-25: asynchronous operation rights reshape the state machine

The reference actually used here is `unreallabsai/unreal-agent` at
`1b9f778453f411c029b39b85102aaefb95e7e48d`: `harness/tool/bash/bash.go`,
`tool/static.go`, `operation/shell.go`, `operation/output.go`, `coordinator/loop.go`
and `contextbuilder/builder.go`. The pi steering/follow-up comparison used
`earendil-works/pi` at `19a0361be89bf78ccf9bbaed9a496d6484759f67`, specifically
`packages/agent/src/agent-loop.ts` and `agent.ts`. No behavior was inferred from
the unrelated Unreal Engine harness.

The important correspondence is an operation, not a shell syntax convention.
A single ToolPending phase made model work and external work mutually exclusive.
The new task state is a product of control phase, operation rights and a sticky
unread-input bit. Its constructors and invariants expose the possible overlap.
Completion consumes its operation ticket without replacing a pending model phase;
the unread bit forces a subsequent turn when a completion races a model reply.
This is materially different from hiding a background-process table in the host:
the complete command/input/receipt refinement sees the operation lifecycle.

Append-only history constrains partial-result design. Replacing a pending output
later would rewrite information already sent to the model; appending another
function output for the same call would claim two final results. An operation is
therefore announced only when a committed model request actually needs its running
status. Fast completion remains an ordinary function output. After announcement,
completion is a distinct operation-result entity. Original call identity, current
operation ownership and whether a running status has been recorded are separately
checked. The provider adapter labels the later event as unprivileged tool data.

The representation exposed a real queue bug: after a batch's last external call
was dispatched, the old implementation could start another model request without
promoting previously queued user input. Promotion now occurs at the end of batch
dispatch, not only after tool settlement. The fork test caught this by observing
the parent's queue separately from the child's inherited history. An incorrect
implementation could remain world-safe while silently omitting that instruction;
operational tests remain necessary alongside safety and correspondence proofs.

Context cuts need a causal boundary, not just a small string. A result can arrive
after a summary's input snapshot; installing that summary would then erase data
it never observed. Native summary/checkpoint eligibility now excludes live
operations. An oversized partial context waits for the other results rather than
sending an oversized request or prematurely summarizing. The existing provider
overflow path resumes summarization when the last right is consumed. A steered
summary loses its ticket, so its late response cannot replace newer user input.

Cancellation has two scopes. Steering replaces model work and undispatched calls
but retains independent operations and queued follow-ups. CancelOperation consumes
one right. If a later internal call cancels an earlier external intent within the
same decision, explicit cancellation withdraws that intent before host execution.
Filtering is driven by that withdrawal, not by a heuristic that hides arbitrary
invalid effects. Unknown external outcomes cannot be retried or undone. Forks
copy context with a nonownership notice, never a parent's live execution rights.

The prior integration fixture assumed an effect belonged to the latest journal
row. Concurrency invalidates that assertion: other completions can advance the log
after an intent is committed but before its process starts. The correct witness
is the effect's own causal committed ticket. Fixtures now check that witness and
still require exactly one execution and no automatic restart replay. This is a
case where changing the concurrency model changes the shape of required evidence,
not merely an implementation detail in the test.

Bash replaced the three file tools; revision-sensitive or atomic editing is now a
project script obligation rather than a second hard-coded mutation API. The root
guidance observer remains separate because its frozen contract is not a tool call.
Output has two units: retained Unicode characters and raw stream bytes. Head/tail
previews preserve code points across arbitrary pipe boundaries; artifact metadata
describes the retained prefix, never a fictitious complete stream. The 65,536-
character ceiling and 8 MiB artifact cap fit this program's native output boundary,
rather than copying the reference's larger limit without analyzing its effect.

This checkpoint passed all 117 tests, including real overlapping Bash processes,
partial-result HTTP model requests, independently scoped process/model cancellation,
background descendant cleanup, same-commit withdrawal, capacity, fork, recovery and
summary races. It does not establish that external mutations commute, that summary
text is faithful, or that early partial results always minimize paid model turns.
Earlier results can improve latency while adding a model round; quiet operations
themselves do not generate polling rounds.

## 2026-09-25: include the user interaction surface in the executable model

### A schema is not ownership of a user interface

The old browser obtained schemas from Bend but still interpreted task snapshots,
provider messages and action rules. Thus the conceptual entry described only part
of the program's behavior. `UI.bend` now owns a typed presentation tree and its
events; `CONCEPTS.Observation.surface` binds its submission, projection and command
gates. Every platform can render this same value without reconstructing a task
model. The remaining client state is an opaque cursor plus unsubmitted widget
drafts, focus and disclosure state. An enabled form describes the availability of
an action, not a proof that arbitrary future input will satisfy its preconditions.

### Projection belongs inside the atomic decision, after scheduling

A command's immediate result is not necessarily its final state: bounded scheduling
can start a model, finish internal work or retire effects before commit. Rendering
earlier produced the wrong conceptual boundary. The native surface is now generated
from the post-scheduling world, before checked full-envelope admission. Output
rejection rolls back both the command and its effects, instead of leaving an
accepted mutation behind a failed view. The response separately carries the native
command receipt; a refused stale action can still return an up-to-date surface.
Refresh and cursor navigation are observations, not persisted scheduling events.

### Storage variants are not user-visible meanings

Ordinary Responses assistant answers are retained as `ModelContext` to avoid
duplicating provider context, alongside encrypted reasoning and compaction items.
Hiding that constructor wholesale erased real answers. Its display projection now
lives in Bend: supported message/refusal text and public summaries are displayed;
encrypted payloads are retained for model continuation but not copied into the
surface. Neither Web nor a future native adapter needs its own provider interpreter.
The native tree is structurally serialized by matching nested list constructors,
so no unchecked mutual recursion or silent depth truncation is needed.

### New conceptual boundaries need public proof interfaces

The surface reused read-only output-admission evidence from another proof module.
The architecture gate correctly rejected calls into that module's private helper.
The shared property became a public `LAWS.delivery_observation_*` obligation, with
its existing proof supplied by the original module. This preserves the graph of
declared propositions rather than allowing a new feature to depend on incidental
proof implementation structure. Native/HTTP/DOM-adapter tests cover post-state
projection, real provider message shapes, stale actions, invalid events, pagination,
independent cancellation, recovery, literal text and unsent drafts. These tests do
not turn the browser into a formally verified renderer or certify a visual design.

## 2026-09-25: extensions as a native authorization and observation protocol

### Rewriting a call creates a correspondence obligation

The old operation invariant equated an executable call directly with its immutable
accepted history entry. Replacing stored arguments would make that proof convenient
but destroy the evidence of what the model requested. Keeping the original while
weakening equality to call-ID matching would instead grant arbitrary arguments.
The missing entity was an authorization derivation: ordered `HookRecord` values
reconstruct an effective call and its remaining chain from the original request.
Checked continuations and operation rights now require that correspondence.
Identity is fixed; only the argument object can change, and the final result is
validated again. These are native entities, not a log that someone must interpret
to infer whether execution was permitted.

### Inheriting knowledge does not inherit authority or event occurrence

Forked tasks share history. Initially this looked compatible with replaying hook
records, but a parent's grant must not authorize a child's pending work. Each grant
is therefore owned by a task, and foreign-owner records provably leave its
authorization state unchanged. This is a concrete example of equal information
not implying equal authority in an otherwise shared formal model.

Event projection exposed a second distinction: an inherited tool result exists in
a child's history but did not just happen there. Deriving births by comparing the
parent's before/after snapshots is ambiguous when forking occurs inside a larger
scheduled transition. `ForkResult` is now an explicit child-birth record. Its public
serialization is proved equal to the previous function-output representation, but
native projection can identify the exact new suffix. No additional public history
record or changed fork return is needed. Pending inherited calls still acquire the
child's own grants when they execute.

### Observer non-interference must include packet admission

It is insufficient to say an observer callback cannot mutate the model. Adding its
event payload to a bounded output envelope can otherwise make a valid command fail
admission. Native notification projection now carries a proof that state, reply and
core effect projection are unchanged; bounded payloads and an optional-batch
admission fallback keep observation from rejecting core work. The host's separate
bounded queues may lose notifications under pressure and report diagnostics.
Delivery is honestly best-effort: callback outcomes are not durable acknowledgments
and replay does not repeat them. Sequence/ordinal identity supports an extension's
own idempotent sink, not a claim of exactly-once external effects.

Running-operation announcements introduced another representational trap. A JSON
value containing `status: "running"` is not a proof that it is an announcement; a
real tool may return that exact value. Native projection uses outstanding operation
rights, typed final results and the newly settled suffix rather than payload
heuristics. Cancellation emits one completion even if an earlier running output
was already published. Replayed inputs and stale completion tickets create no new
model-settlement occurrence.

### Plugin transport is not a policy runtime

The native binary does not need a TypeScript plugin layer. A shared bounded stdio
RPC transport serves both MCP and language-neutral plugin processes, with separate
protocol vocabularies. All internal and external model calls pass through the native
gate before their route-specific interpretation. Callbacks inspect committed
tickets; slow observers have a separate queue and cannot delay native authorization.
Failure or unknown callback outcome closes the gate without repeating a callback
after recovery. The process may still have performed its own effects: formal core
permissions do not sandbox a trusted executable or roll back the operating system.

A registered tool's schema also has to denote one known native structure. Accepting
arbitrary JSON Schema while ignoring unsupported constructs would create an
undeclared interpretation gap. Registration now rejects schemas outside the native
closed fragment. Both the schema language and its bounds are explicit; MCP remains
an external server-validated schema contract rather than pretending these two
interfaces have identical validation semantics.

### Evidence exercises the intended broken correspondence

New negative tests remove the universal gate, discard task ownership, revive a
denied chain, ignore plugin order, retarget a rewritten call or alter an observer's
reply projection. Each must remain syntactically/type-correct until the relevant
law fails; an affine typing error is not evidence that a semantic obligation caught
the regression. Process fixtures also inspect SQLite before each callback and
compare received events with native committed batches. This tests the mechanical
host bridge without confusing it with a proof of an arbitrary plugin policy.

## Relational theory reuse beyond collection and iterator laws

### Standard names are not the point where reuse becomes real

The previous conceptual entry named simulations and state machines, but a standard
name alone does not remove a project's proof burden. The useful boundary is an
existing theorem's premises. The relational protocol now presents exactly that
boundary: concrete input-labelled edges against `PROGRAM.transition`, one-step
refinement and safety, and a correspondence to the actual journal. Existing
closure preorder/idempotence proofs and explicit applications of original
induction proofs supply composition, macro-step flattening, path simulation and
invariant lifting. The project does not maintain another recursive path theory.

The carrier must include the observation a theorem is meant to preserve. A graph
of final worlds alone could silently discard replies or effects while still
satisfying safety. Keeping complete decisions and proving equality with the actual
receipt executor closes that loophole. Negative tests delete old receipts from
both sides of a shared helper: the independent production correspondence still
has to reject the change. A shared helper is not independent evidence.

### Proof portability has an evidence-use interface

Original Rocq induction duplicates a subpath when it passes both that path and its
induction hypothesis to a callback. Arbitrary Bend `Type` evidence is affine, so
literal translation of that interface fails even though the proposition is the
desired one. Marking the evidence reusable would require `Data`; erasing it would
not create live evidence. Neither is a valid shortcut.

The successful boundary is to specialize the original proof at its explicit
application. The simulation callback does not need its original subpath witnesses;
the invariant application does not need the already-known reachable-prefix witness.
Beta reduction removes those unused arguments while preserving original cases and
recursive calls. Generalized induction can also change the unused prefix witness's
type. The translator ignores that domain only after checking the binder is unused,
and still verifies captured arguments and bodies. Raw dependencies and the two
application wrappers remain separately visible in the certificate bundle.

### An index and the evidence needed to discharge a premise are different roles

Runtime endpoint arguments placed before a recursive path prevented Bend from
seeing structural descent: the recursive endpoint changes before the path shrinks.
Making endpoints and intermediate states erased indices fixes the ordering without
unsafe recursion. A dependent reflexive constructor carries an explicit equality
witness for its endpoint. Actual edge evidence separately retains the concrete
source state and input, because the one-step application needs live values.
The distinction is not two state models: endpoint equations bind the retained
values to the exact indexed transition.

### Provenance inventories also need one source of truth

The theory README's old count survived after Boolean proofs were added. The import
inventory now comes directly from both quoted bundles and is checked with the
program. It distinguishes original definitions/theorems, specialized dependencies
and explicit applications, rather than presenting every exported name as an
upstream theorem. Human explanation records the correspondence and limits; it no
longer owns a second manually maintained list of imported entities.

The resulting theory reuse covers arbitrary finite choices of protocol inputs,
including independent completion order and nested macro-steps. It does not assert
that changing external side-effect order is harmless, or that a pending process
eventually responds. Such conclusions need their own theory and premises, not a
stronger-sounding name for reachability.

## 2026-09-27: sandbox effect boundary

A writable-root list cannot enforce permissions in the process adapter. The
adapter now translates an explicit plan into Seatbelt or bubblewrap/seccomp;
neither a failed sandbox startup nor a nonzero command grants an unrestricted
retry. The service journal needs an additional read-only exclusion when a user
selects its ancestor as a workspace root. On Seatbelt, protecting only the
journal's pathname is insufficient: renaming an ancestor could otherwise move
the subtree outside that pathname rule, so ancestor unlink/rename is denied too.

The initial real-process probe failed inside the outer Codex sandbox with
`sandbox_apply: Operation not permitted`. Running the isolated temporary-directory
tests with explicit outer approval produced seven passing sandbox tests on
macOS. This is evidence about the real Seatbelt path, not Linux execution. The
Linux BPF interpreter probes both x86-64 and AArch64 syscall/architecture branches;
the platform matrix separately owns real Linux subprocess tests. `clone3` needs
`ENOSYS`, rather than `EPERM`, to preserve libc's fallback to flag-checked `clone`.

## 2026-09-27: task-local workspace and project defaults

The former service-wide working directory is now only the default for new
unprojected tasks. A task contract contains independent workspace, sandbox,
approval and project coordinates. Project defaults are copied at birth; changing
the project map preserves the task collection by construction and by the
`ContextBoundary.project_frame` proof. Forks keep model/tool/resource invariants
while permitting an explicit child context; existing contracts remain immutable.

The new project ID exhaustion guard initially compared a symbolic `Nat` with
`U32.to_nat(4294967295)`. The pure checker overflowed while specializing the
command-transition proof for CreateProject, even though PROGRAM and the initial
invariant checked. A diagnostic copy of the pinned checker localized that exact
definition; it was not used as proof evidence. Storing the project allocator as
U32 and rejecting its maximum value before increment preserves the bound without
expanding a huge natural literal. The unmodified pinned checker then accepted
PROOF, including the new context-boundary instance.

The real macOS service probe committed canonical multi-root project observations,
dispatched a Bash process in the selected primary root, wrote both authorized
roots, rejected an outside write, and reopened the same journal from another
launch directory without repeating the effect. Journal identity now describes
the kernel/format, not a global workspace. File effects carry task-local plans.

## 2026-09-27: completing the approval boundary and Web interaction

The unfinished approval assembly called a sibling proof's private helper. That
refinement is now the public `LAWS.review_semantics` obligation: protocol supplies
the evidence, and approval assembly consumes the declaration. No architecture
test or invariant was relaxed. The remaining native-test failures confused the
list envelope with its task array, expected an asynchronous notification without
an earlier announcement, and attempted another manual fork while its first fork
had resumed the parent model. Correcting those boundary expectations preserved
the existing scheduling behavior.

Approval controls now come from the native presentation, through the same command
resolver as CLI requests. The surface displays the exact post-hook command,
justification, primary directory and unrestricted one-invocation scope. An old
button is not authority: a stale submit returns a refused receipt with a refreshed
screen. HTTP success only means that the presentation envelope was delivered.
Model review remains a separate tool-free request with its own cancellation
identity; it creates no task and emits no task-stream preview.

An integration probe runs inside the approved child process and opens SQLite
before writing outside the workspace. It requires both the committed review and
the one authorized execution with a fresh ticket. Denial, cancellation, malformed
review output and reopening a pending review produce no such process. A strict
two-string-member wire grammar also rejects duplicate JSON keys before ordinary
JSON decoding can discard an earlier decision. These are external-boundary
checks, not proofs that a reviewer model reliably judges user intent.

The browser test initially missed a mobile overlay because programmatic `.click()`
does not test hit targets. The scroll-to-latest control now lives in the header;
desktop and narrow-screen approval checks use hit-testing and real pointer
coordinates. Both approval actions were exercised against actual Bash effects,
and the screenshots were inspected. The browser reported no runtime exceptions.

Validation on this macOS host: `npm run check` passed the pure proof gate,
certificate reproducibility and syntax checks; `npm test` passed all 188 tests
with no skips; `npm run test:browser` passed. New type-correct mutations that mix
reviewer origins, reuse grants, omit the review effect or change the authorized
command were rejected by the actual proof root. The full process suite was run
outside the outer sandbox so Seatbelt could create its own boundary. This run
does not establish real Linux execution: Linux syscall-filter probes passed for
both supported architectures, and the existing Linux CI job remains responsible
for executing bubblewrap on a Linux kernel. No sandbox was replaced with a
permissive fallback and no commercial model's judgment was treated as proof.

## Desktop presentation without changing the native interaction model

The frontend-only refresh follows the locally installed Codex Desktop
`26.917.71314`; ADR 0020 records the relevant resource names. Native labels,
field bindings and command availability stay unchanged. The adapter moves
existing inputs into a compact composer and retains the two native send/steer
forms behind a menu. Their separate drafts survive the switch.

Chrome can retain layout boxes for descendants of a closed `details` element.
A zero `getClientRects().length` assertion therefore did not establish whether
the settings field was actually visible. The browser check now uses
`checkVisibility()` and real pointer hit-testing; it also verifies that the
mobile navigation makes the conversation inert and that the access dialog
receives focus. All eight browser-check groups passed with no runtime exceptions,
including actual approve/deny clicks and the existing streaming boundary checks.
No Bend source or theorem was changed for this presentation work.

`npm run check` passed, and the final complete `npm test` run passed all 188 tests
with no skips. The DOM fixture was extended with namespace-aware SVG creation
and attribute toggling; the disabled-action assertion still targets the actual
button, not its new label span. An earlier parallel run stalled in a plugin test
process; its isolated rerun passed all 17 checks, and the final full run completed.

## Adaptive reasoning: completion guards and external boundaries

The production reasoning callback originally matched status and phase together.
Although the archived branch ignored every phase, that compilation shape did
not reduce on an unknown phase when constructing the archived-completion proof.
Matching status first makes the unconditional archive guard explicit; the
complete existing obligation then checks without adding assumptions or changing
the admitted callback behavior.

An initial native mutation test selected the same projection expression in both
ordinary and asynchronous tool results. Its assertion failed before testing any
theorem. The mutation now includes the exact FunctionOutput branch and checks
that it is unique, remains type-correct, and is rejected by the production
reasoning boundary. That is evidence about the proof, not another finite
semantic replay. Redundant native lifecycle examples were removed only after
mapping their coverage in tests-bend/README.md; real HTTP cancellation, changed
input during evaluation, account discovery and SQLite/restart checks remain.

The macOS outer command sandbox initially prohibited Seatbelt from starting,
returning `sandbox_apply: Operation not permitted`. The tests were rerun with
normal process permissions instead of reducing the application's isolation.
The final full run passed 219 tests with no skips; the real-browser run passed
all eight check groups with no browser exceptions. These use local fixture
services and an isolated browser profile. No live Jev or commercial ChatGPT
request, decision-quality measurement or cache-savings measurement was made.

## Component locality: testing actual boundaries

Separating `World` into a task component and a parameterized remainder removed
the unrelated record-field edits, but the first extension fixture still missed a
boundary. It checked cursor updates in memory while the universal wire decoder
recreated every cursor from its board projection. A new component's cursor was
therefore reset on its next request. Cursor field encoding, decoding, validation
and clock observation now belong to feature assembly. Shared surface types live
below both renderers, so adding a feature view does not require a UI dependency
cycle. The extension test builds the unchanged `MAIN.bend` and checks actual
transport, rendering, refresh and board-navigation round trips.

The task-storage replacement experiment appends the empty list to an unknown
task list. It intentionally preserves meaning without preserving definitional
equality. Its component proof uses the existing `Std.app_nil_r` certificate. This
exposed a protocol client proof that reconstructed the concrete task update; it
now applies congruence to the storage operation. The permanent fixture changes
only task implementation and its local provider, first checks that the old local
proof rejects the changed definition, then checks that the new local proof
restores the complete root while all clients remain frozen. This extra append is
a proof-boundary probe, not a production optimization.

Bend distinguishes affine and reusable function parameters even for the same
data types. Passing named rendering functions as callbacks required pointwise
lambda adapters rather than assuming their quantity annotations were identical.
The callbacks connect existing pure rendering to feature assembly, not to an
independent behavioral specification that could silently become circular.

Full native compilation exceeded the old fixture's 120-second synchronous limit.
Native builds now have a separate bounded asynchronous step and cancellation
terminates its compiler process group. A native entry's exact three declared IO
boundary diagnostics are accepted only for that entry; the separate proof root
still requires the pure-success report. Compiler timeout remains a failed test,
never evidence of semantic rejection. ADR 0023 and `tests-bend/README.md` describe
the supported changes and the division between proof and boundary-test evidence.

Completion validation on the pinned Bend 2.0.27 toolchain: the full `npm test`
run passed all 260 tests with zero failures and zero skips; the subsequently
added matching-cache regression also passed separately. `npm run check` and the
tracked-file index check passed. The real-browser checks passed eight general UI
groups and eleven board groups. These runs used isolated local services and
browser profiles. The integration suite required normal macOS process permissions
so Selvedge could start its own Seatbelt sandbox; that isolation was not disabled.
