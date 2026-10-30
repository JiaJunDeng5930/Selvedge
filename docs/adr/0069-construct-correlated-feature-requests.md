# 0069: Construct correlated feature requests

Status: accepted.

A feature request is one value: its admitted domain source, receiver location,
identity and protocol body must stay connected through installation, dispatch
and completion. Title, board, connection and context maintenance use the same
construction mechanism.

`TicketedRequest.Scoped.feature_channel` is indexed by the owner's source type.
The owner selects a real source and a `Receiver.located` path in the current
feature state. Keyed locations derive their address from the input; positional
locations come from an observed lookup or the current append position. The
caller cannot independently supply a different address or an out-of-bounds
position. Record views are derived from the owning constructor.

`RequestTypes.Protocol` supplies a wire declaration and the protocol-specific
body projection. `ModelDeclarations.declare_request` checks field-name
uniqueness when that declaration is compiled. The shared interpreter allocates
an identity, constructs one `RequestEnvelope`, installs it through the selected
receiver and emits that same envelope. Task tickets and connection identities
use their existing allocation spaces. A new feature adds its own source,
receiver and body declaration; it does not add a case to a kernel enumeration
of every feature or a new receiver-correspondence theorem.

The owner still decides the facts that depend on its operation: whether a
project exists, whether an authority is current, whether a revision matches,
and whether capacity or a resource permits the operation. These observations
produce the source consumed by the channel. Generic allocation, receiver,
address, frame and emission properties are established with the shared
interpreter.

Maintenance leases retain their selected target and typed input throughout
measurement, preparation, validation and compaction. Follow-up phases consume
that retained value. `RequestTypes.task_bound` declares that an outstanding
request is cancelled with its task. Dispatch derives the task and ticket from
the same receiver and envelope; adding another task-bound protocol does not
add another cancellation case.

Callback declarations are open values as well. A declaration selects either a
marked result, whose `ok` or `error` field chooses its typed branch, or an
unmarked result whose single payload carries the outcome itself. Those forms
cannot be combined inconsistently. The declaration owns its coordinates,
admitted payloads, diagnostic format and physical result observation.
`CallbackDeclarations.declare` derives field-name obligations at construction;
the shared encoder supplies the discriminant and result marker. Domain input
handlers register the same descriptor with their interpretation. A new
callback adds a declaration and a handler, without extending a global callback
enumeration or proving its framing again.

Provider registration follows the same rule. A Responses-compatible backend
uses `ProviderCatalog.responses_backend name endpoint credential`; common
request construction supplies the authority, tool catalog and response
protocol. Account and Web constructors fix the service identity associated
with their authentication semantics. A new wire protocol may require its own
interpreter and protocol-specific laws, but compatible registrations inherit
the existing implementation.

Serialized output budgets and physical IO remain boundaries of their own.
Construction does not claim to establish facts that require observing those
external systems.
