use std::{collections::BTreeSet, time::Duration};

use selvedge_command_model::{
    BeginClientHydration, ClientCommandId, ClientEvent, ClientFrame, ClientId, ClientNotice,
    ClientNoticeLevel, ClientSessionIdentity, ClientSnapshot, ClientSubscription, DebugNoticeEvent,
    DeliverNotice, DeliverSnapshot, DetachClient, DetachReason, DetailLevel,
    EventClientReservationResult, EventControlMessage, EventIngress, HistoryAppendedEvent,
    ReserveClientSession, SnapshotTaskVersion, TaskChangedEvent, TaskProjection, TaskScope,
    TaskStatus, UpdateSubscription,
};
use selvedge_domain_model::{
    HistoryNodeId, ModelProfileKey, ReasoningEffort, TaskId, TaskModelConfig, UnixTs,
};
use selvedge_events::{EventsStartArgs, SpawnEventsError, spawn_events_task};
use tokio::sync::mpsc;

#[tokio::test]
async fn spawn_events_task_validates_capacities_and_stops_after_mailbox_close() {
    assert_eq!(
        spawn_events_task(EventsStartArgs {
            ingress_capacity: 0,
            client_registry_capacity: 1,
            hydration_buffer_capacity: 1,
        })
        .expect_err("invalid ingress capacity"),
        SpawnEventsError::InvalidIngressCapacity
    );

    assert_eq!(
        spawn_events_task(EventsStartArgs {
            ingress_capacity: 1,
            client_registry_capacity: 0,
            hydration_buffer_capacity: 1,
        })
        .expect_err("invalid registry capacity"),
        SpawnEventsError::InvalidClientRegistryCapacity
    );

    assert_eq!(
        spawn_events_task(EventsStartArgs {
            ingress_capacity: 1,
            client_registry_capacity: 1,
            hydration_buffer_capacity: 0,
        })
        .expect_err("invalid buffer capacity"),
        SpawnEventsError::InvalidHydrationBufferCapacity
    );

    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 4,
        client_registry_capacity: 4,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");

    drop(handle.ingress_tx);
    handle.join_handle.await.expect("events task exits cleanly");
}

#[tokio::test]
async fn hydrating_client_receives_snapshot_before_uncovered_buffered_events() {
    let session_1 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 8,
        client_registry_capacity: 4,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");
    let (outbound, mut outbound_rx) = mpsc::channel(8);

    begin_client(
        &handle.ingress_tx,
        &session_1,
        outbound,
        verbose_all_tasks(),
    )
    .await;

    handle
        .ingress_tx
        .send(EventIngress::Publish(ClientEvent::TaskChanged(
            TaskChangedEvent {
                task: task_projection("task-1", 1),
            },
        )))
        .await
        .expect("send covered task event");

    handle
        .ingress_tx
        .send(EventIngress::Publish(ClientEvent::HistoryAppended(
            HistoryAppendedEvent {
                task_id: TaskId("task-1".to_owned()),
                task_state_version: 3,
                appended_nodes: Vec::new(),
            },
        )))
        .await
        .expect("send uncovered history event");

    handle
        .ingress_tx
        .send(EventIngress::Control(EventControlMessage::DeliverSnapshot(
            DeliverSnapshot {
                session: session_1.clone(),
                snapshot: ClientSnapshot {
                    generated_at: UnixTs(100),
                    tasks: vec![task_projection("task-1", 2)],
                    task_parent_edges: Vec::new(),
                    history_nodes: Vec::new(),
                    task_versions: vec![SnapshotTaskVersion {
                        task_id: TaskId("task-1".to_owned()),
                        state_version: 2,
                    }],
                },
            },
        )))
        .await
        .expect("send snapshot");

    let snapshot = recv_frame(&mut outbound_rx).await;
    match snapshot {
        ClientFrame::Snapshot(frame) => {
            assert_eq!(frame.delivery_seq.0, 1);
            assert_eq!(
                frame.client_command_id,
                ClientCommandId("attach-1".to_owned())
            );
            assert_eq!(frame.snapshot.task_versions[0].state_version, 2);
        }
        _ => panic!("expected snapshot frame"),
    }

    let event = recv_frame(&mut outbound_rx).await;
    match event {
        ClientFrame::Event(frame) => {
            assert_eq!(frame.delivery_seq.0, 2);
            match frame.event {
                ClientEvent::HistoryAppended(history) => {
                    assert_eq!(history.task_id, TaskId("task-1".to_owned()));
                    assert_eq!(history.task_state_version, 3);
                }
                _ => panic!("expected history event"),
            }
        }
        _ => panic!("expected event frame"),
    }

    assert!(
        tokio::time::timeout(Duration::from_millis(50), outbound_rx.recv())
            .await
            .is_err()
    );

    drop(handle.ingress_tx);
    handle.join_handle.await.expect("events task exits cleanly");
}

