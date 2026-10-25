# IO host

The Bun host accepts authenticated HTTP and CLI requests, records inputs and
complete decisions in SQLite, and interprets committed effects. It does not own
task policy. `kernel-worker.mjs` invokes the extracted Gallina entry through the
JSON text API built in `.build/kernel-model.mjs`; the extracted world stays
private to that worker.

`kernel.mjs` serializes requests and retires the worker after a failed or timed
out transition. `journal.mjs` commits an accepted durable decision before
publishing it or starting an effect. On reopen it verifies the hash chain and
replays inputs through the current extracted kernel without executing effects.
Only `selvedge-rocq-journal-7` is accepted. Other formats are rejected, without a
conversion path.

`server.mjs` and `cli.mjs` expose the service. Browser snapshots use domain JSON
at `/api/browser/state`; commands use `/api/browser/command`, and observations
arrive through `/api/events`. Domain JSON is independent of Gallina, OCaml and
JavaScript runtime object layouts. Pure adapter decisions are called through
`public/model-boundary.mjs` and come from the same extracted definitions as
their Rocq proofs.

`POST /api/assess` accepts `command`, opaque `editor`, `revision` and the observed
`sequence`. It returns the editor/revision, the worker's actual sequence,
`admitted` and an optional `refusal` with `code`/`message`. The worker evaluates
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

Use the repository build before starting `bun host/cli.mjs server`. The default
service home is `~/.selvedge`; `--home` and `SELVEDGE_HOME` select another home.
See the root README for setup and the public command description.
