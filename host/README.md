# Host effects

The compiled Bend kernel owns authoritative task state. `../KERNEL.bend` is compiled
with the pinned compiler's official `js_lib` backend into
`.build/kernel-model.mjs`; `kernel-worker.mjs` executes it in a Bun Worker.
The host accepts authenticated public commands, interprets committed effects,
and sends their results back as inputs. It commits an input and its decision to
SQLite before publishing replies, world snapshots or starting effects. A failed
commit terminates the kernel; committed inputs replay through the same Bend
transition at the next start.

The compiler's JavaScript backend, Worker transport and operating system remain
external boundaries. `transport.c` belongs to the optional `../MAIN.bend` native
build; it receives bounded, length-prefixed UTF-8 tokens for the checked decoder
without owning task state or policy.

Host integration tests exercise persistence, HTTP delivery, model transport, and
process execution. Bend laws do not prove those implementations or their services.

Board text generation is a committed `RequestBoardText` effect interpreted by
`board-text.mjs`; native ticket/revision matching owns settlement. The
authenticated `board-files.mjs` boundary stores content-addressed, bounded files
and rejects forged metadata or symbolic-link storage. Paste, drop and picker
gestures share this route. The host observes timestamps and file facts; admission,
order, automatic dispatch and execution association remain native.

The suite also exercises browser OAuth login and serialized credential refresh against a
loopback issuer, interruption and restart of an actual HTTP stream, MCP catalog
notifications during shutdown, and suppression of effects withdrawn within a
commit. Credential parsing errors must not quote file contents into task history.
Use `bun run test` to run these checks; they require no real credentials or model calls.

`chatgpt-account.mjs` owns ChatGPT connection configuration, identity, login and
credentials. Consumers obtain account-bound authorization without accessing stored
credential records. `chatgpt-contract.mjs` contains the Responses tool namespace
and model-catalog URL helper. See [ADR 0027](../docs/adr/0027-official-chatgpt-sign-in.md)
for the ownership and protocol choices.

`chatgpt-models.mjs` discovers account models and materializes account-bound
profiles. Its catalog refresh commits the ordinary Configure input without
mutating existing task contracts. Cache freshness and account matching belong to
this external transport boundary.

`../BROWSER.bend` compiles to `public/generated/browser-model.mjs` and runs the UI
production functions in the browser. Bend owns interaction state, layout and
Document construction. `public/renderer.mjs` interprets the Document as DOM;
`public/app.mjs` performs authentication, network requests and physical effects.
The browser submits only public commands through `/api/browser/command`.
The server authenticates those commands and resolves them against the current
kernel world; a local enabled control is not authority to execute. Snapshots are
published only after the authoritative commit. Draft settlement uses the real
command completion and draft revision.

Uncommitted model deltas remain correlated transport observations. Bend decides
their presentation and retirement; JavaScript does not interpret provider roles
or maintain a task lifecycle model. DOM behavior, Markdown formatting, focus,
clipboard and network delivery remain external component boundaries. See
[`public/README.md`](public/README.md).

## Coding effect interpreters

`chatgpt-plugin.mjs` validates dedicated loopback connection credentials and
translates only the plugin's tool envelopes. Project grants and operation policy
are native feature decisions; `service.mjs` interprets committed execution and
cancellation effects. See the [plugin setup guide](../plugins/selvedge-chatgpt/README.md)
and [ADR 0024](../docs/adr/0024-project-scoped-chatgpt-plugin.md).

`jev.mjs` interprets a committed reasoning observation with a separate evaluator
connection, bounded public context and strict typed choices. It has no lease or
task scheduler. `reasoning-config.mjs` separates evaluator connections, endpoint
policies and the ordinary account-discovery preset. See
[`docs/adaptive-reasoning.md`](../docs/adaptive-reasoning.md) for configuration,
disclosure and failure behavior.

`sandbox.mjs` converts an already-authorized execution plan into a Seatbelt or
bubblewrap/seccomp launch. It canonicalizes explicit workspace observations and
fails closed on unavailable isolation; it does not select a task's policy or
decide an approval. See `sandbox.test.mjs` for the OS trust boundary.

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
`../docs/chatgpt-web.md` for configuration, recovery and evidence.

Summary requests use the ordinary model transport but receive no tools. ChatGPT
and API-key profiles use bounded text summarization.
The host does not decide when to compact, which history to retain, or whether a completion
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
