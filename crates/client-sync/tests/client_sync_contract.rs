use std::collections::{BTreeSet, VecDeque};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use selvedge_client_sync::{
    CancelHydration, ClientSnapshotBuildFuture, ClientSnapshotBuildRequest, ClientSnapshotBuilder,
    ClientSyncError, ClientSyncExitStatus, ClientSyncIngress, ClientSyncSender,
    ClientSyncStartArgs, SpawnClientSyncError, spawn_client_sync,
};
use selvedge_command_model::{
    BeginClientHydration, ClientCommandId, ClientFrame, ClientId, ClientNoticeLevel,
    ClientSessionIdentity, ClientSnapshot, ClientSubscription, DetachReason, DetailLevel,
    EventControlMessage, EventIngress, TaskScope,
};
use selvedge_domain_model::UnixTs;
use tokio::sync::{mpsc, oneshot};
use tokio::time::{Duration, timeout};

#[tokio::test]
async fn successful_hydration_sends_begin_before_snapshot() {
    let session_1 = session("client-1", "attach-1");
    let (events_tx, mut events_rx) = mpsc::channel(8);
    let builder = Arc::new(RecordingBuilder::new(vec![BuildAction::Ready(Ok(
        empty_snapshot(),
    ))]));
    let handle = spawn_client_sync(ClientSyncStartArgs {
        events_tx,
        snapshot_builder: builder.clone(),
        ingress_capacity: 8,
    })
    .expect("spawn client sync");

    handle
        .ingress_tx
        .send(ClientSyncIngress::StartHydration(begin(&session_1)))
        .await
        .expect("send start");

    let begin = recv_control(&mut events_rx).await;
    assert_begin(&begin, &session_1);
    let snapshot = recv_control(&mut events_rx).await;
    assert_snapshot(&snapshot, &session_1);
    assert_eq!(builder.requests(), vec![request(&session_1)]);

    shutdown(handle).await;
}

#[tokio::test]
async fn builder_failure_sends_error_notice_then_detach() {
    let session_1 = session("client-1", "attach-1");
    let (events_tx, mut events_rx) = mpsc::channel(8);
    let builder = Arc::new(RecordingBuilder::new(vec![BuildAction::Ready(Err(
        ClientSyncError::SnapshotBuildFailed("db unavailable".to_owned()),
    ))]));
    let handle = spawn_client_sync(ClientSyncStartArgs {
        events_tx,
        snapshot_builder: builder,
        ingress_capacity: 8,
    })
    .expect("spawn client sync");

    handle
        .ingress_tx
        .send(ClientSyncIngress::StartHydration(begin(&session_1)))
        .await
        .expect("send start");

    assert_begin(&recv_control(&mut events_rx).await, &session_1);
    let notice = recv_control(&mut events_rx).await;
    match notice {
        EventControlMessage::DeliverNotice(notice) => {
            assert_eq!(*notice.session.client_id(), ClientId("client-1".to_owned()));
            assert_eq!(
                notice.client_command_id,
                ClientCommandId("attach-1".to_owned())
            );
            assert_eq!(notice.notice.level, ClientNoticeLevel::Error);
            assert!(notice.notice.message_text.contains("db unavailable"));
        }
        other => panic!("expected notice, got {other:?}"),
    }
    let detach = recv_control(&mut events_rx).await;
    match detach {
        EventControlMessage::DetachClient(detach) => {
            assert_eq!(*detach.session.client_id(), ClientId("client-1".to_owned()));
            assert_eq!(
                *detach.session.attach_command_id(),
                ClientCommandId("attach-1".to_owned())
            );
            assert_eq!(detach.reason, DetachReason::DeliveryFailed);
        }
        other => panic!("expected detach, got {other:?}"),
    }

    shutdown(handle).await;
}

