# Working on Selvedge

Read README.md and the README for the domain you change. Start with the product
requirement, then inspect the owning Gallina definitions and requirements.
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

Choose assurance proportional to the actual risk. Prefer domain construction,
types and proofs, then public end-to-end tests for behavior outside those
mechanisms. Do not retain implementation-mirroring tests. Temporary experiments
and the private migration file ledger belong in ignored .workpad/.

Keep one current persistent data format. Do not add obsolete-format fallbacks,
migrations or old-runtime adapters without an explicit requirement.

Defensive branches require a real reachable input, an observed failure or an
explicit contract, and a comment beginning DEFENSE explaining that trigger.
Do not add speculative defaults, silent error suppression or generic retries.

Preserve UTF-8 text and exact domain numeric semantics across extraction. External
JSON admission is part of execution, not a property supplied by internal types.
The Rocq kernel, extraction compiler, JavaScript runtime and physical IO have
different assurance boundaries; report only what the evidence establishes.
