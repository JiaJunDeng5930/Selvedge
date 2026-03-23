set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
    @just --list

bootstrap:
    ./scripts/bootstrap.sh

run:
    cargo run

fmt:
    cargo fmt --all

fmt-check:
    cargo fmt --all -- --check

lint:
    cargo clippy --all-targets --all-features -- -D warnings

test:
    cargo test --all-targets --all-features

check: fmt-check lint test

hooks:
    pre-commit run --all-files
    pre-commit run --all-files --hook-stage pre-push