#[tokio::test]
async fn begin_send_failure_does_not_call_builder() {
    let session_1 = session("client-1", "attach-1");
    let (events_tx, events_rx) = mpsc::channel(1);
    drop(events_rx);
    let builder = Arc::new(RecordingBuilder::new(vec![BuildAction::Ready(Ok(
        empty_snapshot(),
    ))]));
    let handle = spawn_client_sync(ClientSyncStartArgs {
        events_tx,
        snapshot_builder: builder.clone(),
        ingress_capacity: 8,
    })
    .expect("spawn client sync");

    handle
        .ingress_tx
        .send(ClientSyncIngress::StartHydration(begin(&session_1)))
        .await
        .expect("send start");

    let status = handle.join_handle.await.expect("join client sync");
    assert!(matches!(
        status,
        ClientSyncExitStatus::Fatal(message)
            if message.contains("beginning client hydration")
    ));
    assert!(builder.requests().is_empty());
}

#[tokio::test]
async fn snapshot_delivery_send_failure_is_fatal() {
    let session_1 = session("client-1", "attach-1");
    let (events_tx, mut events_rx) = mpsc::channel(8);
    let (release_tx, release_rx) = oneshot::channel();
    let builder = Arc::new(RecordingBuilder::new(vec![BuildAction::Wait(release_rx)]));
    let handle = spawn_client_sync(ClientSyncStartArgs {
        events_tx,
        snapshot_builder: builder,
        ingress_capacity: 8,
    })
    .expect("spawn client sync");

    handle
        .ingress_tx
        .send(ClientSyncIngress::StartHydration(begin(&session_1)))
        .await
        .expect("send start");
    assert_begin(&recv_control(&mut events_rx).await, &session_1);
    drop(events_rx);

    release_tx
        .send(Ok(empty_snapshot()))
        .expect("release builder");

    expect_fatal_contains(handle, "delivering client snapshot").await;
}

#[tokio::test]
async fn builder_failure_notice_send_failure_is_fatal() {
    let session_1 = session("client-1", "attach-1");
    let (events_tx, mut events_rx) = mpsc::channel(8);
    let (release_tx, release_rx) = oneshot::channel();
    let builder = Arc::new(RecordingBuilder::new(vec![BuildAction::Wait(release_rx)]));
    let handle = spawn_client_sync(ClientSyncStartArgs {
        events_tx,
        snapshot_builder: builder,
        ingress_capacity: 8,
    })
    .expect("spawn client sync");

    handle
        .ingress_tx
        .send(ClientSyncIngress::StartHydration(begin(&session_1)))
        .await
        .expect("send start");
    assert_begin(&recv_control(&mut events_rx).await, &session_1);
    drop(events_rx);

    release_tx
        .send(Err(ClientSyncError::SnapshotBuildFailed(
            "db unavailable".to_owned(),
        )))
        .expect("release builder");

    expect_fatal_contains(handle, "delivering client hydration failure notice").await;
}

#[tokio::test]
async fn duplicate_same_command_does_not_start_second_builder() {
    let session_1 = session("client-1", "attach-1");
    let (events_tx, mut events_rx) = mpsc::channel(8);
    let (_release_tx, release_rx) = oneshot::channel();
    let builder = Arc::new(RecordingBuilder::new(vec![BuildAction::Wait(release_rx)]));
    let handle = spawn_client_sync(ClientSyncStartArgs {
        events_tx,
        snapshot_builder: builder.clone(),
        ingress_capacity: 8,
    })
    .expect("spawn client sync");

    handle
        .ingress_tx
        .send(ClientSyncIngress::StartHydration(begin(&session_1)))
        .await
        .expect("send first start");
    handle
        .ingress_tx
        .send(ClientSyncIngress::StartHydration(begin(&session_1)))
        .await
        .expect("send duplicate start");

    assert_begin(&recv_control(&mut events_rx).await, &session_1);
    tokio::time::sleep(Duration::from_millis(10)).await;
    assert_eq!(builder.requests().len(), 1);
    assert!(recv_control_timeout(&mut events_rx).await.is_none());

    shutdown(handle).await;
}

