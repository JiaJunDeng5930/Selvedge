# Contributing to Selvedge

Read [README.md](README.md) and the relevant module README before changing code.
The executable requirements in MODEL, INVARIANTS, and LAWS are the entry point
for behavior changes. PROGRAM executes those definitions; PROOF checks the
required facts. Do not weaken a requirement merely to make an implementation pass.

## Setup and checks

Use Bun 1.4.2 or later and a C compiler on macOS or Linux. Run
`bash scripts/bootstrap.sh` to build with the pinned Bend release and install Git
hooks when `pre-commit` is available. Worktree setup creates a local `.build`
directory without downloading, building, or sharing a kernel executable.

Run `bun run check`, `bun run test`, and `bun run index:check` before submitting work.
The commit hook checks proofs, syntax, and the tracked-file index; the push hook
runs native integration tests. `just check` runs the same checks, and `just hooks`
executes the configured hook stages. CI covers macOS and Linux.

Use proofs for internal semantics, component tests for external boundaries and
end-to-end tests for their combinations. The ownership map is
`tests-bend/README.md`. Do not add finite-example tests that only repeat a proven
state transition; do retain compiler/protocol probes with a concrete fault model
and independent negative tests of the proof infrastructure. Unproved behavior
still needs evidence. A successful Bend proof is not evidence that a host,
compiler or remote provider follows the model.

After adding, renaming, or removing files, stage them, run `bun run index`, and
stage `AGENTS.md`. The index is derived from Git's staged tracked paths. Temporary
logs, benchmark measurements, and investigation notes belong in `.workpad/`.

## Persistent data

A journal belongs to one compiler/source identity. Use a fresh temporary home
for changed kernels. Do not add migration adapters, obsolete-format fallbacks,
or compatibility layers unless explicitly requested. Preserve existing user data
rather than changing it to make a development run succeed.

## Reviews and decisions

Work on a focused branch; `main` is protected. Explain the resulting behavior,
its reason, and the relevant verification. Record architecture choices in an ADR.
Record findings specific to the executable-model exploration in
[docs/bend2-exploration.md](docs/bend2-exploration.md); avoid restating code tables
or maintaining a second state-machine diagram.

Use Conventional Commits: `type(scope): description`, with an English imperative
description starting in lowercase. Allowed types are `feat`, `fix`, `docs`,
`refactor`, `test`, and `chore`. Mark breaking changes with `!` and a
`BREAKING CHANGE:` footer.
