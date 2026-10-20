# ADR 0033: authored button categories and inclusion

## Decision

Use [BUTTONS.bend](../../browser/controls/BUTTONS.bend) as the public entry for
regular authored action buttons, with typed `PROGRAM.Button` construction syntax
and categories defined as predicates over actual construction observations.
Represent category inclusion as a universally quantified implication, and combine
memberships through intersections. Derive help from the final face and action
policy instead of storing independently authored help in the button syntax.

## Reasons

A single icon-button property would leave other ordinary action producers and
consumers outside the construction guarantee. The existing `Activate`,
`ComposerAction`, `PanelToggle` and `Choice` meanings already share the action
representation and authored source path. Moving this whole family gives those
paths one construction boundary while preserving their distinct policies.

Classifying observations permits one button to satisfy several categories
simultaneously. Predicate inclusion gives clients reusable evidence for common
requirements without adding a closed hierarchy of labels. Clients can add a
predicate or intersection over the same observation without changing the base
family. Evidence concerns the emitted source node as well as its description;
checking only a requested face would leave the actual output unconstrained.

The imported relation library exposes binary relation inclusion. A direct unary
predicate implication is the small domain specialization needed here; duplicating
a general relation algebra would introduce unnecessary proof maintenance.
Construction syntax remains an ordinary data value, and universal production
proofs supply its category guarantees without requiring callers to author proofs.

Help depends on face, availability, feedback and name. Keeping a separate help
field lets a transformation retain help for an earlier face. Derivation at the
construction boundary makes the current face determine that policy.

## Boundaries

The executable category predicates state the properties checked for production;
this ADR records why the construction and evidence boundaries were chosen.
The runtime recovery retry button has a separate activation and remount protocol
and remains outside the regular authored action family.

Declared-name retention does not prove a nonempty accessible name. Authored
geometry policy and centering do not prove arbitrary content fitting or final
browser pixel geometry. The compiler-client and mutation results for this change
are recorded in [the exploration record](../bend2-exploration.md); current test
responsibilities are in [the evidence map](../../tests-bend/README.md). Physical
browser behavior requires its own evidence.
