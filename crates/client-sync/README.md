# client-sync

This crate defines the client hydration synchronization boundary used by the server and router attach path.

Use it to pass hydration starts, cancellation, shutdown signals, snapshot builder requests, snapshot builder results, client-sync errors, and the client-sync task handle across package boundaries.

## Hydration Model

`spawn_client_sync` starts one ingress loop. That loop owns the current hydration map keyed by `ClientId`; builder tasks only return snapshot results to the loop. This keeps replacement, cancellation, shutdown, and stale-result dropping in one ordering point.

`ClientSyncIngress::StartHydration` sends `BeginClientHydration` to the events mailbox first. Snapshot building starts after that send succeeds. A closed events mailbox is a fatal client-sync exit, and the builder is left untouched for that request.

Only the current `(ClientId, ClientCommandId)` may deliver its builder result. A new command for the same client replaces the old command. A duplicate start for the current command is ignored. `CancelHydration` removes the matching current command. `Shutdown` stops the loop and drops late builder results.

Successful builder results are forwarded as `DeliverSnapshot` exactly as built. Builder errors are forwarded as an error `DeliverNotice` followed by `DetachClient` with `DetachReason::DeliveryFailed`. If either events send fails, the sync loop exits with `ClientSyncExitStatus::Fatal`.