#[tokio::test]
async fn live_client_receives_only_events_allowed_by_subscription() {
    let session_1 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 8,
        client_registry_capacity: 4,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");
    let (outbound, mut outbound_rx) = mpsc::channel(8);

    begin_client(
        &handle.ingress_tx,
        &session_1,
        outbound,
        summary_task_subscription("task-1"),
    )
    .await;
    deliver_empty_snapshot(&handle.ingress_tx, &session_1).await;
    assert!(matches!(
        recv_frame(&mut outbound_rx).await,
        ClientFrame::Snapshot(_)
    ));

    handle
        .ingress_tx
        .send(EventIngress::Publish(ClientEvent::HistoryAppended(
            HistoryAppendedEvent {
                task_id: TaskId("task-1".to_owned()),
                task_state_version: 3,
                appended_nodes: Vec::new(),
            },
        )))
        .await
        .expect("send verbose event filtered by summary detail");

    handle
        .ingress_tx
        .send(EventIngress::Publish(ClientEvent::TaskChanged(
            TaskChangedEvent {
                task: task_projection("task-2", 3),
            },
        )))
        .await
        .expect("send event filtered by task scope");

    handle
        .ingress_tx
        .send(EventIngress::Publish(ClientEvent::TaskChanged(
            TaskChangedEvent {
                task: task_projection("task-1", 4),
            },
        )))
        .await
        .expect("send allowed task event");

    let task_changed = recv_frame(&mut outbound_rx).await;
    match task_changed {
        ClientFrame::Event(frame) => {
            assert_eq!(frame.delivery_seq.0, 2);
            assert!(matches!(frame.event, ClientEvent::TaskChanged(_)));
        }
        _ => panic!("expected task changed event"),
    }

    handle
        .ingress_tx
        .send(EventIngress::Publish(ClientEvent::DebugNotice(
            DebugNoticeEvent {
                task_id: Some(TaskId("task-1".to_owned())),
                message_text: "debug".to_owned(),
            },
        )))
        .await
        .expect("send allowed debug event");

    let debug = recv_frame(&mut outbound_rx).await;
    match debug {
        ClientFrame::Event(frame) => {
            assert_eq!(frame.delivery_seq.0, 3);
            assert!(matches!(frame.event, ClientEvent::DebugNotice(_)));
        }
        _ => panic!("expected debug event"),
    }

    assert!(
        tokio::time::timeout(Duration::from_millis(50), outbound_rx.recv())
            .await
            .is_err()
    );

    drop(handle.ingress_tx);
    handle.join_handle.await.expect("events task exits cleanly");
}

#[tokio::test]
async fn hydrating_subscription_update_rescreens_buffer_before_snapshot_flush() {
    let session_1 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 8,
        client_registry_capacity: 4,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");
    let (outbound, mut outbound_rx) = mpsc::channel(8);

    begin_client(
        &handle.ingress_tx,
        &session_1,
        outbound,
        verbose_all_tasks(),
    )
    .await;
    handle
        .ingress_tx
        .send(EventIngress::Publish(ClientEvent::HistoryAppended(
            HistoryAppendedEvent {
                task_id: TaskId("task-1".to_owned()),
                task_state_version: 3,
                appended_nodes: Vec::new(),
            },
        )))
        .await
        .expect("send buffered event");

    handle
        .ingress_tx
        .send(EventIngress::Control(
            EventControlMessage::UpdateSubscription(UpdateSubscription {
                session: session_1.clone(),
                subscription: summary_task_subscription("task-2"),
            }),
        ))
        .await
        .expect("send subscription update");

    deliver_empty_snapshot(&handle.ingress_tx, &session_1).await;
    assert!(matches!(
        recv_frame(&mut outbound_rx).await,
        ClientFrame::Snapshot(_)
    ));
    assert!(
        tokio::time::timeout(Duration::from_millis(50), outbound_rx.recv())
            .await
            .is_err()
    );

    drop(handle.ingress_tx);
    handle.join_handle.await.expect("events task exits cleanly");
}

#[tokio::test]
async fn hydrating_buffer_overflow_removes_client_session() {
    let session_1 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 8,
        client_registry_capacity: 4,
        hydration_buffer_capacity: 1,
    })
    .expect("valid events task");
    let (outbound, mut outbound_rx) = mpsc::channel(8);

    begin_client(
        &handle.ingress_tx,
        &session_1,
        outbound,
        verbose_all_tasks(),
    )
    .await;

    for state_version in [1, 2] {
        handle
            .ingress_tx
            .send(EventIngress::Publish(ClientEvent::TaskChanged(
                TaskChangedEvent {
                    task: task_projection("task-1", state_version),
                },
            )))
            .await
            .expect("send raw event");
    }

    let closed = tokio::time::timeout(Duration::from_secs(1), outbound_rx.recv())
        .await
        .expect("client channel closes after overflow");
    assert!(closed.is_none());

    drop(handle.ingress_tx);
    handle.join_handle.await.expect("events task exits cleanly");
}

