# Selvedge

Selvedge runs persistent agent tasks through an executable Bend 2 model. It has a
local web interface and CLI, model profiles, task branching and messaging,
Bash-based coding tools, stdio MCP and plugin tools, context checkpoints, and a SQLite
input journal for restart recovery. Its [task board](docs/task-board.md) adds
planned work, execution roles, drag ordering, files and assisted capture without
creating a second task scheduler. The default profile is an offline echo
demonstration, not a coding model or summarizer.

## Read the program

Start with `Harness` in [CONCEPTS.bend](CONCEPTS.bend): a proof-carrying program
object organized by meaning, composition, recovery and observation. It contains
no implementation functions. `bendlib/architecture.bend` binds these concepts to
the exact production operations and existing list, finite-map, iteration and
relation theories. The entry carries the domain correspondence and required
premises, not a parallel hierarchy of project-owned general algebra.

[COMMANDS.bend](COMMANDS.bend) states what every command means. Its resolver owns
the preconditions and produces an operation whose meaning fixes the complete
post-state, reply, and effects. [MODEL.bend](MODEL.bend) assembles the client
vocabulary and system state. Task-domain values and policy primitives live in
`bendlib/domain.bend`; [FEATURES.bend](FEATURES.bend) assembles independent feature
state and input types. These entries distinguish component contracts from their
application-wide composition.

For implementation/proof details, [PROGRAM.bend](PROGRAM.bend) realizes the
operations and runs bounded scheduling. [LAWS.bend](LAWS.bend) states the exact
command, scheduling, commit and dispatch equations, as well as safety and trace
properties. [PROOF.bend](PROOF.bend) assembles the local proofs in
`bendlib/proofs`; their explicit dependency graph follows the semantic boundaries.
See [INVARIANTS.bend](INVARIANTS.bend) for the validity predicates.

## Component changes and proof reuse

Feature commands, queries, completions and effects cross stable outer categories.
`bendlib/feature-*.bend` owns their resolution, interpretation, codecs, resource
checks and proof composition. Adding a feature extends that assembly and the
feature's own contracts. A shared-resource or scheduling change still requires
its actual interaction proof.

Follow [UI.bend](UI.bend) and [core/interface.bend](core/interface.bend) for
the semantic interface, and [bendlib/feature-codec.bend](bendlib/feature-codec.bend)
for feature command encoding.

`bun run check:components` checks actual source dependencies and private feature
patterns against `components.json`; it runs during normal checks and builds,
including cached builds. `bun run test:locality` freezes existing source files in
temporary copies, extends state and component vocabularies, replaces a component
without changing its contract or clients, and builds the unchanged native entry.
It challenges the source and semantic checks separately.
These checks constrain source changes, not human reading time or whole-build time.

The existing standard-library proof terms and their checked translation live in
[theory/README.md](theory/README.md). Normal builds need neither Rocq nor MetaRocq.

## Workspaces and projects

Each task freezes its own workspace: zero or more canonical directory roots and,
when roots exist, one primary root used as the Bash working directory. Sandbox
settings and approval policy are separate contract fields. A restricted Bash
process can write workspace roots under `workspace-write`, or no roots under
`read-only`; other paths are read-only. It also gets a private temporary directory.
The service home is protected, so keep it separate from project code directories.
macOS uses Seatbelt; Linux requires bubblewrap and seccomp support. Unavailable
isolation fails closed, rather than falling back to an ordinary host shell.

`create_project`, `update_project`, `read_project`, `list_projects` and
`delete_project` are native commands. Task creation/fork accepts a `settings`
object with `project_id`, `workspace`, `sandbox` and `approval`.

Approval policy has three modes. **Full Access** runs Bash without isolation.
**Ask for Approval** keeps ordinary commands sandboxed and shows an exact-command
permission request in the conversation when the agent requests an exception.
**Approval for Me** sends that request to a separate, tool-free model invocation;
it does not create a task. Set `reviewer_profile` to a configured model profile,
or omit it to use the task's profile. The offline echo profile cannot approve.

An agent requests an exception with `sandbox_permissions: "require_escalated"`
and a concrete `justification` before executing the command. The Web UI shows
the complete command, reason, working directory and requested scope, with
**Approve once** and **Deny** buttons for human review. Approval permits only that
invocation outside filesystem and network isolation; it never changes the task's
saved settings.
Cancellation, malformed model replies and interrupted reviews grant no access.
A failed sandbox command is not retried automatically with broader permissions.

The New task and Fork forms accept a `settings` JSON object. `{}` uses the normal
defaults or parent context. For example, `{"project_id": 0}` selects project 0's
workspace for a new task; `{"workspace": {"roots": []}}` explicitly selects no
workspace roots. The same fields are available through the CLI and command API.