#[tokio::test]
async fn completed_hydration_remains_schedulable_during_sustained_ingress() {
    let session_1 = session("client-1", "attach-1");
    const FLOOD_COUNT: usize = 64;

    let (events_tx, mut events_rx) = mpsc::channel(FLOOD_COUNT * 4);
    let builder = Arc::new(FloodingBuilder::new(FLOOD_COUNT));
    let handle = spawn_client_sync(ClientSyncStartArgs {
        events_tx,
        snapshot_builder: builder.clone(),
        ingress_capacity: FLOOD_COUNT,
    })
    .expect("spawn client sync");
    builder.set_ingress_tx(handle.ingress_tx.clone());

    handle
        .ingress_tx
        .send(ClientSyncIngress::StartHydration(begin(&session_1)))
        .await
        .expect("send start");

    let mut begins_before_snapshot = 0;
    loop {
        match recv_control(&mut events_rx).await {
            EventControlMessage::BeginClientHydration(_) => begins_before_snapshot += 1,
            EventControlMessage::DeliverSnapshot(snapshot) => {
                assert_eq!(
                    *snapshot.session.client_id(),
                    ClientId("client-1".to_owned())
                );
                break;
            }
            other => panic!("unexpected hydration event: {other:?}"),
        }
    }
    assert!(
        begins_before_snapshot < FLOOD_COUNT + 1,
        "completed snapshot was starved until ingress drained"
    );

    shutdown(handle).await;
}

#[tokio::test]
async fn new_command_aborts_old_builder() {
    let session_1 = session("client-1", "attach-1");
    let session_2 = session("client-1", "attach-2");
    let (events_tx, mut events_rx) = mpsc::channel(8);
    let (mut old_tx, old_rx) = oneshot::channel();
    let (new_tx, new_rx) = oneshot::channel();
    let builder = Arc::new(RecordingBuilder::new(vec![
        BuildAction::Wait(old_rx),
        BuildAction::Wait(new_rx),
    ]));
    let handle = spawn_client_sync(ClientSyncStartArgs {
        events_tx,
        snapshot_builder: builder,
        ingress_capacity: 8,
    })
    .expect("spawn client sync");

    handle
        .ingress_tx
        .send(ClientSyncIngress::StartHydration(begin(&session_1)))
        .await
        .expect("send old start");
    assert_begin(&recv_control(&mut events_rx).await, &session_1);

    handle
        .ingress_tx
        .send(ClientSyncIngress::StartHydration(begin(&session_2)))
        .await
        .expect("send new start");
    assert_begin(&recv_control(&mut events_rx).await, &session_2);

    timeout(Duration::from_secs(1), old_tx.closed())
        .await
        .expect("old builder was not aborted");
    assert!(recv_control_timeout(&mut events_rx).await.is_none());

    new_tx.send(Ok(empty_snapshot())).expect("release new");
    assert_snapshot(&recv_control(&mut events_rx).await, &session_2);

    shutdown(handle).await;
}

#[tokio::test]
async fn cancel_aborts_builder() {
    let session_1 = session("client-1", "attach-1");
    let (events_tx, mut events_rx) = mpsc::channel(8);
    let (mut release_tx, release_rx) = oneshot::channel();
    let builder = Arc::new(RecordingBuilder::new(vec![BuildAction::Wait(release_rx)]));
    let handle = spawn_client_sync(ClientSyncStartArgs {
        events_tx,
        snapshot_builder: builder,
        ingress_capacity: 8,
    })
    .expect("spawn client sync");

    handle
        .ingress_tx
        .send(ClientSyncIngress::StartHydration(begin(&session_1)))
        .await
        .expect("send start");
    assert_begin(&recv_control(&mut events_rx).await, &session_1);
    handle
        .ingress_tx
        .send(ClientSyncIngress::CancelHydration(CancelHydration {
            session: session_1.clone(),
        }))
        .await
        .expect("send cancel");

    timeout(Duration::from_secs(1), release_tx.closed())
        .await
        .expect("cancelled builder was not aborted");
    assert!(recv_control_timeout(&mut events_rx).await.is_none());

    shutdown(handle).await;
}

