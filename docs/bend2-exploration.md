# Bend 2 migration: exploration record

This record collects findings from implementing the executable model. The current
requirements themselves live in `LAWS.bend`, the domain in `MODEL.bend`, and the
executed transition in `PROGRAM.bend`. Dates describe observations on this branch,
not claims about all Bend versions.

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
