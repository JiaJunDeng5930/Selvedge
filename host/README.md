# Host effects

The native Bend process owns task state. The host accepts JSON commands, performs
the effects returned by that process, and sends their results back as inputs.
It must commit an input and its decision to SQLite before publishing a reply or
starting an effect. A failed commit terminates the process; committed inputs are
replayed through the same Bend transition at the next start.

`transport.c` only receives bounded, length-prefixed UTF-8 tokens. It constructs
the generic token list consumed by the checked JSON decoder. It has no task
constructors, persistence operations, lifecycle rules, or tool policy. The native
compiler's effect ABI and the operating system remain trusted boundaries.

Host integration tests exercise persistence, HTTP delivery, model transport, and
process execution. Bend laws do not prove those implementations or their services.

Board text generation is a committed `RequestBoardText` effect interpreted by
`board-text.mjs`; native ticket/revision matching owns settlement. The
authenticated `board-files.mjs` boundary stores content-addressed, bounded files
and rejects forged metadata or symbolic-link storage. Paste, drop and picker
gestures share this route. The host observes timestamps and file facts; admission,
order, automatic dispatch and execution association remain native. See
`../docs/adr/0022-native-task-board.md`.

The suite also exercises device login and serialized credential refresh against a
loopback issuer, interruption and restart of an actual HTTP stream, MCP catalog
notifications during shutdown, and suppression of effects withdrawn within a
commit. Credential parsing errors must not quote file contents into task history.
Use `npm test` to run these checks; they require no real credentials or model calls.

`chatgpt-contract.mjs` fixes the audited wire version and connection identity.
`chatgpt-models.mjs` reads only this service's credential store, validates the
account catalog and materializes account-bound profiles. Login works without a
model profile. Its authenticated catalog refresh commits the ordinary Configure
input; it does not mutate existing task contracts. Cache freshness, endpoint and
account matching belong to this external transport boundary. The CLI login
integration test exercises discovery, live native selector refresh and restart
against a loopback issuer/model server, not a commercial account.

`POST /api/ui` accepts only an opaque navigation cursor and a public presentation
event. Bend produces the entire typed surface in `UI.bend`: content, titles,
actions, fields, bindings and enabled flags. `public/renderer.mjs` fills declared
event bindings; `public/widgets.mjs` renders the generic widgets with keyed DOM
reconciliation and safe Markdown.
`public/app.mjs` handles authentication, serialized requests and commit invalidation.
Neither file interprets task state or provider message roles. Unsubmitted field
drafts and disclosure/focus state are presentation mechanics, not a domain cache.
Uncommitted model deltas do not replace the native conversation surface. A
separately labelled, bounded streaming preview is correlated with host execution
identity and retired after its native settlement revision. Exact settled text
can retain its already-rendered DOM. See `public/README.md` and ADR 0018 for the
display scheduler, worker formatting, draft retention and evidence boundaries.
The existing command endpoint remains available to CLI and API callers. Both
endpoints revalidate against the current native world; a stale enabled button is
never authority to execute. Navigation/refresh has no journal entry or effects.
The exploration record distinguishes adapter test evidence from the native proof
gate; no theorem here proves the browser's DOM implementation.

## Coding effect interpreters

`jev.mjs` interprets a committed reasoning observation with a separate evaluator
connection, bounded public context and strict typed choices. It has no lease or
task scheduler. `reasoning-config.mjs` separates evaluator connections, endpoint
policies and the ordinary account-discovery preset. See
[`docs/adaptive-reasoning.md`](../docs/adaptive-reasoning.md) for configuration,
disclosure and failure behavior.

`sandbox.mjs` converts an already-authorized execution plan into a Seatbelt or
bubblewrap/seccomp launch. It canonicalizes explicit workspace observations and
fails closed on unavailable isolation; it does not select a task's policy or
decide an approval. See ADR 0019 and `sandbox.test.mjs` for the OS trust boundary.

`approvals.mjs` interprets a committed approval effect as a separate, tool-free
provider request. It creates no task and strictly decodes one allow/deny response;
malformed output and provider failures return failed-review inputs to Bend.
Human reviews use the authenticated command/UI boundary. The native operation
identity, reviewer and complete command bind the decision; a grant never mutates
the task's saved workspace or sandbox. The actual model's judgment is an external
assumption, not a theorem about user intent.

`project.mjs` observes explicitly selected directories and their primary root
guidance before task/project commands. Native `WORKSPACE` and `PROJECTS` own
admission, inheritance and project defaults. Every service Bash effect requires
its committed plan; `service.cwd` is not a process permission or task directory.
Keep the service home separate from writable projects: it is read-only inside a
restricted Bash process, even when a workspace includes its ancestor.

