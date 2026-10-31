# Programming constructions

This directory owns reusable ways to construct programs in Selvedge. Use the
definitions here to inherit their existing guarantees. The engineering reason
and applicability rule are in
[Engineering.v](../../requirements/Engineering.v): choose a construction whose
semantics fit the domain. Its reuse scope may be arbitrary types or a particular
project domain; there is no requirement to fit every model into one paradigm.

## Existing constructions

| Construction | Start here | Guarantee and scope |
| --- | --- | --- |
| Constrained values and boundary admission | [Refinement.v](Refinement.v), [EncodedObject.v](EncodedObject.v), [JsonSchema.v](JsonSchema.v) | Retain the established constraint or compiled schema with the admitted value. The parser and external schema dialect remain in Foundation. |
| Declared records and arguments | [Schema.v](Schema.v), [ArgumentDeclaration.v](ArgumentDeclaration.v), [Arguments.v](Arguments.v), [DeclarationFields.v](DeclarationFields.v) | Field values, branches and codecs come from the same declaration; controlled construction retains field uniqueness and admission constraints. |
| Projections and command payloads | [ArgumentProjection.v](ArgumentProjection.v), [SchemaProjection.v](SchemaProjection.v), [CommandPayload.v](CommandPayload.v), [ObjectMethod.v](ObjectMethod.v) | A projection selects a declared source field; admitted payloads and handler arguments retain the declaration's value types. Command generation remains in Derive. |
| Named declarations and choices | [DeclarationRegistry.v](DeclarationRegistry.v), [FiniteChoice.v](FiniteChoice.v) | Construction requires distinct names; lookup reaches each registered entry, including additions, without shadowing previous names. |
| Observed values and constructor views | [OptionObservation.v](OptionObservation.v), [Constructor.v](Constructor.v) | Continuations retain the actual observation equality. Constructor views derive their projection; complete-case recognition carries its stronger law. |
| Local updates | [Focus.v](Focus.v), [Receiver.v](Receiver.v) | A focus retains the unwritable remainder; receiver paths derive address, lookup and installation from the same structure. |
| Request ownership and completion | [RequestEnvelope.v](RequestEnvelope.v), [Completion.v](Completion.v) | Correlation and receiver selection come from retained requests. Terminal completion cannot reconstruct the pending state through this interface. |

Proof providers sit beside their constructions. `SchemaProofs` and
`ProtocolProofs` retain their stated codec premises; `DeclarationRegistryProofs`,
`OptionObservationProofs`, `ReceiverProofs` and `CompletionProofs` constrain the
shared operations used by consumers. `Focus` and controlled declaration
constructors also carry laws in their definitions. Reusing an operation does
not require proving its shared law again.

Ordinary collection, numeric and text algorithms remain in `Foundation`.
Concrete protocol catalogues and business rules remain with their domains.
Dependencies are tracked between source modules: this directory is an ownership
boundary for constructions, not a rule that every file must depend on a lower
directory. Keep computation independent of proof automation and requirements.
