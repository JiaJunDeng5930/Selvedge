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
the existing executable definitions and propositions. Keep current user and
engineering reasons beside their selected contracts under requirements/.
Select existing contracts with Rocq Export rather than copying their formulas.
Production code must remain independent of the requirements logical root.

## Changes and validation

Use a focused branch; do not commit directly to main. Protect other work.
Use Conventional Commits: type(scope): description, with type feat, fix, docs,
refactor, test or chore and an English lowercase imperative description.

Choose the earliest sufficient assurance owner for each property: domain
construction and language design, then types and proofs, then public end-to-end
tests for the remaining observable behavior. Permanent tests use complete public
operations and requirements independent of the implementation. Do not repeat a
proved domain property in enumerated tests; keep the public integration check
when a helper theorem does not constrain that execution path. Temporary local
experiments and complete command logs belong in ignored .workpad/.

Keep one current persistent data format. Do not add obsolete-format fallbacks,
migrations or old-runtime adapters without an explicit requirement.

Defensive branches require a real reachable input, an observed failure or an
explicit contract, and a comment beginning DEFENSE explaining that trigger.
Do not add speculative defaults, silent error suppression or generic retries.

Preserve UTF-8 text and exact domain numeric semantics across extraction. External
JSON admission is part of execution, not a property supplied by internal types.
The Rocq kernel, extraction compiler, JavaScript runtime and physical IO have
different assurance boundaries; report only what the evidence establishes.
