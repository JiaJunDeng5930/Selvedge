# Host effects

The compiled Bend kernel owns authoritative task state. `../KERNEL.bend` is compiled
with the pinned compiler's official `js_lib` backend into
`.build/kernel-model.mjs`; `kernel-worker.mjs` executes it in a Bun Worker.
The host accepts authenticated public commands, interprets committed effects,
and sends their results back as inputs. It commits an input and its decision to
SQLite before publishing replies, world snapshots or starting effects. A failed
commit terminates the kernel; committed inputs replay through the same Bend
transition at the next start.

Pure host semantics belong to [adapters](adapters/README.md), whose domain
modules construct results from the complete JSON source and consume the resulting
category membership. [MODEL.bend](adapters/MODEL.bend) supplies the shared
construction interface; [PROGRAM.bend](adapters/PROGRAM.bend) dispatches the
actual domain operations, and [PROOF.bend](adapters/PROOF.bend) assembles their
evidence. The root [MODEL.bend](../MODEL.bend) exposes these operations through
`System.host_adapters`; [HOST.bend](../HOST.bend) is the token-to-JSON entry.
[public/model-boundary.mjs](public/model-boundary.mjs) connects host and browser
callers to `public/generated/host-model.mjs`. It unwraps the outer result envelope;
an error-valued accepted payload is distinct from a rejected adapter call.

URL and JSON parsing, clock and arithmetic observations, byte handling, hashing,
OS behavior and network delivery remain explicit external boundaries. Native
calculations consume their observations; correspondence to those calculations
does not prove the observation implementations. Connection secrets stay outside
Bend. [opaque-credentials.mjs](opaque-credentials.mjs) interprets the native
credential plan for both the host and the standalone plugin.

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

[chatgpt-account.mjs](chatgpt-account.mjs) performs ChatGPT discovery, login,
credential storage and authorization effects. [ACCOUNTS.bend](adapters/ACCOUNTS.bend)
owns admission and identity-binding calculations over their observations.
Consumers obtain account-bound authorization without accessing stored credential
records. `chatgpt-contract.mjs` contains the Responses tool namespace
and model-catalog URL helper. See [ADR 0027](../docs/adr/0027-official-chatgpt-sign-in.md)
for the ownership and protocol choices.

`chatgpt-models.mjs` discovers account models and materializes account-bound
profiles. Its catalog refresh commits the ordinary Configure input without
mutating existing task contracts. [ACCOUNTS.bend](adapters/ACCOUNTS.bend) owns
catalog admission, cache freshness and account matching; clock and network
observations come from the host.

The browser build exports `../BROWSER.bend` production functions to
`public/generated/browser-model.mjs`. Its mandatory proof gate first checks the
full `.build/ui-verification.bend` entry, including root `../PROOF.bend`, before
compilation or cache reuse. The compiled `.build/ui-runtime.bend` entry keeps the
existing ordered imports and private providers with root `../PROOF.bend`
excluded, and explicitly includes `../harness/approval/PROOF.bend` for approval
contracts that remain in the runtime closure. Root production instances remain
available through the ordinary typed
`PROOF.system()` and `PROOF.harness()` constructors; their complete model evidence
is retained by the verification entry. Bend owns interaction state, layout and
Document construction. `public/renderer.mjs` interprets the Document as DOM;
Opening the local server URL establishes an HttpOnly browser session;
`public/app.mjs` connects automatically and performs network requests and physical
effects. Reopen that URL after a server restart to refresh the session. The CLI
discovers its separate Bearer credential from the service home; ChatGPT plugin
connections retain their own credentials.
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

[chatgpt-plugin.mjs](chatgpt-plugin.mjs) observes dedicated loopback connections
and interprets credential plans through the opaque-secret boundary.
[PLUGINS.bend](adapters/PLUGINS.bend) owns nonsecret configuration, catalog, route
and tool-envelope calculations. Project grants and operation policy
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
provider request. It creates no task. [EFFECTS.bend](adapters/EFFECTS.bend) admits the observed
approval response and constructs its completion; malformed output and provider
failures return failed-review inputs to Bend.
Account discovery retains the advertised `codex-auto-review` model for approval
selection, including when its catalog visibility is hidden. It uses the same
connection and account binding as that account's task models, with low reasoning
when advertised. This selects the official reviewer model while retaining
Selvedge's review prompt and decision format; it does not run a Codex reviewer
agent or change execution permissions.
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

`worktrees.mjs` interprets committed Git worktree effects and observes their
filesystem receipts on restart. The owning [feature](../features/worktree/README.md)
and harness assembly govern task initialization and resource association.
Creation rejects a service home inside the source Git repository before copying
files, preventing private service state from entering a checkout.
Sandbox launches admit a writable exception only for the task's committed managed
checkout; service state and other checkouts retain their protection.

[stdio-rpc.mjs](stdio-rpc.mjs) is the shared bounded process transport for MCP and
plugins. [RPC.bend](adapters/RPC.bend) owns response classification and correlation
calculations over the transport observations.
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

