set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
    @just --list

bootstrap:
    ./scripts/bootstrap.sh

worktree branch:
    ./scripts/create-worktree.sh "{{branch}}"

agents-index:
    cargo xtask agents-index update

agents-index-check:
    cargo xtask agents-index check

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

hooks:
    pre-commit run --all-files
    pre-commit run --all-files --hook-stage pre-push
