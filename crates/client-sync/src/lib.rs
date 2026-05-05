#![doc = include_str!("../README.md")]

use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

use selvedge_command_model::{
    BeginClientHydration, ClientCommandId, ClientId, ClientSnapshot, ClientSubscription,
    EventIngressSender,
};
use tokio::sync::mpsc;
use tokio::task::JoinHandle;

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

pub fn spawn_client_sync(
    args: ClientSyncStartArgs,
) -> Result<ClientSyncHandle, SpawnClientSyncError> {
    if args.ingress_capacity == 0 {
        return Err(SpawnClientSyncError::InvalidIngressCapacity);
    }

    let (ingress_tx, mut ingress_rx) = mpsc::channel(args.ingress_capacity);
    let _events_tx = args.events_tx;
    let _snapshot_builder = args.snapshot_builder;
    let join_handle = tokio::spawn(async move {
        while let Some(message) = ingress_rx.recv().await {
            if matches!(message, ClientSyncIngress::Shutdown) {
                return ClientSyncExitStatus::Stopped;
            }
        }

        ClientSyncExitStatus::IngressClosed
    });

    Ok(ClientSyncHandle {
        ingress_tx,
        join_handle,
    })
}
