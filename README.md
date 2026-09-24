# Selvedge

Selvedge runs persistent agent tasks through an executable Bend 2 model. It has a
local web interface and CLI, model profiles, task branching and messaging, Bash
and stdio MCP tools, and a SQLite input journal for restart recovery. The default
profile is an offline echo demonstration.

## Read the program

| Entry | What it establishes |
| --- | --- |
| [MODEL.bend](MODEL.bend) | Domain values, lifecycle and recovery policy, frozen contracts, and the command vocabulary used by clients. |
| [INVARIANTS.bend](INVARIANTS.bend) | Executable predicates for valid worlds, append-only task forests, retained history and contracts, and external-effect authority. |
| [LAWS.bend](LAWS.bend) | Requirements stated about the actual program, including admission, invariant preservation through arbitrary finite traces, and observation/replay laws. |
| [PROGRAM.bend](PROGRAM.bend) | The bounded state transition that the native service executes. |
| [PROOF.bend](PROOF.bend) | Checked proofs discharging those requirements, using reusable theory from `bendlib`. |

These files are the model and its implementation. Command descriptions, validation
schemas, lifecycle controls, and client command forms derive from their executable
definitions. [host/README.md](host/README.md) describes the operating-system
boundary; [bendlib/README.md](bendlib/README.md) locates supporting definitions.
[The exploration record](docs/bend2-exploration.md) explains the findings and their
limits. Architectural reasons live in [docs/adr](docs/adr).

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
historical effects are not dispatched. Interrupted external tool outcomes remain
unknown and are not automatically repeated. Interrupted model requests can be
requested again by recovery.

There is one current journal format, tied to the complete Bend source fingerprint
and compiler version. Another kernel or an obsolete Rust database is rejected.
Use a separate home when changing the kernel; this branch provides no migration
or backward-compatible reader. The earlier Rust implementation is retained in
Git history, not as a second runtime in the checkout.

The checked transition either retains the world with no effects, or satisfies the
world and transition predicates. Starting from a valid world, every finite trace
preserves its world invariant. This is a safety result: it does not prove that a
model terminates, that every valid request fits the resource bounds, that the
scheduler is fair, or that an operating system or remote service obeys the model.
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
Bash, stdio MCP, credential-flow fixtures, and negative proof mutations. The
benchmark measures committed transitions and replay on reproducible task trees;
it imposes no machine-dependent CI threshold. CI is configured to run checks and
tests on macOS and Linux. `just` provides aliases for these commands.

After adding or deleting files, stage the changed paths, run `npm run index`, and
stage `AGENTS.md`. The index contains only Git-tracked files. When `pre-commit` is
installed, bootstrap installs the configured commit and push hooks. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the change workflow.
