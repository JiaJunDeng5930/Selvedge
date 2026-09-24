set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
    @just --list

bootstrap:
    bash scripts/bootstrap.sh

run:
    npm start

build:
    npm run build

test:
    npm test

check:
    npm run check
    npm test
    npm run index:check

agents-index:
    npm run index

agents-index-check:
    npm run index:check

bench:
    npm run bench

hooks:
    pre-commit run --all-files
    pre-commit run --all-files --hook-stage pre-push
