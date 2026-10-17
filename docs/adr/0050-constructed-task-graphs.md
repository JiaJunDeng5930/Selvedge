# Constructed task graphs

Status: accepted

Agent collaboration needs editable connections between existing tasks. A test
author's reply, for example, can become another task's input while both tasks
retain their own contracts and execution. Giving each collaboration pattern its
own scheduler case would duplicate task policy and make new working methods
require kernel changes.

Follow ADR 0038's capability construction approach. Ordinary Bend functions
construct data declarations over task references, creation requests and output
reactions. Checked constructions bind their requirements to the actual candidate.
Persist resolved references and rules; derive execution and presentation from
that declaration. Arbitrary captured callbacks would require a separate account
of their display and persistence, so they are not the stored representation.

Task creation and message delivery keep their existing resolution, workspace and
contract rules. Local construction references connect newly created tasks without
introducing another task identity or settings model. Installation must establish
these connections before the created tasks can run. Graph removal removes the
connections, leaving task lifecycle changes to the existing task operations.

Directory canonicalization and instruction snapshots remain host observations.
Native creation can select already observed contexts within the caller's existing
delegation scope; model-supplied settings cannot stand in for a host observation.
Public graph commands reuse the ordinary creation observation boundary.

Reliable handoff belongs inside the committed transition. Plugin observations
are best effort and tool hooks describe tool invocation, so neither is a reliable
task-output transport. Derive reactions from accepted ordinary replies and reuse
normal message delivery before committing the complete decision. Keep delivery
rejections observable without discarding the accepted source reply. This provides
local committed delivery, not exactly-once execution of external effects.

Rules remain editable independently of frozen task contracts. Existing journal
input order determines which rules apply to a reply; an edit does not replay old
outputs or retract messages already delivered. Finite reaction declarations keep
the extension within the bounded-transition model. Cyclic connections do not
synchronously run another model, and do not imply that the overall conversation
terminates.

The graph feature owns its declarations and state. Core execution exposes a
stable reaction boundary and continues to know only the assembled outer feature
categories. Production proofs cover declaration admission, binding, interpretation
and preservation; native and service tests cover serialization, commit ordering
and restart behavior.
