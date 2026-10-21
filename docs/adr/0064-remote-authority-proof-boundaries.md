# 0064: Separate remote authority from transport and connection-job proofs

Date: 2026-10-21
Status: Accepted

## Context

Remote delegation has two different obligations. The native transition decides
whether the current controller generation may run a command and whether a retry
returns a retained result. The IO host establishes the controller identity,
prepares observations and maintains relay sessions. A proof of native authority
cannot establish those external facts or undo a command already committed before
a socket disconnects.

An authorization theorem whose premise already says that authorization returned
a replay only establishes dispatch behavior. It does not establish that a real
retained result can be retrieved. Conversely, rejection-only safety properties
also hold for an implementation that refuses every authorized operation.

Remote commands and ChatGPT connection jobs previously shared one proof module.
They have different execution and retry contracts; coupling their proof checking
makes an unrelated authority edit invalidate the other domain's checked proofs.

## Decision

Keep the existing native command and component declarations as the semantic
source. Remote permission requirements consume the decoded command sum. The IO
protocol remains an explicit JSON boundary; native model-tool, extension and MCP
schema restrictions do not define what the remote protocol may transport.

Specify authority componentwise and derive fresh authorization from actual grant,
generation, bounds and receipt facts. Derive replay from the result recorded by
the production transition, rather than accepting a successful authorization
outcome as a premise. Include a scoped positive control theorem using the actual
native executor, so the checked contract also requires a real lifecycle change
and its retained success.

Check native remote laws in `RemoteProofs.v`, their real-executor composition in
`RemoteEntryProofs.v`, and connection-job laws in `SharingProofs.v`. Executable
remote definitions import neither proof module. Ordinary Gallina definitions and
generic JSON laws suffice; a separate remote DSL or MetaRocq generator would add
an unnecessary semantic description.

## Consequences

These proofs establish the stated native authority, receipt and lifecycle laws.
They do not assert correctness of every command delegated through that authority.
The workspace admission predicate is an explicit premise of the scoped positive
control law, rather than an assumption that execution succeeded.

The kernel checks the proofs. Extraction and compilation remain trusted
translations. Authentication, faithful preparation, journal persistence, relay
identity, WebSocket session fencing and physical process behavior remain IO
obligations. Existing complete-service restart/retry and real Durable Object
hibernation tests exercise parts of that boundary; they do not turn its external
assumptions into kernel theorems.
