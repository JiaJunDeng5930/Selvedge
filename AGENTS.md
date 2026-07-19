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
- `pre-commit` checks package README Mermaid diagrams with `cargo xtask readme check-mermaid`
- `pre-push` checks `cargo test --workspace --all-targets --all-features`
- `pre-push` checks package README freshness metadata with `cargo xtask readme check-freshness`

## Package README State Machines

- Each workspace package README contains a Mermaid package-level state machine.
- Read the package state machine before changing package behavior or boundary errors.
- Package README metadata includes `freshness_fingerprint`, a history-independent hash of the package's tracked paths and staged blob ids. The package README is excluded.
- `cargo xtask readme check-freshness` compares the recorded fingerprint with the current Git index and reports stale packages.
- After reviewing affected state machines, run `cargo xtask readme update-freshness` to refresh every package fingerprint.

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

## Code Marker Comments

- Allowed tags: `TODO`, `FIXME`, `HACK`, `NOTE`, `XXX`.
- Format: `<comment marker> <TAG>(<optional issue>): <specific action or reason>`.
- Marker comments must explain the intent, decision, risk, or follow-up behind the code. Do not use marker comments to restate facts already visible from the code.
- `TODO` means known follow-up work while current code is acceptable.
- `FIXME` means a known defect that needs repair.
- `HACK` means a temporary workaround that should be replaced by normal design.
- `NOTE` means important context that affects code understanding.
- `XXX` means high-risk code that needs reviewer attention.

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
|crates:{api/,chatgpt-api/,chatgpt-auth/,chatgpt-login/,client-sync/,client/,command-model/,config-model/,config/,core/,db/,domain-model/,events/,harness/,local-client/,local-protocol/,logging/,model-credentials/,model-providers/,router/,server/,systemd/,task-runtime-factory/,test-support/,tui/,web/}
|crates/api:{src/,tests/,Cargo.toml,README.md}
|crates/api/src:{lib.rs}
|crates/api/tests:{api_contract.rs}
|crates/chatgpt-api:{src/,tests/,Cargo.toml,README.md}
|crates/chatgpt-api/src:{lib.rs}
|crates/chatgpt-api/tests:{support/,public_api.rs,request_contract.rs,stream_integration.rs}
|crates/chatgpt-api/tests/support:{mod.rs}
|crates/chatgpt-auth:{src/,tests/,Cargo.toml,README.md}
|crates/chatgpt-auth/src:{auth_file.rs,config.rs,jwt.rs,lib.rs,lock.rs,refresh.rs,resolve.rs}
|crates/chatgpt-auth/tests:{support/,parse_contract.rs,public_api.rs,resolve_integration.rs}
|crates/chatgpt-auth/tests/support:{mod.rs}
|crates/chatgpt-login:{src/,tests/,Cargo.toml,README.md}
|crates/chatgpt-login/src:{auth_file.rs,device_code.rs,lib.rs,token_exchange.rs}
|crates/chatgpt-login/tests:{support/,complete_login_integration.rs,device_code_start_integration.rs,public_api.rs}
|crates/chatgpt-login/tests/support:{mod.rs}
|crates/client:{src/,tests/,Cargo.toml,README.md}
|crates/client-sync:{src/,tests/,Cargo.toml,README.md}
|crates/client-sync/src:{lib.rs}
|crates/client-sync/tests:{client_sync_contract.rs}
|crates/client/src:{config_resolution.rs,lib.rs,redaction.rs,redirect_runtime.rs,request_prep.rs,runtime.rs,single_hop.rs}
|crates/client/tests:{support/,http_integration.rs}
|crates/client/tests/support:{mod.rs}
|crates/command-model:{src/,tests/,Cargo.toml,README.md}
|crates/command-model/src:{lib.rs}
|crates/command-model/tests:{command_contract.rs}
|crates/config:{examples/,src/,tests/,Cargo.toml,README.md}
|crates/config-model:{src/,tests/,Cargo.toml,README.md}
|crates/config-model/src:{lib.rs}
|crates/config-model/tests:{model_contract.rs}
|crates/config/examples:{README.md,layered_sources.rs,load_defaults.rs,runtime_updates.rs}
|crates/config/src:{lib.rs}
|crates/config/tests:{public_api.rs}
|crates/core:{src/,tests/,Cargo.toml,README.md}
|crates/core/src:{lib.rs}
|crates/core/tests:{runtime_contract.rs}
|crates/db:{src/,tests/,Cargo.toml,README.md}
|crates/db/src:{lib.rs,schema.sql}
|crates/db/tests:{fixtures/,db_contract.rs}
|crates/db/tests/fixtures:{schema_v5.sql}
|crates/domain-model:{src/,tests/,Cargo.toml,README.md}
|crates/domain-model/src:{lib.rs}
|crates/domain-model/tests:{domain_contract.rs}
|crates/events:{src/,tests/,Cargo.toml,README.md}
|crates/events/src:{lib.rs}
|crates/events/tests:{events_contract.rs}
|crates/harness:{src/,tests/,Cargo.toml,README.md}
|crates/harness/src:{lib.rs,mcp.rs}
|crates/harness/tests:{fixtures/,bash_contract.rs,executor_contract.rs,mcp_contract.rs,protocol_contract.rs}
|crates/harness/tests/fixtures:{mcp_server.sh}
|crates/local-client:{src/,tests/,Cargo.toml,README.md}
|crates/local-client/src:{lib.rs}
|crates/local-client/tests:{local_client_contract.rs}
|crates/local-protocol:{src/,tests/,Cargo.toml,README.md}
|crates/local-protocol/src:{lib.rs}
|crates/local-protocol/tests:{local_protocol_contract.rs}
|crates/logging:{src/,Cargo.toml,README.md}
|crates/logging/src:{lib.rs}
|crates/model-credentials:{src/,tests/,Cargo.toml,README.md}
|crates/model-credentials/src:{lib.rs}
|crates/model-credentials/tests:{credential_contract.rs}
|crates/model-providers:{src/,tests/,Cargo.toml,README.md}
|crates/model-providers/src:{lib.rs}
|crates/model-providers/tests:{provider_contract.rs}
|crates/router:{src/,tests/,Cargo.toml,README.md}
|crates/router/src:{lib.rs}
|crates/router/tests:{router_contract.rs}
|crates/server:{src/,tests/,Cargo.toml,README.md}
|crates/server/src:{command.rs,lib.rs}
|crates/server/tests:{server_contract.rs}
|crates/systemd:{src/,tests/,Cargo.toml,README.md}
|crates/systemd/src:{lib.rs}
|crates/systemd/tests:{systemd_contract.rs}
|crates/task-runtime-factory:{src/,tests/,Cargo.toml,README.md}
|crates/task-runtime-factory/src:{lib.rs}
|crates/task-runtime-factory/tests:{factory_contract.rs}
|crates/test-support:{src/,Cargo.toml,README.md}
|crates/test-support/src:{chatgpt_auth.rs,config.rs,db.rs,http.rs,lib.rs,local_transport.rs,process.rs}
|crates/tui:{src/,Cargo.toml,README.md}
|crates/tui/src:{lib.rs,tests.rs}
|crates/web:{src/,tests/,Cargo.toml,README.md}
|crates/web/src:{lib.rs}
|crates/web/tests:{web_contract.rs}
|scripts:{bootstrap.sh,create-worktree.sh}
|src:{lib.rs,main.rs}
|tests:{config_integration.rs,stdout_stderr_integration.rs,worktree_tool_integration.rs}
|xtask:{src/,Cargo.toml,README.md}
|xtask/src:{agents_index.rs,lib.rs,main.rs,readme_gate.rs}
```
<!-- END AGENTS_MD_PROJECT_INDEX -->
