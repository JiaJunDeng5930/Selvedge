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
`Representation.Action` carries that value. The action meanings
(`Activate`, `SupportingControl`, `PanelToggle` and `Choice`) use this family through
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
category label alone does not establish membership. `MODEL` loads the independent
[button provider](button-proof.bend) before its live `Buttons.construct` and
`constructed_node` consumer. The raw `BUTTONS.source` remains the owning
calculation. Constructor correspondence equates the complete returned node with
that calculation at the caller's exact inputs; membership alone would not exclude
an unrelated valid node. The fixed compiler checks live references in definition
order, so the provider must precede this production call. Icon membership also observes the sole emitted glyph and
its inner main/cross alignment, with `icon_glyph_centered` exposing the inclusion
into `glyph_centered`.

The obligations cover the emitted node's binding, declared name, availability,
policy attributes, content and geometry policy. They do not establish that an
arbitrary declared name is nonempty, that arbitrary content fits every allocation,
or that a final browser control is physically centered. The native recovery retry
button has its own actual-source category entry in
[browser/runtime/frontend-utility.bend](../runtime/frontend-utility.bend), with
production construction evidence in the independent
[runtime utility provider](../runtime/utility-proof.bend). Its native
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
The independent [authored provider](authored-proof.bend) supplies the input and
movable factories and their evidence before `MODEL` consumes their constructed
nodes. Its helpers do not depend on the assembled controls model, keeping the
import closure acyclic. Complete constructor equations retain every caller
coordinate and the same raw calculation.

These construction boundaries do not hide every raw source constructor. Earlier
check results and the current validation status are recorded in
[the exploration notes](../../docs/bend2-exploration.md). The production provider
adoption passed the formal check and the focused original construction fixtures.
Physical browser layout, focus and interaction still require external evidence.

`CONTRACT.AuthoredShellRequirements` binds navigation placement and the complete
source styles of responsive toolbar and composer action groups. These groups use
layout's horizontal-or-vertical allocation. `property_current_values` and
`property_caption_wraps` bind property face text to its measured wrapping modes.

The actual native input request uses `CONTROLS.native_field_policy`: message
inputs start with the activity grammar's two writing lines, while other inputs
retain one line. The source policy factory retains positive ordered line bounds.
`layout/SOURCE.field_natural_height_at` combines that minimum, the resolved font
and bounded native measurements; appearance does not resolve a second writing
height. Property faces similarly reserve their operable glyph floor while
`layout/SOURCE.text_natural_demand` owns actual text demand.

Property summaries retain complete recognition units. Permission summaries place
filesystem, network and approval consequence phrases together when they fit and
stack the complete phrases in smaller content areas. Other summaries, including
model and reasoning, remain one complete caption. Their surrounding icons and
chevrons keep their authored dimensions.