`stdio-rpc.mjs` is the shared bounded process transport for MCP and plugins.
`plugins.mjs` implements only the manifest, ticketed callback/tool protocol and
best-effort observer queue. `service.mjs` dispatches committed native `CheckTool`,
`CheckResult` and `NotifyPlugins` effects; it neither classifies domain events nor bypasses the
native chain for internal tools. Policy order is configuration order, not process
startup completion order. Revision loss withdraws live routes without rewriting
task contracts. See `../docs/plugins.md` for schemas, recovery and delivery limits.

`process.mjs` is the single local coding-effect interpreter. Reading, writing,
editing and running a reusable script are ordinary Bash commands, not redundant
tool implementations. `project.mjs` observes bounded primary-root guidance at
configuration and explicit workspace selection; it is not a model-callable file
tool. File locking, atomic editing
and revision checks required by a project belong in its commands or reusable
scripts. Process isolation does not provide cross-process filesystem transactions.

`process.mjs` drains both pipes with bounded previews and bounded artifact files
under the service home's `artifacts` directory. Output beyond the artifact cap is
discarded but counted and reported. Previews retain Unicode head and tail, and
artifact prefixes do not split UTF-8 retention boundaries. Raw byte counts and
omitted-character counts are separate. Arbitrary binary output can still require
a binary-aware Bash reader.
Artifacts have private permissions; they are not automatically garbage-collected
because durable history may reference them. File synchronization is reported in
artifact metadata; filesystem loss or external deletion remains possible.

The journal stores canonical task-local workspace observations and verifies the
kernel fingerprint/current format before reconstruction. Existing execution plans
retain their meaning after a restart in another launch directory. No workspace
migration or global directory binding is involved. Different operations and
service homes do not serialize arbitrary filesystem mutations, even when pointed
at the same workspace.

Native operations have stable task/operation identities and one current effect
ticket. An after callback gets a fresh ticket without changing the operation ID.
Cancellation targets that live ticket, not its retired execution ticket. The
host can run several tools for one task and a model request at the same time.
`cancel_ticket` aborts exactly one controller; task-wide cancellation is separate.
Neither the host nor a timer invents model polling turns. Running announcements,
completion notification, queue promotion and summary eligibility are native
policy. Providers enable parallel calls and encode a later `operation_result` as
explicit unprivileged asynchronous-result data, not a duplicate function output.

After-hook transport carries the frozen route, operation/callback identities,
effective call and current result. Only value replacement is allowed; execution
errors cannot be cleared by plugins. The raw execution receipt remains durable
but outside the default provider projection. A result-processing restart failure
does not repeat the execution or callback. Tests cross real process/SQLite/provider
boundaries; the semantic obligations themselves belong to the Bend proof root.

Every external intent must belong to its own earlier committed decision, not
necessarily the latest journal row. Concurrent completions may advance the log
before an already-authorized process starts. Integration fixtures verify causal
authorization by operation identity and retain the no-replay-on-restart check.

`providers.mjs` consumes the instructions and retry policy supplied by the native
model. Only pre-stream connection failures and declared transient HTTP statuses
are retried, within the request's overall deadline. Waiting is cancellable;
excessive `Retry-After` is a failure rather than permission to retry too early.
An already exposed SSE stream is not retried automatically. Transport attempts
share one committed model ticket and do not replay any tool effect.

`model-request.mjs` prepares the common committed input before provider encoding.
`chatgpt-web.mjs` implements the independent Web API v1 protocol and stores
external request receipts in `chatgpt-web-store.mjs`. Opaque native context carries
the explicit page identity and sent-input span, including deferred messages and
async results committed before a model reply. It never chooses a page by matching
message text. Native cancellation retires a specific receipt and attempts remote
Stop; observer timeout or shutdown does not. The generic preview interface
distinguishes replacement snapshots from append-only deltas. See
`../docs/chatgpt-web.md` and ADR 0024 for configuration, recovery and evidence.

Summary requests use the ordinary model transport but receive no tools. ChatGPT
uses streaming remote compaction v2 and returns one unchanged encrypted checkpoint;
API-key profiles retain text summarization. Compaction deltas are not displayed.
The host
does not decide when to compact, which history to retain, or whether a completion
is current. Bend performs those decisions, validates summaries, and commits a
checkpoint before using its context projection. Supplied checkpoints need no
host/model effect. Model retries and text deltas are notices, not extra task
history or a second scheduler.

An explicit `context_length_exceeded` code in HTTP 400 or a pre-output SSE failure
becomes a typed native completion. Diagnostic substrings, incomplete responses
and failures after emitted output do not grant automatic compaction/retry. The
native phase owns whether to summarize, retry with a fresh ticket or stop; the
adapter has no hidden context-recovery counter. Upstream error bodies are not
copied into the durable conversation.

Root project guidance is observed once before configuration and durably recorded
in the environment. Providers consume the frozen task snapshot from the committed
effect, never a fresh filesystem read. It is unprivileged repository data, not an
extra system prompt. `project-context.test.mjs` and `context-recovery.test.mjs`
exercise restart and compaction with this same contract.
