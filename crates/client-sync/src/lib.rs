#![doc = include_str!("../README.md")]
//! @behavior selvedge.client.sync The client sync task converts client hydration commands into ordered event control messages and caller-visible exit statuses.

use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

use selvedge_command_model::{
    BeginClientHydration, ClientCommandId, ClientId, ClientNotice, ClientNoticeLevel,
    ClientSnapshot, ClientSubscription, DeliverNotice, DeliverSnapshot, DetachClient, DetachReason,
    EventControlMessage, EventIngress, EventIngressSender,
};
use tokio::sync::mpsc;
use tokio::task::JoinHandle;

#[derive(Clone)]
// @intent selvedge.client.sync.start_args Client sync start arguments carry the events mailbox, snapshot builder, and ingress capacity selected by the caller.
// @behavior selvedge.client.sync.start_args.config Client sync start arguments expose the events mailbox, snapshot builder, and ingress capacity to spawning callers.
pub struct ClientSyncStartArgs {
    /// @behavior selvedge.client.sync.start_args.events Client sync start arguments carry the event mailbox used for hydration event delivery.
    pub events_tx: EventIngressSender,
    /// @behavior selvedge.client.sync.start_args.builder Client sync start arguments carry the snapshot builder used for client hydration.
    pub snapshot_builder: Arc<dyn ClientSnapshotBuilder>,
    /// @constraint selvedge.client.sync.start_args.capacity Client sync start arguments carry the requested positive ingress capacity.
    pub ingress_capacity: usize,
}

#[derive(Debug)]
// @behavior selvedge.client.sync.handle Spawning client sync returns an ingress sender and join handle that callers use to drive and observe the sync task.
pub struct ClientSyncHandle {
    /// @behavior selvedge.client.sync.handle.ingress The client sync handle exposes the sender used to submit hydration controls.
    pub ingress_tx: ClientSyncSender,
    /// @behavior selvedge.client.sync.handle.join The client sync handle exposes a join handle that resolves to the task exit status.
    pub join_handle: JoinHandle<ClientSyncExitStatus>,
}

// @intent selvedge.client.sync.sender The client sync sender is the package boundary for hydration start, cancellation, and shutdown commands.
// @behavior selvedge.client.sync.sender.control The client sync sender accepts hydration control messages from callers.
pub type ClientSyncSender = mpsc::Sender<ClientSyncIngress>;

