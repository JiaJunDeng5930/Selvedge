# Verification responsibilities

The formal entry is [PROOF.bend](../PROOF.bend), with production obligations in
[LAWS.bend](../LAWS.bend), [INVARIANTS.bend](../INVARIANTS.bend),
[core/interface.bend](../core/interface.bend). Follow those entries for the executable
requirements and their evidence. Tests target compiler, certificate and external
boundary faults rather than repeat proved finite state-transition examples.

| Boundary or fault model | Evidence owner |
| --- | --- |
| Missing, false, circular, unsafe or corrupted proof evidence | `pure-proof.test.mjs`, `proof-gate.test.mjs`, `whole-program-proof.test.mjs` |
| Specification import independence, IO-only native entry, proof-carrying conceptual entry and acyclic proof dependencies | `architecture.test.mjs` |
| Certificate translation rejection and compiler rejection of mutated algebra, map and closure evidence | `stdlib.test.mjs`, `association-map.test.mjs`, `relations.test.mjs` |
| Production board/reasoning mutations remain type-correct and fail their obligations | `board-proof.test.mjs`, `reasoning-proof.test.mjs` |
| Component extension and contract-preserving replacement with unrelated source files frozen; native decode/commit/query/effect round trips | `locality.test.mjs`, `locality-support.mjs`, `fixtures/locality-extension.mjs`; actual-source boundary checks in `scripts/check-components.mjs` |
| Private model construction and binding/case destructuring rejected by the actual source gate; public command values, explicit model/proof owners and inert text accepted; malformed, unknown and duplicate representation policies rejected | `locality.test.mjs`; source-boundary mutants are checked as legal Bend independently of semantic proof mutants |
| Bend-generated JavaScript, Worker and codec transport: Unicode, embedded controls, exact numeric lexemes and malformed completion envelopes | `kernel-boundaries.test.mjs` |
| Pending approval decoder rejects extra authority fields, absent reasons, invalid decisions and oversized reasons | `approval-decoding.test.mjs` |
| HTTP approval, SQLite grants and actual subprocess authorization, malformed/duplicate decisions, cancellation and reopen | `approvals.test.mjs`, `fixtures/approved-tool.mjs`; the child checks its committed grant before writing outside the workspace |
| Actual adaptive history through providerInput/responseBody: prefix preservation, configuration updates, audit filtering and request effort; nested private continuation projection | `reasoning-boundaries.test.mjs` |
| Typed Jev HTTP payloads, Unicode/token budgets, provider identity, evaluator cancellation, committed dispatch and restart | `reasoning.test.mjs` |
| SQLite journal framing, commit faults, replay and restart | `journal.test.mjs`, `service-recovery.test.mjs` |
| Subprocess execution, real tool results, deferred input and cancellation | `process.test.mjs`, `coding.test.mjs`, `async-service.test.mjs` |
| Filesystem observations, Seatbelt quoting, seccomp ABI encoding and actual OS write isolation | `sandbox.test.mjs` |
| Canonical workspace observations, committed execution plans, real subprocess cwd/permissions and journal reopen | `workspaces.test.mjs` |
| Project filesystem observations, invalid project revision decoding and committed project guidance through dispatch/restart | `project-context.test.mjs` |
| Overflow and summary are committed before retry; completed file mutation is not repeated after restart | `context-recovery.test.mjs` |
| Provider/MCP/plugin wire formats, faults, cancellation and commit-before-callback | `providers.test.mjs`, `plugins.test.mjs`, `after-hooks.test.mjs`, `service-recovery.test.mjs` |
| ChatGPT Web v1 predecessors, durable same-key observation, tool batches, concurrent/deferred inputs, cancellation, reviews/drafts and restart | `chatgpt-web.test.mjs`, `fixtures/chatgpt-web.mjs`; loopback HTTP, SQLite and sandboxed subprocesses |
| ChatGPT account authorization, public Responses/model discovery and encrypted compaction transport | `auth.test.mjs`, `chatgpt.test.mjs`, `chatgpt-models.test.mjs`, `chatgpt-compaction.test.mjs`, `fixtures/chatgpt.mjs`; signed loopback OAuth/OIDC and HTTP/SSE fixtures, not a live account |
| Authentication, HTTP/SSE delivery and committed service dispatch | `auth.test.mjs`, `service.test.mjs` |
| Board HTTP/SQLite, cancellation, authenticated uploads, file bytes and provider text payloads | `board-service.test.mjs`, `board-files.test.mjs`, `board-text.test.mjs` |
| Connection authentication, standalone MCP discovery, private installed settings, project-scoped physical execution, retry deduplication and restart | `chatgpt-plugin*.test.mjs`; local fixtures, not live OpenAI Tunnel or ChatGPT |
| Type-correct loss of dispatch/cancellation, replay, cross-connection ownership, restart replay and unrelated feature damage | `chatgpt-plugin-proof.test.mjs`; mutated operational root must type-check before production proof rejection |

Use Bun 1.4.2 or later and the pinned Bend compiler installed by
`bash scripts/bootstrap.sh`; see [the repository workflow](../README.md).
`bun run check` checks source boundaries, certificates, the production proof root
and script syntax. `bun run test` builds the kernel/browser JavaScript libraries
before running this directory with two concurrent test files.
`bun run test:locality` selects the extension/replacement checks.
`bun run build:native` is the optional native entry build and requires a C compiler.
Compiler mutation tests and locality native probes also require that toolchain.

Semantic mutations must type-check under the relevant production root before the
required proof rejects them. A timeout, syntax error or missing import does not
establish semantic fault detection. Certificate fault injection independently
checks translation and proof acceptance; normal check/build owns reproducibility.
The locality fixture emits an effect intention and does not provide a new physical
host interpreter for that effect.

These files describe evidence responsibilities, not results for the current
checkout. Loopback fixtures do not establish commercial model quality or
availability. Browser geometry, focus and physical interaction need actual
browser evidence; no current executable browser fixture supplies it.

Before removing another test, identify the proven property, its premises, its
production binding and any additional boundary it exercises. Unproved pure logic
still needs evidence. Keep type-correct semantic mutations: they test whether
the proof obligations can reject an incorrect implementation, not whether a
particular input produces the expected domain result. A timeout, syntax error or
missing import is not an acceptable semantic-mutation success.

## CI scope

`bun run test:ci` builds the production JavaScript libraries and runs regular integration tests
on Linux. The six files listed in `scripts/test.mjs` remain in `bun run test` and
the pre-push hook: their repeated whole-program proof checks and native extension
builds dominated hosted test time. Production proofs and certificate checks still
run in every PR. Pure-proof trust-boundary rejection tests and certificate mutation
tests remain in the regular CI suite. The workflow's manual `full` input runs the
complete suite on Linux and macOS; this entry is available once the
workflow is present on the default branch.
