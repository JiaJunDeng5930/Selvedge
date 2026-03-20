# Selvedge

Selvedge is a Rust repository scaffold with a clean local development flow, pre-commit hooks, and GitHub Actions CI.

## What is included

- Cargo binary crate with a small library surface for testing
- `rust-toolchain.toml` to keep the repository on the stable toolchain
- `.pre-commit-config.yaml` for formatting, lint, and test checks
- GitHub Actions CI for `fmt`, `clippy`, and `test`
- Basic repository hygiene files such as `.gitignore` and `.editorconfig`

## Quickstart

```bash
cargo run
cargo test
```

## Development setup

```bash
./scripts/bootstrap.sh
```

Run this once in a clean Ubuntu environment. It installs the Rust toolchain, `pre-commit`, and the repository hooks. When run as a non-root user, it will prompt for `sudo` during package installation.

See [CONTRIBUTING.md](./CONTRIBUTING.md) for the contribution workflow and pull request expectations.
