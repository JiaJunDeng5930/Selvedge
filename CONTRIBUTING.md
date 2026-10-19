# Contributing to Selvedge

Read [README.md](README.md) and the relevant module README before changing code.
Start from the engineering goal and the behavior the change needs to provide.
The executable specifications in [harness/MODEL.bend](harness/MODEL.bend),
[harness/INVARIANTS.bend](harness/INVARIANTS.bend) and
[harness/LAWS.bend](harness/LAWS.bend) are the execution entry points to review.
[harness/PROGRAM.bend](harness/PROGRAM.bend) executes those definitions;
[PROOF.bend](PROOF.bend) checks the
stated properties. Correct specifications along with their implementations when
they do not express the goal. A passing proof or an existing behavior does not
establish that the specification is appropriate; do not weaken a real requirement
merely to make an implementation pass.

## Setup and checks

Use Bun 1.4.2 or later and a C compiler on macOS or Linux. Run
`bash scripts/bootstrap.sh` to build with the pinned Bend release and install Git
hooks when `pre-commit` is available. Worktree setup creates a local `.build`
directory without downloading, building, or sharing a kernel executable.

Run `bun run verify` before submitting work. It checks proofs, syntax, all tests
and the file index while building production assets once. Individual stages remain
available as `bun run check`, `bun run test`, and `bun run index:check`.
The commit hook checks proofs, syntax, and the tracked-file index; the push hook
runs the focused physical regression suite after the production build.
`just check` runs the same checks, and `just hooks`
executes the configured hook stages. GitHub Actions CI is disabled; run these checks locally.

Choose assurance for the behavior at risk. Use domain construction, types and
proofs where they establish the needed property, then assess what a test would
add: a real failure history, a credible failure path, or an observation outside
that guarantee. Retain a test only when that evidence justifies its runtime and
maintenance cost; a duplicate assertion or an external boundary alone is
insufficient. Prefer focused checks and share related physical setup. See
[tests-bend/README.md](tests-bend/README.md) for the current responsibilities.
The configured production proof and certificate checks validate the model and
its evidence; they do not prove that a host, compiler or remote provider obeys it.

After adding, renaming, or removing files, stage them, run `bun run index`, and
stage `AGENTS.md`. The index is derived from Git's staged tracked paths. Temporary
logs, benchmark measurements, and investigation notes belong in `.workpad/`.

## Persistent data

Use a fresh temporary home for tests. Do not add migration adapters, obsolete-format fallbacks,
or compatibility layers unless explicitly requested. Preserve existing user data
rather than changing it to make a development run succeed.

## Reviews and decisions

Work on a focused branch; `main` is protected. Explain the resulting behavior,
its reason, and the relevant verification. Express decision reasons that are
program requirements as Bend entities, executable specifications or public rules
bound to actual production computations. Documentation can explain their goal,
rationale, use and evidence limits; link to the owning definitions instead of
maintaining a competing specification. ADRs record decisions in their original
scope and do not freeze their implementations or supply new requirements.
Record findings specific to the executable-model exploration in
[docs/bend2-exploration.md](docs/bend2-exploration.md); avoid restating code tables
or maintaining a second state-machine diagram.

Use Conventional Commits: `type(scope): description`, with an English imperative
description starting in lowercase. Allowed types are `feat`, `fix`, `docs`,
`refactor`, `test`, and `chore`. Mark breaking changes with `!` and a
`BREAKING CHANGE:` footer.
