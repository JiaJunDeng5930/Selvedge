# Verification responsibilities

The pure proof root is `PROOF.bend`. It checks the actual production import
closure, the concept assembly, functional correspondence and state invariants.
Tests do not maintain a second finite-example specification of those semantics.

Board proof mutations require a pure production/UI type-check before rejecting
the assembled proof. Board service tests cover real HTTP/SQLite, cancellation,
upload authentication and order preservation through replay. File/text tests
cover external bytes and provider payloads. `npm run test:board-browser` drives
Chrome through the actual UI, including pointer insertion, compact pickers,
continuous creation, pasted files, safe previews and responsive layouts. It fails
when Chrome is unavailable instead of silently counting an unrun check as passed.

| Guarantee / fault model | Evidence owner |
| --- | --- |
| Commands, queue order, task lifecycle, branch inheritance, control/operation separation and recovery semantics | `LAWS.bend`, `INVARIANTS.bend`, `bendlib/architecture.bend`, discharged by `bendlib/proofs/*` and assembled in `PROOF.bend` |
| Ordered before/after authorization and result settlement, call/error identity, audit projection | `HOOKS.bend`, `architecture.PluginBoundary` / `ResultBoundary`, `proofs/plugins.bend` / `results.bend` |
| Adaptive routing, bounded generation leases, frozen prefix, public evaluator projection and ticket/revision correlation | `REASONING.bend`, `reasoning-spec.bend`, `reasoning-architecture.ReasoningBoundary`, discharged by `proofs/reasoning.bend` in the production proof root |
| General concatenation, map, iteration and reachability results | Original checked source certificates in `stdlib.bend`, `relations.bend`, `association-map.bend`; the application proves correspondence and domain premises |
| Proof checker / evidence chain rejects false, missing, circular, unsafe or corrupted evidence | `pure-proof`, `proof-gate`, `whole-program-proof`, `architecture`, `stdlib`, `relations`, `association-map` tests |
| Native compiler, framing and codec faults: Unicode, embedded controls, exact numeric lexemes, malformed completion envelopes | `native-boundaries.test.mjs`; these are targeted executable probes, not a lifecycle truth table |
| SQLite journal transactions, persistence format, locking and corruption | `journal.test.mjs` |
| Physical processes, cancellation, descendants, output files and UTF-8 capture | `process.test.mjs`, `coding.test.mjs`, `async-service.test.mjs` |
| Workspace path observations, Seatbelt quoting, seccomp ABI encoding and real OS write boundaries | `sandbox.test.mjs`; native policy proofs do not prove OS isolation |
| Canonical project/workspace observations → committed task plan → real subprocess cwd/permissions → journal reopen | `workspaces.test.mjs`; pure context properties are in `workspace-architecture.bend` / `proofs/workspaces.bend` |
| Approval command/completion encoding, strict reviewer payloads, stable operation IDs and fresh execution-ticket serialization | `approvals-native.test.mjs`; native review properties are bound in `approval-architecture.bend` / `proofs/approvals.bend` |
| HTTP approval → SQLite grant → actual subprocess authorization; rejected/stale UI input, independent provider calls, malformed/duplicate decisions, cancellation and reopen | `approvals.test.mjs` and `fixtures/approved-tool.mjs`; the executed child checks its own prior committed grant before writing outside the workspace |
| Provider/MCP/plugin wire formats, failures, actual cancellation and commit-before-callback | `providers`, `plugins`, `after-hooks`, `service-recovery` tests |
| Authentication, HTTP/SSE and generic browser rendering | `auth`, `ui`, `service` tests |
| Paced Markdown, safe links, fragmented SSE, draft races and preview identity/revision | `web-streaming.test.mjs`; browser mechanics, not native-domain proofs |
| Real browser DOM identity, focus, scroll, worker formatting, responsive layout, unobscured approve/deny pointer targets, native form/actions and account compaction | `npm run test:browser`; isolated Chrome, loopback provider, native kernel and SQLite; captures in `.workpad/chatgpt-webui/` |
| Audited ChatGPT OAuth/Responses, account model discovery and encrypted compaction transport, restart and cancellation | `chatgpt-contract`, `chatgpt-models`, `chatgpt-compaction` tests; loopback services, not a live commercial account |
| Typed Jev HTTP protocols, Unicode/token budgets, provider identity, evaluator cancellation, committed dispatch and restart | `reasoning.test.mjs`; `reasoning-native.test.mjs` retains exact provider/evaluator/UI wire probes, not a second lifecycle specification; `reasoning-proof.test.mjs` checks type-correct production mutations |
| Cross-boundary create → commit → execution → callback → model delivery → restart | `service`, `service-recovery`, `context-recovery`, `after-hooks`, `coding`, `project-context` tests using real loopback servers/processes and SQLite |

`npm run check` verifies the certificates, actual proof root, native entry and
script syntax. `npm test` always checks those proof prerequisites before using a
cached native binary, then runs the component, end-to-end and evidence-chain
tests. Loopback services exercise real protocols, not a commercial model's
reasoning quality or a production service's availability.

The former `commands`, `async-operations`, `hooks-native`, `notifications` and
large `kernel` semantic example suites, plus native-only UI state examples, were
removed. Their proven transition examples were not a separate guarantee just
because a test spawned the native process. Exact serialization and malformed-wire
probes remain in `native-boundaries`; observer byte limits now run through a real
plugin process and read the committed value by cursor.

Before removing another test, identify the proven property, its premises, its
production binding and any additional boundary it exercises. Unproved pure logic
still needs evidence. Keep type-correct semantic mutations: they test whether
the proof obligations can reject an incorrect implementation, not whether a
particular input produces the expected domain result. A timeout, syntax error or
missing import is not an acceptable semantic-mutation success.

The adaptive-reasoning work removed native-only example replays of unsupported
choices, queued input, stale tool results, lifecycle/recovery and fork lease
ownership. These are covered by `ReasoningBoundary`'s admissibility, ownership,
invalidation and correlation fields, complete `start_meaning` /
`completion_meaning`, and the existing task/protocol refinement. They exercised
no additional external component. Exact byte/payload probes and real HTTP/SQLite
flows remain, alongside the semantic mutations that independently test the proof.

Approval mutations include accepting the wrong reviewer origin, consuming a grant
twice, dropping the independent review effect and changing the approved command
at dispatch. Each mutation must type-check under the production module root and
then be rejected by `approval_boundary` or `LAWS.execution_semantics`.