#[tokio::test]
async fn queued_cancel_precedes_a_completed_builder_result() {
    for trial in 0..16 {
        let session_1 = session("client-1", "attach-1");
        let session_2 = session("gate", "gate");
        let session_3 = session("blocker", "blocker");
        let (events_tx, mut events_rx) = mpsc::channel(1);
        let gate_tx = events_tx.clone();
        let (release_tx, release_rx) = oneshot::channel();
        let (_blocker_tx, blocker_rx) = oneshot::channel();
        let builder = Arc::new(RecordingBuilder::new(vec![
            BuildAction::Wait(release_rx),
            BuildAction::Wait(blocker_rx),
        ]));
        let handle = spawn_client_sync(ClientSyncStartArgs {
            events_tx,
            snapshot_builder: builder,
            ingress_capacity: 1,
        })
        .expect("spawn client sync");

        handle
            .ingress_tx
            .send(ClientSyncIngress::StartHydration(begin(&session_1)))
            .await
            .expect("send target start");
        assert_begin(&recv_control(&mut events_rx).await, &session_1);

        gate_tx
            .send(EventIngress::Control(
                EventControlMessage::BeginClientHydration(begin(&session_2)),
            ))
            .await
            .expect("fill events mailbox");
        handle
            .ingress_tx
            .send(ClientSyncIngress::StartHydration(begin(&session_3)))
            .await
            .expect("send blocker start");
        drop(
            timeout(Duration::from_secs(1), handle.ingress_tx.reserve())
                .await
                .expect("blocker was not received")
                .expect("reserve ingress capacity"),
        );

        release_tx
            .send(Ok(empty_snapshot()))
            .expect("release target builder");
        tokio::task::yield_now().await;
        tokio::task::yield_now().await;
        handle
            .ingress_tx
            .try_send(ClientSyncIngress::CancelHydration(CancelHydration {
                session: session_1.clone(),
            }))
            .expect("queue cancel");

        assert_begin(&recv_control(&mut events_rx).await, &session_2);
        assert_begin(&recv_control(&mut events_rx).await, &session_3);
        assert!(
            recv_control_timeout(&mut events_rx).await.is_none(),
            "trial {trial} delivered a snapshot after its cancellation was queued"
        );

        shutdown(handle).await;
    }
}

#[tokio::test]
async fn shutdown_aborts_builder_before_task_stops() {
    let session_1 = session("client-1", "attach-1");
    let (events_tx, mut events_rx) = mpsc::channel(8);
    let (mut release_tx, release_rx) = oneshot::channel();
    let builder = Arc::new(RecordingBuilder::new(vec![BuildAction::Wait(release_rx)]));
    let handle = spawn_client_sync(ClientSyncStartArgs {
        events_tx,
        snapshot_builder: builder,
        ingress_capacity: 8,
    })
    .expect("spawn client sync");

    handle
        .ingress_tx
        .send(ClientSyncIngress::StartHydration(begin(&session_1)))
        .await
        .expect("send start");
    assert_begin(&recv_control(&mut events_rx).await, &session_1);
    handle
        .ingress_tx
        .send(ClientSyncIngress::Shutdown)
        .await
        .expect("send shutdown");
    assert_eq!(
        handle.join_handle.await.expect("join client sync"),
        ClientSyncExitStatus::Stopped
    );

    timeout(Duration::from_secs(1), release_tx.closed())
        .await
        .expect("builder remained live after shutdown");
    assert!(recv_control_timeout(&mut events_rx).await.is_none());
}

#[tokio::test]
async fn invalid_ingress_capacity_is_rejected() {
    let (events_tx, _events_rx) = mpsc::channel(8);
    let builder = Arc::new(RecordingBuilder::new(Vec::new()));

    let result = spawn_client_sync(ClientSyncStartArgs {
        events_tx,
        snapshot_builder: builder,
        ingress_capacity: 0,
    });

    assert!(matches!(
        result,
        Err(SpawnClientSyncError::InvalidIngressCapacity)
    ));
}

