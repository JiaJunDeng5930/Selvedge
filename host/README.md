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

The browser consumes command schemas and allowed lifecycle controls returned by
the running model. It does not own a second lifecycle table. The exploration
record distinguishes browser interaction evidence from the native proof gate.

## Coding effect interpreters

`file-tools.mjs` interprets committed file observations and mutations. Reads are
bounded regular-file UTF-8 snapshots with SHA-256 revisions. Mutations resolve
symlink aliases, serialize per canonical path, reject stale revisions and
ambiguous literal edits, preserve existing permission bits, and publish through
a same-directory temporary file. Exclusive creation does not clobber an existing
path. Multiply-linked files are rejected for mutation; BOM and line endings are
not normalized. File and directory synchronization are attempted before success.
Independent processes can still race a check and replacement: this is an explicit
filesystem boundary, not a proved cross-process transaction or access sandbox.

`process.mjs` drains both pipes with bounded previews and bounded artifact files
under the service home's `artifacts` directory. Output beyond the artifact cap is
discarded but counted and reported. UTF-8 prefixes are not split at retention
boundaries. Arbitrary binary output can still require a binary-aware Bash reader.
Artifacts have private permissions; they are not automatically garbage-collected
because durable history may reference them. File synchronization is reported in
artifact metadata; filesystem loss or external deletion remains possible.

The journal binds the canonical workspace before reconstructing a kernel. This
prevents identical relative paths from acquiring a different meaning after a
restart in another directory. The source fingerprint and workspace are checked,
not migrated. Different service homes do not coordinate their file mutation
queues, even when intentionally pointed at the same workspace.

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
