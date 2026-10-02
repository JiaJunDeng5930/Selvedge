# ADR 0030: Project and execution context

## Decision

Keep project context visible throughout ordinary work, while observing execution
space and permissions through their own product concepts. Render those concepts
from the Bend model at the DOM boundary.

## Reason

A project gives ongoing work its grouping and creation context. Making its normal
entry a management screen interrupts that work, so ordinary navigation and
inspection or configuration need distinct entries. Persistent project ownership
also helps users retain orientation while reading an individual task.

Project membership does not establish where an agent executes. Showing the
working folder and permissions independently avoids presenting a project name
as an execution contract. Draft configuration describes a prospective execution;
a submitted task has an admitted contract that must remain observable rather
than becoming an editable draft. Keeping those observations separate preserves
the distinction when projects change or explicit draft overrides remain active.

The DOM adapter executes Bend's declared controls and presentation. Reconstructing
project or execution behavior in browser JavaScript would create another source
of product meaning and could disagree with command admission and evidence.

Service-observed root guidance is trusted execution context, not a client-owned
HTTP field. A separate Bend request projection preserves the internal command
while respecting that ownership boundary. A refusal before journal submission
is definite failure; treating it as unknown would prevent correct draft recovery.

Transient notices must not replace the application shell or its focus targets.
Keeping the shell stable preserves control identity during submission and
feedback, while notices retain their own presentation.

Valid project guidance can be long enough to exhaust the JavaScript stack in
non-tail string traversal. Tail-recursive byte counting and model-field equality
retain the existing limits and Unicode semantics through refinement proofs,
rather than changing trusted content or weakening admission checks.

## Boundary

The executable model and production proof aggregates define the requirements.
Physical browser behavior and external execution remain their own boundaries.
