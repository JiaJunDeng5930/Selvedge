# Contributing to Selvedge

Thank you for contributing to Selvedge.

## Development setup

Run the bootstrap script from the repository root in a clean Ubuntu environment:

```bash
./scripts/bootstrap.sh
```

The script installs the Rust toolchain, `pre-commit`, and the repository Git hooks.

## Development workflow

1. Start from an up-to-date branch based on `main`.
2. Create a focused feature or fix branch.
3. Make the smallest coherent change that solves the problem.
4. Open a pull request back to `main`.

`main` is protected, so changes should land through pull requests rather than direct pushes.

## Local checks

Before opening a pull request, make sure these commands pass:

```bash
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --all-targets --all-features
```

You can also run the configured Git hooks manually:

```bash
pre-commit run --all-files
pre-commit run --all-files --hook-stage pre-push
```

The first command runs hooks configured for the default `pre-commit` stage, including `cargo fmt` and `cargo clippy`. The second command runs the `pre-push` hook, which executes `cargo test`.

## Pull requests

- Keep pull requests scoped to one change.
- Describe the intent of the change and any user-visible behavior.
- Include test coverage or explain why additional tests are not needed.
- Update documentation when behavior or workflow changes.

## Commit messages

Use short, imperative commit messages that describe the change clearly.
