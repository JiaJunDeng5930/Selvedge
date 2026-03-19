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

## Local checks

```bash
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --all-targets --all-features
```

## Pre-commit

Install `pre-commit` in your environment, then enable the hooks:

```bash
pre-commit install
pre-commit install --hook-type pre-push
pre-commit run --all-files
```
