# ADR 0060: Construct domain authority before host execution

## Context

The migration review found several failures at boundaries that individually
accepted valid data. Fork postprocessing confused later scheduler births with
the children it owned. Resource inheritance was treated as resource creation.
An archived task's resource gate also prevented its accepted tool result from
settling. Rechecking the complete candidate at the end could reject an incorrect
composition, but did not establish that the intended operation would succeed.

Independent string switches also allowed command ownership, effect callbacks
and physical interpreters to diverge. Audio admission exposed that risk through
a consumer reading a field absent from the rejected result.

## Decision

Keep command declarations independent of worlds and feature implementations.
Derive the command sum and its complete handler record from those declarations.
The final assembly must supply every handler. Put an operation's implementation
in its owning module, including the local and cloud cases of execution settings.
This makes a missing interpreter a construction error rather than a runtime
fallback.

Share effect wire declarations with callback classification and generated
TypeScript discriminated unions. Check the actual host consumers with strict
TypeScript; declarations alone would leave the observed consumer error intact.
Retain exact domain numbers in that interface instead of narrowing every natural
to a JavaScript number. Transport counters with a bounded contract still have
separate, exact admission.

Use domain-specific constructions where the same authority is otherwise copied:
creation plans distinguish inherited bindings from provisioning, fork births
carry their exact child references, and ticketed requests install pending state
and emit its request together. Execution and result settlement have different
lifecycle and resource requirements. Shared hook transformations supply both
production results and their specification.

Manual fork receipts need a fresh identity within the retained task history.
A ticket-derived prefix alone can equal an arbitrary provider call ID and make
the receipt appear to complete that call. Construct freshness from the actual
retained identifiers rather than reserving an undocumented provider namespace.

Generate optional plugin notifications once, from the admitted final state and
business effects. They are an output observation, not a business effect that a
feature may insert and a later validator must reconstruct. Their optional size
budget must not discard the business decision.

Host control transitions use the same extracted definitions as their proofs.
The host reports physical observations and interprets primitive actions. Large
process output remains in the physical scalar buffer: the pure controller owns
the retained count and absolute cursor and supplies slice instructions. Sending
the entire tail through JSON for each chunk failed the existing throughput
acceptance criterion without strengthening the policy boundary.

## Consequences

The Rocq kernel checks domain constructions and their stated theorems. Extraction,
lossless JSON admission, JavaScript execution, SQLite durability and external IO
remain distinct boundaries. Public tests cover those actual boundaries; they do
not replace a positive theorem about a composed domain operation. Existing
Reasoning and TaskGraph scenarios stay until their relevant compositions have
that guarantee.

Keep global world and cross-step admission where later domain operations can
change history, settings or feature references. A local request's frame does not
establish those final relationships. Remove the reasoning request's duplicate
model field instead: its model is the snapshot's profile by construction, so
that self-comparison needs no runtime check. The comparison with the final task
profile still protects a relationship across steps.

The archived-settlement theorem permits a well-formed background under explicit
scheduler and feature frames. [ADR 0065](0065-commit-fork-before-independent-scheduling.md)
supersedes the initial finite fork proof with general constructor preservation
and a separate durable fork transaction before independent scheduling.

Corrected decisions and final effect encoding change journal replay. Format 6
rejects previous formats before replay instead of trying to reinterpret them.
There is one current data format.

The resource, audio, remote and transaction protocols explain their specific IO
assumptions in ADRs 0061–0064. This decision does not promise exactly-once
arbitrary external execution.