#[tokio::test]
async fn registry_capacity_rejects_new_clients_after_limit() {
    let session_1 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let session_2 = ClientSessionIdentity::new(
        ClientId("client-2".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 8,
        client_registry_capacity: 1,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");
    let (first_outbound, mut first_rx) = mpsc::channel(8);
    let (second_outbound, mut second_rx) = mpsc::channel(8);

    begin_client(
        &handle.ingress_tx,
        &session_1,
        first_outbound,
        verbose_all_tasks(),
    )
    .await;
    begin_client(
        &handle.ingress_tx,
        &session_2,
        second_outbound,
        verbose_all_tasks(),
    )
    .await;

    let rejected = tokio::time::timeout(Duration::from_secs(1), second_rx.recv())
        .await
        .expect("rejected client channel closes");
    assert!(rejected.is_none());

    deliver_empty_snapshot(&handle.ingress_tx, &session_1).await;
    assert!(matches!(
        recv_frame(&mut first_rx).await,
        ClientFrame::Snapshot(_)
    ));

    drop(handle.ingress_tx);
    handle.join_handle.await.expect("events task exits cleanly");
}

#[tokio::test]
async fn reservation_capacity_rejects_new_clients_after_limit() {
    let session_1 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let session_2 = ClientSessionIdentity::new(
        ClientId("client-2".to_owned()),
        ClientCommandId("attach-2".to_owned()),
    );
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 8,
        client_registry_capacity: 1,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");

    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &session_1).await,
        EventClientReservationResult::Reserved
    );
    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &session_2).await,
        EventClientReservationResult::ClientRegistryFull
    );

    drop(handle.ingress_tx);
    handle.join_handle.await.expect("events task exits cleanly");
}

#[tokio::test]
async fn replacement_reservation_shares_existing_client_capacity_slot() {
    let session_1 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let session_2 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-2".to_owned()),
    );
    let session_3 = ClientSessionIdentity::new(
        ClientId("client-2".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let session_4 = ClientSessionIdentity::new(
        ClientId("client-3".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 8,
        client_registry_capacity: 2,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");
    let (outbound, _rx) = mpsc::channel(8);

    begin_client(
        &handle.ingress_tx,
        &session_1,
        outbound,
        verbose_all_tasks(),
    )
    .await;
    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &session_2).await,
        EventClientReservationResult::Reserved
    );
    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &session_3).await,
        EventClientReservationResult::Reserved
    );
    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &session_4).await,
        EventClientReservationResult::ClientRegistryFull
    );

    drop(handle.ingress_tx);
    handle.join_handle.await.expect("events task exits cleanly");
}

#[tokio::test]
async fn dropped_reservation_waiter_does_not_consume_capacity() {
    let session_1 = ClientSessionIdentity::new(
        ClientId("client-2".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let session_2 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 8,
        client_registry_capacity: 1,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");
    let (result_tx, result_rx) = tokio::sync::oneshot::channel();
    drop(result_rx);

    handle
        .ingress_tx
        .send(EventIngress::Control(
            EventControlMessage::ReserveClientSession(ReserveClientSession {
                session: session_2.clone(),
                result_tx,
            }),
        ))
        .await
        .expect("send abandoned reservation");
    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &session_1).await,
        EventClientReservationResult::Reserved
    );

    drop(handle.ingress_tx);
    handle.join_handle.await.expect("events task exits cleanly");
}

#[tokio::test]
async fn failed_pending_replacement_restores_previous_reservation() {
    let session_1 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let session_2 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-2".to_owned()),
    );
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 8,
        client_registry_capacity: 1,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");
    let (outbound, mut rx) = mpsc::channel(8);

    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &session_1).await,
        EventClientReservationResult::Reserved
    );
    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &session_2).await,
        EventClientReservationResult::Reserved
    );
    handle
        .ingress_tx
        .send(EventIngress::Control(EventControlMessage::DetachClient(
            DetachClient {
                session: session_2.clone(),
                reason: DetachReason::ClientDisconnected,
            },
        )))
        .await
        .expect("send failed replacement cleanup");
    begin_unreserved(
        &handle.ingress_tx,
        &session_1,
        outbound,
        verbose_all_tasks(),
    )
    .await;
    deliver_empty_snapshot(&handle.ingress_tx, &session_1).await;

    assert!(matches!(
        recv_frame(&mut rx).await,
        ClientFrame::Snapshot(_)
    ));

    drop(handle.ingress_tx);
    handle.join_handle.await.expect("events task exits cleanly");
}

#[tokio::test]
async fn hidden_begin_hydrates_after_failed_pending_replacement() {
    let session_1 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let session_2 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-2".to_owned()),
    );
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 8,
        client_registry_capacity: 1,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");
    let (outbound, mut rx) = mpsc::channel(8);

    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &session_1).await,
        EventClientReservationResult::Reserved
    );
    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &session_2).await,
        EventClientReservationResult::Reserved
    );
    begin_unreserved(
        &handle.ingress_tx,
        &session_1,
        outbound,
        verbose_all_tasks(),
    )
    .await;
    handle
        .ingress_tx
        .send(EventIngress::Control(EventControlMessage::DetachClient(
            DetachClient {
                session: session_2.clone(),
                reason: DetachReason::ClientDisconnected,
            },
        )))
        .await
        .expect("send failed replacement cleanup");
    deliver_empty_snapshot(&handle.ingress_tx, &session_1).await;

    assert!(matches!(
        recv_frame(&mut rx).await,
        ClientFrame::Snapshot(_)
    ));

    drop(handle.ingress_tx);
    handle.join_handle.await.expect("events task exits cleanly");
}

