# events

<!-- selvedge-package-readme
package: selvedge-events
freshness_fingerprint: a67e2d81fdc7f3ba05792d32b764075cca3a22c0
-->

This crate runs the client outbound event aggregator task.

Use it from the router to register client outbound channels, deliver attach snapshots, update subscriptions, detach clients, and fan out raw command-model events as client frames.

This crate only receives router-mediated ingress and only sends `ClientFrame` values through router-provided client channels. It does not access the database, filesystem, network, API providers, tools, or task runtimes.

Client session capacity is admitted by `ReserveClientSession`. A matching `BeginClientHydration` consumes the reservation and installs or replaces the active session; stale begin, snapshot, notice, update, and detach controls are filtered by `ClientCommandId`.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([spawn event aggregator])
  Loop[Aggregator loop running]
  Reserved[Client session reserved]
  Hydrating[Hydration active for client command]
  Attached[Client session attached]
  Deliver[Deliver snapshot, event, notice, or subscription update]
  Detached[Detach client]
  Ignored[Ignore stale client command]
  Shutdown[Exit after ingress closes]
  Fatal[Exit on delivery channel failure]

  Start -->|router supplies ingress receiver| Loop
  Loop -->|ReserveClientSession arrives and capacity is available| Reserved
  Loop -->|ReserveClientSession arrives and capacity is full| Loop
  Reserved -->|BeginClientHydration matches reservation| Hydrating
  Loop -->|BeginClientHydration lacks matching reservation or has stale command| Ignored
  Hydrating -->|DeliverSnapshot matches current client command| Attached
  Hydrating -->|DeliverSnapshot has stale command| Ignored
  Attached -->|RawEvent matches subscription scope and detail| Deliver
  Attached -->|DeliverNotice, UpdateSubscription, or matching snapshot arrives| Deliver
  Deliver -->|client frame send succeeds| Attached
  Deliver -->|client frame send fails| Detached
  Attached -->|DetachClient matches current command or client disconnect is observed| Detached
  Detached -->|session removed and capacity released| Loop
  Ignored -->|next ingress is received| Loop
  Loop -->|event ingress channel closes| Shutdown
  Deliver -->|internal delivery invariant fails| Fatal
```
