# Shared Bend library

This directory contains reusable component frames, parameterized effects, equality,
JSON, open semantic categories and imported list, finite-map and relation theory. Domain behavior belongs to
[harness](../harness/README.md), [features](../features/README.md),
[interaction](../interaction/README.md) and [browser](../browser/README.md).

Read [component.bend](component.bend) for local state with an opaque remainder,
[effects.bend](effects.bend) for parameterized effect payloads,
[categories.bend](categories.bend) for value-indexed membership, predicate
inclusion, intersection and checked admission,
[json.bend](json.bend) for bounded JSON decoding/rendering, and
[theory.bend](theory.bend) for domain-independent imported theory adapters.
The generated certificates and regeneration instructions are documented in
[theory/README.md](../theory/README.md); normal builds do not require Rocq or MetaRocq.

Library proof providers stay beside their definitions. The application proof
reading guide is [docs/proofs.md](../docs/proofs.md); domain correspondence and
production bindings belong to the models that consume the library. Do not add a
parallel general algebra hierarchy or import concrete feature state here.

Categories accept arbitrary predicates rather than a closed list of labels.
`Membership` carries an actual value and evidence indexed by that value;
`Intersection` carries two properties of the same subject. Inclusion supplies an
implication for every subject. These packages use affine `Type`, so operation
functions and live evidence need not be stored in `Data` or copied.

`holds` lifts a Boolean predicate over a data candidate. `admit` checks that
predicate on the candidate and returns membership only on success;
`admit_intersection` checks both predicates on that same candidate. The checked
helpers require equations connecting their observations to the actual candidate.
Their intrinsically filled evidence permits use in production models without
importing separate proof providers. Domain predicates and rejection behavior
remain with their owners. This library does not require wrapping every Boolean
branch or replacing already verified pure constructions.

For context-bound results, follow `Construction`, `constructed_by` and `construct`
in [categories.bend](categories.bend). Root operational packages additionally use
`Implementation` to pair specification and operation bundles; their fieldwise
faithfulness obligations belong to [MODEL.bend](../MODEL.bend).
