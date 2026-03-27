# Selvedge

Selvedge is a Rust repository scaffold with a clean local development flow, pre-commit hooks, and GitHub Actions CI.

## What is included

- Cargo binary crate with a small library surface for testing
- `Justfile` shortcuts for bootstrap, formatting, lint, test, and hook execution
- A dedicated `cargo xtask` command for AGENTS.md project-index maintenance
- Root `AGENTS.md` guidance for coding agents, including a repository file index
- `rust-toolchain.toml` to keep the repository on the stable toolchain
- `.pre-commit-config.yaml` for formatting, lint, project-index, and test checks
- GitHub Actions CI for `fmt`, `clippy`, and `test`
- Basic repository hygiene files such as `.gitignore` and `.editorconfig`

## Quickstart

```bash
just run
just test
```

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
just worktree feature/my-change
```

Use `just agents-index` after adding, removing, or renaming tracked files so the project index in `AGENTS.md` stays current. Use `just agents-index-check` to verify that the index is up to date without rewriting the file. The index is built from Git-tracked files, so ignored and untracked files stay out automatically. Both commands warn when an indexed directory has an unusually large number of direct filesystem entries.

The underlying repository commands are `cargo xtask agents-index update` and `cargo xtask agents-index check`.

## Parallel development with worktrees

Use the repository root as the `main` checkout and create one worktree per focused task:

```bash
just worktree feature/config-layering
```

The helper script creates a new branch and a matching checkout under `.worktrees/`. The directory name is derived from the branch name, with path separators normalized to `-`. `.worktrees/` is Git-ignored on purpose, so worktree contents stay out of the main checkout.

Run the command from an up-to-date branch based on `main`. The helper fails fast if `.worktrees/` is not ignored, if the branch already exists, or if the target worktree path already exists.

See [CONTRIBUTING.md](./CONTRIBUTING.md) for the contribution workflow and pull request expectations.
