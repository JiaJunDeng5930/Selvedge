# Verification responsibilities

The formal entry is [PROOF.bend](../PROOF.bend), with production obligations in
[LAWS.bend](../harness/LAWS.bend), [INVARIANTS.bend](../harness/INVARIANTS.bend),
[interaction/presentation/PROGRAM.bend](../interaction/presentation/PROGRAM.bend). Follow those entries for the executable
requirements and their evidence. Universal properties belong to production
constructions and proofs. Tests exercise actual generated execution, translator
source-data boundaries and external behavior; they do not re-test Bend acceptance
or rejection of source code, proofs or certificates.

| Boundary or fault model | Evidence owner |
| --- | --- |
| Generic clients execute affine operational memberships and observe complete execution and application results without concrete state | `model-abstraction.test.mjs` |
| JavaScript translators reject unsupported source AST, constants, inductives, proof syntax, changed statements and reflection premises | `stdlib.test.mjs`, `association-map.test.mjs`, `relations.test.mjs` |
| Category admission and intersection execute and extract actual admitted values, with Some/None outcomes | `categories.test.mjs` |
| Generic input, movable-source and recovery clients execute native fields and check emitted nodes, bindings and filtering | `control-categories.test.mjs` |
| Component extensions with unrelated source and clients frozen; the complete extended production proof gate followed by generated decode/commit/query/effect round trips; current production JavaScript cache hits cannot bypass component policy | `locality.test.mjs`, `locality-support.mjs`, `fixtures/locality-extension.mjs`; actual-source boundary checks in `scripts/check-components.mjs` |
| Private model construction and binding/case destructuring rejected by the actual source gate; public command values, explicit model/proof owners and inert text accepted; malformed, unknown and duplicate representation policies rejected | `locality.test.mjs`; JavaScript source and configuration boundary checks |
| Bend-generated JavaScript, Worker and codec transport: Unicode, embedded controls, exact numeric lexemes and malformed completion envelopes | `kernel-boundaries.test.mjs` |
| Committed instruction/guidance deltas, Unicode edits, source withdrawal versus read failure, fork/compaction/restart and Responses/Web continuation payloads | `context-deltas.test.mjs`, `project-context.test.mjs`; loopback HTTP and SQLite |
| Explicit skill metadata files, bounded nofollow observations, quoted whitespace metadata through the host-to-kernel boundary, live context configuration and unloaded skill body isolation | `context-sources.test.mjs`; real temporary files and generated host boundary |
| New text and arbitrary-field metadata definitions with generic sources, context selection and proofs frozen; the complete extended production proof gate, compiled observation, committed deltas and provider rendering | `context-definitions.test.mjs`; compiled kernel extension and real temporary files |
| Pending approval decoder rejects extra authority fields, absent reasons, invalid decisions and oversized reasons | `approval-decoding.test.mjs` |
| HTTP approval, SQLite grants and actual subprocess authorization, malformed/duplicate decisions, cancellation and reopen | `approvals.test.mjs`, `fixtures/approved-tool.mjs`; the child checks its committed grant before writing outside the workspace |
| Actual adaptive history through providerInput/responseBody: complete history prefixes, recorded reasoning changes, audit encoding and request effort; nested private continuation projection | `reasoning-boundaries.test.mjs` |
| Typed Jev HTTP payloads, Unicode/token budgets, provider identity, evaluator cancellation, committed dispatch, bounded evaluator previews after raw history exceeds a kernel frame, and restart | `reasoning.test.mjs` |
| SQLite journal framing, commit faults, replay and restart | `journal.test.mjs`, `service-recovery.test.mjs` |
| Graph codec and Worker transport, installation and accepted-output handoffs in one SQLite commit, rollback, journal reopen, unknown nested settings and overdeep message templates | `task-graph.test.mjs`; generated execution and actual SQLite commits |
| Native graph tool capabilities, immediate service replies, restart, canonical workspace observations and refreshed creation guidance | `task-graph-service.test.mjs`; actual service effects and frozen model tool catalogs |
| Subprocess execution, real tool results, deferred input and cancellation | `process.test.mjs`, `coding.test.mjs`, `async-service.test.mjs` |
| Filesystem observations, Seatbelt quoting, seccomp ABI encoding and actual OS write isolation | `sandbox.test.mjs` |
| Idle-task execution configuration, in-flight model/approval rejection, unchanged project/workspace/history, actual next-provider routing, task-local ChatGPT Web root restart after model or policy changes, and preserved continuation after no-op configuration or another task's change | `task-execution.test.mjs`, `approvals.test.mjs`; authenticated loopback HTTP, actual native commands and provider fixtures |
| Canonical workspace observations, committed execution plans, real subprocess cwd/permissions and journal reopen | `workspaces.test.mjs` |
| Configured/global/project snapshots, root order, inherited and explicit fork prefixes, file changes and committed dispatch/restart | `project-context.test.mjs` |
| Context-limit failure without summary/retry; complete history and completed file mutations survive restart | `context-recovery.test.mjs` |
| Provider/MCP/plugin wire formats, faults, cancellation, commit-before-callback and metered compaction retaining its consumer after external credential rotation | `providers.test.mjs`, `plugins.test.mjs`, `after-hooks.test.mjs`, `service-recovery.test.mjs` |
| ChatGPT Web v1 predecessors, durable same-key observation, tool batches, concurrent/deferred inputs, cancellation, reviews/drafts, restart and byte-chunked SSE Unicode/CRLF decoding with invalid UTF-8 rejection | `chatgpt-web.test.mjs`, `fixtures/chatgpt-web.mjs`; loopback HTTP, SQLite and sandboxed subprocesses |
| ChatGPT account authorization, public Responses/model discovery, native compact request and complete replacement window, retained original history, cancellation and restart | `auth.test.mjs`, `chatgpt.test.mjs`, `chatgpt-models.test.mjs`, `chatgpt-compaction.test.mjs`, `fixtures/chatgpt.mjs`; signed loopback OAuth/OIDC and HTTP/SSE fixtures, not a live account |
| Committed context measurements, readable UTF-8 upper-bound fallback, frozen/stopped observation quiescence, complete request budgets, background continuation, hard-threshold waiting, oversized concurrent suffix reconstruction, idle revisions and endpoint switching | `automatic-compaction.test.mjs`, `fixtures/compaction.mjs`; real service, SQLite journal and HTTP token-count/compact fixtures |
| Production browser boot catalog observation, manual model preference persistence/restoration, unchanged existing task model and actual next-created task provider routing; empty-catalog unavailability; generated task reasoning single-choice controls encoded by the production semantic surface and accepted by authenticated HTTP for all approval policies, with complete unrelated task state preserved | `chatgpt-models.test.mjs`; compiled browser runtime and signed loopback account/provider fixtures |
| Failed physical snapshot closes its event stream; the compiled model schedules a real reconnect timer and fresh connection/snapshot; cancellation suppresses late snapshot publication | `browser-connection.test.mjs`, `browser-model-support.mjs`; loopback HTTP/SSE and actual timers |
| UI source separation and unique law-provider bindings; production activity surfaces, decisions, obstructions and compound cancellation through generated semantic surfaces and service HTTP | `ui-verification.test.mjs`; actual JavaScript source gates, generated execution and loopback HTTP |
| Production renderer preserves keyed DOM identity, selection and composition state; portal/target properties reach DOM/CSSOM; native focus and hit geometry, font/layout measurements, DOM keyboard mapping and stored appearance observed in a fresh iframe | `browser-dom.test.mjs`, `fixtures/browser-dom.mjs`, `browser-model-support.mjs`; actual Chromium controlled through CDP |
| Authentication, HTTP/SSE delivery and committed service dispatch | `auth.test.mjs`, `service.test.mjs` |
| Board HTTP/SQLite, cancellation, authenticated uploads, file bytes and provider text payloads | `board-service.test.mjs`, `board-files.test.mjs`, `board-text.test.mjs` |
| Connection authentication, standalone MCP discovery, private installed settings, deployment file allowlisting, byte-chunked HTTP Unicode and invalid UTF-8 rejection, project-scoped physical execution, retry deduplication and restart | `chatgpt-plugin*.test.mjs`; local fixtures, not live OpenAI Tunnel or ChatGPT |

