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

The small physical suite targets failure mechanisms that the model cannot rule
out: SQLite failing after a kernel transition, execution before durable authority,
subprocess pipe pressure and process-tree cleanup, filesystem links and content
integrity, byte-split network decoding, credential rotation and secret-file
handling, transport teardown, and observed browser connection/IME regressions.
The handwritten source scanners retain small syntax regressions. These checks
exercise the actual production paths rather than test-only models.

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

The remote receipt probe also exercises account-authenticated Codex review and a
subprocess that inspects its durable grant before writing. Independent Web text
requests retain a focused regression for effects without task history.

Title settings retain one physical probe for independent Task/Agent prompt
payloads, durable authority before HTTP dispatch and saved settings across SQLite
reopen. Title lifecycle, entry preservation, cancellation and settings conflicts
remain production proof obligations.

Work probes exercise the HTTP creation path's Project workspace observation and
the native tool transport's caller identity, command payloads and SQLite reopen
without another model request. The combined Work/worktree command also exercises
HTTP default-cwd observation and real Git dirty-file copying across reopen. Work
membership, graph admission and ordinary Task independence remain production
construction and proof obligations.

Interactive Markdown keeps focused checks for parser completion notifications,
buffered storage writes and failures, provider output coordinates, legal SSE
frames crossing HTTP backpressure, and the reproduced V8 stack overflow on
ordinary streamed output. The language's semantics remain production proof
obligations. The real Chromium checks exercise streaming controls and IME,
restoration, live graph display and action delivery through a controlled model
HTTP peer. The standalone command builds the production libraries once:

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

The fresh proof book feeds one official backend emission for eligible production
entries. Standalone modules retain their own reachable generated declarations;
complete source and tool identities plus output hashes guard reuse. Joint inputs
conservatively share their invalidation scope. JavaScript compilation uses Bun;
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
