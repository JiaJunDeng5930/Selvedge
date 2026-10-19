# ADR 0041: Operational user experience relations

## Context

The interface previously assigned text roles and layout areas to independently
constructed controls. Those roles helped rendering, but could not explain why a
choice belonged to a particular property, why its selected value agreed with its
operation, or why several controls belonged to one submission. The resulting
interface flattened object properties into unrelated rows. Styling those rows
could conceal the loss without repairing it.

## Decision

Introduce an owner-local experience model between domain observations and surface
construction. Its public operations construct property decisions, workspace
collections and actions from the observations that also determine their behavior.
Their state carriers are owned by the experience component. Presentation consumes
those operations; browser construction consumes the resulting relationships.

This boundary follows the user's objects and goals rather than the available
HTML elements. A decision admits compatible alternatives before it can produce
an edit. A collection retains the workspace against which membership and primary
directory references are interpreted. An action retains the editor and draft
revision shared by its content, supporting controls and feedback.

The browser's hierarchy grammar expresses proximity and nesting as relationships:
members are closer than a heading and its body, and separate groups are farther
apart. This keeps hierarchy construction independent of any particular calibrated
spacing value. Selection and focus remain separate observations because choosing
a value and locating the current interaction answer different user questions.

## Evidence boundary

Production proofs bind the actual operations and surface construction to these
relations. They establish operational correspondence, scope and structural
hierarchy. They do not establish that a user finds a page attractive or understands
it. Generated browser interaction checks and inspection of the rendered interface
remain necessary at that boundary.

The design draws on [mental models](https://www.nngroup.com/articles/mental-models/),
[object-oriented UX](https://ooux.com/),
[proximity](https://www.nngroup.com/articles/gestalt-proximity/) and
[visual hierarchy](https://www.nngroup.com/articles/visual-hierarchy-ux-definition/).
These inform the choice of relationships; the executable definitions encode the
chosen relationships for checking against the user's activity and goals.
