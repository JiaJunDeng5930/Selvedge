use std::{collections::BTreeSet, time::Duration};

use selvedge_command_model::{
    BeginClientHydration, ClientCommandId, ClientEvent, ClientFrame, ClientId, ClientNotice,
    ClientNoticeLevel, ClientSnapshot, ClientSubscription, DebugRawEvent, DeliverNotice,
    DeliverSnapshot, DetailLevel, EventControlMessage, EventIngress, HistoryAppendedRawEvent,
    RawEvent, SnapshotTaskVersion, TaskChangedRawEvent, TaskProjection, TaskProjectionStatus,
    TaskScope, UpdateSubscription,
};
use selvedge_domain_model::{HistoryNodeId, ModelProfileKey, ReasoningEffort, TaskId, UnixTs};
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
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 8,
        client_registry_capacity: 4,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");
    let (outbound, mut outbound_rx) = mpsc::channel(8);

    handle
        .ingress_tx
        .send(EventIngress::Control(
            EventControlMessage::BeginClientHydration(BeginClientHydration {
                client_id: client_id(),
                client_command_id: ClientCommandId("attach-1".to_owned()),
                outbound,
                subscription: verbose_all_tasks(),
            }),
        ))
        .await
        .expect("send begin hydration");

    handle
        .ingress_tx
        .send(EventIngress::Raw(RawEvent::TaskChanged(
            TaskChangedRawEvent {
                task: task_projection("task-1", 1),
            },
        )))
        .await
        .expect("send covered task event");

    handle
        .ingress_tx
        .send(EventIngress::Raw(RawEvent::HistoryAppended(
            HistoryAppendedRawEvent {
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
                client_id: client_id(),
                client_command_id: ClientCommandId("attach-1".to_owned()),
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
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 8,
        client_registry_capacity: 4,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");
    let (outbound, mut outbound_rx) = mpsc::channel(8);

    begin_client(
        &handle.ingress_tx,
        outbound,
        summary_task_subscription("task-1"),
    )
    .await;
    deliver_empty_snapshot(&handle.ingress_tx).await;
    assert!(matches!(
        recv_frame(&mut outbound_rx).await,
        ClientFrame::Snapshot(_)
    ));

    handle
        .ingress_tx
        .send(EventIngress::Raw(RawEvent::HistoryAppended(
            HistoryAppendedRawEvent {
                task_id: TaskId("task-1".to_owned()),
                task_state_version: 3,
                appended_nodes: Vec::new(),
            },
        )))
        .await
        .expect("send verbose event filtered by summary detail");

    handle
        .ingress_tx
        .send(EventIngress::Raw(RawEvent::TaskChanged(
            TaskChangedRawEvent {
                task: task_projection("task-2", 3),
            },
        )))
        .await
        .expect("send event filtered by task scope");

    handle
        .ingress_tx
        .send(EventIngress::Raw(RawEvent::TaskChanged(
            TaskChangedRawEvent {
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
        .send(EventIngress::Raw(RawEvent::Debug(DebugRawEvent {
            task_id: Some(TaskId("task-1".to_owned())),
            message_text: "debug".to_owned(),
        })))
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
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 8,
        client_registry_capacity: 4,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");
    let (outbound, mut outbound_rx) = mpsc::channel(8);

    begin_client(&handle.ingress_tx, outbound, verbose_all_tasks()).await;
    handle
        .ingress_tx
        .send(EventIngress::Raw(RawEvent::HistoryAppended(
            HistoryAppendedRawEvent {
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
                client_id: client_id(),
                subscription: summary_task_subscription("task-2"),
            }),
        ))
        .await
        .expect("send subscription update");

    deliver_empty_snapshot(&handle.ingress_tx).await;
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
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 8,
        client_registry_capacity: 4,
        hydration_buffer_capacity: 1,
    })
    .expect("valid events task");
    let (outbound, mut outbound_rx) = mpsc::channel(8);

    begin_client(&handle.ingress_tx, outbound, verbose_all_tasks()).await;

    for state_version in [1, 2] {
        handle
            .ingress_tx
            .send(EventIngress::Raw(RawEvent::TaskChanged(
                TaskChangedRawEvent {
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
async fn notice_during_hydration_uses_current_delivery_sequence() {
    let handle = spawn_events_task(EventsStartArgs {
        ingress_capacity: 8,
        client_registry_capacity: 4,
        hydration_buffer_capacity: 4,
    })
    .expect("valid events task");
    let (outbound, mut outbound_rx) = mpsc::channel(8);

    begin_client(&handle.ingress_tx, outbound, verbose_all_tasks()).await;
    handle
        .ingress_tx
        .send(EventIngress::Control(EventControlMessage::DeliverNotice(
            DeliverNotice {
                client_id: client_id(),
                client_command_id: ClientCommandId("notice-1".to_owned()),
                notice: ClientNotice {
                    level: ClientNoticeLevel::Warning,
                    message_text: "heads up".to_owned(),
                },
            },
        )))
        .await
        .expect("send notice");
    deliver_empty_snapshot(&handle.ingress_tx).await;

    let notice = recv_frame(&mut outbound_rx).await;
    match notice {
        ClientFrame::Notice(frame) => {
            assert_eq!(frame.delivery_seq.0, 1);
            assert_eq!(
                frame.client_command_id,
                ClientCommandId("notice-1".to_owned())
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

async fn recv_frame(rx: &mut mpsc::Receiver<ClientFrame>) -> ClientFrame {
    tokio::time::timeout(Duration::from_secs(1), rx.recv())
        .await
        .expect("frame received before timeout")
        .expect("client channel remains open")
}

fn client_id() -> ClientId {
    ClientId("client-1".to_owned())
}

fn verbose_all_tasks() -> ClientSubscription {
    ClientSubscription {
        task_scope: TaskScope::AllTasks,
        detail_level: DetailLevel::Verbose,
        include_model_call_status: true,
        include_tool_execution_status: true,
        include_debug_notices: true,
    }
}

fn summary_task_subscription(task_id: &str) -> ClientSubscription {
    ClientSubscription {
        task_scope: TaskScope::TaskIds(BTreeSet::from([TaskId(task_id.to_owned())])),
        detail_level: DetailLevel::Summary,
        include_model_call_status: true,
        include_tool_execution_status: true,
        include_debug_notices: true,
    }
}

async fn begin_client(
    ingress_tx: &selvedge_command_model::EventIngressSender,
    outbound: selvedge_command_model::ClientFrameSender,
    subscription: ClientSubscription,
) {
    ingress_tx
        .send(EventIngress::Control(
            EventControlMessage::BeginClientHydration(BeginClientHydration {
                client_id: client_id(),
                client_command_id: ClientCommandId("attach-1".to_owned()),
                outbound,
                subscription,
            }),
        ))
        .await
        .expect("send begin hydration");
}

async fn deliver_empty_snapshot(ingress_tx: &selvedge_command_model::EventIngressSender) {
    ingress_tx
        .send(EventIngress::Control(EventControlMessage::DeliverSnapshot(
            DeliverSnapshot {
                client_id: client_id(),
                client_command_id: ClientCommandId("attach-1".to_owned()),
                snapshot: ClientSnapshot {
                    generated_at: UnixTs(100),
                    tasks: Vec::new(),
                    task_parent_edges: Vec::new(),
                    history_nodes: Vec::new(),
                    task_versions: Vec::new(),
                },
            },
        )))
        .await
        .expect("send snapshot");
}

fn task_projection(task_id: &str, state_version: u64) -> TaskProjection {
    TaskProjection {
        task_id: TaskId(task_id.to_owned()),
        status: TaskProjectionStatus::Active,
        cursor_node_id: HistoryNodeId(1),
        model_profile_key: ModelProfileKey("default".to_owned()),
        reasoning_effort: ReasoningEffort::Medium,
        state_version,
        created_at: UnixTs(10),
        updated_at: UnixTs(20),
    }
}
