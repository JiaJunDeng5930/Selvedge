# Selvedge

Selvedge runs persistent agent tasks through an executable Bend 2 model. It has a
local web interface and CLI, model profiles, task branching and messaging, file
read/write/edit tools, Bash and stdio MCP tools, context checkpoints, and a SQLite
input journal for restart recovery. The default profile is an offline echo
demonstration, not a coding model or summarizer.

## Read the program

Start with `Harness` in [CONCEPTS.bend](CONCEPTS.bend): a proof-carrying program
object organized by meaning, composition, recovery and observation. It contains
no implementation functions. `bendlib/architecture.bend` binds these concepts to
the exact production operations, with proof-carrying simulation, journal actions,
recovery homomorphisms and projections rather than a separate architecture model.

[COMMANDS.bend](COMMANDS.bend) states what every command means. Its resolver owns
the preconditions and produces an operation whose meaning fixes the complete
post-state, reply, and effects. [MODEL.bend](MODEL.bend) defines the domain values,
policy and client vocabulary. These three files are the conceptual entry.

For implementation/proof details, [PROGRAM.bend](PROGRAM.bend) realizes the
operations and runs bounded scheduling. [LAWS.bend](LAWS.bend) states the exact
command, scheduling, commit and dispatch equations, as well as safety and trace
properties. [PROOF.bend](PROOF.bend) assembles the local proofs in
`bendlib/proofs`; their explicit dependency graph follows the semantic boundaries.
[INVARIANTS.bend](INVARIANTS.bend)
defines the reflected validity/admission predicates. The full command refinement
includes `bendlib/commit.bend`'s rollback, output-bound, and refusal semantics;
it is not merely a pre-scheduling postcondition. `bendlib/protocol.bend` completes
the interaction vocabulary with asynchronous results, configuration, restart,
scheduler ticks and accepted internal tool calls. The input-wide refinement fixes
their post-state, reply and effects, including refusal versus tool-error settlement.
`bendlib/execution.bend` independently specifies work resolution, effect dispatch
and finite scheduling. Neither it nor the command/protocol/commit specification
imports PROGRAM; the complete refinement closes over this independent scheduler.
The independent native-interface and transcript specifications extend this chain
to malformed packets and finite input sequences. Trace simulation retains complete
decision receipts, not only the final world. Existing Stdlib iterator theorems
provide finite-run simulation, partition and invariant lifting; the project proves
the one-step and tape/journal correspondences. MAIN contains only the IO boundary.
The shared proof gate rejects unsafe/foreign evidence even when a compiled kernel
is cached; MAIN's separately reported foreign input and service loop are not proofs.

The existing standard-library proof terms and their checked translation live in
[theory/README.md](theory/README.md). Normal builds need neither Rocq nor MetaRocq.
Command descriptions, validation schemas, lifecycle controls, and client forms
derive from the executable definitions. [host/README.md](host/README.md) describes
the operating-system boundary; [bendlib/README.md](bendlib/README.md) locates support.
[The exploration record](docs/bend2-exploration.md) explains the findings and their
limits. Architectural reasons live in [docs/adr](docs/adr).

[UI.bend](UI.bend) is the platform-independent interaction entry. It defines a
typed presentation tree, form bindings, navigation events, conversation visibility
and action availability against the live command resolver. The Web client renders
that tree through `/api/ui`; it has no task snapshot, lifecycle table or provider
message interpreter. Its only retained state is an opaque navigation cursor and
unsubmitted widget drafts. Presentation is generated after scheduling and admitted
with the same atomic decision. SwiftUI, Windows UI and TUI adapters are not required
to reinterpret the domain and are not implemented in this checkout.

## Run

Install Node.js 26 or later and a C compiler on macOS or Linux, then run:

```bash
bash scripts/bootstrap.sh
npm start
```

Bootstrap uses the Bend version in `bend-version`. When necessary, it downloads
the corresponding release into this checkout's `.build/bend` and verifies the
archive against `bend-checksums.txt`. It changes neither the system compiler nor
another worktree. There are no npm runtime dependencies.

The server prints a local URL with its access token. Open it to create a task,
send messages, control its lifecycle, or use the schema-derived Commands dialog.
The default `demo` profile runs without credentials or an external model request.
`Ctrl-C` closes the service and its owned processes.