The journal stores canonical task-local workspace observations. Reopening checks
the stored format and integrity, then validates complete committed decisions by
replaying them through the current kernel without executing their effects.
Format 3 is independent of build provenance. Persisted formats are not migrated;
unknown formats and incompatible decisions fail without altering the journal. Existing execution plans retain
their meaning after a restart in another launch directory. No workspace migration
or global directory binding is involved. Different operations and service homes
do not serialize arbitrary filesystem mutations, even when pointed at the same
workspace.

Native operations have stable task/operation identities and one current effect
ticket. An after callback gets a fresh ticket without changing the operation ID.
Cancellation targets that live ticket, not its retired execution ticket. The
host can run several tools for one task and a model request at the same time.
`cancel_ticket` aborts exactly one controller; task-wide cancellation is separate.
Neither the host nor a timer invents model polling turns. Running announcements,
completion notification, queue promotion and compaction eligibility are native
policy. Providers enable parallel calls and encode a later `operation_result` as
explicit unprivileged asynchronous-result data, not a duplicate function output.

After-hook transport carries the frozen route, operation/callback identities,
effective call and current result. Only value replacement is allowed; execution
errors cannot be cleared by plugins. The raw execution receipt remains durable and is encoded as tagged history data
in model requests. A result-processing restart failure
does not repeat the execution or callback. Tests cross real process/SQLite/provider
boundaries; the semantic obligations themselves belong to the Bend proof root.

Every external intent must belong to its own earlier committed decision, not
necessarily the latest journal row. Concurrent completions may advance the log
before an already-authorized process starts. Integration fixtures verify causal
authorization by operation identity and retain the no-replay-on-restart check.

`providers.mjs` consumes the recorded history and retry policy supplied by the
native model. Only pre-stream connection failures and declared transient HTTP statuses
are retried, within the request's overall deadline. Waiting is cancellable;
excessive `Retry-After` is a failure rather than permission to retry too early.
An already exposed SSE stream is not retried automatically. Transport attempts
share one committed model ticket and do not replay any tool effect.

[model-request.mjs](model-request.mjs) supplies the committed input to
[BACKENDS.bend](adapters/BACKENDS.bend), which owns request preparation, provider
encoding and output interpretation.
`chatgpt-web.mjs` implements the independent Web API v1 protocol and stores
external request receipts in `chatgpt-web-store.mjs`.
[WEB.bend](adapters/WEB.bend) owns request, receipt, resource and stream admission
and the pure store transitions. Opaque native context carries
the explicit page identity and sent-input span, including deferred messages and
async results committed before a model reply. It never chooses a page by matching
message text. Native cancellation retires a specific receipt and attempts remote
Stop; observer timeout or shutdown does not. The generic preview interface
distinguishes replacement snapshots from append-only deltas. See
`../docs/chatgpt-web.md` for configuration, recovery and evidence.

Compaction preserves the immutable original history and records a complete
replacement window. Context selection appends only messages committed after the
captured prefix. Native account compaction uses `/responses/compact`; portable
rebuilding processes readable original records through bounded summary calls.
The feature in Bend owns thresholds, idle observations, call correlation and
adoption. The host meters the actual request, performs each committed call, and
reports its result. Background jobs run independently of normal inference; a
blocking threshold waits for compaction and remeasures the replacement with the
current suffix before dispatch. Supplied portable summaries enter the same
replacement path without a model call.

An explicit `context_length_exceeded` code in HTTP 400 or a pre-output SSE failure
becomes a typed native completion. Diagnostic substrings, incomplete responses
and failures after emitted output do not grant automatic compaction/retry. The
committed transition owns any subsequent preparation or failure; the adapter
has no hidden context-recovery counter. Upstream error bodies are not
copied into the durable conversation.

Set `instructions` in the service home's `config.json` to customize the initial
assistant instruction. Omitting the key uses the kernel default; an empty string
is accepted. Values must be valid UTF-8 without NUL bytes and fit the instruction
byte limit. Place global guidance in `<service home>/AGENTS.md`; the service reads
it as a bounded regular UTF-8 file, rejects symbolic links, and records its content
hash. A missing file supplies no global guidance.

Root tasks record initial configured, global and project guidance in their
history. Before model dispatch or manually requested compaction, a committed
context observation effect reads the current instruction sources. Its completion is accepted by the
kernel before the final request is emitted. Only changes are appended, as patches
against the last accepted revision of that source. Requests use the resulting
committed history, including the original baseline and patches. An observation
failure preserves the previous value and records its diagnostic; a confirmed
missing source withdraws its content. Execution settings remain the task's frozen
contract.

The `instructions` and `skills` fields in `config.json` are observed again for
these updates; other running service configuration is not reloaded. `skills` is
an array of `SKILL.md` file paths, resolved relative to the service home. Skill
frontmatter supplies `name` and `description`; only that metadata and the path
enter history. The remaining body is not injected. Skill files use the same
bounded, regular UTF-8 file observation as guidance files.

A fork inherits its parent's baseline and patches. An explicit workspace
selection records the selected guidance after the inherited history; later
observations follow the selected primary root. Provider input also carries
recorded settings, reasoning changes, receipts and audit records.
