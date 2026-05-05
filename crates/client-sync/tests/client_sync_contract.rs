use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

use selvedge_client_sync::{
    CancelHydration, ClientSnapshotBuildFuture, ClientSnapshotBuildRequest, ClientSnapshotBuilder,
    ClientSyncError, ClientSyncExitStatus, ClientSyncIngress, ClientSyncStartArgs,
    SpawnClientSyncError, spawn_client_sync,
};
use selvedge_command_model::{
    ClientCommandId, ClientId, ClientSnapshot, ClientSubscription, DetailLevel, EventIngress,
    EventIngressSender, TaskScope,
};

#[test]
fn snapshot_builder_trait_returns_boxed_snapshot_future() {
    let builder = StaticSnapshotBuilder;
    let request = build_request("client-1", "attach-1");
    let future = builder.build_snapshot(request);

    let _future: ClientSnapshotBuildFuture = future;
}

#[tokio::test]
async fn spawn_client_sync_exposes_ingress_handle_and_shutdown_status() {
    let args = ClientSyncStartArgs {
        events_tx: event_sender(),
        snapshot_builder: Arc::new(StaticSnapshotBuilder),
        ingress_capacity: 4,
    };

    let handle = spawn_client_sync(args).expect("valid client-sync start args");
    handle
        .ingress_tx
        .send(ClientSyncIngress::Shutdown)
        .await
        .expect("send shutdown");

    assert_eq!(
        handle.join_handle.await.expect("join client-sync task"),
        ClientSyncExitStatus::Stopped
    );
}

#[test]
fn spawn_client_sync_rejects_empty_ingress_capacity() {
    let args = ClientSyncStartArgs {
        events_tx: event_sender(),
        snapshot_builder: Arc::new(StaticSnapshotBuilder),
        ingress_capacity: 0,
    };

    assert!(matches!(
        spawn_client_sync(args),
        Err(SpawnClientSyncError::InvalidIngressCapacity)
    ));
}

#[test]
fn client_sync_ingress_carries_cancellation_identity() {
    let cancel = CancelHydration {
        client_id: ClientId("client-1".to_owned()),
        client_command_id: ClientCommandId("attach-1".to_owned()),
    };

    match ClientSyncIngress::CancelHydration(cancel) {
        ClientSyncIngress::CancelHydration(cancel) => {
            assert_eq!(cancel.client_id, ClientId("client-1".to_owned()));
            assert_eq!(
                cancel.client_command_id,
                ClientCommandId("attach-1".to_owned())
            );
        }
        _ => panic!("unexpected ingress"),
    }
}

struct StaticSnapshotBuilder;

impl ClientSnapshotBuilder for StaticSnapshotBuilder {
    fn build_snapshot(&self, request: ClientSnapshotBuildRequest) -> ClientSnapshotBuildFuture {
        assert_eq!(request.client_id.0.trim(), request.client_id.0);
        Box::pin(snapshot_future())
    }
}

fn snapshot_future() -> Pin<Box<dyn Future<Output = Result<ClientSnapshot, ClientSyncError>> + Send>>
{
    Box::pin(async {
        Ok(ClientSnapshot {
            generated_at: selvedge_domain_model::UnixTs(1),
            tasks: Vec::new(),
            task_parent_edges: Vec::new(),
            history_nodes: Vec::new(),
            task_versions: Vec::new(),
        })
    })
}

fn build_request(client_id: &str, client_command_id: &str) -> ClientSnapshotBuildRequest {
    ClientSnapshotBuildRequest {
        client_id: ClientId(client_id.to_owned()),
        client_command_id: ClientCommandId(client_command_id.to_owned()),
        subscription: ClientSubscription {
            task_scope: TaskScope::AllTasks,
            detail_level: DetailLevel::Summary,
            include_model_call_status: false,
            include_tool_execution_status: false,
            include_debug_notices: false,
        },
    }
}

fn event_sender() -> EventIngressSender {
    let (tx, _rx) = tokio::sync::mpsc::channel::<EventIngress>(4);
    tx
}
