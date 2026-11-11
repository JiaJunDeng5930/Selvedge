# IO host

The Bun host accepts authenticated HTTP and CLI requests, records inputs in
SQLite, and interprets committed effects. It does not own
task policy. `kernel-worker.mjs` invokes the extracted Gallina entry through the
JSON text API built in `.build/kernel-model.mjs`; the extracted world stays
private to that worker.

`journal.mjs` serializes requests through their complete transaction and owns
its private `kernel.mjs` connection, which retires the worker after a failed or
timed out transition. The journal commits an admitted input before publishing
its decision or starting an effect. On reopen it replays inputs through the current
extracted kernel without executing effects.
`journal.mjs` migrates known SQLite storage versions while holding the single
writer lock. It validates the separate input replay format and replays the
candidate records before committing the migration.

`server.mjs` and `cli.mjs` expose the service. Browser snapshots use domain JSON
at `/api/browser/state`; commands use `/api/browser/command`, and observations
arrive through `/api/events`. Domain JSON is independent of Gallina, OCaml and
JavaScript runtime object layouts. Pure adapter decisions are called through
`public/model-boundary.mjs` and come from the same extracted definitions as
their Rocq proofs.

`POST /api/assess` accepts `command`, opaque `editor`, `revision` and the observed
`sequence`. It returns the editor/revision, the worker's actual sequence,
`admitted`, an optional `refusal` with `code`/`message`, and a nullable
`card_save_consequence` for admitted card changes. The consequence describes the
current scheduler's response to the hypothetical save. The worker evaluates
the same pure command interpreter used by submission against its current world,
then discards the hypothetical decision. Assessment is serialized after pending
journal work; it does not append a journal row, replace the world or dispatch
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
