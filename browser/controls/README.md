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

Property recognition is produced by experience's `property_recognition_summary`:
it retains the original Property, principal Subject/value and optional dependent
Subject/value. `property_summary_text` projects that same observation for Full or
Compact and authors an indivisible horizontal unit. Principal and dependent
captions use the same font and line box; secondary foreground expresses
dependency while keeping one measured baseline. The whole supporting-controls
region selects one presentation form from actual preferred and available width.
Every member consumes that form, including unavailable members; there is no
per-entry fallback. Compact removes dependent details and retains each principal
identity. Permission identity follows actual effective access; inactive sandbox
limits are absent under Full access. Standalone `property_summary` remains the
complete semantic/help caption, independent of visual projection.

[NAVIGATION.bend](NAVIGATION.bend) owns transient row attention, exact owner
admission, menu ownership and navigation content roles. `PROGRAM.Context` carries
that vocabulary and derives descendant depth when entering a project group.
`PROGRAM.NavigationRow` carries independent auxiliary exposure and owner feedback
values; the latter excludes the always-visible auxiliary rule for touch devices.
[SIDEBAR.bend](SIDEBAR.bend) owns authored rows, slots and hierarchy collections.
`MODEL` loads [navigation-proof.bend](navigation-proof.bend) before consuming
`construct` and `construct_collection`; the policy entry remains independent of
source and design types to avoid a dependency cycle through `PROGRAM`.
Its observation predicates bind complete source correspondence, original native
command fields, full row allocation and shared leading, caption and trailing axes
to the actual constructors. `SingleAction` carries one captured native command;
`ProjectActions` retains the four independently captured project commands.
`CONTRACT.NavigationRequirements` binds the production context, exposure and
command-preservation calculations; `PROOF` supplies its provider.

Navigation titles retain their complete accessible text and command binding while
their stretch targets align captions at the leading edge. Project membership
controls indentation; the separate collection of tasks without a project keeps
its own heading and does not acquire project depth.

`SURFACE.ActivityRow` preserves descendant decision, field and command meanings
while `MODEL.activity_row` supplies their common physical organization.
`SHELL.activity_width` and the actual button/input constructors consume observed
activity font parameters, so preferred surface demand comes from authored
content rather than the activity's name.

`NAVIGATION.leading_geometry` distinguishes the visual rail from its independent
command target. `SIDEBAR.aligned_sidebar` observes the complete sidebar's visual
rails, while a separate centered envelope reserves the independent target and
prevents it from overlapping the title command. The enclosing navigation region
owns the root edge; row padding does not add another edge. Target clearance is
paid from the visual-to-caption gap once, so a larger hit area cannot silently
move every visible icon and caption farther inward. Descendant indentation starts
from these same axes. `leading_frame_preserved` and `row_edge_preserved` observe
the actual authored allocation, target dimensions, centering and row frame in
addition to the retained command, whole-row and hierarchy evidence.

The geometry/source constructor and its complete observation evidence share an
explicit capacity parameter. Fixed public entry points instantiate the existing
layout capacity; generic evidence compares the real constructor operations
without repeatedly normalizing that closed numeric bound. This keeps the
runtime bound and full production obligations unchanged.
