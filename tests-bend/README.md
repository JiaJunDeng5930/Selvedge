# Test responsibilities

For each property, prefer construction in the domain language, then types, then
proofs, then focused tests, and finally end-to-end tests. Inspect the actual
production binding before claiming a property is guaranteed. Do not test it again
at a later layer.

A test also needs a convincing likelihood of real failure relative to its setup,
runtime and maintenance cost. A possible error, an unproved property or an
external boundary alone is insufficient; default to deletion when the case is
unconvincing. Merge related checks and setup. Do not preserve scenario matrices
inside one large test merely to reduce the reported test count.

The mandatory [production proof root](../PROOF.bend), source-ownership gate and
certificate checks run through `bun run check` and ordinary builds. They own
semantic requirements, component refinement and unrelated-state preservation.
Tests do not recompile hypothetical application extensions or repeat semantic
traces through HTTP and SQLite.

Audio acceptance uses the running service's public HTTP and browser entry points
with a real ChatGPT account. Internal media and injected audio fixtures are
temporary debugging aids because they bypass the production login and transport.

The source gate checks core entries' actual transitive dependencies against
application and feature ownership, private representation access, and production
proof coverage. Independent helpers need no duplicate import whitelist. The UI
gate checks public law providers and their load order; construction evidence may
live with the code that produces it, and a requirements type needs no extra law
solely because of its name.

The small physical suite targets failure mechanisms that the model cannot rule
out: SQLite failing after a kernel transition, execution before durable authority,
subprocess pipe pressure and process-tree cleanup, filesystem links and content
integrity, byte-split network decoding, credential rotation and secret-file
handling, transport teardown, and observed browser connection/IME regressions.
The handwritten source scanners retain small syntax regressions. These checks
exercise the actual production paths rather than test-only models. The process
probe sends real model tool calls through the service to exercise live retained
output under pipe pressure, stdin closure, terminal resizing and signals, and
cleanup of owned subprocesses.

Managed worktrees add focused real-Git checks for copying local edits without
executing repository programs, archive/recovery and interrupted checkout ownership.
Project task hierarchy, shared-worktree archive permission and Worktree preference
propagation remain production construction and proof obligations.

Hierarchical context discovery keeps one filesystem check for Git boundaries,
multiple roots, override selection, skill metadata and incomplete scans. Context
admission, deltas, inherited history and provider selection remain native
construction and proof obligations.

Remote control keeps focused physical checks for atomic command receipts across
SQLite reopen, WebSocket session teardown and the real Durable Object runtime.
Grant permissions, generations and command classification belong to native
constructions and their production proofs.

The remote receipt probe retries after its workspace guidance becomes unreadable,
so receipt lookup must precede fresh filesystem observations. Account refresh and
durable process authority have their own focused probes. Independent Web text
requests retain a focused regression for effects without task history.

Work probes exercise the HTTP creation path's current Project guidance and the
combined Work/worktree command's default-cwd observation. The dedicated Git probe
owns dirty-file copying and recovery. Native caller identity, Work and graph
commands remain in the [native invocation construction](../harness/protocol/PROGRAM.bend)
and [feature assembly evidence](../harness/features/laws.bend).
[Title evidence](../features/titles/PROOF.bend) owns saved settings and generation;
titles use the ordinary host model transport and journal, without another
feature-specific HTTP/SQLite trace.

Interactive Markdown keeps focused checks for parser completion notifications,
buffered storage writes and failures, live sparse SSE coordinates, legal SSE
frames crossing HTTP backpressure, and the reproduced V8 stack overflow on
ordinary streamed output. The language's semantics remain production proof
obligations. The real Chromium checks exercise streaming controls and IME,
local-storage restoration, code scrolling, action delivery and removal of stale
content from visible and inert measurement DOM through a controlled model HTTP
peer. [Output origins](../harness/conversation/origin-contract.bend),
[interactive actions and state](../interaction/interactive_markdown/CONTRACT.bend)
and [live graph projections](../interaction/interactive_markdown/documents-contract.bend)
remain production obligations. The standalone command builds the production libraries once:

```sh
BUN_BIN=/path/to/bun CHROMIUM_BIN=/path/to/chromium bun run test:interactive-markdown
```

The browser script requires Python Playwright. It uses temporary local services
and saves failures under `.workpad/interactive-browser-results`; no live model
account is used.

Its `--mode side` probe holds real parent and side model HTTP streams open while
the browser uses separate composers, a side Interactive Markdown input and IME.
It checks local dismissal, explicit return delivery through the running parent's
queue, provider encoding of filtered records, and the return cursor after SQLite
reopen. Side snapshot and filtering semantics remain production proof obligations.

`history-search.test.mjs` follows original message locations through HTTP, an actual
native agent tool call and SQLite reopen. After the production build, its companion
Chromium check searches conversations and clicks a result to scroll to the original
message:

```sh
BUN_BIN=/path/to/bun CHROMIUM_BIN=/path/to/chromium python3 scripts/test-history-search-browser.py
```

It reuses the temporary model HTTP fixture, requires Python Playwright and saves
browser evidence under `.workpad/history-search-browser-results`.

Use Bun 1.4.2 or later and the pinned Bend toolchain installed by
`bash scripts/bootstrap.sh`:

```sh
bun run verify
```

`bun run verify` checks the complete production proof, native entry, syntax and
certificates, builds the production libraries once, runs the complete suite and
checks the tracked-file index. `bun run test` builds once and invokes Bun's
standard sequential test runner with assertion deadlines disabled. Each invocation
owns its subprocess group, drains both output pipes and validates the complete
normal test footer. Explicit cancellation terminates the owned process group.

The compiler cache and guarded-intrinsic probes compile small isolated inputs:
changed imports, retargeted files, changed toolchain/export identities and damaged
outputs must execute current code; joint modules must preserve independent entry
functions and constructor identities. Differential execution checks Unicode,
control escapes, malformed strings, bounded accumulators and missing browser
primitives against the original generated functions. These target the actual
artifact-cache and intrinsic failures addressed by this change; they do not
recompile hypothetical application extensions or replay model semantics.

The JavaScript purity probe reproduces a runtime-transitive `@unsafe` declaration
outside the verification entry's prefix. The compiler's upstream `book_promises`
check rejects it before artifact reuse or emission.

Kernel and browser entries share a fresh checked book; the official backend
emits separate modules using its reachability and erasure rules. Their compiler
exits before host and plugin entries compile in separate processes with their
own imports and proof providers. This releases the full proof book and browser
IR before host emission at the cost of repeating some shared compilation.
Complete source and tool identities plus output hashes guard reuse. Shared-book
inputs conservatively share their invalidation scope. JavaScript compilation uses Bun;
native-entry checking uses the official release compiler. Neither has a scripted
time or heap limit. The checker and compiler source remain pinned and unchanged.
The suite uses temporary homes, loopback servers and subprocesses; no
real model account or paid request is needed. OS isolation requires Seatbelt on
macOS or bubblewrap/seccomp on Linux. Chromium or Google Chrome is required for
the focused DOM regression; `SELVEDGE_BROWSER` may name its executable.

A passing physical probe is local evidence, not a proof about all compiler,
operating-system or provider behavior. Synthetic keyboard events do not establish
hardware input or operating-system IME behavior. Loopback OAuth and model fixtures
do not establish commercial service availability or model quality. GitHub Actions
CI is disabled; run the checks explicitly. Git hooks apply only when installed.