#[tokio::test]
async fn hidden_reservation_duplicate_is_rejected() {
    let session_1 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let session_2 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-2".to_owned()),
    );
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 8,
        client_registry_capacity: 1,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");

    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &session_1).await,
        EventClientReservationResult::Reserved
    );
    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &session_2).await,
        EventClientReservationResult::Reserved
    );
    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &session_1).await,
        EventClientReservationResult::DuplicateAttach
    );

    drop(handle.ingress_tx);
    handle.join_handle.await.expect("events task exits cleanly");
}

#[tokio::test]
async fn hidden_reservation_detach_prevents_later_restore() {
    let session_1 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let session_2 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-2".to_owned()),
    );
    let session_3 = ClientSessionIdentity::new(
        ClientId("client-2".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 8,
        client_registry_capacity: 1,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");
    let (outbound, mut rx) = mpsc::channel(8);

    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &session_1).await,
        EventClientReservationResult::Reserved
    );
    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &session_2).await,
        EventClientReservationResult::Reserved
    );
    begin_unreserved(
        &handle.ingress_tx,
        &session_1,
        outbound,
        verbose_all_tasks(),
    )
    .await;
    handle
        .ingress_tx
        .send(EventIngress::Control(EventControlMessage::DetachClient(
            DetachClient {
                session: session_1.clone(),
                reason: DetachReason::ClientDisconnected,
            },
        )))
        .await
        .expect("send hidden detach");
    handle
        .ingress_tx
        .send(EventIngress::Control(EventControlMessage::DetachClient(
            DetachClient {
                session: session_2.clone(),
                reason: DetachReason::ClientDisconnected,
            },
        )))
        .await
        .expect("send top detach");
    deliver_empty_snapshot(&handle.ingress_tx, &session_1).await;
    if let Ok(Some(_)) = tokio::time::timeout(Duration::from_millis(50), rx.recv()).await {
        panic!("detached hidden reservation should not receive frames");
    }
    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &session_3).await,
        EventClientReservationResult::Reserved
    );

    drop(handle.ingress_tx);
    handle.join_handle.await.expect("events task exits cleanly");
}

#[tokio::test]
async fn reserved_client_session_is_consumed_by_matching_begin() {
    let session_1 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let session_2 = ClientSessionIdentity::new(
        ClientId("client-2".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 8,
        client_registry_capacity: 1,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");
    let (reserved_outbound, mut reserved_rx) = mpsc::channel(8);
    let (blocked_outbound, mut blocked_rx) = mpsc::channel(8);

    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &session_1).await,
        EventClientReservationResult::Reserved
    );
    begin_client(
        &handle.ingress_tx,
        &session_2,
        blocked_outbound,
        verbose_all_tasks(),
    )
    .await;
    begin_client(
        &handle.ingress_tx,
        &session_1,
        reserved_outbound,
        verbose_all_tasks(),
    )
    .await;

    deliver_empty_snapshot(&handle.ingress_tx, &session_1).await;
    assert!(matches!(
        recv_frame(&mut reserved_rx).await,
        ClientFrame::Snapshot(_)
    ));
    assert!(
        tokio::time::timeout(Duration::from_secs(1), blocked_rx.recv())
            .await
            .expect("blocked client channel closes")
            .is_none()
    );

    drop(handle.ingress_tx);
    handle.join_handle.await.expect("events task exits cleanly");
}

#[tokio::test]
async fn begin_without_matching_reservation_does_not_create_session() {
    let session_1 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 8,
        client_registry_capacity: 1,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");
    let (outbound, mut rx) = mpsc::channel(8);

    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &session_1).await,
        EventClientReservationResult::Reserved
    );
    handle
        .ingress_tx
        .send(EventIngress::Control(EventControlMessage::DetachClient(
            DetachClient {
                session: session_1.clone(),
                reason: DetachReason::ClientDisconnected,
            },
        )))
        .await
        .expect("send detach");
    begin_unreserved(
        &handle.ingress_tx,
        &session_1,
        outbound,
        verbose_all_tasks(),
    )
    .await;
    deliver_empty_snapshot(&handle.ingress_tx, &session_1).await;

    assert!(
        tokio::time::timeout(Duration::from_secs(1), rx.recv())
            .await
            .expect("unreserved begin channel closes")
            .is_none()
    );

    drop(handle.ingress_tx);
    handle.join_handle.await.expect("events task exits cleanly");
}