Use Bun 1.4.2 or later and the pinned Bend compiler installed by
`bash scripts/bootstrap.sh`; see [the repository workflow](../README.md).
`bun run check` checks source boundaries, certificates, the production proof root
and script syntax. `bun run test` builds the kernel/browser JavaScript libraries
before running this directory with one isolated worker.
`bun run test:locality` selects source-boundary checks, extended production proof
gates and generated execution round trips.
`bun run build:native` is the optional native entry build and requires a C compiler.
Locality native probes also require that toolchain.
Browser DOM checks require Chromium or Google Chrome. Common system installation
paths are detected automatically; set `SELVEDGE_BROWSER` to the executable's
absolute path otherwise. These checks fail when no browser is available.

Production proof and certificate gates remain mandatory in ordinary checks and
builds. Translator tests use their existing source-data and reflection-premise
assertions; actual compilation tests inspect generated execution results. The
locality fixture emits an effect intention and does not provide a new physical
host interpreter for that effect.

Open categories and admission predicates are specified in their owning model
entries and [bendlib/categories.bend](../bendlib/categories.bend). Their universal
properties are supplied by the production constructions and proofs. Runtime
fixtures check the concrete values and external boundaries listed above.

These files describe evidence responsibilities, not results for the current
checkout. Loopback fixtures do not establish commercial model quality or
availability. The Chromium fixture checks actual DOM, CSSOM, focus, geometry and
measurements. Composition, input and keyboard events are synthesized DOM events;
they do not establish operating-system IME or hardware input behavior. Appearance
restoration uses a fresh same-origin iframe, not a browser process restart.

Do not add tests whose only criterion is Bend accepting or rejecting source code,
proofs or certificates. Keep actual compiler execution, JavaScript translator
boundaries and external integration assertions distinct from production proof
requirements.

## Local validation scope

GitHub Actions CI is disabled by project decision; this checkout has no automated
PR or manual workflow guarantee. `bun run test:ci` remains a local shorter suite:
it builds the production JavaScript libraries and runs regular integration tests.
`locality.test.mjs` and `context-definitions.test.mjs` run in `bun run test` and the
configured pre-push hook because they include extension compiler workloads.
Both commands prepare the build once through `scripts/test.mjs`. Git hooks apply
when installed; run the validation commands explicitly otherwise.
