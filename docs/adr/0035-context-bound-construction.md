# ADR 0035: context-bound construction for complete operation consumers

## Context

[ADR 0034](0034-open-category-construction.md) established value-indexed
membership and checked admission. A local property such as a valid
`ProjectGrant`, a matching callback origin, or an available execution grant does
not establish that a supplied result is the resolution of the original request
in the current state. A result can retain that property while being paired with
a different world, owner, task or operation.

The existing universal calculation laws already describe complete decisions,
including state, replies and effects. Those laws must remain the domain
requirements. Their existence alone does not make a consumer of a separately
supplied result and world require evidence that those arguments belong together.

## Decision

Use the shared `Construction` mechanism in
[bendlib/categories.bend](../../bendlib/categories.bend) to carry the source
request and its result together. Each owning constructor captures the original
request and state and supplies `constructed_by` evidence equating the result to
the canonical resolver applied to that captured request. The complete public
consumer accepts this membership and extracts its context internally. It cannot
be supplied a second world independently of that evidence.

Canonical constructors provide the equation for arbitrary requests, so callers
do not write a new proof for every instance. The original input-wide calculation
laws remain the generic proof of domain behavior; construction and consumer
correspondence connect callers to that calculation rather than duplicating or
weakening its requirements. Component assembly retains ordinary data commands
and constructs and consumes their proof-bearing membership at interpretation.

Root operational packages also pair an explicit specification bundle with the
actual operation bundle. Pointwise faithfulness covers every field of
`ExecutionOperations`, `ApplicationOperations` and `DisplayOperations`, including
state, reply, effect and observation projections. Requiring those equations
alongside the existing semantic categories prevents a package from satisfying
one projection's requirement while exposing a mismatched operation elsewhere.
The obligations and canonical bundles are defined in the root
[MODEL.bend](../../MODEL.bend) and its production proof providers.

## Consequences and limits

Approval origin and execution availability helpers retain their local duties.
They are not promoted into complete authority over a decision. Board launches
continue through feature assembly and ordinary core task creation; this choice
does not move task scheduling or policy into the board.

Public command and observation vocabulary remains transparent. Raw
`*_calculation` functions remain available as implementation and proof
primitives. Bend does not enforce module encapsulation here, so this decision
neither makes imports inaccessible nor claims that all underlying functions have
been removed. The advertised complete interfaces are the constructors and their
membership-consuming operations, whose entry paths are listed in the owning
READMEs.

The design draws on the distinction between properties of values and
specifications of computations explained by the official F* tutorial's
[Primitive Effect Refinements](https://fstar-lang.org/tutorial/book/part4/part4_pure.html).
The connection is conceptual: Selvedge expresses explicit construction equations
and operation laws in Bend, without implementing F*'s effect system or weakest
precondition inference.

## Validation

The existing complete domain laws and the generic consumer correspondence
equations establish behavior against the captured source context. Production
assembly must consume the constructed memberships, and existing native
integration tests cover normal cross-boundary behavior. The construction-source
relation remains part of the semantic contract.

Successful compiler and integration results must be established separately;
this decision record is not validation evidence.
