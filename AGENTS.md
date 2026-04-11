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

## Branch Protection

- `main` is a protected branch.
- Do not commit work directly on `main`.
- Do not use `main` as the active branch for task work unless the user explicitly asks for a change on `main`.

## Branch And Worktree Workflow

- Default workflow: if the user does not explicitly ask for multi-branch parallel development, create or switch branches in the repository root and work there.
- Only use `just worktree <branch-name>` when the user explicitly asks for multi-branch parallel development.
- When the user explicitly asks for multi-branch parallel development, keep the repository root on `main`; do not turn the root checkout into a feature branch.
- A branch created from the repository root should place its worktree under the repository root `.worktrees/`.
- A branch created from an existing worktree should place its child worktree under that worktree's own `.worktrees` namespace, not under the repository root `.worktrees/`.
- Child worktrees must not live inside their parent worktree checkout; keep them in that parent worktree's adjacent `.worktrees` storage so removing the parent does not delete the child.
- Do not use this helper from a worktree that lives outside the repository root `.worktrees/` hierarchy; fail fast instead of creating worktrees in ad-hoc locations.
- Do not flatten every parallel branch worktree into the repository root `.worktrees/` when the new branch belongs under an existing branch worktree.
- Each `.worktrees/` directory must stay Git-ignored. Fail fast if the ignore rule is missing.
- When working inside a worktree, only edit files inside that worktree and that worktree's own `.workpad/`.
- Do not edit parent directories, sibling worktrees, or any ancestor `.workpad/` while working inside a worktree.
- Each worktree should stay focused on one task so review and cleanup remain straightforward.

## Working Notes

- Unless the user explicitly asks otherwise, place temporary task documents (such as specs, plans, and research notes) under `.workpad/`.
- `.workpad/` is git-ignored on purpose and should be used for task artifacts that should not be committed.

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
|crates:{chatgpt-auth/,chatgpt-login/,client/,config-model/,config/,logging/}
|crates/chatgpt-auth:{src/,tests/,Cargo.toml,README.md}
|crates/chatgpt-auth/src:{auth_file.rs,config.rs,jwt.rs,lib.rs,lock.rs,refresh.rs,resolve.rs}
|crates/chatgpt-auth/tests:{support/,parse_contract.rs,public_api.rs,resolve_integration.rs}
|crates/chatgpt-auth/tests/support:{mod.rs}
|crates/chatgpt-login:{src/,tests/,Cargo.toml,README.md}
|crates/chatgpt-login/src:{auth_file.rs,config.rs,device_code.rs,id_token.rs,lib.rs,token_exchange.rs}
|crates/chatgpt-login/tests:{support/,complete_login_integration.rs,device_code_start_integration.rs,public_api.rs}
|crates/chatgpt-login/tests/support:{mod.rs}
|crates/client:{src/,tests/,Cargo.toml,README.md}
|crates/client/src:{config_resolution.rs,lib.rs,redaction.rs,redirect_runtime.rs,request_prep.rs,runtime.rs,single_hop.rs}
|crates/client/tests:{support/,http_integration.rs}
|crates/client/tests/support:{mod.rs}
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
