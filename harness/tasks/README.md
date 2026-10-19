# Task storage

Updates tasks through an abstract carrier. Its contract also describes initial context order and selected fork history independently of the production append operations.

Start with [PROGRAM.bend](PROGRAM.bend), [CONTRACT.bend](CONTRACT.bend), [PROOF.bend](PROOF.bend).

[side-contract.bend](side-contract.bend) defines side conversation snapshot and
return-content meaning. [side-conversation.bend](side-conversation.bend) constructs
the fresh child and the quoted return transcript; [side-proof.bend](side-proof.bend)
binds those operations to the required child and ordered content projection.
Administrative side contexts and tracked parent lifecycle edits never enter the
returned content. Returned records remain quoted data in ordinary user input.

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.
