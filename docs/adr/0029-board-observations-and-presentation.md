# ADR 0029: Board observations and presentation

## Decision

Restore the board's existing observations and admitted user operations in the
Bend product interface. Keep their Web layout and document presentation in the
Web component, preserving the original identities and actions.

## Reason

Earlier UI changes lost board information and capabilities. Preserving page
regions alone could faithfully render an incomplete board: construction laws
cannot recover content that the producer no longer supplies. Restore observations
from the actual board, task, project and owner registries and the observed clock,
instead of inventing renderer-only content or a second interaction engine.

Separating product observations and user operations from Web presentation lets
each layer state its own obligations. Retaining existing keys and declared
actions preserves their ownership and command admission while allowing their
visual organization to change. Production remains grounded in real data; no
seeded cards or fabricated tasks are needed to make the board visible.

Constrained dialogs give their body an independent scroll region so their
sections retain their content dimensions. Placing the close control in the
dialog header also changes the Web presentation order. The scene and frame
contract share that order as an input, while Core retains its semantic order
instead of changing it for layout. `WrongTabOrder` remains a contract rejection.

Restored labels, assistance inputs, card details and keyboard move actions must
come from the model; remove the native move menu that had no modeled counterpart.

Space must be owned by the scene before controls are placed: reserving an
unrendered heading or repeating container spacing reduces usable content space.
Shared content gutters and distinct group, object and control boundaries keep
board observations readable. Dialog regions own their padding, and a semantically
identified terminal submit suffix can occupy a footer while preserving node and
tab order. These choices belong in the Bend presentation model rather than host
selector patches.

## Boundary

The executable models and existing proof aggregates own the requirements.
Browser layout, scrolling and physical event delivery remain external boundaries;
this decision does not turn them into Bend guarantees.
