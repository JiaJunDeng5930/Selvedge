# Controls

Composes authored controls and surfaces and constrains their content, containment and interaction.

Start with [MODEL.bend](MODEL.bend), [CONTROLS.bend](CONTROLS.bend), [CONTRACT.bend](CONTRACT.bend), [PROOF.bend](PROOF.bend).

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.

For icon-only actions, use `AuthoredControls.IconButton` and
`icon_button_source` in [CONTROLS.bend](CONTROLS.bend). The family supports
`icon_button_replace_icon` and `icon_button_resize` without accepting arbitrary
layout or offset fields. Its universal interpreter obligations belong in
[CONTRACT.bend](CONTRACT.bend); callers do not supply instance proofs.
Interpret a changed value with
`icon_button_source(icon_button_resize(icon_button_replace_icon(button, icon), geometry))`.
The [compiler-boundary client](../../tests-bend/icon-button-construction.test.mjs)
shows construction and this composition without listing instance obligations.
[ADR 0033](../../docs/adr/0033-controlled-icon-button-construction.md) explains
this limited construction experiment and its geometric and browser boundaries.
