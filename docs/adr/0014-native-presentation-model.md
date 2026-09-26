# 0014: native presentation model

Status: accepted, 2026-09-25.

## Context

Returning command schemas and allowed lifecycle names did not make the UI a
projection. The Web client still chose task selection behavior, message visibility,
form meanings and action rules from raw domain/provider data. Those decisions
would have to be reimplemented by every platform and were outside the conceptual
program entry.

## Decision

`UI.bend` defines a typed tree of groups, text, values, actions and forms. Actions
carry public events; form fields carry bindings into a native event template.
Availability calls `COMMANDS.resolve`, and every actual submission invokes that
resolver again against the live world. A form's enabled flag says that the action
is presently available, not that every possible future field value is valid.

The client retains an opaque cursor and unsubmitted widget drafts. Cursor events
are observations: no scheduler work or journal append. Command submissions retain
normal command semantics, and projection occurs after scheduling but before full
decision admission. An oversized result rolls back the candidate and all effects.
The reply includes the original command receipt as well as the resulting surface.

The Web adapter renders widget types and fills declared bindings. Authentication,
transport reconnection, DOM focus and draft retention are host mechanics. Provider
message interpretation, including ordinary Responses messages preserved as
`ModelContext`, belongs to Bend. Encrypted context is not a display value.

## Consequences

The conceptual entry carries a `UserSurface` with checked read-only projection,
submission correspondence and command-gate laws. Future platform adapters need
not recreate a task model. The DOM renderer itself is still an external boundary;
native proofs do not certify a browser or visual layout. Native/HTTP/adapter tests
cover stale actions, malformed events, cancellation, pagination, post-state
rendering, restart, literal text rendering and draft preservation. The Web view
uses committed snapshots rather than independently interpreting provider deltas.
