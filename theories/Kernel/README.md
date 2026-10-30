# Task runtime and history

Start with the product operation in `Packet.packet` and its owning definitions.
The host keeps the world opaque: it starts from `initial` and replays accepted
input records through the packet entry. Constructors own the state properties
needed by those operations.

`TaskChange` restricts ordinary edits to lifecycle, queued input and appended
history. `OperationEvent` interprets each hook, approval or tool outcome into
its receipt and continuation together. `TicketedRequest` allocates a request's
ticket and installs its receiver in the same operation. New operations should
reuse these constructors before introducing a separate proof obligation.

`CommandPayload` distinguishes an editor proposal from an admitted command.
MetaRocq generates both from the owning declaration. Execution payloads retain
`ArgumentDeclaration` values, including nested structure and bounds; their
`*_admitted` projections feed content, settings, graph and authority
interpreters directly. JSON encoding belongs at a transport or display
boundary. A new command does not provide a second parser or remember a set of
per-field proof obligations.

Task input selects a `Tasks.input_target` from the actual task reference and
resource observation. Preparing resources can retain queued input; failed
creation cannot admit new input, a side or a fork. Creation and fork plans own
workspace selection before constructing tasks. Archiving consumes the current
resource-borrowing relation. Stop, interrupt, unfreeze and execution settings
retain their own lifecycle and authority rules; only actual execution requires
the resource to be ready. Callers reuse these operations without a second
command-enumeration gate or a scan of the resulting world.

`DecisionComposition` gives scheduling and delivery transformations read-only
access to the initiating reply. The shared interpreter retains that reply;
transformations return only their next world and effects. Its narrower
maintenance language permits only appended effects, so feature maintenance also
retains earlier emissions. Scheduling may withdraw requests that cannot be sent
or were cancelled. Both forms compose without a per-step reply theorem.

`Delivery` owns the actual serialized output budget. `Dispatch` cancels stale
requests and freezes their final context. The packet selects a complete
business outcome before adding notifications and the journal receipt. A delivery
failure cannot partially commit that outcome.

External manual forks and native forks commit their controlled task birth before
independent scheduling. `ForkConstructionProofs` covers the unique ancestry and
capacity requirements; `ForkCommitProofs` and `NativeForkCommitProofs` cover the
durable continuation. See ADR 0065 for the commit boundary.

`JournalProofs` covers receipt order and input replay. Extraction, physical
journal persistence and effect execution have their own external boundaries.
Generic construction properties belong with their interpreter; feature proofs
cover the additional behavior required by that feature.

For reasoning policy, start with `Domain`, `Codec.parse_reasoning_policy`, and
`Reasoning.next`. `ReasoningProofs` states the requirements on the actual
scheduler, context callbacks, generation history, and public evaluator preview;
`Features.CompactionProofs` connects manual summary cancellation to that same
context boundary. `ReasoningView` is an evaluator transport preview, while the
retained task history remains the source for model requests. Host tokenizer
budgets and the evaluator's choice quality remain separate execution boundaries.