The actual command and context guarantees are bound by
`bendlib/workspace-architecture.bend` in `CONCEPTS.Harness.working_context`.
Journal format 2 records these task-local plans, not a global working directory;
opening an older kernel/format is rejected without automatic migration.
Command descriptions, validation schemas, lifecycle controls, and client forms
derive from the executable definitions. [host/README.md](host/README.md) describes
the operating-system boundary; [bendlib/README.md](bendlib/README.md) locates support.
[The exploration record](docs/bend2-exploration.md) explains the findings and their
limits. Decision reasons that are program requirements belong in Bend entities,
executable specifications or public rules bound to actual production computations.
Do not maintain another account in documentation of requirements already expressed
there.

[UI.bend](UI.bend) is the platform-independent interaction entry. Its typed
presentation, form bindings, navigation and action availability are evaluated
against the command resolver. [BROWSER.bend](BROWSER.bend) compiles these production
functions into JavaScript that runs directly in the browser. Bend owns local UI
state, layout and document construction; JavaScript interprets DOM, network and
physical capabilities. Authenticated public commands reach the authoritative
kernel, and the browser observes world snapshots only after journal commit.
Drafts settle against the actual command completion and their revision.

See [the browser adapter](host/public/README.md).

See [docs/plugins.md](docs/plugins.md) for configuration, the protocol,
example and explicit delivery/trust boundaries.

## Run

Optional adaptive effort selection, its independent Jev credentials and the
login-generated Astra Auto profile are described in
[adaptive reasoning](docs/adaptive-reasoning.md).

Install Bun 1.4.2 or later on macOS or Linux, then run:

```bash
bash scripts/bootstrap.sh
bun run start
```

The default build checks proofs and compiles two libraries with Bend 2.0.27's
official `js_lib` backend: `KERNEL.bend` to `.build/kernel-model.mjs`, executed
in a Bun Worker, and `BROWSER.bend` to
`host/public/generated/browser-model.mjs`, executed by the browser.
`bun run build:native` optionally builds `MAIN.bend` and requires a C compiler.

Bootstrap uses the Bend version in `bend-version`. When necessary, it downloads
the corresponding release into this checkout's `.build/bend` and verifies the
archive against `bend-checksums.txt`. It changes neither the system compiler nor
another worktree. Bootstrap installs the locked Bun dependencies; `gpt-tokenizer`
provides the local token-budget estimate used by the optional reasoning evaluator.

The server prints a local URL with its access token. Open it to create a task,
send or steer messages, and open Details for task controls, branches, context
checkpoints and the frozen tool contract. The task sidebar, conversation and
composer adapt to desktop and narrow screens, with light/dark themes. Streaming
Markdown preserves stable blocks and unsent drafts.
The default `demo` profile runs without credentials or an external model request.
`Ctrl-C` closes the service and its owned processes.

With the server running, the same operations are available through the CLI:

```bash
bun host/cli.mjs describe
bun host/cli.mjs create --profile demo --message "Hello"
bun host/cli.mjs read --task-id 0
bun host/cli.mjs watch
```

Use `describe` for the current command fields instead of maintaining a second
command specification. `bun host/cli.mjs help` lists host-level commands.

## Use it on a project

The service launch directory supplies the default workspace for a new task that
does not select a project or explicit roots. It is not a shared task directory
or a permission boundary. For example, after building this checkout:

```bash
cd /absolute/path/to/project
bun /absolute/path/to/Selvedge/host/cli.mjs --home /absolute/path/to/task-home server
```

The journal records each task's canonical roots and execution settings. Restarting
from a different directory cannot reinterpret existing tasks' relative paths;
only new unprojected tasks use the new launch default. Tasks can select different
workspaces in the same service. A task fork does not create a Git worktree or copy
files. Bash uses its task's sandbox unless Full Access or a one-operation grant
explicitly permits unrestricted execution. Keep the service home separate from
project code. MCP servers and plugins are trusted host components; the Bash
sandbox does not isolate those extension processes.

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

At startup the service captures default root guidance. Supplying explicit
workspace roots observes the primary root's `AGENTS.md` as a bounded UTF-8 snapshot
with a content revision. Selecting a saved project reuses its recorded workspace
and guidance. A new task freezes the selected guidance in its contract; inherited
forks, checkpoints and restarts retain it. Later file changes
are visible through Bash, but do not silently rewrite an existing task's
instructions. Restarting captures new guidance for subsequently created tasks.
Nested module guidance is read on demand. Repository text remains task context,
not privileged system authority.

These controls also appear in the browser from the native model.

