# IO host

The Bun host accepts authenticated HTTP and CLI requests, records inputs in
SQLite, and interprets committed effects. It does not own
task policy. `kernel-worker.mjs` invokes the extracted Gallina entry through the
JSON text API built in `.build/kernel-model.mjs`; the extracted world stays
private to that worker.

`journal.mjs` serializes requests through their complete transaction and owns
its private `kernel.mjs` connection, which retires the worker after a failed or
timed out transition. The journal commits the changed records before publishing
its decision or starting an effect. Task metadata is stored separately from
append-only history chunks. Each shared state section has its own record, so
allocating a ticket does not re-encode feature data or the tool catalog. The
sequence, task cursor, and new chunks commit together. On reopen it checks
the chunk offsets and restores the committed
records into the Worker. During managed updates, the candidate validates a
read-only view, then loads the final records after acquiring the writer lock.

`server.mjs` and `cli.mjs` expose the service. Browser snapshots use domain JSON
at `/api/browser/state`; commands use `/api/browser/command`, and observations
arrive through `/api/events`. A connected browser sends
`x-selvedge-browser-sequence` with its installed commit. A retained range is
returned as `after` and consecutive `updates` through `sequence`. Each update
carries changed task facts, newly appended messages, any changed cross-task
reference fields, and applicable shared fields. The service publishes them
after SQLite commits. The browser requests an outline on opening or recovering
a gap. The outline includes Task facts without conversation messages. A
browser fetches a history and its frozen tool metadata from
`/api/browser/state?history=<task-id>&after=<offset>` when that conversation
becomes visible. Incremental state reads carry new messages
for visible conversations. A command receipt can also carry the new history
of the tasks affected by that command.
Domain JSON is independent of Gallina, OCaml and JavaScript runtime object
layouts. Pure adapter decisions are called through
`public/model-boundary.mjs` and come from the same extracted definitions as
their Rocq proofs.

`POST /api/assess` accepts `command`, opaque `editor`, `revision` and the observed
`sequence`. It returns the editor/revision, the worker's actual sequence,
`admitted`, an optional `refusal` with `code`/`message`, and a nullable
`card_save_consequence` for admitted card changes. The consequence describes the
current scheduler's response to the hypothetical save. The worker evaluates
the same pure command interpreter used by submission against its current world,
then discards the hypothetical decision. Assessment is serialized after pending
journal work; it does not write state, replace the world or dispatch
effects. Clients discard responses for an older draft or world observation and
still submit through the ordinary command boundary. Filesystem preparation and
external execution are not predicted by this read-only operation.

The remaining modules observe and change the filesystem, processes, network,
credentials, model connections, audio devices and managed worktrees. Those
observations, SQLite durability, worker delivery, remote servers and the OS are
external assumptions. The host does not turn successful input validation or a
committed effect into a claim that an external operation completed correctly.

`bun run update` stages an independent runtime from the repository build and
coordinates a managed handoff. For a standalone foreground service, build the
repository before starting `bun host/cli.mjs server`. The default service home is
`~/.selvedge`; `--home` and `SELVEDGE_HOME` select another home. See the root README
for setup and the public command description.
