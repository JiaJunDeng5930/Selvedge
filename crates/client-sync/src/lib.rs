#![doc = include_str!("../README.md")]

use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

use selvedge_command_model::{
    BeginClientHydration, ClientCommandId, ClientId, ClientNotice, ClientNoticeKind,
    ClientNoticeLevel, ClientSnapshot, ClientSubscription, DeliverNotice, DeliverSnapshot,
    DetachClient, DetachReason, EventControlMessage, EventIngress, EventIngressSender,
    SnapshotMode,
};
use selvedge_domain_model::UnixTs;
use tokio::sync::mpsc;
use tokio::task::{AbortHandle, JoinHandle, JoinSet};

#[derive(Clone)]
pub struct ClientSyncStartArgs {
    pub events_tx: EventIngressSender,
    pub snapshot_builder: Arc<dyn ClientSnapshotBuilder>,
    pub ingress_capacity: usize,
}

#[derive(Debug)]
pub struct ClientSyncHandle {
    pub ingress_tx: ClientSyncSender,
    pub join_handle: JoinHandle<ClientSyncExitStatus>,
}

pub type ClientSyncSender = mpsc::Sender<ClientSyncIngress>;

#[derive(Debug)]
pub enum ClientSyncIngress {
    StartHydration(BeginClientHydration),
    CancelHydration(CancelHydration),
    Shutdown,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CancelHydration {
    pub client_id: ClientId,
    pub client_command_id: ClientCommandId,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ClientSyncExitStatus {
    Stopped,
    IngressClosed,
    Fatal(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SpawnClientSyncError {
    InvalidIngressCapacity,
    TokioSpawnFailed,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ClientSyncError {
    EventsMailboxClosed,
    SnapshotBuildFailed(String),
    RequestCancelled,
    StaleHydrationResult,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ClientSnapshotBuildRequest {
    pub client_id: ClientId,
    pub client_command_id: ClientCommandId,
    pub subscription: ClientSubscription,
}

pub type ClientSnapshotBuildFuture =
    Pin<Box<dyn Future<Output = Result<ClientSnapshot, ClientSyncError>> + Send>>;

pub trait ClientSnapshotBuilder: Send + Sync + 'static {
    fn build_snapshot(&self, request: ClientSnapshotBuildRequest) -> ClientSnapshotBuildFuture;
}

struct HydrationBuildResult {
    request: ClientSnapshotBuildRequest,
    result: Result<ClientSnapshot, ClientSyncError>,
}

struct ActiveHydration {
    client_command_id: ClientCommandId,
    abort_handle: AbortHandle,
}

pub fn spawn_client_sync(
    args: ClientSyncStartArgs,
) -> Result<ClientSyncHandle, SpawnClientSyncError> {
    if args.ingress_capacity == 0 {
        return Err(SpawnClientSyncError::InvalidIngressCapacity);
    }

    let (ingress_tx, mut ingress_rx) = mpsc::channel(args.ingress_capacity);
    let events_tx = args.events_tx;
    let snapshot_builder = args.snapshot_builder;
    let handle = tokio::runtime::Handle::try_current()
        .map_err(|_| SpawnClientSyncError::TokioSpawnFailed)?;
    let join_handle = handle.spawn(async move {
        let mut current = HashMap::<ClientId, ActiveHydration>::new();
        let mut builds = JoinSet::<HydrationBuildResult>::new();

        loop {
            tokio::select! {
                message = ingress_rx.recv() => {
                    match message {
                        Some(ClientSyncIngress::StartHydration(begin)) => {
                            let client_id = begin.client_id.clone();
                            let client_command_id = begin.client_command_id.clone();

                            if current.get(&client_id).map(|hydration| &hydration.client_command_id)
                                == Some(&client_command_id)
                            {
                                continue;
                            }

                            let request = ClientSnapshotBuildRequest {
                                client_id: client_id.clone(),
                                client_command_id: client_command_id.clone(),
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
                                builds.shutdown().await;
                                current.clear();
                                return ClientSyncExitStatus::Fatal(
                                    "events mailbox closed while beginning client hydration".to_owned(),
                                );
                            }

                            let abort_handle = spawn_snapshot_build(
                                &mut builds,
                                snapshot_builder.clone(),
                                request,
                            );
                            if let Some(previous) = current.insert(
                                client_id,
                                ActiveHydration {
                                    client_command_id,
                                    abort_handle,
                                },
                            ) {
                                previous.abort_handle.abort();
                            }
                        }
                        Some(ClientSyncIngress::CancelHydration(cancel)) => {
                            if current.get(&cancel.client_id).map(|hydration| &hydration.client_command_id)
                                == Some(&cancel.client_command_id)
                                && let Some(cancelled) = current.remove(&cancel.client_id)
                            {
                                cancelled.abort_handle.abort();
                            }
                        }
                        Some(ClientSyncIngress::Shutdown) => {
                            builds.shutdown().await;
                            current.clear();
                            return ClientSyncExitStatus::Stopped;
                        }
                        None => {
                            builds.shutdown().await;
                            current.clear();
                            return ClientSyncExitStatus::IngressClosed;
                        }
                    }
                }
                joined = builds.join_next(), if !builds.is_empty() => {
                    let build_result = match joined {
                        Some(Ok(build_result)) => build_result,
                        Some(Err(error)) if error.is_cancelled() => continue,
                        Some(Err(error)) => {
                            builds.shutdown().await;
                            current.clear();
                            return ClientSyncExitStatus::Fatal(format!(
                                "client snapshot builder task failed: {error}"
                            ));
                        }
                        None => continue,
                    };
                    // NOTE: This loop owns the current hydration map. Builder results deliver only
                    // while their client command is still current after replacement or cancellation.
                    if current.get(&build_result.request.client_id)
                        .map(|hydration| &hydration.client_command_id)
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
                        builds.shutdown().await;
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

fn spawn_snapshot_build(
    builds: &mut JoinSet<HydrationBuildResult>,
    snapshot_builder: Arc<dyn ClientSnapshotBuilder>,
    request: ClientSnapshotBuildRequest,
) -> AbortHandle {
    builds.spawn(async move {
        let result = match request.subscription.snapshot_mode {
            SnapshotMode::Empty => Ok(empty_snapshot()),
            SnapshotMode::CurrentState => snapshot_builder.build_snapshot(request.clone()).await,
        };
        HydrationBuildResult { request, result }
    })
}

fn empty_snapshot() -> ClientSnapshot {
    ClientSnapshot {
        generated_at: UnixTs(0),
        tasks: Vec::new(),
        task_parent_edges: Vec::new(),
        history_nodes: Vec::new(),
        task_versions: Vec::new(),
    }
}

async fn deliver_build_result(
    events_tx: &EventIngressSender,
    build_result: HydrationBuildResult,
) -> Result<(), &'static str> {
    match build_result.result {
        Ok(snapshot) => {
            let delivery = send_control(
                events_tx,
                EventControlMessage::DeliverSnapshot(DeliverSnapshot {
                    client_id: build_result.request.client_id,
                    client_command_id: build_result.request.client_command_id,
                    snapshot,
                }),
            )
            .await;
            delivery.map_err(|_| "delivering client snapshot")
        }
        Err(error) => {
            let notice = DeliverNotice {
                client_id: build_result.request.client_id.clone(),
                client_command_id: build_result.request.client_command_id.clone(),
                notice: ClientNotice {
                    level: ClientNoticeLevel::Error,
                    kind: ClientNoticeKind::Text,
                    message_text: format!("client snapshot build failed: {error:?}"),
                },
            };
            send_control(events_tx, EventControlMessage::DeliverNotice(notice))
                .await
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
            .map_err(|_| "detaching failed client hydration")
        }
    }
}

async fn send_control(
    events_tx: &EventIngressSender,
    control: EventControlMessage,
) -> Result<(), mpsc::error::SendError<EventIngress>> {
    let ingress = EventIngress::Control(control);
    events_tx.send(ingress).await
}
