set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
    @just --list

bootstrap:
    bash scripts/bootstrap.sh

run:
    bun run start

build:
    bun run build

test:
    bun run test

check:
    bun run check
    bun run test
    bun run index:check

agents-index:
    bun run index

agents-index-check:
    bun run index:check

bench:
    bun run bench

hooks:
    pre-commit run --all-files
    pre-commit run --all-files --hook-stage pre-push