```bash
bun host/cli.mjs steer --task-id 0 --message 'Prioritize this instruction.'
bun host/cli.mjs cancel_operation --task-id 0 --operation-id 12
```

On an active idle task, `compact` requests a summary
without starting another assistant turn. A supplied summary requires no provider
and also works on stopped or frozen idle tasks:

```bash
bun host/cli.mjs compact --task-id 0
bun host/cli.mjs interrupt --task-id 0
bun host/cli.mjs compact --task-id 0 --summary 'Completed work, verified results, unresolved problems, and next steps.'
bun host/cli.mjs send --task-id 0 --message 'Continue from the checkpoint.'
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

The default home is `~/.selvedge-bend`. `bun host/cli.mjs init` creates its
`config.json` without overwriting an existing file. `--home PATH` and `--config
FILE` select explicit locations; both options also work with `bun run start ...`.
Configuration is read at server startup.

To use your ChatGPT subscription, sign in. No model configuration is required:

```bash
bun host/cli.mjs login
bun host/cli.mjs models
```

Complete the device-code flow at the displayed OpenAI address. Login fetches
the account's Codex model catalog and refreshes an already-running server. At
startup the server also loads these models into the existing native selector;
advertised account models precede the offline demo. `models --refresh` fetches
a fresh catalog. Model names are not hardcoded and API-key availability is not
used to filter subscription models. Discovery is bounded and a fresh catalog is
cached for five minutes; transient failures may use a matching account's cache
for at most 24 hours. Authentication failures never fall back to another account.

The separate [ChatGPT Web backend](docs/chatgpt-web.md) uses
`provider: "chatgpt-web"`, a model such as `chatgpt-web/high`, and the API
application token in `CHATGPT_WEB_TOKEN`. Its default endpoint is
`http://127.0.0.1:8787/v1/responses`. It retains explicit request/response receipts,
supports ordinary task and tool calls through the same model interface, and
requires the API service's `full` mode for caller tools. It is not an OAuth/Codex
or OpenAI Responses endpoint; those profiles remain separate.

Optional `chatgpt` connection settings are `endpoint`, `issuer`, `client_id`,
`auth_file`, and `timeout_ms`; their defaults target OpenAI. `chatgpt: false`
disables default account discovery. Explicit model profiles remain available for
custom routing; `login PROFILE` selects a configured ChatGPT connection. Generated
profile identities bind the account and endpoint so changing credentials cannot
silently run an old task under a different account. Reasoning levels are checked
against the selected account model; use an advertised level in the native field.

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
started. Reopening verifies the hash chain and replays the same executable kernel.
Repeated file observations may observe a newer revision.

Transient model connection/HTTP failures use bounded, abortable backoff from the
native boundary policy. Permanent failures and excessive `Retry-After` delays
are not retried. A partially exposed response stream is never silently replayed;
retry notices are visible in the event stream and browser.

There is one current journal format, tied to the complete Bend source fingerprint
and compiler version, with task-local workspace settings stored in its inputs.
Another kernel or an obsolete database format is rejected; a different service
launch directory is not a reason to reject an otherwise matching journal.
Use a separate home when changing the kernel; this branch provides no migration
or backward-compatible reader. The earlier Rust implementation is retained in
Git history, not as a second runtime in the checkout.

The Bend proofs do not establish model termination, that every valid request fits
the resource bounds, scheduler fairness, or that an operating system or remote
service obeys the model.
Host-owned atomic writes do not make arbitrary Bash edits transactional.
Concurrent commands and editors can change the same files; any required locking,
revision checks or atomic replacement belong in the project's commands or scripts.
The Bend checker/compiler, generated JavaScript, Bun Worker, browser DOM,
SQLite, OS and remote protocols remain explicit external boundaries. The optional
native transport is also outside the proof boundary. Local integration tests exercise those paths;
live provider acceptance and physical history sharing are not claimed.

## Develop and verify

```bash
bun run check
bun run test
bun run index:check
bun run bench
```

`check` verifies the pinned compiler, proof obligations and host/script syntax.
The default build also produces the kernel and browser JavaScript libraries.
The remaining tests cover compiler and external component boundaries, integration
flows and negative proof mutations; their evidence responsibilities are recorded
in [tests-bend/README.md](tests-bend/README.md). Test commands listed here do not
claim that a particular checkout has passed them. Tests that exercise workspace
isolation require a working platform sandbox. The benchmark measures committed
transitions and replay without a machine-dependent CI threshold. `just` provides
aliases for the development commands.

After adding or deleting files, stage the changed paths, run `bun run index`, and
stage `AGENTS.md`. The index contains only Git-tracked files. When `pre-commit` is
installed, bootstrap installs the configured commit and push hooks. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the change workflow.
