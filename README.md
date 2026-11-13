# Selvedge

Selvedge runs persistent agent tasks with a local web interface and CLI. Bun
interprets IO effects; Rocq definitions own the pure task, interaction and browser
semantics. Executable code is extracted from the definitions that proofs constrain.
Fresh installations start without model profiles. Sign in to use ChatGPT account
models or add a provider in Settings.

## Run

Install the pinned Rocq/MetaRocq and OCaml toolchain and Bun 1.4.2 or later:

```sh
bash scripts/bootstrap.sh
bun run start
```

See [usage](docs/usage.md) for projects, local and cloud task environments, model
connections, tools, compaction and voice conversations.
[Card board](docs/task-board.md), [plugins](docs/plugins.md),
[remote control](docs/remote-control.md), [ChatGPT Web](docs/chatgpt-web.md), and
[adaptive reasoning](docs/adaptive-reasoning.md) describe those user workflows.

The default home is `~/.selvedge`. Choose a different location explicitly to keep
services separate. During development, install and start the current checkout
with `bun run update`. Subsequent updates keep the same home and address and let
running tools finish before restarting. See [development updates](docs/usage.md#development-updates).

## Change the program

Read [CONTRIBUTING.md](CONTRIBUTING.md) and the owning domain's definitions and
requirements before changing behavior. [Requirements and design reasons](requirements/README.md)
connect current user and engineering goals to the actual checked operations.
They have a separate source root that production code cannot import.
The [programming constructions](theories/Programming/README.md) collect the
existing reusable languages, controlled constructors and their shared laws.

```sh
bun run check
bun run test
bun run bench
```

Rocq checking covers the stated propositions about the defined computations.
Standard extraction, js_of_ocaml, Bun, browser DOM, SQLite, the operating system
and remote providers remain explicit trust boundaries. Neither a proof nor a
passing test establishes the behavior of an unconstrained model or external service.
