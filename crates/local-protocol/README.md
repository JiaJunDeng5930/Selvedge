# local-protocol

<!-- selvedge-package-readme
package: selvedge-local-protocol
freshness_commit: 592f95539c225023a2f2d66f8096a3f85ac304ee
-->

This crate defines the localhost protocol data model shared by the Selvedge server, root CLI, local client, TUI, and web client.

Use it for serializable ready probes, command submission envelopes, attach requests, attach responses, client subscriptions, client frames, snapshots, projections, events, and validation errors.

This crate does not access the network, database, filesystem, runtime, or mailbox. Transport limits, authentication, concrete command support, payload schemas, and task existence checks are enforced by the crates that own those boundaries.

Command rejection and attach rejection use separate reason enums. Command rejection must cover malformed request, server readiness, missing client attachment, login contention, unsupported command, router mailbox closure, and internal failure. Attach rejection must cover malformed request, server not ready, duplicate active attach, client registry capacity exhaustion, router mailbox closure, client-sync unavailability, attach channel creation failure, and internal failure.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([local protocol JSON value])
  ReadyProbe[Decode ready probe request or response]
  Command[Decode command submission envelope]
  Attach[Decode attach request or response]
  Frame[Decode client frame stream item]
  Validate[Validate fields, ids, and enum reason]
  Accepted[Value accepted by server or client boundary]
  Rejected[Return protocol validation or rejection reason]
  Encode[Encode response or frame]

  Start -->|ready endpoint payload is received| ReadyProbe
  Start -->|command endpoint payload is received| Command
  Start -->|attach endpoint payload is received| Attach
  Start -->|attach stream frame is received| Frame
  ReadyProbe -->|JSON shape matches ready request or response| Validate
  Command -->|JSON shape has command id, name, payload, and client id where required| Validate
  Attach -->|JSON shape has client id, command id, and subscriptions| Validate
  Frame -->|JSON shape matches snapshot, event, notice, or detach frame| Validate
  Validate -->|all required fields and enum values are accepted| Accepted
  Validate -->|malformed request, readiness, missing attachment, login contention, duplicate attach, capacity, router, client-sync, channel, unsupported command, or internal condition is reported| Rejected
  Accepted -->|caller serializes boundary value| Encode
  Rejected -->|caller serializes rejection response| Encode
```