#[derive(Debug)]
// @behavior selvedge.client.sync.ingress Client sync ingress accepts hydration starts, matching hydration cancellations, and shutdown requests.
pub enum ClientSyncIngress {
    StartHydration(BeginClientHydration),
    CancelHydration(CancelHydration),
    Shutdown,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.client.sync.cancel A hydration cancellation identifies the client and command whose late snapshot result becomes unobservable.
pub struct CancelHydration {
    // @behavior selvedge.client.sync.cancel.client_id Hydration cancellation exposes the client ID selected for cancellation.
    pub client_id: ClientId,
    // @behavior selvedge.client.sync.cancel.command_id Hydration cancellation exposes the client command ID selected for cancellation.
    pub client_command_id: ClientCommandId,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.client.sync.exit The client sync join handle reports stopped, closed-ingress, or fatal mailbox failure exit statuses.
pub enum ClientSyncExitStatus {
    Stopped,
    IngressClosed,
    Fatal(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.client.sync.spawn_error Client sync spawning reports invalid ingress capacity and missing Tokio runtime as typed errors.
pub enum SpawnClientSyncError {
    InvalidIngressCapacity,
    TokioSpawnFailed,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.client.sync.error Client sync errors expose events mailbox closure, snapshot build failure, cancellation, and stale result outcomes.
pub enum ClientSyncError {
    EventsMailboxClosed,
    SnapshotBuildFailed(String),
    RequestCancelled,
    StaleHydrationResult,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.client.sync.build_request Snapshot build requests expose the client ID, command ID, and subscription selected for hydration.
pub struct ClientSnapshotBuildRequest {
    /// @behavior selvedge.client.sync.build_request.client_id Snapshot build requests expose the client ID selected for hydration.
    pub client_id: ClientId,
    /// @behavior selvedge.client.sync.build_request.command_id Snapshot build requests expose the client command ID selected for hydration.
    pub client_command_id: ClientCommandId,
    /// @behavior selvedge.client.sync.build_request.subscription Snapshot build requests expose the subscription selected for hydration.
    pub subscription: ClientSubscription,
}

// @intent selvedge.client.sync.build_future Snapshot build futures return either a client snapshot or a typed client sync error across package boundaries.
// @behavior selvedge.client.sync.build_future.result Snapshot build futures expose snapshot success or typed sync error completion to callers.
pub type ClientSnapshotBuildFuture =
    Pin<Box<dyn Future<Output = Result<ClientSnapshot, ClientSyncError>> + Send>>;

// @intent selvedge.client.sync.builder Snapshot builders provide caller-owned snapshot construction for client hydration.
// @behavior selvedge.client.sync.builder.contract Snapshot builders receive hydration request data and return a future that completes with a snapshot or sync error.
pub trait ClientSnapshotBuilder: Send + Sync + 'static {
    // @behavior selvedge.client.sync.builder.build Snapshot builders receive the caller-visible hydration request and return a snapshot or typed sync error.
    fn build_snapshot(&self, request: ClientSnapshotBuildRequest) -> ClientSnapshotBuildFuture;
}

// @intent selvedge.client.sync.result Hydration build results carry snapshot builder output back to the client sync delivery loop.
// @behavior selvedge.client.sync.result.delivery Hydration build results preserve request identity and snapshot build outcome for event delivery.
// @constraint selvedge.client.sync.result.identity Hydration build results keep request identity paired with the builder outcome used for delivery.
struct HydrationBuildResult {
    request: ClientSnapshotBuildRequest,
    result: Result<ClientSnapshot, ClientSyncError>,
}

// @behavior selvedge.client.sync.spawn Client sync spawning validates capacity, requires a Tokio runtime, and returns a handle for hydration controls.
pub fn spawn_client_sync(
    args: ClientSyncStartArgs,
) -> Result<ClientSyncHandle, SpawnClientSyncError> {
    // @constraint selvedge.client.sync.capacity Client sync rejects zero ingress capacity before spawning the task.
    if args.ingress_capacity == 0 {
        return Err(SpawnClientSyncError::InvalidIngressCapacity);
    }

    let (ingress_tx, mut ingress_rx) = mpsc::channel(args.ingress_capacity);
    let (result_tx, mut result_rx) = mpsc::unbounded_channel();
    let events_tx = args.events_tx;
    let snapshot_builder = args.snapshot_builder;
    // @behavior selvedge.client.sync.spawn.runtime Client sync spawning returns TokioSpawnFailed when no current Tokio runtime handle is available.
    let handle = tokio::runtime::Handle::try_current()
        .map_err(|_| SpawnClientSyncError::TokioSpawnFailed)?;
    // @behavior selvedge.client.sync.spawn.task Client sync spawning creates the hydration event loop and returns its join handle to the caller.
    let join_handle = handle.spawn(async move {
        let mut current = HashMap::<ClientId, ClientCommandId>::new();

        loop {
            tokio::select! {
                biased;
                // NOTE: Queued controls are applied before builder results. This preserves
                // replacement, cancellation, and shutdown decisions that reached client-sync first.
                message = ingress_rx.recv() => {
                    match message {
                        Some(ClientSyncIngress::StartHydration(begin)) => {
                            // @behavior selvedge.client.sync.start Starting hydration sends BeginClientHydration before requesting a snapshot build.
                            let client_id = begin.client_id.clone();
                            let client_command_id = begin.client_command_id.clone();

                            // @behavior selvedge.client.sync.duplicate A duplicate hydration start for the current client command produces no second builder request or event.
                            if current.get(&client_id) == Some(&client_command_id) {
                                continue;
                            }

                            // @behavior selvedge.client.sync.replace A new hydration command for the same client replaces the current command and makes the old builder result unobservable.
                            current.insert(client_id.clone(), client_command_id.clone());
                            let request = ClientSnapshotBuildRequest {
                                client_id,
                                client_command_id,
                                subscription: begin.subscription.clone(),
                            };

                            // NOTE: Begin is the state handoff to events. Snapshot building starts after
                            // that mailbox accepts Begin, so a closed events mailbox is a fatal hydration
                            // boundary failure and the builder remains untouched.
                            if send_control(
                                &events_tx,
                                EventControlMessage::BeginClientHydration(begin),
                            )
                            .await
                            .is_err()
                            {
                                // @behavior selvedge.client.sync.begin_failure If BeginClientHydration cannot be sent, client sync exits fatally before starting the snapshot builder.
                                current.clear();
                                return ClientSyncExitStatus::Fatal(
                                    "events mailbox closed while beginning client hydration".to_owned(),
                                );
                            }

                            spawn_snapshot_build(
                                snapshot_builder.clone(),
                                result_tx.clone(),
                                request,
                            );
                        }
                        Some(ClientSyncIngress::CancelHydration(cancel)) => {
                            // @behavior selvedge.client.sync.cancel.match A cancellation removes only the matching current client command from observable hydration delivery.
                            if current.get(&cancel.client_id) == Some(&cancel.client_command_id) {
                                current.remove(&cancel.client_id);
                            }
                        }
                        Some(ClientSyncIngress::Shutdown) => {
                            // @behavior selvedge.client.sync.shutdown Shutdown stops the sync task and drops late builder results.
                            current.clear();
                            return ClientSyncExitStatus::Stopped;
                        }
                        None => {
                            // @behavior selvedge.client.sync.ingress_closed A closed ingress mailbox stops the sync task with IngressClosed status.
                            current.clear();
                            return ClientSyncExitStatus::IngressClosed;
                        }
                    }
                }
                Some(build_result) = result_rx.recv() => {
                    // @constraint selvedge.client.sync.current_result Only the current client command may deliver a snapshot build result to the events mailbox.
                    // NOTE: This loop owns the current hydration map. Builder results deliver only
                    // while their client command is still current after replacement or cancellation.
                    if current.get(&build_result.request.client_id)
                        != Some(&build_result.request.client_command_id)
                    {
                        continue;
                    }
                    let result_client_id = build_result.request.client_id.clone();

                    let stage = deliver_build_result(
                        &events_tx,
                        build_result,
                    )
                    .await
                    .err();

                    if let Some(stage) = stage {
                        // @behavior selvedge.client.sync.delivery_failure If result delivery cannot reach the events mailbox, client sync exits with a fatal status naming the failed delivery stage.
                        current.clear();
                        return ClientSyncExitStatus::Fatal(format!(
                            "events mailbox closed while {stage}"
                        ));
                    }

                    current.remove(&result_client_id);
                }
            }
        }
    });

    Ok(ClientSyncHandle {
        ingress_tx,
        join_handle,
    })
}

// @intent selvedge.client.sync.builder_task The snapshot builder task isolates caller-provided snapshot construction from the hydration event loop.
// @behavior selvedge.client.sync.builder_task.spawn Snapshot builder tasks return hydration build results to the client sync loop with original request identity.
fn spawn_snapshot_build(
    snapshot_builder: Arc<dyn ClientSnapshotBuilder>,
    result_tx: mpsc::UnboundedSender<HydrationBuildResult>,
    request: ClientSnapshotBuildRequest,
) {
    // @behavior selvedge.client.sync.builder_task.start Snapshot building starts as a Tokio task that returns its result to client sync.
    tokio::spawn(async move {
        let result = snapshot_builder.build_snapshot(request.clone()).await;
        // @behavior selvedge.client.sync.builder_result Snapshot builders return their result to client sync with the original client and command identity.
        let _ = result_tx.send(HydrationBuildResult { request, result });
    });
}

// @intent selvedge.client.sync.delivery Result delivery maps snapshot builder outcomes into event control messages.
// @behavior selvedge.client.sync.delivery.result Result delivery sends snapshots, error notices, or detaches through the events mailbox.
async fn deliver_build_result(
    events_tx: &EventIngressSender,
    build_result: HydrationBuildResult,
) -> Result<(), &'static str> {
    match build_result.result {
        Ok(snapshot) => {
            // @behavior selvedge.client.sync.snapshot A successful snapshot build sends DeliverSnapshot with the original client and command identity.
            let delivery = send_control(
                events_tx,
                EventControlMessage::DeliverSnapshot(DeliverSnapshot {
                    client_id: build_result.request.client_id,
                    client_command_id: build_result.request.client_command_id,
                    snapshot,
                }),
            )
            .await;
            // @behavior selvedge.client.sync.snapshot.failure A closed events mailbox during snapshot delivery returns the delivering client snapshot fatal stage.
            delivery.map_err(|_| "delivering client snapshot")
        }
        Err(error) => {
            // @behavior selvedge.client.sync.snapshot_error A failed snapshot build sends an error notice and then detaches the client with DeliveryFailed.
            let notice = DeliverNotice {
                client_id: build_result.request.client_id.clone(),
                client_command_id: build_result.request.client_command_id.clone(),
                notice: ClientNotice {
                    level: ClientNoticeLevel::Error,
                    message_text: format!("client snapshot build failed: {error:?}"),
                },
            };
            send_control(events_tx, EventControlMessage::DeliverNotice(notice))
                .await
                // @behavior selvedge.client.sync.snapshot_error.notice_failure A closed events mailbox during failure notice delivery returns the delivering client hydration failure notice fatal stage.
                .map_err(|_| "delivering client hydration failure notice")?;

            send_control(
                events_tx,
                EventControlMessage::DetachClient(DetachClient {
                    client_id: build_result.request.client_id,
                    client_command_id: build_result.request.client_command_id,
                    reason: DetachReason::DeliveryFailed,
                }),
            )
            .await
            // @behavior selvedge.client.sync.snapshot_error.detach_failure A closed events mailbox during failed hydration detach returns the detaching failed client hydration fatal stage.
            .map_err(|_| "detaching failed client hydration")
        }
    }
}

// @behavior selvedge.client.sync.event_send.call Event control sending wraps one control message in EventIngress::Control and returns mailbox send errors to the caller.
async fn send_control(
    events_tx: &EventIngressSender,
    control: EventControlMessage,
) -> Result<(), mpsc::error::SendError<EventIngress>> {
    // @behavior selvedge.client.sync.event_send Client sync sends event control messages through EventIngress::Control.
    let ingress = EventIngress::Control(control);
    // @behavior selvedge.client.sync.event_send.failure A closed events mailbox returns the original control message as a send error.
    events_tx.send(ingress).await
}
