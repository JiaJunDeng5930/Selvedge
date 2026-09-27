# Verification responsibilities

The pure proof root is `PROOF.bend`. It checks the actual production import
closure, the concept assembly, functional correspondence and state invariants.
Tests do not maintain a second finite-example specification of those semantics.

| Guarantee / fault model | Evidence owner |
| --- | --- |
| Commands, queue order, task lifecycle, branch inheritance, control/operation separation and recovery semantics | `LAWS.bend`, `INVARIANTS.bend`, `bendlib/architecture.bend`, discharged by `bendlib/proofs/*` and assembled in `PROOF.bend` |
| Ordered before/after authorization and result settlement, call/error identity, audit projection | `HOOKS.bend`, `architecture.PluginBoundary` / `ResultBoundary`, `proofs/plugins.bend` / `results.bend` |
| General concatenation, map, iteration and reachability results | Original checked source certificates in `stdlib.bend`, `relations.bend`, `association-map.bend`; the application proves correspondence and domain premises |
| Proof checker / evidence chain rejects false, missing, circular, unsafe or corrupted evidence | `pure-proof`, `proof-gate`, `whole-program-proof`, `architecture`, `stdlib`, `relations`, `association-map` tests |
| Native compiler, framing and codec faults: Unicode, embedded controls, exact numeric lexemes, malformed completion envelopes | `native-boundaries.test.mjs`; these are targeted executable probes, not a lifecycle truth table |
| SQLite journal transactions, persistence format, locking and corruption | `journal.test.mjs` |
| Physical processes, cancellation, descendants, output files and UTF-8 capture | `process.test.mjs`, `coding.test.mjs`, `async-service.test.mjs` |
| Provider/MCP/plugin wire formats, failures, actual cancellation and commit-before-callback | `providers`, `plugins`, `after-hooks`, `service-recovery` tests |
| Authentication, HTTP/SSE and generic browser rendering | `auth`, `ui`, `service` tests |
| Audited ChatGPT OAuth/Responses, account model discovery and encrypted compaction transport, restart and cancellation | `chatgpt-contract`, `chatgpt-models`, `chatgpt-compaction` tests; loopback services, not a live commercial account |
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
