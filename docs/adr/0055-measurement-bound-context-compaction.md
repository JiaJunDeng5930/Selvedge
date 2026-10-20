# 0055: Bind context compaction to captured input and append-only history

Status: accepted

## Context

The previous feature separated a constructed meaning from its realization, then proved many equalities between them. Those equalities did not independently establish that a provider result could replace only the history it measured. A count or scope observation becomes stale when history, settings, tool definitions, or callable capabilities change. A current invocation identity alone does not establish that a returned representation is usable by the next provider.

## Decision and alternatives

Use ordinary Gallina data and functions for this domain. The existing command declaration mechanism already supplies public commands. A separate compaction DSL would add declarations, an interpreter, and proof obligations without removing another independently maintained domain description. Controlled artifact and budget constructors do remove repeated validity facts, while external JSON still requires actual admission.

Reuse one context-selection interpretation for provider requests and compaction. Independent implementations would let measurement and execution disagree about native scope, fixed task context, images, or the retained suffix. Bind observations to their captured input and validate the current suffix before adoption; ticket equality alone is insufficient when a task can evolve during external work. Manual compaction reuses the existing context-observation operation because bypassing it would measure an outdated workspace view.

Append replacement records rather than deleting captured history. Destructive adoption would lose provenance and make later scope changes depend on material already discarded. The retained history also gives the validation rule an independent source boundary. A response can therefore be rejected without reconstructing the pre-compaction state.

Keep computational definitions separate from proof modules. Replace implementation-to-itself equalities with positive public-entry behavior and independent constraints on history preservation, callback authority, request selection, and time. These properties exclude specific violating implementations; they do not establish the factual quality of a generated summary or whole-application correctness.

Use an accumulator-based shared list prefix rather than reducing input limits or changing compiler stack settings. A real 320 KiB Unicode history overflowed the extracted recursive map, and a configurable large chunk can exceed the same stack through the ordinary list prefix. The shared prefix has a checked refinement to the standard operation, so this choice addresses execution cost without changing Unicode boundaries or the accepted model window.

## Trust boundary and consequences

Following Rocq's distinction between [kernel checking and extraction](https://rocq-prover.org/doc/v9.2/refman/addendum/extraction.html), the checked statements constrain Gallina computations. OCaml extraction, native runtime mappings, JavaScript compilation, and host IO remain trusted execution components. Provider token counts, scope identities, output limits, model summary quality, clock observations, and network delivery remain external observations or assumptions. A typed budget does not turn an external count into a static guarantee.

The migration intentionally corrects demonstrated paths: a future activity boundary is rejected rather than saturated to the present; core operation-result records settle their calls; unsuccessful context observation cannot start manual compaction; measured selection reaches the actual model request; and large valid Unicode input must execute without recursive-list stack overflow. Valid stale completions retain the existing outer input classification while the compaction handler gives them no authority over its own history or effects. No claim of whole-application acceptance follows from this block's local proofs or probes.
