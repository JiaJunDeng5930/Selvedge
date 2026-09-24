# Selvedge

<!-- selvedge-package-readme
package: selvedge
freshness_fingerprint: cb74caa5b30d33c2deadd7470b3e1a087ac7c495
-->

Selvedge runs a local server for persistent AI tasks. This branch explores a Bend 2
rewrite in which the task model, executable transition, and requirements are
checked together. Start with these executable entry points:

- [MODEL.bend](MODEL.bend): task identity, ancestry, frozen contracts, lifecycle,
  work phases, commands, and effect boundaries.
- [LAWS.bend](LAWS.bend): the precise requirements currently proved about those
  definitions and the running transition.
- [PROGRAM.bend](PROGRAM.bend): the bounded transition that the native server
  executes. [PROOF.bend](PROOF.bend) supplies the proofs and connects reusable
  theory to that same transition.

Install Bend at the version recorded in `bend-version` and Node.js 26 or later.
The host uses Node's built-in SQLite support and has no npm dependencies.

```bash
npm run check
npm test
npm start
```

The server prints its local web URL, including an access token. The default `demo`
profile is an offline echo model. Run `node host/cli.mjs help` for the command
interface. Configuration and the journal use a separate `~/.selvedge-bend` home;
obsolete persistence formats are rejected. The current exploration and its
verification limits are recorded in [docs/bend2-exploration.md](docs/bend2-exploration.md).

The Rust workspace below remains available as the earlier implementation while
the Bend experiment is being completed. Its commands do not launch the Bend host.

## Earlier Rust repository navigation

Read each package README before changing its behavior. Start with the boundary relevant to your change:

- [server](crates/server/README.md) and [web](crates/web/README.md): startup, local commands, and HTTP delivery.
- [core](crates/core/README.md), [db](crates/db/README.md), and [harness](crates/harness/README.md): durable task execution, persistence, and tools.
- [model-providers](crates/model-providers/README.md): model request adapters and provider selection.
- [local-client](crates/local-client/README.md) and [tui](crates/tui/README.md): local protocol access and terminal interaction.
- [config](crates/config/README.md): runtime configuration and storage paths.
- [xtask](xtask/README.md): repository checks and documentation maintenance.

[AGENTS.md](AGENTS.md) contains the complete tracked-file index and repository policies. Architectural decisions are recorded in [docs/adr](docs/adr).

## Earlier Rust quickstart

```bash
just run
just test
```

`just run` starts the local server. `Ctrl-C` exits with status 130 after cancelling an in-progress startup or supervising a running server to shutdown, including releasing the singleton lock in either phase.

Server startup builds the current harness and MCP runtime catalog, reconciles existing tasks' unavailable-tool sets without changing their frozen tool definitions, and requests recovery for every active durable task. The current CLI still supplies no model profiles and does not provision a root task, so those remain separate prerequisites for a model-driven production session.

## Development setup

```bash
./scripts/bootstrap.sh
```

Run this once in a clean Ubuntu environment. It installs the Rust toolchain, `just`, `pre-commit`, and the repository hooks. When run as a non-root user, it will prompt for `sudo` during package installation.

## Common commands

```bash
just fmt
just check
just hooks
just agents-index
just readme-freshness
```

Use `just agents-index` after adding, removing, or renaming tracked files so the project index in `AGENTS.md` stays current. Use `just agents-index-check` to verify that the index is up to date without rewriting the file. The index is built from Git-tracked files, so ignored and untracked files stay out automatically. Both commands warn when an indexed directory has an unusually large number of direct filesystem entries.

The underlying repository commands are `cargo xtask agents-index update` and `cargo xtask agents-index check`.

## Package State Machine

The diagram records the root package observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([selvedge binary starts])
  Runtime[Create multi-thread Tokio runtime]
  RunCli[Run selvedge::run_cli with process argv]
  Parse[Parse process arguments]
  InitConfig[Initialize config and logging through CLI flow]
  Command{parsed command}
  RunServer[Run local server]
  StopServer[Request supervised server shutdown]
  Submit[Submit command to local server]
  WaitTerminal[Wait for terminal notice]
  Success[Exit code 0]
  Interrupted[Exit code 130]
  Failure[Exit code 1]
  PanicExit[Process exits through Rust panic path]

  Start -->|main is invoked by the operating system| Runtime
  Runtime -->|Tokio runtime builds successfully| RunCli
  Runtime -->|Tokio runtime construction panics before CLI status mapping runs| PanicExit
  RunCli -->|CLI execution starts| Parse
  Parse -->|argv identifies a supported command| InitConfig
  Parse -->|argv is empty, malformed, or contains an unsupported command shape| Failure
  InitConfig -->|config and logging initialize successfully| Command
  InitConfig -->|config read, validation, or logging initialization fails| Failure
  Command -->|parsed command is RunServer| RunServer
  Command -->|parsed command is SubmitCommand| Submit
  RunServer -->|server startup and run complete successfully| Success
  RunServer -->|server startup, runtime, or dependency fails| Failure
  RunServer -->|SIGINT is received during startup| Interrupted
  RunServer -->|SIGINT is received after startup| StopServer
  StopServer -->|server tasks stop and the singleton lock is released| Interrupted
  Submit -->|server accepts typed login-chatgpt or list-models command| WaitTerminal
  Submit -->|local client connection, readiness, command rejection, or server wait fails| Failure
  WaitTerminal -->|matching CommandCompleted notice arrives| Success
  WaitTerminal -->|matching CommandFailed notice, stream close, or protocol error arrives| Failure
```

See [CONTRIBUTING.md](./CONTRIBUTING.md) for the contribution workflow and pull request expectations.