#[tokio::test]
async fn notice_during_hydration_uses_current_delivery_sequence() {
    let session_1 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 8,
        client_registry_capacity: 4,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");
    let (outbound, mut outbound_rx) = mpsc::channel(8);

    begin_client(
        &handle.ingress_tx,
        &session_1,
        outbound,
        verbose_all_tasks(),
    )
    .await;
    handle
        .ingress_tx
        .send(EventIngress::Control(EventControlMessage::DeliverNotice(
            DeliverNotice {
                session: session_1.clone(),
                client_command_id: ClientCommandId("attach-1".to_owned()),
                notice: ClientNotice {
                    level: ClientNoticeLevel::Warning,
                    kind: selvedge_command_model::ClientNoticeKind::Text,
                    message_text: "heads up".to_owned(),
                },
            },
        )))
        .await
        .expect("send notice");
    deliver_empty_snapshot(&handle.ingress_tx, &session_1).await;

    let notice = recv_frame(&mut outbound_rx).await;
    match notice {
        ClientFrame::Notice(frame) => {
            assert_eq!(frame.delivery_seq.0, 1);
            assert_eq!(
                frame.client_command_id,
                ClientCommandId("attach-1".to_owned())
            );
            assert_eq!(frame.notice.level, ClientNoticeLevel::Warning);
        }
        _ => panic!("expected notice frame"),
    }

    let snapshot = recv_frame(&mut outbound_rx).await;
    match snapshot {
        ClientFrame::Snapshot(frame) => {
            assert_eq!(frame.delivery_seq.0, 2);
            assert_eq!(
                frame.client_command_id,
                ClientCommandId("attach-1".to_owned())
            );
        }
        _ => panic!("expected snapshot frame"),
    }

    drop(handle.ingress_tx);
    handle.join_handle.await.expect("events task exits cleanly");
}

