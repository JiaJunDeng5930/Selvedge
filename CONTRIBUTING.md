# Contributing to Selvedge

Read README.md and the owning domain's definitions and requirements before
modifying them. Read its README when one exists. Start from the engineering goal. A proof of an inappropriate
specification does not establish the required behavior; correct the specification
and implementation together without weakening the requirement.

## Setup and checks

Use the toolchain versions selected by scripts/bootstrap.sh and Bun 1.4.2 or
later. Run `bun run check` for production proof checking, extraction and host
syntax, and `bun run test` for public end-to-end behavior. `bun run bench`
measures clean, unchanged and edited production builds. Report the checks actually performed and
their scope. GitHub Actions remains disabled; run validation locally.

Browser end-to-end tests use a system Chromium with the pinned `playwright-core`
driver. Install `chromium` or `chromium-browser`, or set
`SELVEDGE_CHROMIUM_EXECUTABLE_PATH` to its executable. The tests report a missing
browser as a setup error.

To enable the configured hooks, install `pre-commit`, then run
`pre-commit install` and `pre-commit install --hook-type pre-push`.
`just hooks` runs both configured stages manually.

Keep pure domain rules in Gallina. Executable entries must use those definitions;
foreign code interprets effects and translates external data. Reuse shared
field and command descriptions, indexed types and generic operations rather than
maintaining repeated structural facts. Keep computational modules independent of
MetaRocq and proof automation to preserve useful incremental checking.

Assign every desired property one earliest sufficient assurance owner:
construction and domain languages, then types and proofs, then unit/component
tests, then end-to-end tests. Permanent unit tests are appropriate for pure
boundary code that cannot be covered by the earlier mechanisms. Public
end-to-end tests are reserved for faults that require real processes, storage,
networking, extraction or several interacting boundaries. A theorem about a
helper does not cover an unrelated public dispatcher; retain the boundary
assertion until the theorem is bound to the operation the product executes.

For an assertion, identify the property and its quantifier, the construction,
type or theorem that already owns it, and any remaining independent boundary
fault. Remove duplicate pure assertions after that binding is established.
Do not retain tests that merely reproduce a function's branches. Temporary
experiments, complete command logs and migration accounting belong in ignored
.workpad/. Tests use fresh temporary service homes where a service is needed.

## Persistent data

There is one current journal format. Reject incompatible data explicitly rather
than adding fallback reads, migrations or old-runtime bridges. Never rewrite
existing user data to make a development run succeed.

## Reviews and decisions

Work on a focused branch; main is protected. Explain the resulting behavior,
reason and relevant verification. Keep executable requirements authoritative.
ADRs record the reason for architectural choices without duplicating definitions
or freezing obsolete implementation mechanisms.

Use Conventional Commits: `type(scope): description`, with an English imperative
description starting in lowercase. Allowed types are feat, fix, docs, refactor,
test and chore. Mark breaking changes with `!` and a BREAKING CHANGE footer.
