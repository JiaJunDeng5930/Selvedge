set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
    @just --list

bootstrap:
    ./scripts/bootstrap.sh

worktree branch:
    ./scripts/create-worktree.sh {{ quote(branch) }}

agents-index:
    cargo xtask agents-index update

agents-index-check:
    cargo xtask agents-index check

req-scan:
    cargo xtask req scan

req-fmt:
    cargo xtask req fmt-agents

req-check:
    cargo xtask req check --all

readme-mermaid-check:
    cargo xtask readme check-mermaid

readme-freshness-check:
    cargo xtask readme check-freshness

run:
    cargo run

fmt:
    cargo fmt --all

fmt-check:
    cargo fmt --all -- --check

lint:
    cargo clippy --workspace --all-targets --all-features -- -D warnings

test:
    cargo test --workspace --all-targets --all-features

check: fmt-check lint test
    @just agents-index-check
    @just req-check
    @just readme-mermaid-check
    @just readme-freshness-check

hooks:
    pre-commit run --all-files
    pre-commit run --all-files --hook-stage pre-push
