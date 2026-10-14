# Appearance

Owns design, typography, font observations and painting behavior.

Start with [MODEL.bend](MODEL.bend), [PROGRAM.bend](PROGRAM.bend), [CONTRACT.bend](CONTRACT.bend), [PROOF.bend](PROOF.bend).

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.

`TYPOGRAPHY.information_role` owns `NavigationCaption` typography. The appearance
consumer assigns its text role before heading styling; `CONTROLS` applies its
secondary foreground when authoring the owned text.

Project-header feedback resolves the owner feedback value into actual Chrome in
`MODEL.final_style`, because native state channels are consumed only by controls.
The owning contracts bind that final background and preserve the remaining style
fields.
