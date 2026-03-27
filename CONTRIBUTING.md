# Contributing to Selvedge

Thank you for contributing to Selvedge.

## Development setup

Run the bootstrap script from the repository root in a clean Ubuntu environment:

```bash
./scripts/bootstrap.sh
```

The script installs the Rust toolchain, `just`, `pre-commit`, and the repository Git hooks.

The installed `pre-commit` hooks check formatting, linting, and whether the project index in `AGENTS.md` is current. The installed `pre-push` hook runs the test suite.

## Development workflow

1. Start from an up-to-date branch based on `main`.
2. Create a focused feature or fix branch.
3. Make the smallest coherent change that solves the problem.
4. Open a pull request back to `main`.

`main` is protected, so changes should land through pull requests rather than direct pushes.

If you want parallel workspaces, `just worktree <branch-name>` creates a new branch and a matching checkout under `.worktrees/`. Keep the repository root on `main`, and treat each worktree as a single-task workspace.

## Local checks

Before opening a pull request, make sure these commands pass:

```bash
just check
```

Use these shortcuts during development:

```bash
just fmt
just lint
just test
just hooks
just agents-index
just worktree feature/my-change
```

`just fmt` rewrites formatting. `just agents-index` refreshes the project index stored in `AGENTS.md` after tracked files move. `just agents-index-check` verifies the index without rewriting it. Both index commands warn when an indexed directory has an unusually large number of direct filesystem entries. The underlying repository commands are `cargo xtask agents-index update` and `cargo xtask agents-index check`. `just check` runs the read-only formatting, lint, test, and project-index checks used for local validation. `just hooks` runs both configured Git hook stages manually.

## Pull requests

- Keep pull requests scoped to one change.
- Describe the intent of the change and any user-visible behavior.
- Include test coverage or explain why additional tests are not needed.
- Update documentation when behavior or workflow changes.

## Commit messages

Use short, imperative commit messages that describe the change clearly.