With the server running, the same operations are available through the CLI:

```bash
node host/cli.mjs describe
node host/cli.mjs create --profile demo --message "Hello"
node host/cli.mjs read --task-id 0
node host/cli.mjs watch
```

Use `describe` for the current command fields instead of maintaining a second
command specification. `node host/cli.mjs help` lists host-level commands.

## Use it on a project

Start the server from the project's directory; that directory is the workspace
for relative file and Bash paths. For example, after building this checkout:

```bash
cd /absolute/path/to/project
node /absolute/path/to/Selvedge/host/cli.mjs --home /absolute/path/to/task-home server
```

The journal pins the workspace's canonical path. Restart from the same workspace;
a different directory is rejected before replay or tool dispatch. Tasks within a
service share that workspace; a task fork is not a separate Git worktree or an OS
sandbox. Bash runs with the service user's permissions, and absolute
paths are allowed. Use only trusted local users and tools.

Use `bash` for reading, writing, editing, searching, scripts and tests; there is no
second set of file tools. Independent calls from one reply run concurrently. Put
dependent commands in one shell invocation. Each operation owns a committed
ticket, separate from the task's model/control phase. Partial results or new input
can resume the model while siblings continue. Quiet operations do not poll the
model. `read` exposes their operation IDs; `phase: idle` alone does not mean all
external work has completed—also check that `operations` is empty.

`max_output_length` bounds retained Unicode characters per stream (default 40,000,
maximum 65,536), excluding the omission marker. Previews keep the head and tail;
metadata reports raw byte counts and omitted character counts. Truncated streams
carry private artifact paths, SHA-256 revisions and explicit retention limits.
An artifact capped at 8 MiB is a retained prefix, not the complete output. Inspect
it through Bash. Nonzero exits, deadlines and cancellation are tool errors, and
shell descendants are terminated when the shell exits.
The executable catalog and `limits` in `describe` are authoritative.

At startup the service captures the root `AGENTS.md` as a bounded UTF-8 snapshot
with a content revision and canonical workspace. A new task freezes that snapshot
in its contract; forks, checkpoints and restarts retain it. Later file changes
are visible through Bash, but do not silently rewrite an existing task's
instructions. Restarting captures new guidance for subsequently created tasks.
Nested module guidance is read on demand. Repository text remains task context,
not privileged system authority.

`stop` lets already accepted tools settle. `interrupt` cancels current work,
closes outstanding calls with explicit cancellation/unknown-outcome results,
and retains queued input. A later `send` resumes the task. `archive` remains
permanent. These controls also appear in the browser from the native model.

`send` retains queued follow-ups. `steer` replaces the current model request and
undispatched accepted calls with immediate input, preserving independent running
operations and queued follow-ups. `cancel_operation` cancels one operation rather
than the whole task; the model can also call this tool. Neither operation undoes
side effects. Late or duplicate results cannot reacquire a consumed ticket.

```bash
node host/cli.mjs steer --task-id 0 --message 'Prioritize this instruction.'
node host/cli.mjs cancel_operation --task-id 0 --operation-id 12
```

An operation is reported as `running` only when another model request needs its
status. Fast completions remain ordinary function outputs. Later completion of
an announced operation is a separate `operation_result`, never a second final
function output. Forks inherit context, not operation ownership; restart records
unknown outcomes instead of repeating external commands.

Long contexts are summarized automatically with no in-flight operations. Oversized
partial context waits for the remaining results, so a summary cannot erase an
event received after its snapshot. The model
receives a checkpoint and its subsequent history; `read`/`read_task` still expose
the complete original record. On an active idle task, `compact` requests a summary
without starting another assistant turn. A supplied summary requires no provider
and also works on stopped or frozen idle tasks:

```bash
node host/cli.mjs compact --task-id 0
node host/cli.mjs interrupt --task-id 0
node host/cli.mjs compact --task-id 0 --summary 'Completed work, verified results, unresolved problems, and next steps.'
node host/cli.mjs send --task-id 0 --message 'Continue from the checkpoint.'
```

