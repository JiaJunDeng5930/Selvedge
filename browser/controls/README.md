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
actual authored source node. `Inclusion` means that, for every observation,
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
or that a final browser control is physically centered. The runtime recovery
retry button belongs to its separate native recovery protocol in
[browser/runtime](../runtime/README.md).