enum BuildAction {
    Ready(Result<ClientSnapshot, ClientSyncError>),
    Wait(oneshot::Receiver<Result<ClientSnapshot, ClientSyncError>>),
}

struct RecordingBuilder {
    actions: Mutex<VecDeque<BuildAction>>,
    requests: Mutex<Vec<ClientSnapshotBuildRequest>>,
}

struct FloodingBuilder {
    ingress_tx: Mutex<Option<ClientSyncSender>>,
    flood_once: AtomicBool,
    flood_count: usize,
}

impl FloodingBuilder {
    fn new(flood_count: usize) -> Self {
        Self {
            ingress_tx: Mutex::new(None),
            flood_once: AtomicBool::new(true),
            flood_count,
        }
    }

    fn set_ingress_tx(&self, ingress_tx: ClientSyncSender) {
        *self.ingress_tx.lock().expect("ingress sender lock") = Some(ingress_tx);
    }
}

impl ClientSnapshotBuilder for FloodingBuilder {
    fn build_snapshot(&self, _request: ClientSnapshotBuildRequest) -> ClientSnapshotBuildFuture {
        let ingress_tx = self
            .ingress_tx
            .lock()
            .expect("ingress sender lock")
            .clone()
            .expect("ingress sender");
        let flood_count = self.flood_count;
        let should_flood = self.flood_once.swap(false, Ordering::SeqCst);

        Box::pin(async move {
            if should_flood {
                for index in 0..flood_count {
                    ingress_tx
                        .try_send(ClientSyncIngress::StartHydration(begin(&session(
                            &format!("flood-client-{index}"),
                            &format!("flood-attach-{index}"),
                        ))))
                        .expect("fill ingress");
                }
            }
            Ok(empty_snapshot())
        })
    }
}

impl RecordingBuilder {
    fn new(actions: Vec<BuildAction>) -> Self {
        Self {
            actions: Mutex::new(actions.into()),
            requests: Mutex::new(Vec::new()),
        }
    }

    fn requests(&self) -> Vec<ClientSnapshotBuildRequest> {
        self.requests.lock().expect("requests lock").clone()
    }
}

impl ClientSnapshotBuilder for RecordingBuilder {
    fn build_snapshot(&self, request: ClientSnapshotBuildRequest) -> ClientSnapshotBuildFuture {
        self.requests.lock().expect("requests lock").push(request);
        let action = self
            .actions
            .lock()
            .expect("actions lock")
            .pop_front()
            .expect("builder action");

        Box::pin(async move {
            match action {
                BuildAction::Ready(result) => result,
                BuildAction::Wait(rx) => rx.await.unwrap_or(Err(ClientSyncError::RequestCancelled)),
            }
        })
    }
}

fn begin(session: &ClientSessionIdentity) -> BeginClientHydration {
    let (outbound, _rx) = mpsc::channel::<ClientFrame>(8);
    BeginClientHydration {
        session: session.clone(),
        outbound,
        subscription: subscription(),
    }
}

fn request(session: &ClientSessionIdentity) -> ClientSnapshotBuildRequest {
    ClientSnapshotBuildRequest {
        session: session.clone(),
        subscription: subscription(),
    }
}

fn subscription() -> ClientSubscription {
    ClientSubscription {
        task_scope: TaskScope::TaskIds(BTreeSet::new()),
        detail_level: DetailLevel::Summary,
        snapshot_mode: selvedge_command_model::SnapshotMode::CurrentState,
        include_model_call_status: false,
        include_tool_execution_status: false,
        include_debug_notices: false,
    }
}

fn empty_snapshot() -> ClientSnapshot {
    ClientSnapshot {
        generated_at: UnixTs(1),
        tasks: Vec::new(),
        task_parent_edges: Vec::new(),
        history_nodes: Vec::new(),
        task_versions: Vec::new(),
    }
}