Summaries are fallible continuation data, not verified equivalents of the original
conversation. Automatic thresholds count serialized UTF-8 bytes, not provider
tokens. An explicit provider context-limit error before output enters the native
compact-and-retry path even below that byte threshold. A checkpoint with no new
work is not compacted again; persistent overflow stops with an actionable error.
Empty, oversized, tool-bearing, stale, or cancelled model summaries are not
installed. When the provider cannot read the old context at all, use the supplied
summary path after settling or interrupting current work. Failed summaries retain
the original history and do not strand independently queued user input. Without
new input they stop rather than starting an unbounded retry loop.

## Model and tool configuration

The default home is `~/.selvedge-bend`. `node host/cli.mjs init` creates its
`config.json` without overwriting an existing file. `--home PATH` and `--config
FILE` select explicit locations; both options also work with `npm start -- ...`.
Configuration is read at server startup.

For a ChatGPT profile, replace `MODEL_ID` with an available model identifier:

```json
{
  "format": "selvedge-bend-config-1",
  "profiles": {
    "agent": { "provider": "chatgpt", "model": "MODEL_ID" }
  },
  "mcp": {}
}
```

Run `node host/cli.mjs login agent` to perform the explicit device-code login.
A Responses API profile uses `provider: "responses"`, `model`, and optionally
`endpoint` and `api_key_env` (default `OPENAI_API_KEY`). A stdio MCP entry under
`mcp` uses its server name as the key and `command`, `args`, optional `cwd`, and
optional string-valued `env` as its process settings. Unknown fields are rejected;
[host/config.mjs](host/config.mjs) is the configuration parser.

Each task retains its selected model identity and complete tool definitions.
Later MCP catalog notifications change availability without rewriting that
contract. Forked tasks inherit the contract and message prefix, with explicit
branch results and fresh task identities.

## Persistence and guarantees

The journal records admitted inputs and decisions before any external effect is
started. Reopening verifies the hash chain and replays the same executable kernel;
historical effects are not dispatched. Interrupted external mutations remain
unknown and are not automatically repeated. File observations can be repeated,
possibly observing a newer revision. Interrupted ordinary model requests and
automatic summaries can be requested again by recovery. An interrupted manually
requested summary leaves the original history intact and can be requested again
explicitly.

Transient model connection/HTTP failures use bounded, abortable backoff from the
native boundary policy. Permanent failures and excessive `Retry-After` delays
are not retried. A partially exposed response stream is never silently replayed;
retry notices are visible in the event stream and browser.

There is one current journal format, tied to the complete Bend source fingerprint,
compiler version, and canonical workspace. Another kernel, a different workspace,
or an obsolete Rust database is rejected.
Use a separate home when changing the kernel; this branch provides no migration
or backward-compatible reader. The earlier Rust implementation is retained in
Git history, not as a second runtime in the checkout.

The checked transition either retains the world with no effects, or satisfies the
world and transition predicates. Starting from a valid world, every finite trace
preserves its world invariant. This is a safety result: it does not prove that a
model terminates, that every valid request fits the resource bounds, that the
scheduler is fair, or that an operating system or remote service obeys the model.
File mutations are serialized within this host, revision-checked, and published
with atomic replacement or exclusive creation. They are not a global
compare-and-swap against independent editors, Bash processes, or other services.
The Bend checker/compiler, native transport, Node, SQLite, OS, and remote protocols
remain explicit trust boundaries. Local integration tests exercise those paths;
live provider acceptance and physical history sharing are not claimed.

## Develop and verify

```bash
npm run check
npm test
npm run index:check
npm run bench
```

`check` verifies the pinned compiler, every proof obligation, and host/script
syntax. Tests run the native kernel, real loopback HTTP/SSE services, SQLite,
Bash, file revision conflicts and concurrent edits, an actual coding/test loop,
compaction and interruption, stdio MCP, credential-flow fixtures, and negative
proof mutations. The
benchmark measures committed transitions and replay on reproducible task trees;
it imposes no machine-dependent CI threshold. CI is configured to run checks and
tests on macOS and Linux. `just` provides aliases for these commands.

After adding or deleting files, stage the changed paths, run `npm run index`, and
stage `AGENTS.md`. The index contains only Git-tracked files. When `pre-commit` is
installed, bootstrap installs the configured commit and push hooks. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the change workflow.
