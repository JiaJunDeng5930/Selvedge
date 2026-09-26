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

The suite also exercises device login and serialized credential refresh against a
loopback issuer, interruption and restart of an actual HTTP stream, MCP catalog
notifications during shutdown, and suppression of effects withdrawn within a
commit. Credential parsing errors must not quote file contents into task history.
Use `npm test` to run these checks; they require no real credentials or model calls.

`POST /api/ui` accepts only an opaque navigation cursor and a public presentation
event. Bend produces the entire typed surface in `UI.bend`: content, titles,
actions, fields, bindings and enabled flags. `public/renderer.mjs` renders generic
widgets, escapes text through DOM text nodes, and fills the declared event bindings.
`public/app.mjs` handles authentication, serialized requests and commit invalidation.
Neither file interprets task state or provider message roles. Unsubmitted field
drafts and disclosure/focus state are presentation mechanics, not a domain cache.
Uncommitted model deltas do not replace the native conversation surface.
The existing command endpoint remains available to CLI and API callers. Both
endpoints revalidate against the current native world; a stale enabled button is
never authority to execute. Navigation/refresh has no journal entry or effects.
The exploration record distinguishes adapter test evidence from the native proof
gate; no theorem here proves the browser's DOM implementation.

## Coding effect interpreters

`process.mjs` is the single local coding-effect interpreter. Reading, writing,
editing and running a reusable script are ordinary Bash commands, not redundant
tool implementations. `project.mjs` only observes bounded root guidance before
configuration; it is not a model-callable file tool. File locking, atomic editing
and revision checks required by a project belong in its commands or reusable
scripts. This service is not a cross-process filesystem transaction or sandbox.

`process.mjs` drains both pipes with bounded previews and bounded artifact files
under the service home's `artifacts` directory. Output beyond the artifact cap is
discarded but counted and reported. Previews retain Unicode head and tail, and
artifact prefixes do not split UTF-8 retention boundaries. Raw byte counts and
omitted-character counts are separate. Arbitrary binary output can still require
a binary-aware Bash reader.
Artifacts have private permissions; they are not automatically garbage-collected
because durable history may reference them. File synchronization is reported in
artifact metadata; filesystem loss or external deletion remains possible.

The journal binds the canonical workspace before reconstructing a kernel. This
prevents identical relative paths from acquiring a different meaning after a
restart in another directory. The source fingerprint and workspace are checked,
not migrated. Different operations and service homes do not serialize arbitrary
filesystem mutations, even when pointed at the same workspace.

Native operations are independently keyed by task ID and committed ticket. The
host can run several tools for one task and a model request at the same time.
`cancel_ticket` aborts exactly one controller; task-wide cancellation is separate.
Neither the host nor a timer invents model polling turns. Running announcements,
completion notification, queue promotion and summary eligibility are native
policy. Providers enable parallel calls and encode a later `operation_result` as
explicit unprivileged asynchronous-result data, not a duplicate function output.

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

Summary requests use the ordinary model transport but receive no tools. The host
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
