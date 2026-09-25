# Core coding effects and checkpointed model context

## Decision

Keep the existing certified Bend transition and its input journal. Extend that
program with native file-tool contracts, explicit nonterminal interruption, and
context checkpoints rather than adding another task controller in Node.

`MODEL.Execution` distinguishes internal operations, external observations, and
external mutations. Dispatch and crash-recovery permission both consume that
classification. `read_file` may be repeated; `write_file`, `edit_file`, Bash, and
unclassified MCP effects may not be repeated after an unknown outcome. Host file
operations require revision evidence and publish atomically within the documented
OS boundary. Shell failure is an error result, not a successful test or build.

`interrupt` is distinct from `stop` and `archive`. Its pure transition closes
accepted function calls, retains queued messages and the frozen contract, settles
the phase, and commits cancellation before the host aborts work. Late completions
cannot match the settled phase. This reuses ticket correlation and the existing
transition/replay certificate instead of inventing a second cancellation state
machine in the host.

Full history is the durable record; `MODEL.context_history` is an idempotent
projection for a model request. A checkpoint replaces only that request view.
`SummaryPending` and `RequestSummary` give summary work a correlated ticket with
no tool manifest. Effect admission requires all calls in the projected context
to be settled. Empty, oversized, tool-bearing, cancelled, or stale summaries
cannot become checkpoints. A supplied bounded checkpoint is an explicit command
and remains available when no provider can consume the old context.

Instructions, schemas, byte bounds, retry policy, and checkpoint rules live in
the native entry points. Node interprets authorized effects and OS/network
results. Canonical workspace identity is a persisted precondition of that
interpretation; the same journal cannot be reopened under another working
directory. No legacy format reader or migration is introduced.

## Reference evidence

The inspected references are pinned, not claims about every version of a project.
Local clones live in ignored `.workpad/references` and are not vendored.

| Reference | Inspected revision and relevant source | Design used here |
| --- | --- | --- |
| `earendil-works/pi` | `19a0361be89bf78ccf9bbaed9a496d6484759f67`; `packages/agent/src/harness/tools/read.ts`, `edit.ts`, `runtime/drive/retry.ts`; `packages/coding-agent/docs/compaction.md` | Bounded recoverable output, unambiguous file edits, serialized mutations, abortable retry, and separation of the retained session from model context. |
| `shpz/UnrealHarness` | `af72d7e53a096bc97bbc3a6fd50e8e4bda183a8c`; `skills/ue-build/build.py`; `benchmarks/ue5-skillsbench/runner/verifier.py` | Real exit status, useful build deadlines, retained execution evidence, and verification separate from the agent's assertion of success. |

The public `UnrealHarness` match is a UE build/skills/benchmark suite, not a
general-purpose agent loop. We do not attribute a scheduler, recovery protocol,
or measured general harness improvement to it. These are independently written
implementations of the selected ideas: for example, Selvedge uses UTF-8 byte
pagination and mandatory revision guards rather than copying Pi's read/edit API.

## Consequences and evidence boundaries

Global safety/replay proofs continue to instantiate the existing generic
transition induction and list-monoid theory with `PROGRAM.next`. New domain
lemmas establish interruption and context-projection properties. They do not
prove a model summary semantically equivalent to a conversation, Node's file
implementation correct, or a test suite sufficient for a user's requirements.

The local integration suite runs a real read/write/edit/Node-test loop through
the native journal and loopback provider, compacts it, reopens it, and checks
that the tool was not rerun. Separate tests cover live process interruption,
revision races, UTF-8 bounds, retry exhaustion, and checkpoint failure/recovery.
These are positive boundary observations, not remote-model acceptance tests or
whole-program liveness proofs.

Context thresholds are serialized-byte budgets, not exact provider token counts.
Full journal/history growth and replay costs remain; context projection is not
a storage compactor. Artifact retention is bounded per stream but cumulative,
and cleanup must account for references from retained history. File guards are
not a global atomic compare-and-swap against uncooperative external writers.
These limitations are explicit rather than hidden by an overly broad theorem.