#[tokio::test]
async fn full_client_channel_is_removed_without_blocking_other_clients() {
    let session_1 = ClientSessionIdentity::new(
        ClientId("slow".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let session_2 = ClientSessionIdentity::new(
        ClientId("fast".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 16,
        client_registry_capacity: 4,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");
    let (slow_outbound, mut slow_rx) = mpsc::channel(1);
    let (fast_outbound, mut fast_rx) = mpsc::channel(8);

    begin_client(
        &handle.ingress_tx,
        &session_1,
        slow_outbound,
        verbose_all_tasks(),
    )
    .await;
    begin_client(
        &handle.ingress_tx,
        &session_2,
        fast_outbound,
        verbose_all_tasks(),
    )
    .await;
    deliver_empty_snapshot(&handle.ingress_tx, &session_1).await;
    deliver_empty_snapshot(&handle.ingress_tx, &session_2).await;

    assert!(matches!(
        recv_frame(&mut fast_rx).await,
        ClientFrame::Snapshot(_)
    ));

    handle
        .ingress_tx
        .send(EventIngress::Publish(ClientEvent::TaskChanged(
            TaskChangedEvent {
                task: task_projection("task-1", 1),
            },
        )))
        .await
        .expect("send raw event");

    let fast_event = recv_frame(&mut fast_rx).await;
    match fast_event {
        ClientFrame::Event(frame) => {
            assert_eq!(frame.delivery_seq.0, 2);
            assert!(matches!(frame.event, ClientEvent::TaskChanged(_)));
        }
        _ => panic!("expected fast client event"),
    }

    let slow_snapshot = recv_frame(&mut slow_rx).await;
    assert!(matches!(slow_snapshot, ClientFrame::Snapshot(_)));
    let slow_closed = tokio::time::timeout(Duration::from_secs(1), slow_rx.recv())
        .await
        .expect("slow channel closes after full delivery attempt");
    assert!(slow_closed.is_none());

    drop(handle.ingress_tx);
    handle.join_handle.await.expect("events task exits cleanly");
}

#[tokio::test]
async fn stale_hydration_snapshot_is_ignored_after_replacement_begin() {
    let session_1 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let session_2 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-2".to_owned()),
    );
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 8,
        client_registry_capacity: 4,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");
    let (first_outbound, mut first_rx) = mpsc::channel(8);
    let (second_outbound, mut second_rx) = mpsc::channel(8);

    begin_client(
        &handle.ingress_tx,
        &session_1,
        first_outbound,
        verbose_all_tasks(),
    )
    .await;
    begin_client(
        &handle.ingress_tx,
        &session_2,
        second_outbound,
        verbose_all_tasks(),
    )
    .await;

    handle
        .ingress_tx
        .send(EventIngress::Control(EventControlMessage::DeliverNotice(
            DeliverNotice {
                session: session_1.clone(),
                client_command_id: ClientCommandId("attach-1".to_owned()),
                notice: ClientNotice {
                    level: ClientNoticeLevel::Warning,
                    kind: selvedge_command_model::ClientNoticeKind::Text,
                    message_text: "stale".to_owned(),
                },
            },
        )))
        .await
        .expect("send stale notice");
    assert!(
        tokio::time::timeout(Duration::from_millis(50), second_rx.recv())
            .await
            .is_err()
    );

    handle
        .ingress_tx
        .send(EventIngress::Control(EventControlMessage::DeliverSnapshot(
            DeliverSnapshot {
                session: session_1.clone(),
                snapshot: empty_snapshot(),
            },
        )))
        .await
        .expect("send stale snapshot");

    handle
        .ingress_tx
        .send(EventIngress::Publish(ClientEvent::TaskChanged(
            TaskChangedEvent {
                task: task_projection("task-1", 1),
            },
        )))
        .await
        .expect("send raw event");

    assert!(
        tokio::time::timeout(Duration::from_millis(50), second_rx.recv())
            .await
            .is_err()
    );
    assert!(
        tokio::time::timeout(Duration::from_secs(1), first_rx.recv())
            .await
            .expect("first channel closes when replaced")
            .is_none()
    );

    handle
        .ingress_tx
        .send(EventIngress::Control(EventControlMessage::DeliverSnapshot(
            DeliverSnapshot {
                session: session_2.clone(),
                snapshot: empty_snapshot(),
            },
        )))
        .await
        .expect("send active snapshot");

    let snapshot = recv_frame(&mut second_rx).await;
    match snapshot {
        ClientFrame::Snapshot(frame) => {
            assert_eq!(frame.delivery_seq.0, 1);
            assert_eq!(
                frame.client_command_id,
                ClientCommandId("attach-2".to_owned())
            );
        }
        _ => panic!("expected active snapshot"),
    }

    let event = recv_frame(&mut second_rx).await;
    match event {
        ClientFrame::Event(frame) => {
            assert_eq!(frame.delivery_seq.0, 2);
            assert!(matches!(frame.event, ClientEvent::TaskChanged(_)));
        }
        _ => panic!("expected buffered event"),
    }

    handle
        .ingress_tx
        .send(EventIngress::Control(EventControlMessage::DeliverSnapshot(
            DeliverSnapshot {
                session: session_1.clone(),
                snapshot: empty_snapshot(),
            },
        )))
        .await
        .expect("send late stale snapshot");
    assert!(
        tokio::time::timeout(Duration::from_millis(50), second_rx.recv())
            .await
            .is_err()
    );

    drop(handle.ingress_tx);
    handle.join_handle.await.expect("events task exits cleanly");
}

#[tokio::test]
async fn stale_session_controls_do_not_mutate_replacement_client() {
    let session_1 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-1".to_owned()),
    );
    let session_2 = ClientSessionIdentity::new(
        ClientId("client-1".to_owned()),
        ClientCommandId("attach-2".to_owned()),
    );
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 16,
        client_registry_capacity: 4,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");
    let (first_outbound, mut first_rx) = mpsc::channel(8);
    let (second_outbound, mut second_rx) = mpsc::channel(8);

    begin_client(
        &handle.ingress_tx,
        &session_1,
        first_outbound,
        verbose_all_tasks(),
    )
    .await;
    begin_client(
        &handle.ingress_tx,
        &session_2,
        second_outbound,
        verbose_all_tasks(),
    )
    .await;

    handle
        .ingress_tx
        .send(EventIngress::Control(
            EventControlMessage::UpdateSubscription(UpdateSubscription {
                session: session_1.clone(),
                subscription: summary_task_subscription("task-2"),
            }),
        ))
        .await
        .expect("send stale subscription update");
    handle
        .ingress_tx
        .send(EventIngress::Control(EventControlMessage::DetachClient(
            DetachClient {
                session: session_1.clone(),
                reason: DetachReason::ClientRequested,
            },
        )))
        .await
        .expect("send stale detach");

    assert!(
        tokio::time::timeout(Duration::from_secs(1), first_rx.recv())
            .await
            .expect("first channel closes when replaced")
            .is_none()
    );

    handle
        .ingress_tx
        .send(EventIngress::Control(EventControlMessage::DeliverSnapshot(
            DeliverSnapshot {
                session: session_2.clone(),
                snapshot: empty_snapshot(),
            },
        )))
        .await
        .expect("send active snapshot");
    assert!(matches!(
        recv_frame(&mut second_rx).await,
        ClientFrame::Snapshot(_)
    ));

    handle
        .ingress_tx
        .send(EventIngress::Publish(ClientEvent::TaskChanged(
            TaskChangedEvent {
                task: task_projection("task-1", 1),
            },
        )))
        .await
        .expect("send raw event");
    let event = recv_frame(&mut second_rx).await;
    match event {
        ClientFrame::Event(frame) => assert!(matches!(frame.event, ClientEvent::TaskChanged(_))),
        _ => panic!("expected task event"),
    }

    drop(handle.ingress_tx);
    handle.join_handle.await.expect("events task exits cleanly");
}

async fn recv_frame(rx: &mut mpsc::Receiver<ClientFrame>) -> ClientFrame {
    tokio::time::timeout(Duration::from_secs(1), rx.recv())
        .await
        .expect("frame received before timeout")
        .expect("client channel remains open")
}

fn verbose_all_tasks() -> ClientSubscription {
    ClientSubscription {
        task_scope: TaskScope::AllTasks,
        detail_level: DetailLevel::Verbose,
        snapshot_mode: selvedge_command_model::SnapshotMode::CurrentState,
        include_model_call_status: true,
        include_tool_execution_status: true,
        include_debug_notices: true,
    }
}

fn summary_task_subscription(task_id: &str) -> ClientSubscription {
    ClientSubscription {
        task_scope: TaskScope::TaskIds(BTreeSet::from([TaskId(task_id.to_owned())])),
        detail_level: DetailLevel::Summary,
        snapshot_mode: selvedge_command_model::SnapshotMode::CurrentState,
        include_model_call_status: true,
        include_tool_execution_status: true,
        include_debug_notices: true,
    }
}

async fn begin_client(
    ingress_tx: &selvedge_command_model::EventIngressSender,
    session: &ClientSessionIdentity,
    outbound: selvedge_command_model::ClientFrameSender,
    subscription: ClientSubscription,
) {
    let _ = reserve_client_session(ingress_tx, session).await;
    begin_unreserved(ingress_tx, session, outbound, subscription).await;
}

async fn begin_unreserved(
    ingress_tx: &selvedge_command_model::EventIngressSender,
    session: &ClientSessionIdentity,
    outbound: selvedge_command_model::ClientFrameSender,
    subscription: ClientSubscription,
) {
    ingress_tx
        .send(EventIngress::Control(
            EventControlMessage::BeginClientHydration(BeginClientHydration {
                session: session.clone(),
                outbound,
                subscription,
            }),
        ))
        .await
        .expect("send begin hydration");
}

async fn reserve_client_session(
    ingress_tx: &selvedge_command_model::EventIngressSender,
    session: &ClientSessionIdentity,
) -> EventClientReservationResult {
    let (result_tx, result_rx) = tokio::sync::oneshot::channel();
    ingress_tx
        .send(EventIngress::Control(
            EventControlMessage::ReserveClientSession(ReserveClientSession {
                session: session.clone(),
                result_tx,
            }),
        ))
        .await
        .expect("send reservation");
    result_rx.await.expect("reservation result")
}

async fn deliver_empty_snapshot(
    ingress_tx: &selvedge_command_model::EventIngressSender,
    session: &ClientSessionIdentity,
) {
    ingress_tx
        .send(EventIngress::Control(EventControlMessage::DeliverSnapshot(
            DeliverSnapshot {
                session: session.clone(),
                snapshot: empty_snapshot(),
            },
        )))
        .await
        .expect("send snapshot");
}

fn empty_snapshot() -> ClientSnapshot {
    ClientSnapshot {
        generated_at: UnixTs(100),
        tasks: Vec::new(),
        task_parent_edges: Vec::new(),
        history_nodes: Vec::new(),
        task_versions: Vec::new(),
    }
}

fn task_projection(task_id: &str, state_version: u64) -> TaskProjection {
    TaskProjection {
        task_id: TaskId(task_id.to_owned()),
        status: TaskStatus::Active,
        cursor_node_id: HistoryNodeId(1),
        model_config: std::sync::Arc::new(
            TaskModelConfig::new(
                ModelProfileKey("default".to_owned()),
                ReasoningEffort::Medium,
            )
            .expect("valid model configuration"),
        ),
        state_version,
        created_at: UnixTs(10),
        updated_at: UnixTs(20),
    }
}

#[tokio::test]
async fn hidden_completed_snapshot_is_restored_once_before_uncovered_events() {
    let a = ClientSessionIdentity::new(ClientId("client-1".into()), ClientCommandId("a".into()));
    let b = ClientSessionIdentity::new(ClientId("client-1".into()), ClientCommandId("b".into()));
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 16,
        client_registry_capacity: 1,
        hydration_buffer_capacity: 4,
    })
    .expect("events task");
    let (outbound, mut rx) = mpsc::channel(8);
    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &a).await,
        EventClientReservationResult::Reserved
    );
    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &b).await,
        EventClientReservationResult::Reserved
    );
    begin_unreserved(&handle.ingress_tx, &a, outbound, verbose_all_tasks()).await;
    publish_task_version(&handle.ingress_tx, 1).await;
    let mut snapshot = empty_snapshot();
    snapshot.tasks.push(task_projection("task-1", 2));
    snapshot.task_versions.push(SnapshotTaskVersion {
        task_id: TaskId("task-1".into()),
        state_version: 2,
    });
    handle
        .ingress_tx
        .send(EventIngress::Control(EventControlMessage::DeliverSnapshot(
            DeliverSnapshot {
                session: a.clone(),
                snapshot: snapshot.clone(),
            },
        )))
        .await
        .expect("complete hidden hydration");
    publish_task_version(&handle.ingress_tx, 3).await;
    // Reservation acknowledgement proves all earlier messages were processed while A was hidden.
    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &b).await,
        EventClientReservationResult::DuplicateAttach
    );
    assert!(matches!(
        rx.try_recv(),
        Err(mpsc::error::TryRecvError::Empty)
    ));
    handle
        .ingress_tx
        .send(EventIngress::Control(EventControlMessage::DetachClient(
            DetachClient {
                session: b,
                reason: DetachReason::DeliveryFailed,
            },
        )))
        .await
        .expect("roll back failed replacement");
    match recv_frame(&mut rx).await {
        ClientFrame::Snapshot(frame) => {
            assert_eq!(frame.delivery_seq.0, 1);
            assert_eq!(frame.client_command_id, *a.attach_command_id());
            assert_eq!(frame.snapshot, snapshot);
        }
        other => panic!("expected restored snapshot, got {other:?}"),
    }
    assert_task_version(recv_frame(&mut rx).await, 2, 3);
    publish_task_version(&handle.ingress_tx, 4).await;
    assert_task_version(recv_frame(&mut rx).await, 3, 4);
    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &a).await,
        EventClientReservationResult::DuplicateAttach
    );
    assert!(matches!(
        rx.try_recv(),
        Err(mpsc::error::TryRecvError::Empty)
    ));
    drop(handle.ingress_tx);
    handle.join_handle.await.expect("events task stops");
}

