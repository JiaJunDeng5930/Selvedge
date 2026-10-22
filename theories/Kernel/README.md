# Task runtime and history

Start with the product operation in `Packet.packet` and its owning definitions.
`WorldInvariant.world_valid` states the retained world requirements as named
checks over the actual runtime values. `well_formed` exposes their environment,
project, task, correlation and feature obligations separately.

`WorldInvariantProofs` establishes initial validity and the commit admission
contract: accepted candidates retain their exact state and effects; invalid
candidates restore the previous state and discard every effect. `PacketProofs`
instantiates preservation at the exported packet boundary, including scheduling,
notifications, output admission and the journal cursor.

`Journal` defines histories of that packet operation. `JournalProofs` proves
preservation for an actual history step, reachability, finite execution and
replay, in addition to receipt order and replay correspondence. The safety
results depend on packet preservation, rather than equality between two traces.

The kernel checks these propositions about the Gallina computations. Extraction,
JSON admission, physical journal persistence and effect execution have separate
validation boundaries. Inter-transition retention and effect authorization are
additional contracts; a well-formed candidate alone does not establish them.


For reasoning policy, start with `Domain`, `Codec.parse_reasoning_policy`, and
`Reasoning.next`. `ReasoningProofs` states the requirements on the actual
scheduler, context callbacks, generation history, and public evaluator preview;
`Features.CompactionProofs` connects manual summary cancellation to that same
context boundary. `ReasoningView` is an evaluator transport preview, while the
retained task history remains the source for model requests. Host tokenizer
budgets and the evaluator's choice quality remain separate execution boundaries.
