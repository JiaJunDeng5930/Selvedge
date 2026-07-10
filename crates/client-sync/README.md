# client-sync

<!-- selvedge-package-readme
package: selvedge-client-sync
freshness_fingerprint: f45e8446b71a47011333ae4392d9bf26d89cdbf7
-->

This crate defines the client hydration synchronization boundary used by the server and router attach path.

Use it to pass hydration starts, cancellation, shutdown signals, snapshot builder requests, snapshot builder results, client-sync errors, and the client-sync task handle across package boundaries.

## Hydration Model

`spawn_client_sync` starts one ingress loop. That loop owns the current hydration map keyed by `ClientId` and a `JoinSet` containing every builder task. Each current entry holds its builder's `AbortHandle`, while the `JoinSet` owns completion and cleanup. Ingress and builder completions use fair `select!` scheduling.

`ClientSyncIngress::StartHydration` sends `BeginClientHydration` to the events mailbox first. Current-state snapshot building starts after that send succeeds. Empty snapshot mode delivers an empty snapshot without calling the builder. A closed events mailbox is a fatal client-sync exit, and the builder is left untouched for that request.

Only the current `(ClientId, ClientCommandId)` may deliver its builder result. A new command for the same client aborts the old builder. A duplicate start for the current command is ignored. `CancelHydration` aborts the matching builder. `Shutdown` aborts and joins every builder before the loop stops.

Successful builder results are forwarded as `DeliverSnapshot` exactly as built. Builder errors are forwarded as an error `DeliverNotice` followed by `DetachClient` with `DetachReason::DeliveryFailed`. If either events send fails, the sync loop exits with `ClientSyncExitStatus::Fatal`.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([spawn_client_sync])
  Loop[Ingress loop running]
  ReserveHydration[Send BeginClientHydration]
  Build[Build requested snapshot]
  DeliverSnapshot[Send DeliverSnapshot]
  DeliverFailure[Send DeliverNotice then DetachClient]
  IgnoreDuplicate[Keep current hydration unchanged]
  Cancel[Remove matching hydration]
  DropStale[Drop stale builder result]
  Shutdown[Stop loop]
  Fatal[Exit Fatal]

  Start -->|caller supplies events sender and builder| Loop
  Loop -->|StartHydration for new client command arrives| ReserveHydration
  Loop -->|StartHydration matches current client and command| IgnoreDuplicate
  Loop -->|CancelHydration matches current client and command; abort builder| Cancel
  Loop -->|CancelHydration misses current command| Loop
  Loop -->|Shutdown ingress arrives; abort and join all builders| Shutdown
  ReserveHydration -->|BeginClientHydration send succeeds| Build
  Build -->|new command replaces current command; abort old builder| ReserveHydration
  ReserveHydration -->|events mailbox send fails| Fatal
  Build -->|builder returns snapshot for current command| DeliverSnapshot
  Build -->|builder returns error for current command| DeliverFailure
  Build -->|builder result client or command is no longer current| DropStale
  DeliverSnapshot -->|events mailbox send succeeds| Loop
  DeliverSnapshot -->|events mailbox send fails| Fatal
  DeliverFailure -->|notice and detach sends both succeed| Loop
  DeliverFailure -->|notice or detach send fails| Fatal
  IgnoreDuplicate -->|next ingress is received| Loop
  Cancel -->|next ingress is received| Loop
  DropStale -->|next ingress is received| Loop
```
