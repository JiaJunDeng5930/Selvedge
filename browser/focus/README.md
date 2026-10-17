# Focus

Owns focus state and the retention and dismissal behavior of browser controls.

Start with [MODEL.bend](MODEL.bend), [CONTRACT.bend](CONTRACT.bend), [PROOF.bend](PROOF.bend).

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.

The complete `DismissalRequirements.layer_children` equation retains the actual
activity-derived label alongside the original layer key, role, dismissal meaning
and content. Focus and outside/Escape ownership continue to use those actual
keys and occurrence values, independently of whether the activity needs an outer
heading.
