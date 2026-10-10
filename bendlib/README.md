# Shared Bend library

This directory contains reusable component frames, parameterized effects, equality,
JSON and imported list, finite-map and relation theory. Domain behavior belongs to
[harness](../harness/README.md), [features](../features/README.md),
[interaction](../interaction/README.md) and [browser](../browser/README.md).

Read [component.bend](component.bend) for local state with an opaque remainder,
[effects.bend](effects.bend) for parameterized effect payloads,
[json.bend](json.bend) for bounded JSON decoding/rendering, and
[theory.bend](theory.bend) for domain-independent imported theory adapters.
The generated certificates and regeneration instructions are documented in
[theory/README.md](../theory/README.md); normal builds do not require Rocq or MetaRocq.

Library proof providers stay beside their definitions. The application proof
reading guide is [docs/proofs.md](../docs/proofs.md); domain correspondence and
production bindings belong to the models that consume the library. Do not add a
parallel general algebra hierarchy or import concrete feature state here.
