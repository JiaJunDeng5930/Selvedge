# Interaction sessions

Owns application and session observations, navigation and interaction transitions.

Work selection is session navigation. Each Work and All Tasks retain their own
latest route and Task and new-graph editor identities; pending directory observations and
command completions keep that same editor scope. Work membership is read from the
kernel, independently of Project configuration and Task ancestry.

Board, Project management and Agent collection destinations select All Tasks;
Task creation, conversations and Task graphs retain their owning Work scope.
Work creation captures the current navigation generation. Later navigation or
another creation invalidates its automatic selection, while the created Work
remains available in the tab strip.
An explicit Task-navigation toggle also advances that attention claim, so an
earlier Work-creation reply cannot replace a list the user has just opened.

Current Work creation attends its new tab and then the new Task's message field.
Native focus exposes an overflowing tab and leaves the composer ready for typing.
Refused selections and stale replies retain their current attention.

Work overview uses the existing temporary layer stack. Selecting its current
scope dismisses the layer and advances navigation generation; another selection
attends that scope's real tab or compact title before its message field. New Work
keeps the overview available until a current successful creation selects its Work.
Opening the overview attends the selected card, including when it is below the
initial scroll position, while retaining the overview's ordinary layer identity.

Narrow global navigation is another ordinary `GlobalNavigation` panel. Opening
and closing it preserve the active Work, drafts and Task-navigation intent.
`consume_global_navigation` removes that origin when Settings passes to its
service owner, returns attention to the launcher and invalidates an older layer
claim. Destination navigation retains its existing route and Work behavior.

Start with [MODEL.bend](MODEL.bend), [PROGRAM.bend](PROGRAM.bend), [CONTRACT.bend](CONTRACT.bend), [PROOF.bend](PROOF.bend).

The imports in these entries compose the subordinate concepts and their required
evidence. Read named observations and intended updates before private state
representations. Local proofs are collected in the concept's `PROOF.bend`;
independent evidence used across concepts remains separate where needed to keep
the imports acyclic. The root [PROOF.bend](../../PROOF.bend) assembles the production evidence.

Submission admission calls the experience `draft_can_prepare` operation on the
same draft, pending state and world used by presentation. A refused admission
returns the first assessment obstruction, preserves the complete application and
emits no directory observation. Accepted preparation keeps the immutable draft
snapshot and the command resolver as the authoritative execution boundary.
`submission_requirements_gate` and `invalid_preparation_complete_refusal` bind
these guarantees to the production admission and refusal operations.

`settle_workspace` retains only correlated directory failures; `retry_workspace`
uses the same draft through the normal preparation guards. `toggle_property_source`
requests the matching setting inspection without changing the work or model preference.
`PropertySource{origin}` is a distinct child activity on the existing layer stack.
Opening it requires the actual top layer to own that origin and be in inspection,
with no requested dependent field. Object editing and workspace configuration
are already their owning settings activities.
The child retains the original panel as its source identity; its explicit return
uses `ClosePanel`, preserving the complete parent inspection and project draft.
A source child has no decision editor, so parameter edits cannot target it.

Choice layers carry one requested field and a separate `parameter_buffer`.
`requested_decision` and `requested_parameter` read them only for the actual
owning editor. `EnterDecision` admits retained properties, `LeaveDecision`
returns from a dependency to its inspection parent (or from inspection to the
principal view), and `TogglePropertySource` requests inspection while clearing a
competing dependent view and buffer. Full access has no sandbox or network
parameter; the reviewer parameter belongs only to automatic review.

`WriteDecisionParameter` changes the open parameter buffer without changing the
applied draft or task. `CompleteDecisionParameter` validates the complete value
against the actual open profile and invokes the existing canonical model edit.
Finite dependent choices use the same canonical edit. Completion returns a
parameter to its parent; a principal choice dismisses its layer and restores its
trigger. Current-task changes still issue `ConfigureTaskExecution` immediately.
`ExecutionViewCompletion` associates that accepted command result with its
requesting view occurrence; a stale result must not dismiss another view. A real
field or inspection view change allocates a fresh occurrence; ordinary buffer
text input retains that identity. Returning while a task command is in flight
therefore cannot let its old completion close the new view.

`ClosePanel` is explicit dismissal. It discards a project's complete uncommitted
draft, directory entry, feedback and pending directory observations; other
applied settings survive. Raw `close_panel` remains the success path, retaining a
saved project result. The shared fresh layer occurrence counter reserves a value
above the discarded draft revision before reopening a project. That reserved
occurrence seeds the fresh draft revision, preventing late accepted results from
settling a different draft with the same editor identity. Already accepted
kernel commands remain accepted and their persisted results are retained.
