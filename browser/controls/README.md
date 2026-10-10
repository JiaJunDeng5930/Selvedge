# Controls

Composes authored controls and surfaces and constrains their content, containment and interaction.

Start with [MODEL.bend](MODEL.bend), [BUTTONS.bend](BUTTONS.bend),
[PROGRAM.bend](PROGRAM.bend), [CONTRACT.bend](CONTRACT.bend),
[PROOF.bend](PROOF.bend). [CONTROLS.bend](CONTROLS.bend) supplies shared authored
content and attribute helpers.

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.

## Authored buttons

[BUTTONS.bend](BUTTONS.bend) is the public category and construction entry for
regular scene action buttons. `PROGRAM.Button` is the typed construction syntax;
`Representation.Action` carries that value. All four existing action meanings
(`Activate`, `ComposerAction`, `PanelToggle` and `Choice`) use this family through
`MODEL`. Face, behavior, geometry, placement and feedback remain explicit inputs.
Help is derived from the final face, availability, feedback and declared name by
`PROGRAM.button_help`; callers cannot independently supply a stale help value.

A category is a predicate over an `Observation` of the construction inputs and
actual authored source node. The shared [categories library](../../bendlib/categories.bend) supplies membership,
inclusion and intersection. `Inclusion` means that, for every observation,
membership in one predicate implies membership in another. `Intersection` carries
both memberships. Authored buttons belong to several common categories at once;
icon, choice and picker categories add their face-specific observations and retain
those common memberships through inclusion. These predicates are open to client
extensions rather than a closed enumeration or a class inheritance hierarchy.
The construction evidence refers to the actual `BUTTONS.source` function, so a
category label alone does not establish membership. Ordinary construction takes
typed button syntax through `BUTTONS.source`; `MODEL` does not import the proof
provider. The universally quantified `construction_evidence` binds category
membership to that actual function. Proof clients use `construct` and `Membership`
after loading the provider or root proof, without making that package part of the
production model path. Icon membership also observes the sole emitted glyph and
its inner main/cross alignment, with `icon_glyph_centered` exposing the inclusion
into `glyph_centered`.

The obligations cover the emitted node's binding, declared name, availability,
policy attributes, content and geometry policy. They do not establish that an
arbitrary declared name is nonempty, that arbitrary content fits every allocation,
or that a final browser control is physically centered. The native recovery retry
button has its own actual-source category entry in
[browser/runtime/frontend-utility.bend](../runtime/frontend-utility.bend), with
production evidence in [runtime/PROOF.bend](../runtime/PROOF.bend). Its native
`@browser/retry` protocol remains distinct from ordinary action-button syntax.

## Source construction boundaries

The controlled producers in [MODEL.bend](MODEL.bend) and
[PROGRAM.bend](PROGRAM.bend) also describe input and movable-source requirements
against their actual emitted nodes. Transparent construction syntax remains
available; semantic membership is evidence about the construction, rather than a
label attached to syntax. Reusing a verified producer supplies its established
properties without a new proof for each instance.

Input observations carry an explicit `InputFieldRequest`. Canonical request
evidence relates that request to `native_input_request`; the actual public input
producer and membership constructor share `input_source_request`. This preserves
the complete content and native policy obligations while keeping the request
available to generic proof clients. `construct_input` retains its four arguments.

These construction boundaries do not hide every raw source constructor. The root
production proof check passes with the pinned compiler, including input-content
and exact-viewport obligations for all 14 widgets; the current check and test
status is recorded in [the exploration notes](../../docs/bend2-exploration.md).
Physical browser layout, focus and interaction still require external evidence.
