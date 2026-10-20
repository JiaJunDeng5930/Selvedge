# ADR 0034: open categories and value-indexed construction

## Context

[ADR 0032](0032-operational-model-abstraction.md) established operational packages
with abstract carriers and universal properties bound to production operations.
[ADR 0033](0033-button-category-inclusion.md) applied open predicates, inclusion
and intersection to authored button observations. The same relationship between
an actual value and its properties is needed across operational interfaces and
domain admission boundaries.

A detached Boolean argument cannot itself identify the candidate whose admission
it authorizes. Closed semantic category labels would also make simultaneous
properties and client extensions depend on a central enumeration. Syntax sum
types remain useful vocabulary, but their alternatives do not define semantic
category inheritance.

## Decision and reasons

Use [bendlib/categories.bend](../../bendlib/categories.bend) for shared membership,
inclusion, intersection and checked admission. A category is an open predicate
on a subject. Inclusion supplies implication for every subject; intersection
requires both properties on the same subject. `Membership` stores the actual
subject with dependent evidence, preserving that connection through construction
and use. Domain predicates remain in their owning model entries.

Separate operational functions from their category evidence while keeping evidence
indexed by those actual functions. Operation records and witnesses are affine
`Type` values. They cannot be placed in `Data` or freely duplicated. Generic
clients consume memberships and operations while the existing existential
packages continue to hide state and result carriers.

Keep domain vocabulary and wire candidates transparent. A semantic admission gate
checks its predicate on the candidate; its successful continuation requires the
corresponding membership and consumes that admitted value. Checked helpers require
the equation relating a Boolean observation to that candidate. They cannot accept
an unrelated permission bit. The shared admission definitions contain their
evidence intrinsically and need no proof-provider import on their own.

Retain pure calculation helpers where unconditional, input-wide computation
equations need a subject. Their equations do not make them alternative semantic
admission interfaces. Ordinary internal classification and already verified pure
construction do not need forced wrappers around every Boolean. Clients can reuse
such constructions or classifiers without proving every individual instance.

The migration also exposed that `hook_record_order` compared `record` with
`checked`, which shared its implementation and therefore could not independently
constrain plugin-identity rejection. Its requirement now computes the expected
conditional behavior independently with `D.plugin_same`, including refusal when
plugin identities differ. The calculation helper remains a computation subject
for the law, rather than a new authorization entry. This strengthens the
verification requirement without treating the previous equation as an independently
reproduced runtime failure.

Controlled button, input, movable-source and native recovery producers state
requirements on their actual emitted nodes. This extends the authored-button decision without changing
the historical scope or validation claims of ADR 0033. Directory placement alone
is not representation hiding, and this decision does not hide every raw
constructor.

Input observations retain an explicit native request and evidence that it equals
the canonical request derived from the construction inputs. Both the public input
producer and membership factory use the same source producer. Passing an arbitrary
request together with its canonicality evidence to the generic input theorem
avoids expanding the fixed compiler's 48-bit capacity computation during dependent
`Type` conversion. This changes the proof presentation, while retaining the
capacity limit, content fields and complete native policy requirements.

Production button, input, movable and recovery consumers now call the membership
factories and extract their constructed nodes. Complete constructor equations
bind each result to the raw owner calculation at the caller's exact inputs,
preventing unrelated valid membership from satisfying the consumer's source
correspondence. The raw calculations retain their specification role.

The fixed compiler checks live references at definition events: an ordinary
library constructor calling still-unfilled evidence is rejected. Independent
construction providers therefore fill the owning constructor laws before the
production model's live consumers. Their leaf dependency closures avoid cycles
through the assembled models. This is an ordering constraint, not a namespace
resolution failure or a reason to weaken the contracts.

Certified construction libraries have a different dependency role from the
assembled system proof. An earlier `construction_providers` registry in
`components.json` allowed these libraries through a blanket model-to-proof import
restriction. That restriction and its exception registry have since been removed:
provider discovery and unique law bindings already locate the required evidence,
without prescribing provider filenames, directories or one contract per provider.
Production models consume the constructions through their actual dependencies;
the compiler still checks complete caller-source correspondence, foreign
boundaries and absence of proof holes. The formal and focused fixture results in
the exploration notes describe the earlier registry's adoption.

Recovery uses the independent runtime utility provider. Its source replaces only
recovery children through the proved factory and shares `source_with_recovery`
with the raw owner calculation, preserving the existing diagnostic and layout
computation. The native `@browser/retry` protocol remains the operational behavior.

Incoming application worlds are checked with `I.world` before loading. Invalid
worlds retain the application through the exact refusal path. This replaces a
previously trusted input boundary; it is not evidence of a reproduced historical
failure. Complete decision, invocation and committed refinement, including
rejection outcomes, remain obligations of production proofs.

## Verification boundaries

The executable model and production proof entries state and check the intended
properties; this ADR does not duplicate their law definitions. Isolated compiler
checks establish only the closures they actually check. The whole-project check and test results belong
to [the exploration notes](../bend2-exploration.md). The pinned production proof
check includes input-content and exact-viewport construction obligations; the
earlier project check, locality tests and complete integration suite passed as
recorded there. The production provider adoption now has its own formal and
focused fixture evidence, recorded separately from those historical runs. Each
result covers its own boundary rather than inferring integration success from
proof acceptance alone.

Proofs describe produced values and committed effects. They do not establish
physical browser layout, focus or interaction, nor execution of external effects
by the host. Focused compiler and integration tests retain those distinct
responsibilities in [the evidence map](../../tests-bend/README.md).
