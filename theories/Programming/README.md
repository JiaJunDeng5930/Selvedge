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
| Projections and object handlers | [ArgumentProjection.v](ArgumentProjection.v), [SchemaProjection.v](SchemaProjection.v), [ObjectMethod.v](ObjectMethod.v) | A projection selects a declared source field; handler arguments retain the declaration's value types. |
| Command construction | [CommandFields.v](CommandFields.v), [CommandDeclarations.v](CommandDeclarations.v), [CommandPayload.v](CommandPayload.v) | Internal shape, external admission, host observation and typed dispatch come from the declared command. Concrete command vocabularies stay in Kernel. |
| Callback and request protocols | [Callback.v](Callback.v), [Variant.v](Variant.v), [InputRoute.v](InputRoute.v) | Framing, branch values, correlation coordinates and receivers are derived from the selected declaration. A domain supplies its own callback catalogue and diagnostics. |
| Named declarations and choices | [DeclarationRegistry.v](DeclarationRegistry.v), [FiniteChoice.v](FiniteChoice.v) | Construction requires distinct names; lookup reaches each registered entry, including additions, without shadowing previous names. |
| Observed values and constructor views | [OptionObservation.v](OptionObservation.v), [Constructor.v](Constructor.v) | Continuations retain the actual observation equality. Constructor views derive their projection; complete-case recognition carries its stronger law. |
| Local updates | [Focus.v](Focus.v), [Receiver.v](Receiver.v) | A focus retains the unwritable remainder; receiver paths derive address, lookup and installation from the same structure. |
| Request ownership and completion | [RequestEnvelope.v](RequestEnvelope.v), [Completion.v](Completion.v) | Correlation and receiver selection come from retained requests. Terminal completion cannot reconstruct the pending state through this interface. |
| Task selection and birth | [TaskScope.v](TaskScope.v), [TaskBirth.v](TaskBirth.v) | A reference retains the task actually found in its source world. A prepared birth receives its fresh identity and preserves the other world fields. |
| Task edits and result updates | [TaskChange.v](TaskChange.v), [TaskResult.v](TaskResult.v) | Caller-supplied edits retain the task frame and append history. Result updates keep wake behavior coupled to pending context demand. |
| Issued requests and operation results | [RequestTypes.v](RequestTypes.v), [TicketedRequest.v](TicketedRequest.v), [OperationEvent.v](OperationEvent.v) | A request installs its receiver and emits its correlated effect together; one operation observation determines its receipt and continuation. |
| Decisions and commit composition | [CommandResult.v](CommandResult.v), [DecisionComposition.v](DecisionComposition.v), [CommitPacket.v](CommitPacket.v), [DeferredCommit.v](DeferredCommit.v) | Refusal carries no candidate update. Composition retains the initiating reply; maintenance also retains prior emissions. Commit construction finalizes the selected outcome. |
| Asynchronous resource results | [Resource.v](Resource.v) | Arbitrary request and result types share pending-only settlement, matching tickets and retention of the original request. |
| Error and budget composition | [Outcome.v](Outcome.v), [Metered.v](Metered.v), [MeteredProofs.v](MeteredProofs.v) | Error-aware continuations and traversals compose directly. Budget composition inherits non-increase from the supplied computations; the expression language keeps its own charging policy. |
| Shared presentation programs | [Presentation/Model.v](Presentation/Model.v), [Presentation/Surface.v](Presentation/Surface.v), [Presentation/Construction.v](Presentation/Construction.v), [Presentation/Composer.v](Presentation/Composer.v), [Graphics.v](Graphics.v) | Authors construct controls, surface trees and graphics with the existing typed actions, field owners and shared event interpretation. Pages and domain observations supply their concrete content. |

Proof providers sit beside their constructions. `SchemaProofs` and
`ProtocolProofs` retain their stated codec premises; `DeclarationRegistryProofs`,
`OptionObservationProofs`, `ReceiverProofs` and `CompletionProofs` constrain the
shared operations used by consumers. `Focus` and controlled declaration
constructors also carry laws in their definitions. Reusing an operation does
not require proving its shared law again.

The task constructions deliberately use `Kernel.Domain` and `Kernel.State`.
Their shared contracts quantify over the edits, channels, continuations or
prepared values accepted by those interfaces. Start, fork, lifecycle admission,
scheduling and individual commit plans remain domain operations that use them.
Keeping that concrete meaning avoids adding a second model of the task world.

The presentation constructions likewise retain the project's subject and action
vocabulary. `Presentation/SurfaceProofs` constrains their common event handling;
the domain page recipes, observations and browser interpreter stay at their
owners. The interactive Markdown language remains a product feature, using the
shared outcome, budget and graphics constructions where its semantics fit.

Ordinary collection, numeric and text algorithms remain in `Foundation`.
Concrete protocol catalogues and business rules remain with their domains.
Dependencies are tracked between source modules: this directory is an ownership
boundary for constructions, not a rule that every file must depend on a lower
directory. Keep computation independent of proof automation and requirements.
