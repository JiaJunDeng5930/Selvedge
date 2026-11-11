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
Find the existing construction interfaces and their applicability in
[theories/Programming](theories/Programming/README.md).

Assign every desired property one earliest sufficient assurance owner:
construction and domain languages, then types and proofs, then public end-to-end
tests. Design permanent tests from the required external behavior and execute
complete public operations. A theorem about a helper does not cover an unrelated
public dispatcher; retain the boundary assertion until the theorem is bound to
the operation the product executes.

For an assertion, identify the property and its quantifier, the construction,
type or theorem that already owns it, and any remaining independent boundary
fault. Remove duplicate pure assertions after that binding is established.
Do not retain tests that merely reproduce a function's branches. Temporary
experiments and complete command logs belong in ignored
.workpad/. Tests use fresh temporary service homes where a service is needed.

## Browser screenshots

After `bun run build`, run `bun run screenshots` to capture the browser UI with
isolated local data. Each run writes an `index.html` gallery, the original
images, a JSON manifest, and capture logs to a new directory under
`.workpad/browser-screenshots/`. Pass `--out DIRECTORY` to choose another parent
directory. Chrome or Chromium can be selected with
`SELVEDGE_CHROMIUM_EXECUTABLE_PATH`.

```sh
bun run screenshots --groups properties,settings --viewports marked,short,large
bun run screenshots --help
```

The default matrix covers navigation, conversations, task creation and its
property menus, projects and search, the board, graphs, shared UI, and settings.
It includes desktop and compact navigation, a short landscape window, and
200% text. Each row shows an opened UI state across the selected sizes.
Cells may link to the bottom or right edge of a scroll area. Navigation also
includes views on either side of the sidebar breakpoint. A cell marked
not applicable has no equivalent state at that size. Missing captures and
failed capture processes produce a nonzero exit code. Open the gallery to
find the affected states and the corresponding capture log.

## Persistent data

There is one current SQLite schema and one current journal replay format. A
supported older format is converted under exclusive ownership before ordinary
service execution. Write explicit migrations when changing a supported format
and validate replay before committing them. Reject unknown formats and preserve
the previous data when startup cannot complete.

## Requirements and reviews

Work on a focused branch; main is protected. Explain the resulting behavior,
reason and relevant verification. Keep executable requirements authoritative.
Read [requirements/](requirements/README.md) for current user and engineering
reasons beside their checked contracts. Reuse a named contract with selective
Export; add a derivation only for a relationship not already established.
Requirements import the actual domain definitions and proof providers, while
production compilation cannot import requirements. New files are discovered by
the existing build; there is no list of all requirement owners to maintain.

When changing a rule, review its meaning, premises, actual execution binding and
adjacent reason together. Apply the
[capability design requirements](requirements/Engineering.v)
when deciding where a capability belongs and whether it needs a basic operation.
Keep the current reasons here and earlier designs in version control.

Use Conventional Commits: `type(scope): description`, with an English imperative
description starting in lowercase. Allowed types are feat, fix, docs, refactor,
test and chore. Mark breaking changes with `!` and a BREAKING CHANGE footer.