#[tokio::test]
async fn reused_attach_command_ignores_old_generation_controls() {
    let old_a =
        ClientSessionIdentity::new(ClientId("client-1".into()), ClientCommandId("a".into()));
    let b = ClientSessionIdentity::new(ClientId("client-1".into()), ClientCommandId("b".into()));
    let new_a =
        ClientSessionIdentity::new(ClientId("client-1".into()), ClientCommandId("a".into()));
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 16,
        client_registry_capacity: 1,
        hydration_buffer_capacity: 4,
    })
    .expect("events task");
    for identity in [&old_a, &b] {
        let (outbound, mut rx) = mpsc::channel(8);
        begin_client(&handle.ingress_tx, identity, outbound, verbose_all_tasks()).await;
        deliver_empty_snapshot(&handle.ingress_tx, identity).await;
        assert!(matches!(
            recv_frame(&mut rx).await,
            ClientFrame::Snapshot(_)
        ));
    }
    let (outbound, mut rx) = mpsc::channel(8);
    begin_client(&handle.ingress_tx, &new_a, outbound, verbose_all_tasks()).await;
    deliver_empty_snapshot(&handle.ingress_tx, &new_a).await;
    assert!(matches!(
        recv_frame(&mut rx).await,
        ClientFrame::Snapshot(_)
    ));
    for stale in [&old_a, &b] {
        deliver_empty_snapshot(&handle.ingress_tx, stale).await;
        handle
            .ingress_tx
            .send(EventIngress::Control(
                EventControlMessage::UpdateSubscription(UpdateSubscription {
                    session: stale.clone(),
                    subscription: summary_task_subscription("other-task"),
                }),
            ))
            .await
            .expect("stale subscription update");
        handle
            .ingress_tx
            .send(EventIngress::Control(EventControlMessage::DeliverNotice(
                DeliverNotice {
                    session: stale.clone(),
                    client_command_id: ClientCommandId("operation".into()),
                    notice: ClientNotice {
                        level: ClientNoticeLevel::Error,
                        kind: selvedge_command_model::ClientNoticeKind::Diagnostic {
                            client_command_id: None,
                        },
                        message_text: "stale failure".into(),
                    },
                },
            )))
            .await
            .expect("stale notice");
        handle
            .ingress_tx
            .send(EventIngress::Control(EventControlMessage::DetachClient(
                DetachClient {
                    session: stale.clone(),
                    reason: DetachReason::ClientDisconnected,
                },
            )))
            .await
            .expect("stale detach");
    }
    publish_task_version(&handle.ingress_tx, 1).await;
    assert_task_version(recv_frame(&mut rx).await, 2, 1);
    assert_eq!(
        reserve_client_session(&handle.ingress_tx, &new_a).await,
        EventClientReservationResult::DuplicateAttach
    );
    assert!(matches!(
        rx.try_recv(),
        Err(mpsc::error::TryRecvError::Empty)
    ));
    drop(handle.ingress_tx);
    handle.join_handle.await.expect("events task stops");
}

async fn publish_task_version(ingress: &selvedge_command_model::EventIngressSender, version: u64) {
    ingress
        .send(EventIngress::Publish(ClientEvent::TaskChanged(
            TaskChangedEvent {
                task: task_projection("task-1", version),
            },
        )))
        .await
        .expect("publish task update");
}

fn assert_task_version(frame: ClientFrame, sequence: u64, version: u64) {
    match frame {
        ClientFrame::Event(frame) => {
            assert_eq!(frame.delivery_seq.0, sequence);
            assert!(
                matches!(frame.event, ClientEvent::TaskChanged(event) if event.task.state_version == version)
            );
        }
        other => panic!("expected task event, got {other:?}"),
    }
}
