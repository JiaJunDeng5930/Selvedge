# Working on Selvedge

Read README.md, then inspect the owning Gallina definitions and requirements.
Read the domain README when one exists. Start with the product requirement.
Correct a specification that does not express the goal; never weaken a real
requirement merely to obtain a proof or a passing test.

## Semantic authority

Gallina owns pure domain behavior. Runtime code is extracted from those same
definitions. Keep IO and external observations explicit. Do not implement a
second version of a rule in JavaScript, OCaml foreign code or test fixtures.
Use shared domain declarations and generic operations before introducing new
mechanisms. MetaRocq derives declarations where ordinary functions cannot remove
structural duplication. Computational modules must not import MetaRocq or proof
automation. Important theorems constrain the extracted operations callers use.
No axioms, admitted obligations, unchecked recursion or fabricated observations.

Read the existing domain model before adding a feature. Prefer reuse,
composition, a justified common abstraction, or an extension inside the owning
module before adding independent state or special cases. Keep requirements in
executable definitions and propositions. Document reasons in ADRs rather than
maintaining a second description of the architecture or transition tables.

## Changes and validation

Use a focused branch; do not commit directly to main. Protect other work.
Use Conventional Commits: type(scope): description, with type feat, fix, docs,
refactor, test or chore and an English lowercase imperative description.

Choose the earliest sufficient assurance owner for each property: domain
construction and language design, then types and proofs, then focused unit or
component tests, and finally public end-to-end tests when the property crosses
real boundaries that a smaller check cannot cover. Record the property and its
quantifier, its actual production binding, and the remaining boundary failure a
test detects. Do not repeat a proved domain property in enumerated tests; do not
remove an integration check merely because a helper proves a similar statement.
Temporary experiments and the private migration file ledger belong in ignored
.workpad/.

Keep one current persistent data format. Do not add obsolete-format fallbacks,
migrations or old-runtime adapters without an explicit requirement.

Defensive branches require a real reachable input, an observed failure or an
explicit contract, and a comment beginning DEFENSE explaining that trigger.
Do not add speculative defaults, silent error suppression or generic retries.

Preserve UTF-8 text and exact domain numeric semantics across extraction. External
JSON admission is part of execution, not a property supplied by internal types.
The Rocq kernel, extraction compiler, JavaScript runtime and physical IO have
different assurance boundaries; report only what the evidence establishes.
