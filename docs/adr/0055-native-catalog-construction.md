# ADR 0055: Keep catalog schemas abstract during proof checking

## Context

Production proof tracing found prolonged normalization and high memory use in
`initial_world_valid`. An isolated check located the same behavior in its closed
catalog-routing fact. Computing the catalog's list structure enters
`catalog_entry`, whose checked construction evaluates schema admission before
returning a tool. Establishing routing therefore brought concrete schema terms
into a proof about tool capabilities.

Further isolated checks reached full-world fallback normalization when a
zero-argument initialization wrapper and an explicit constructor expression had
to be compared. Keeping those expressions aligned avoids requiring that
comparison to inspect unrelated state fields.

The initial-world guarantee must remain unconditional and bound to the actual
production constructor. Its routing and name properties should follow from the
same declarations and construction rules used at runtime.

## Decision

Use the existing Request representation as the single ordered source of native
tool declarations. Fold those requests through the existing checked construction.
This gives generic inductive proofs a construction boundary at which schema
contents can remain abstract, while the production instance supplies the actual
declarations and their checked name constraints.

The declaration list retains each tool's name, schema, capability and position.
The fold retains the existing admission and rejection branches. Both runtime
construction and proofs consume that list, so there is no second declaration
list to maintain.

Pass the authoritative Request list explicitly to the single initial-world
constructor at production startup and in its invariant. The constructor performs
the checked fold internally, keeping catalog construction at the model boundary.
Each startup therefore uses the same production declarations that the theorem
names, without exposing catalog assembly to entry points or the browser.

## Consequences

Catalog construction gains a shared fold over an existing domain representation.
Runtime admission remains part of tool construction; proof composition can use
its general properties without evaluating every concrete schema to establish
routing or uniqueness. This changes proof organization while preserving the
original initial-world invariant and its production binding.