async fn recv_control(rx: &mut mpsc::Receiver<EventIngress>) -> EventControlMessage {
    match timeout(Duration::from_secs(1), rx.recv())
        .await
        .expect("event timeout")
        .expect("event")
    {
        EventIngress::Control(control) => control,
        EventIngress::Publish(_) => panic!("expected control event"),
    }
}

async fn recv_control_timeout(
    rx: &mut mpsc::Receiver<EventIngress>,
) -> Option<EventControlMessage> {
    match timeout(Duration::from_millis(10), rx.recv()).await {
        Ok(Some(EventIngress::Control(control))) => Some(control),
        Ok(Some(EventIngress::Publish(_))) => panic!("expected control event"),
        Ok(None) | Err(_) => None,
    }
}

fn assert_begin(control: &EventControlMessage, session: &ClientSessionIdentity) {
    match control {
        EventControlMessage::BeginClientHydration(begin) => assert_eq!(&begin.session, session),
        other => panic!("expected begin, got {other:?}"),
    }
}

fn assert_snapshot(control: &EventControlMessage, session: &ClientSessionIdentity) {
    match control {
        EventControlMessage::DeliverSnapshot(snapshot) => assert_eq!(&snapshot.session, session),
        other => panic!("expected snapshot, got {other:?}"),
    }
}

async fn shutdown(handle: selvedge_client_sync::ClientSyncHandle) {
    handle
        .ingress_tx
        .send(ClientSyncIngress::Shutdown)
        .await
        .expect("send shutdown");
    assert_eq!(
        handle.join_handle.await.expect("join client sync"),
        ClientSyncExitStatus::Stopped
    );
}

async fn expect_fatal_contains(handle: selvedge_client_sync::ClientSyncHandle, expected: &str) {
    let status = handle.join_handle.await.expect("join client sync");
    assert!(matches!(
        status,
        ClientSyncExitStatus::Fatal(message) if message.contains(expected)
    ));
}

fn session(client_id: &str, command_id: &str) -> ClientSessionIdentity {
    ClientSessionIdentity::new(
        ClientId(client_id.to_owned()),
        ClientCommandId(command_id.to_owned()),
    )
}

#[tokio::test]
async fn stale_cancel_does_not_abort_reused_attach_command_generation() {
    let old_a = session("client-1", "a");
    let b = session("client-1", "b");
    let new_a = session("client-1", "a");
    let (events_tx, mut events_rx) = mpsc::channel(8);
    let (mut old_tx, old_rx) = oneshot::channel();
    let (mut b_tx, b_rx) = oneshot::channel();
    let (new_tx, new_rx) = oneshot::channel();
    let builder = Arc::new(RecordingBuilder::new(vec![
        BuildAction::Wait(old_rx),
        BuildAction::Wait(b_rx),
        BuildAction::Wait(new_rx),
    ]));
    let handle = spawn_client_sync(ClientSyncStartArgs {
        events_tx,
        snapshot_builder: builder.clone(),
        ingress_capacity: 8,
    })
    .expect("client sync");
    for identity in [&old_a, &b, &new_a] {
        handle
            .ingress_tx
            .send(ClientSyncIngress::StartHydration(begin(identity)))
            .await
            .expect("start generation");
        assert_begin(&recv_control(&mut events_rx).await, identity);
    }
    timeout(Duration::from_secs(1), old_tx.closed())
        .await
        .expect("old A builder aborted");
    timeout(Duration::from_secs(1), b_tx.closed())
        .await
        .expect("B builder aborted");
    for identity in [&old_a, &b] {
        handle
            .ingress_tx
            .send(ClientSyncIngress::CancelHydration(CancelHydration {
                session: identity.clone(),
            }))
            .await
            .expect("stale cancellation");
    }
    new_tx.send(Ok(empty_snapshot())).expect("finish newest A");
    assert_snapshot(&recv_control(&mut events_rx).await, &new_a);
    assert_eq!(
        builder.requests(),
        vec![request(&old_a), request(&b), request(&new_a)]
    );
    assert!(recv_control_timeout(&mut events_rx).await.is_none());
    shutdown(handle).await;
}
