# AGENTS.md

This file is for coding agents working in this repository.

## Start Here

- Read [README.md](./README.md) first for the repository-level workflow.
- Before you call or modify a module, read that module's `README.md` first.
- If the relevant `README.md` already answers your question, do not open the module internals first.

## Git Hooks

- `pre-commit` checks `cargo fmt --all -- --check`
- `pre-commit` checks `cargo clippy --workspace --all-targets --all-features -- -D warnings`
- `pre-commit` checks that the project index in this file is up to date
- `pre-push` checks `cargo test --workspace --all-targets --all-features`

## Worktree Workflow

- Keep the repository root on `main`; do not turn the root checkout into a feature branch.
- Do not default to worktrees for parallel development. Use `just worktree <branch-name>` only when the user explicitly asks you to create a worktree.
- The helper script creates a new branch and a matching checkout under `.worktrees/`.
- `.worktrees/` must stay Git-ignored. The helper fails fast if the ignore rule is missing.
- Each worktree should stay focused on one task so review and cleanup remain straightforward.

## Project Index Workflow

- Update the index with `just agents-index`
- Check whether the index is current with `just agents-index-check`
- The underlying repository commands are `cargo xtask agents-index update` and `cargo xtask agents-index check`
- Run all configured hooks with `just hooks`
- The index only includes Git-tracked files. Git-ignored and untracked files are excluded on purpose.
- Index commands warn when an indexed directory has an unusually large number of direct filesystem entries.

## Project Index

<!-- BEGIN AGENTS_MD_PROJECT_INDEX -->
```text
[Project Index]|root:.
|source:git-tracked-files-only
|excluded:{git-ignored,git-untracked}
|.:{.cargo/,.github/,crates/,scripts/,src/,tests/,xtask/,.editorconfig,.gitignore,.pre-commit-config.yaml,AGENTS.md,CONTRIBUTING.md,Cargo.lock,Cargo.toml,Justfile,README.md,rust-toolchain.toml}
|.cargo:{config.toml}
|.github:{workflows/}
|.github/workflows:{ci.yml}
|crates:{config-model/,config/,logging/}
|crates/config:{examples/,src/,tests/,Cargo.toml,README.md}
|crates/config-model:{src/,tests/,Cargo.toml,README.md}
|crates/config-model/src:{lib.rs}
|crates/config-model/tests:{model_contract.rs}
|crates/config/examples:{README.md,layered_sources.rs,load_defaults.rs,runtime_updates.rs}
|crates/config/src:{lib.rs}
|crates/config/tests:{public_api.rs}
|crates/logging:{src/,Cargo.toml,README.md}
|crates/logging/src:{lib.rs}
|scripts:{bootstrap.sh,create-worktree.sh}
|src:{lib.rs,main.rs}
|tests:{config_integration.rs,stdout_stderr_integration.rs,worktree_tool_integration.rs}
|xtask:{src/,Cargo.toml}
|xtask/src:{agents_index.rs,lib.rs,main.rs}
```
<!-- END AGENTS_MD_PROJECT_INDEX -->
