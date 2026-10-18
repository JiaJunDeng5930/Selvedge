# Conversation meaning

Defines provider-independent conversation observations and binds them to production presentation.

Start with [MODEL.bend](MODEL.bend), [PROGRAM.bend](PROGRAM.bend), [CONTRACT.bend](CONTRACT.bend), [PROOF.bend](PROOF.bend).

[CODEC.bend](CODEC.bend) owns serialization of committed messages. Endpoint input
selection belongs to [context](../context/README.md), so observing the conversation
does not replace its original records with a compressed input.

[TITLE.bend](TITLE.bend) owns the shared task-title prompt, structured output
schema, input budget and output normalization. The independent
[titles feature](../../features/titles/README.md) owns background requests and
saved names; these names do not change conversation history.

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.
