# ADR 0042: construct context kinds from executable definitions

## Context

ADR 0041 unified context history events, but adding a kind still required cases
in source observation, patching, encoding and provider rendering. Each case
repeated facts about the kind's identity and fields. A shared event constructor
therefore did not provide a reusable way to define another context kind.

The useful extension operation is to define another observed text or metadata
record, then reuse the existing guarantees about accepted changes and history.
That operation should not require repeating those guarantees in a new proof or
coordinating a second schema in JavaScript.

## Decision

Use a small executable definition language with text and record constructions.
Definitions select from shared observation and field-projection operations. The
kernel supplies their descriptors to the host, which interprets those operations
without identifying concrete context kinds. One assembly entry selects the
definitions admitted by production decoding.

The generic construction family supplies properties of the actual snapshot,
patch and history operations for each definition. Runtime definitions remain
data; production proof packages bind their operations to the shared laws. This
keeps proof providers out of the runtime import closure and lets another
definition reuse evidence without carrying proof closures in persisted state.

Keep provider translation independent of the concrete assembly. Its generic
decoder checks the self-describing structure, while kernel admission checks the
registered definition. This allows a newly assembled kind to use the same host
and provider implementation without weakening kernel acceptance.

Every retained concept must affect an operation or a consumer's decision.
Identity targets changes; field declarations restrict admissible values and
edits; source declarations determine observations; scope determines retirement
when the workspace changes. Semantic descriptions tell the model how content
applies to its task. Revisions protect the machine's patch baseline and are
omitted from model-facing text because the model does not use them to apply
edits. The original value and explicit edits remain the model's usable history.

## Consequences

Adding a kind that uses existing observation operations changes its definition
and assembly. Introducing a new external observation operation still requires
an interpreter implementation and boundary validation; the construction language
does not claim to implement arbitrary new effects from declarations alone.

The extension fixture exercises another text kind and a record with different
metadata fields through actual compiled execution, file observation and provider
translation, with generic sources and proofs frozen. This tests the intended
extension operation separately from universal production proofs.

The changed representation has one current persisted format. Superseded values
fail validation; no compatibility decoder is introduced.
