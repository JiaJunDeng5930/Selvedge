# Contributing to Selvedge

Thank you for contributing to Selvedge.

## Development setup

Run the bootstrap script from the repository root in a clean Ubuntu environment:

```bash
./scripts/bootstrap.sh
```

The script installs the Rust toolchain, `just`, `pre-commit`, and the repository Git hooks.

The installed hooks enforce the checks documented in [AGENTS.md](AGENTS.md#git-hooks). [`.pre-commit-config.yaml`](.pre-commit-config.yaml) defines their commands and stages.

## Worktree build cache

Codex local environment setup runs `bash scripts/setup-worktree.sh` when creating a worktree. For a manually created worktree, run the same command from its repository root.

Setup links the worktree's `target` directory to the main checkout's existing `target` directory. Cargo's downloaded dependencies already share the user's Cargo home; the link also shares compiled artifacts and incremental caches without downloading dependencies, building, or testing during setup. An existing worktree-local `target` is preserved and setup reports that it must be moved aside first.

Concurrent Cargo builds may wait for the shared build directory lock. Different source changes, compiler options, or toolchains can still require rebuilding. Final binaries are shared too, so use `cargo run` for the current checkout instead of relying on a previously built `target/debug` executable. `cargo clean` affects all worktrees sharing this directory. Keep the main checkout in place while its worktrees use the cache.

## Development workflow

1. Start from an up-to-date branch based on `main`.
2. Create a focused feature or fix branch.
3. Make the smallest coherent change that solves the problem.
4. Open a pull request back to `main`.

`main` is protected, so changes should land through pull requests rather than direct pushes.

## Local checks

Before opening a pull request, make sure these commands pass:

```bash
just check
```

`just check` runs all local validation gates defined in [Justfile](Justfile), including package README Mermaid rendering and freshness checks. `just hooks` runs both configured Git hook stages manually. Use `just --list` to find individual commands.

After adding, removing, or renaming files, stage them and run `just agents-index` to refresh the tracked-file index. After reviewing affected package state machines, stage package changes and run `just readme-freshness`, then stage the updated READMEs. Freshness compares against the Git index, so working-tree changes alone are not its input. See [xtask's README](xtask/README.md) for the maintenance commands and [AGENTS.md](AGENTS.md#package-readme-state-machines) for the review policy.

## Pull requests

- Keep pull requests scoped to one change.
- Describe the intent of the change and any user-visible behavior.
- Include test coverage or explain why additional tests are not needed.
- Update documentation when behavior or workflow changes.

## Commit messages

Use Conventional Commits: `type(scope): description`, with an English imperative description starting in lowercase. Allowed types are `feat`, `fix`, `docs`, `refactor`, `test`, and `chore`. Mark breaking changes with `!` and a `BREAKING CHANGE:` footer.
