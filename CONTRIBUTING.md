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

If you do not need parallel development, work directly in the repository root by switching to the branch you need. If you do want multi-branch parallel development, keep the repository root on `main` and use `just worktree <branch-name>`. The helper creates a new branch from the current branch and a matching checkout under the current checkout's `.worktrees` namespace, so child branches created from an existing worktree stay grouped with that worktree without being stored inside the parent checkout itself. The helper only supports the repository root and helper-managed worktrees under the repository root `.worktrees/` hierarchy.

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
