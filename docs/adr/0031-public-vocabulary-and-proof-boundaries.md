# 0031: Public vocabulary and proof boundaries

## Context

Presentation clients exchanged scenes, nodes and gestures through modules that
also computed views and performed interaction. Importing a public type therefore
pulled implementation dependencies into clients that only needed vocabulary.
Validation computations in requirement modules similarly forced production code
to import open laws. Consolidating every proof in a directory into one provider
then made unrelated evidence share dependency order and private helpers.

## Decision and reasons

Separate the public vocabulary from the decisions that implement it. Scene
vocabulary belongs to presentation `MODEL.bend`; node, gesture and surface
vocabulary belongs to `SURFACE.bend`. `VIEW.bend` generates scenes and
`PROGRAM.bend` realizes surfaces. Interaction `TYPES.bend` supplies input, state
and observation types; `STATE.bend` retains their computations. These boundaries
let vocabulary clients remain independent of implementation choices without
introducing wrappers or compatibility exports.

[Parnas's original modularity paper](https://prl.khoury.northeastern.edu/img/p-tr-1971.pdf)
provides the rationale for organizing modules around design decisions that can
change independently. Here the vocabulary and its implementation are separate
such decisions. The paper informs this choice; it is not evidence that this
project's implementation or verification has completed.

Place executable validation with the production computation that owns it.
Contracts can refer to that computation without production clients having to
import a law-bearing module. This direction avoids a dependency cycle between
requirements, computations and their evidence.

Group contracts and proof units by complete responsibility. Geometry, allocation,
measured size and its source correspondence, rendering, semantic scenes and
surface interaction warrant distinct reasoning boundaries. A single property
does not automatically warrant a file, and a directory does not automatically
warrant one combined proof. Concept `PROOF.bend` entries retain necessary aggregate
evidence; the global proof entry imports all production providers. Preserve
independent evidence when its clients require an earlier dependency boundary.

[Bend's law and qualified-definition syntax](https://github.com/bendlang/bend/blob/main/guide/GUIDE.md)
binds evidence to a module's law declaration. Moving a provider must preserve
that identity, its full proposition and its consumers. File organization does
not make any required evidence optional.

## Tradeoffs and evidence boundaries

The additional public entries make import intent explicit, while cohesive
contracts and proof units reduce navigation between isolated properties. Moving
private helpers requires updating their actual consumers and preserving proof
dependency order. Executable definitions and contracts remain authoritative;
documentation supplies reading directions and reasons rather than another
property catalog.

Source ownership checks and compiler proof checks establish their respective
boundaries. They do not establish the behavior of concrete browser effects or
host execution. Focused boundary and end-to-end checks retain those obligations;
this decision records no final file count or completed validation result.
