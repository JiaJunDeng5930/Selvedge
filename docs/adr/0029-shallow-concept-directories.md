# 0029: Shallow concept directories

## Context

Grouping domain implementation under a shared library, presentation under `core`,
and browser implementation under `webui` obscured the concepts that own behavior.
Separate proof directories also required readers to reconstruct the connection
between an executable contract and its provider. Deep directory hierarchies would
replace that problem with additional navigation and ambiguous ownership.

## Decision and reasons

Organize production sources by concept: `harness` owns execution semantics,
`features` owns independent board and ChatGPT capabilities, `interaction` owns
platform-independent user interaction, and `browser` owns browser realization.
Use at most two directory levels for these models. Each concept's README points
to a small set of actual public entries; imports express the subordinate
composition rather than another documentation inventory.

Keep evidence beside the concept it establishes, using `PROOF.bend` for the
concept provider and `*-proof.bend` for narrower providers. Keep the root
`CONCEPTS.bend` and `PROOF.bend` as conceptual and production-evidence assembly
entries. Root `MAIN.bend`, `KERNEL.bend` and `BROWSER.bend` retain their native
boundary roles. Keep reusable theory, JSON, component frames and parameterized
effects in `bendlib`; domain correspondence stays with its owning model.

Move sources and resolve their imports without changing their non-import bodies.
The executable requirements, mandatory contracts and proof assembly remain the
semantic authority. Source ownership and closed import boundaries follow the
new paths; the model representation decision in
[ADR 0028](0028-model-representation-boundaries.md) remains in force. Do not retain
old-path forwarding modules or symlinks, or document a second migration map.

## Tradeoffs and evidence boundaries

A shallow tree keeps related definitions and proofs visible but gives large
concepts more files in one directory. Public entries and concept READMEs provide
the reading order; helper filenames do not create additional architecture tiers.
The physical move changes import and tool configuration paths even when source
semantics are unchanged. Mandatory proof checks, source ownership checks and
native integration boundaries retain their existing responsibilities. Document
link validity and unchanged source bodies alone do not establish that a full
build or integration test passed.
