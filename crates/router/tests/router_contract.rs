use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use selvedge_api::ApiExecutorConfig;
use selvedge_command_model::{
    ApiCallCorrelation, ApiEffectId, ApiOutputEnvelope, ClientCommandId, ClientId,
    ClientSubscription, CoreOutputEnvelope, CoreOutputMessage, DetachReason, DetailLevel,
    DomainEvent, DomainEventPublishRequest, EventClientReservationResult, EventControlMessage,
    EventIngress, ModelCallError, ModelCallErrorKind, ModelRunId, RawEvent,
    RouterAttachAdmissionResult, RouterCommand, RouterCommandEnvelope, RouterIngressMessage,
    TaskRuntimeCommand, TaskRuntimeControl, TaskRuntimeExitNotice, TaskRuntimeExitReason,
    TaskScope, ToolExecutionRequest, ToolExecutionResult, ToolExecutionRunId,
};
use selvedge_core::{
    SpawnTaskRuntimeArgs, SpawnTaskRuntimeError, SpawnedTaskRuntime, TaskRuntimeConfig,
    TaskRuntimeSpawnDeps, TaskRuntimeSpawner,
};
use selvedge_db::{DbPool, ModelProfileKey, TaskId, UnixTs};
use selvedge_domain_model::{FunctionCallId, HistoryNodeId, ModelProviderProfile, ToolName};
use selvedge_router::{
    RouterExitStatus, RouterStartArgs, ToolExecutionSpawnError, ToolExecutionSpawner, spawn_router,
};
use selvedge_test_support::db::{
    create_root_task_with_user_message, default_model_profiles, open_memory_db,
};

#[tokio::test]
async fn attach_client_command_is_forwarded_to_events() {
    let db = open_memory_db();
    let (events_tx, mut events_rx) = tokio::sync::mpsc::channel(8);

    let handle = spawn_router(RouterStartArgs {
        db,
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: HashMap::new(),
        }),
    })
    .expect("spawn router");

    let (outbound, _outbound_rx) = tokio::sync::mpsc::channel(4);
    let (admission_tx, admission_rx) = tokio::sync::oneshot::channel();
    let subscription = ClientSubscription {
        task_scope: TaskScope::AllTasks,
        detail_level: DetailLevel::Verbose,
        snapshot_mode: selvedge_command_model::SnapshotMode::CurrentState,
        include_model_call_status: true,
        include_tool_execution_status: true,
        include_debug_notices: true,
    };
    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommandEnvelope {
            client_id: Some(ClientId("client-1".to_owned())),
            client_command_id: Some(ClientCommandId("attach-1".to_owned())),
            command: RouterCommand::AttachClient {
                client_id: ClientId("client-1".to_owned()),
                client_command_id: ClientCommandId("attach-1".to_owned()),
                outbound,
                subscription: subscription.clone(),
                admission_tx,
            },
        }))
        .expect("send command");

    let event = events_rx.recv().await.expect("events ingress");
    let EventIngress::Control(EventControlMessage::ReserveClientSession(reservation)) = event
    else {
        panic!("unexpected events ingress");
    };
    assert_eq!(reservation.client_id, ClientId("client-1".to_owned()));
    assert_eq!(
        reservation.client_command_id,
        ClientCommandId("attach-1".to_owned())
    );
    reservation
        .result_tx
        .send(EventClientReservationResult::Reserved)
        .expect("send reservation result");
    assert_eq!(
        admission_rx.await.expect("admission result"),
        RouterAttachAdmissionResult::Accepted
    );

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
}

#[tokio::test]
async fn cancelled_attach_admission_detaches_reserved_events_session() {
    let db = open_memory_db();
    let (events_tx, mut events_rx) = tokio::sync::mpsc::channel(8);

    let handle = spawn_router(RouterStartArgs {
        db,
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: HashMap::new(),
        }),
    })
    .expect("spawn router");

    let (outbound, _outbound_rx) = tokio::sync::mpsc::channel(4);
    let (admission_tx, admission_rx) = tokio::sync::oneshot::channel();
    drop(admission_rx);
    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommandEnvelope {
            client_id: Some(ClientId("client-1".to_owned())),
            client_command_id: Some(ClientCommandId("attach-1".to_owned())),
            command: RouterCommand::AttachClient {
                client_id: ClientId("client-1".to_owned()),
                client_command_id: ClientCommandId("attach-1".to_owned()),
                outbound,
                subscription: verbose_subscription(),
                admission_tx,
            },
        }))
        .expect("send command");

    let EventIngress::Control(EventControlMessage::ReserveClientSession(reservation)) =
        events_rx.recv().await.expect("reservation")
    else {
        panic!("unexpected events ingress");
    };
    reservation
        .result_tx
        .send(EventClientReservationResult::Reserved)
        .expect("send reservation result");
    let EventIngress::Control(EventControlMessage::DetachClient(detach)) =
        events_rx.recv().await.expect("detach")
    else {
        panic!("unexpected events ingress");
    };
    assert_eq!(detach.client_id, ClientId("client-1".to_owned()));
    assert_eq!(
        detach.client_command_id,
        ClientCommandId("attach-1".to_owned())
    );
    assert_eq!(detach.reason, DetachReason::ClientDisconnected);

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
}

#[tokio::test]
async fn task_local_command_creates_runtime_and_flushes_deferred_user_input() {
    let db = open_memory_db();
    create_root(&db, "task-1");
    let spawner = Arc::new(CapturingRuntimeSpawner::default());
    let (events_tx, _events_rx) = tokio::sync::mpsc::channel(8);

    let handle = spawn_router(RouterStartArgs {
        db,
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::with_spawner(
            TaskRuntimeConfig {
                mailbox_capacity: 8,
                model_profiles: model_profiles(),
            },
            spawner.clone(),
        ),
    })
    .expect("spawn router");

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommandEnvelope {
            client_id: None,
            client_command_id: None,
            command: RouterCommand::SendUserInput {
                task_id: TaskId("task-1".to_owned()),
                message_text: "hello".to_owned(),
            },
        }))
        .expect("send command");

    let mut runtime_rx = spawner.wait_receiver("task-1").await;
    let start = runtime_rx.recv().await.expect("start command");
    assert!(matches!(start, TaskRuntimeCommand::Start));
    let input = runtime_rx.recv().await.expect("user input command");
    let TaskRuntimeCommand::UserInput { message_text } = input else {
        panic!("unexpected task runtime command");
    };
    assert_eq!(message_text, "hello");

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    spawner.finish_stop("task-1").await;
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
}

#[tokio::test]
async fn api_tool_and_stop_messages_are_routed_to_live_runtime() {
    let db = open_memory_db();
    create_root(&db, "task-1");
    let spawner = Arc::new(CapturingRuntimeSpawner::default());
    let (events_tx, _events_rx) = tokio::sync::mpsc::channel(8);

    let handle = spawn_router(RouterStartArgs {
        db,
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::with_spawner(
            TaskRuntimeConfig {
                mailbox_capacity: 8,
                model_profiles: model_profiles(),
            },
            spawner.clone(),
        ),
    })
    .expect("spawn router");

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommandEnvelope {
            client_id: None,
            client_command_id: None,
            command: RouterCommand::EnsureTaskRuntime {
                task_id: TaskId("task-1".to_owned()),
            },
        }))
        .expect("send ensure");
    let mut runtime_rx = spawner.wait_receiver("task-1").await;
    assert!(matches!(
        runtime_rx.recv().await.expect("start command"),
        TaskRuntimeCommand::Start
    ));

    let api_output = ApiOutputEnvelope::Failure {
        correlation: correlation("task-1"),
        error: ModelCallError {
            kind: ModelCallErrorKind::ProviderNetwork,
            message: "network failed".to_owned(),
        },
    };
    handle
        .ingress_tx
        .send(RouterIngressMessage::ApiOutput(api_output))
        .expect("send api output");
    let api_command = runtime_rx.recv().await.expect("api command");
    assert!(matches!(api_command, TaskRuntimeCommand::ApiModelReply(_)));

    handle
        .ingress_tx
        .send(RouterIngressMessage::Tool(tool_result("task-1")))
        .expect("send tool output");
    let tool_command = runtime_rx.recv().await.expect("tool command");
    assert!(matches!(tool_command, TaskRuntimeCommand::ToolResult(_)));

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    spawner.finish_stop("task-1").await;
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
}

#[tokio::test]
async fn stop_runtime_removes_sender_before_later_task_commands() {
    let db = open_memory_db();
    create_root(&db, "task-1");
    let spawner = Arc::new(CapturingRuntimeSpawner::default());
    let (events_tx, _events_rx) = tokio::sync::mpsc::channel(8);

    let handle = spawn_router(RouterStartArgs {
        db,
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::with_spawner(
            TaskRuntimeConfig {
                mailbox_capacity: 8,
                model_profiles: model_profiles(),
            },
            spawner.clone(),
        ),
    })
    .expect("spawn router");

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommandEnvelope {
            client_id: None,
            client_command_id: None,
            command: RouterCommand::EnsureTaskRuntime {
                task_id: TaskId("task-1".to_owned()),
            },
        }))
        .expect("send ensure");
    let mut stopped_runtime_rx = spawner.wait_receiver("task-1").await;
    let stopped_runtime_control = spawner.wait_control("task-1").await;
    assert!(matches!(
        stopped_runtime_rx.recv().await.expect("start command"),
        TaskRuntimeCommand::Start
    ));

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommandEnvelope {
            client_id: None,
            client_command_id: None,
            command: RouterCommand::StopTaskRuntime {
                task_id: TaskId("task-1".to_owned()),
            },
        }))
        .expect("send stop");
    finish_stop(stopped_runtime_control.clone()).await;

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommandEnvelope {
            client_id: None,
            client_command_id: None,
            command: RouterCommand::SendUserInput {
                task_id: TaskId("task-1".to_owned()),
                message_text: "after stop".to_owned(),
            },
        }))
        .expect("send user input");
    let mut replacement_runtime_rx = spawner.wait_receiver("task-1").await;
    assert!(matches!(
        replacement_runtime_rx
            .recv()
            .await
            .expect("replacement start"),
        TaskRuntimeCommand::Start
    ));
    let TaskRuntimeCommand::UserInput { message_text } = replacement_runtime_rx
        .recv()
        .await
        .expect("replacement input")
    else {
        panic!("unexpected task runtime command");
    };
    assert_eq!(message_text, "after stop");
    if let Ok(Some(command)) =
        tokio::time::timeout(Duration::from_millis(50), stopped_runtime_rx.recv()).await
    {
        panic!("unexpected stopped runtime command: {command:?}");
    }

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    spawner.finish_stop("task-1").await;
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
}

#[tokio::test]
async fn stale_runtime_exit_preserves_replacement_runtime() {
    let db = open_memory_db();
    create_root(&db, "task-1");
    let spawner = Arc::new(CapturingRuntimeSpawner::default());
    let (events_tx, _events_rx) = tokio::sync::mpsc::channel(8);

    let handle = spawn_router(RouterStartArgs {
        db,
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::with_spawner(
            TaskRuntimeConfig {
                mailbox_capacity: 8,
                model_profiles: model_profiles(),
            },
            spawner.clone(),
        ),
    })
    .expect("spawn router");

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommandEnvelope {
            client_id: None,
            client_command_id: None,
            command: RouterCommand::EnsureTaskRuntime {
                task_id: TaskId("task-1".to_owned()),
            },
        }))
        .expect("send ensure");
    let mut stopped_runtime_rx = spawner.wait_receiver("task-1").await;
    let stopped_runtime_control = spawner.wait_control("task-1").await;
    assert!(matches!(
        stopped_runtime_rx.recv().await.expect("start command"),
        TaskRuntimeCommand::Start
    ));

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommandEnvelope {
            client_id: None,
            client_command_id: None,
            command: RouterCommand::StopTaskRuntime {
                task_id: TaskId("task-1".to_owned()),
            },
        }))
        .expect("send stop");
    finish_stop(stopped_runtime_control.clone()).await;

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommandEnvelope {
            client_id: None,
            client_command_id: None,
            command: RouterCommand::SendUserInput {
                task_id: TaskId("task-1".to_owned()),
                message_text: "after stop".to_owned(),
            },
        }))
        .expect("send user input");
    let mut replacement_runtime_rx = spawner.wait_receiver("task-1").await;
    assert!(matches!(
        replacement_runtime_rx
            .recv()
            .await
            .expect("replacement start"),
        TaskRuntimeCommand::Start
    ));
    assert!(matches!(
        replacement_runtime_rx
            .recv()
            .await
            .expect("replacement input"),
        TaskRuntimeCommand::UserInput { .. }
    ));

    handle
        .ingress_tx
        .send(RouterIngressMessage::RuntimeExit(TaskRuntimeExitNotice {
            task_id: TaskId("task-1".to_owned()),
            task_runtime_control: stopped_runtime_control,
            reason: TaskRuntimeExitReason::Stopped,
        }))
        .expect("send stale exit");

    handle
        .ingress_tx
        .send(RouterIngressMessage::ApiOutput(
            ApiOutputEnvelope::Failure {
                correlation: correlation("task-1"),
                error: ModelCallError {
                    kind: ModelCallErrorKind::ProviderNetwork,
                    message: "network failed".to_owned(),
                },
            },
        ))
        .expect("send api output");
    assert!(matches!(
        replacement_runtime_rx.recv().await.expect("api reply"),
        TaskRuntimeCommand::ApiModelReply(_)
    ));

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    spawner.finish_stop("task-1").await;
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
}

#[tokio::test]
async fn current_runtime_exit_removes_registry_entry() {
    let db = open_memory_db();
    create_root(&db, "task-1");
    let spawner = Arc::new(CapturingRuntimeSpawner::default());
    let (events_tx, mut events_rx) = tokio::sync::mpsc::channel(8);

    let handle = spawn_router(RouterStartArgs {
        db,
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::with_spawner(
            TaskRuntimeConfig {
                mailbox_capacity: 8,
                model_profiles: model_profiles(),
            },
            spawner.clone(),
        ),
    })
    .expect("spawn router");

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommandEnvelope {
            client_id: None,
            client_command_id: None,
            command: RouterCommand::EnsureTaskRuntime {
                task_id: TaskId("task-1".to_owned()),
            },
        }))
        .expect("send ensure");
    let mut first_runtime_rx = spawner.wait_receiver("task-1").await;
    let first_runtime_control = spawner.wait_control("task-1").await;
    assert!(matches!(
        first_runtime_rx.recv().await.expect("start command"),
        TaskRuntimeCommand::Start
    ));

    handle
        .ingress_tx
        .send(RouterIngressMessage::RuntimeExit(TaskRuntimeExitNotice {
            task_id: TaskId("task-1".to_owned()),
            task_runtime_control: first_runtime_control,
            reason: TaskRuntimeExitReason::Stopped,
        }))
        .expect("send current exit");
    let exit_debug = events_rx.recv().await.expect("exit debug");
    assert_debug_contains(
        exit_debug,
        Some(TaskId("task-1".to_owned())),
        "task runtime exited",
    );

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommandEnvelope {
            client_id: None,
            client_command_id: None,
            command: RouterCommand::EnsureTaskRuntime {
                task_id: TaskId("task-1".to_owned()),
            },
        }))
        .expect("send replacement ensure");
    let mut replacement_runtime_rx = spawner.wait_receiver("task-1").await;
    assert!(matches!(
        replacement_runtime_rx
            .recv()
            .await
            .expect("replacement start"),
        TaskRuntimeCommand::Start
    ));

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    spawner.finish_stop("task-1").await;
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
}

#[tokio::test]
async fn inactive_archive_is_delivered_before_runtime_start() {
    let db = open_memory_db();
    create_root(&db, "task-1");
    let spawner = Arc::new(CapturingRuntimeSpawner::default());
    let (events_tx, _events_rx) = tokio::sync::mpsc::channel(8);

    let handle = spawn_router(RouterStartArgs {
        db,
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::with_spawner(
            TaskRuntimeConfig {
                mailbox_capacity: 8,
                model_profiles: model_profiles(),
            },
            spawner.clone(),
        ),
    })
    .expect("spawn router");

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommandEnvelope {
            client_id: None,
            client_command_id: None,
            command: RouterCommand::ArchiveTask {
                task_id: TaskId("task-1".to_owned()),
            },
        }))
        .expect("send archive");
    let mut runtime_rx = spawner.wait_receiver("task-1").await;
    assert!(matches!(
        runtime_rx.recv().await.expect("archive command"),
        TaskRuntimeCommand::Archive
    ));
    if let Ok(Some(command)) =
        tokio::time::timeout(Duration::from_millis(50), runtime_rx.recv()).await
    {
        panic!("unexpected archive runtime command: {command:?}");
    }

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    spawner.finish_stop("task-1").await;
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
}

#[tokio::test]
async fn stale_outputs_and_runtime_ready_are_published_to_events() {
    let db = open_memory_db();
    let (events_tx, mut events_rx) = tokio::sync::mpsc::channel(8);

    let handle = spawn_router(RouterStartArgs {
        db,
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: model_profiles(),
        }),
    })
    .expect("spawn router");

    handle
        .ingress_tx
        .send(RouterIngressMessage::ApiOutput(
            ApiOutputEnvelope::Failure {
                correlation: correlation("missing"),
                error: ModelCallError {
                    kind: ModelCallErrorKind::ProviderNetwork,
                    message: "network failed".to_owned(),
                },
            },
        ))
        .expect("send api output");
    let stale_api = events_rx.recv().await.expect("stale api debug");
    assert_debug_contains(stale_api, Some(TaskId("missing".to_owned())), "stale api");

    handle
        .ingress_tx
        .send(RouterIngressMessage::Tool(tool_result("missing")))
        .expect("send tool output");
    let stale_tool = events_rx.recv().await.expect("stale tool debug");
    assert_debug_contains(stale_tool, Some(TaskId("missing".to_owned())), "stale tool");

    handle
        .ingress_tx
        .send(RouterIngressMessage::Core(CoreOutputEnvelope {
            task_id: TaskId("task-ready".to_owned()),
            message: CoreOutputMessage::RuntimeReady,
        }))
        .expect("send runtime ready");
    let ready = events_rx.recv().await.expect("ready debug");
    assert_debug_contains(
        ready,
        Some(TaskId("task-ready".to_owned())),
        "task runtime ready",
    );

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
}

#[tokio::test]
async fn data_domain_events_are_not_published_to_events() {
    let db = open_memory_db();
    let (events_tx, mut events_rx) = tokio::sync::mpsc::channel(8);

    let handle = spawn_router(RouterStartArgs {
        db,
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: model_profiles(),
        }),
    })
    .expect("spawn router");

    handle
        .ingress_tx
        .send(RouterIngressMessage::PublishToEvents(
            DomainEventPublishRequest {
                task_id: TaskId("task-1".to_owned()),
                event: DomainEvent::UserMessageCommitted {
                    node_id: HistoryNodeId(1),
                },
            },
        ))
        .expect("send data event");
    assert!(
        tokio::time::timeout(Duration::from_millis(50), events_rx.recv())
            .await
            .is_err()
    );

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
}

#[tokio::test]
async fn core_tool_execution_request_uses_configured_tool_spawner() {
    let db = open_memory_db();
    let (events_tx, _events_rx) = tokio::sync::mpsc::channel(8);
    let tool_spawner = Arc::new(CapturingToolSpawner::default());

    let handle = spawn_router(RouterStartArgs {
        db,
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: tool_spawner.clone(),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: model_profiles(),
        }),
    })
    .expect("spawn router");

    handle
        .ingress_tx
        .send(RouterIngressMessage::Core(CoreOutputEnvelope {
            task_id: TaskId("task-1".to_owned()),
            message: CoreOutputMessage::RequestToolExecution(tool_request("task-1")),
        }))
        .expect("send core tool request");

    let request = tool_spawner.wait_request().await;
    assert_eq!(request.task_id, TaskId("task-1".to_owned()));
    assert_eq!(request.tool_name, ToolName("tool".to_owned()));

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
}

#[tokio::test]
async fn mismatched_core_tool_task_id_is_ignored() {
    let db = open_memory_db();
    let (events_tx, _events_rx) = tokio::sync::mpsc::channel(8);
    let tool_spawner = Arc::new(CapturingToolSpawner::default());

    let handle = spawn_router(RouterStartArgs {
        db,
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: tool_spawner.clone(),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: model_profiles(),
        }),
    })
    .expect("spawn router");

    handle
        .ingress_tx
        .send(RouterIngressMessage::Core(CoreOutputEnvelope {
            task_id: TaskId("task-1".to_owned()),
            message: CoreOutputMessage::RequestToolExecution(tool_request("task-2")),
        }))
        .expect("send core tool request");

    tokio::time::sleep(Duration::from_millis(20)).await;
    assert_eq!(tool_spawner.request_count(), 0);

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
}

#[tokio::test]
async fn core_tool_execution_spawn_failure_returns_error_tool_result() {
    let db = open_memory_db();
    create_root(&db, "task-1");
    let spawner = Arc::new(CapturingRuntimeSpawner::default());
    let (events_tx, _events_rx) = tokio::sync::mpsc::channel(8);

    let handle = spawn_router(RouterStartArgs {
        db,
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(FailingToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::with_spawner(
            TaskRuntimeConfig {
                mailbox_capacity: 8,
                model_profiles: model_profiles(),
            },
            spawner.clone(),
        ),
    })
    .expect("spawn router");

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommandEnvelope {
            client_id: None,
            client_command_id: None,
            command: RouterCommand::EnsureTaskRuntime {
                task_id: TaskId("task-1".to_owned()),
            },
        }))
        .expect("send ensure");
    let mut runtime_rx = spawner.wait_receiver("task-1").await;
    assert!(matches!(
        runtime_rx.recv().await.expect("start command"),
        TaskRuntimeCommand::Start
    ));

    handle
        .ingress_tx
        .send(RouterIngressMessage::Core(CoreOutputEnvelope {
            task_id: TaskId("task-1".to_owned()),
            message: CoreOutputMessage::RequestToolExecution(tool_request("task-1")),
        }))
        .expect("send core tool request");

    let TaskRuntimeCommand::ToolResult(result) =
        runtime_rx.recv().await.expect("tool result command")
    else {
        panic!("unexpected task runtime command");
    };
    assert!(result.is_error);
    assert!(result.output_text.contains("tool execution spawn failed"));

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    spawner.finish_stop("task-1").await;
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
}

#[tokio::test]
async fn spawn_router_uses_unbounded_ingress() {
    let db = open_memory_db();
    let (events_tx, _events_rx) = tokio::sync::mpsc::channel(8);
    let handle = spawn_router(RouterStartArgs {
        db,
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: model_profiles(),
        }),
    })
    .expect("spawn router");
    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
}

#[tokio::test]
async fn router_exits_when_ingress_sender_is_dropped() {
    let db = open_memory_db();
    let (events_tx, _events_rx) = tokio::sync::mpsc::channel(8);
    let handle = spawn_router(RouterStartArgs {
        db,
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: model_profiles(),
        }),
    })
    .expect("spawn router");

    drop(handle.ingress_tx);

    let status = tokio::time::timeout(Duration::from_millis(50), handle.join_handle)
        .await
        .expect("router exit")
        .expect("join router");
    assert_eq!(status, RouterExitStatus::RouterMailboxClosed);
}

#[tokio::test]
async fn router_exits_when_ingress_sender_is_dropped_with_live_runtime() {
    let db = open_memory_db();
    create_root(&db, "task-1");
    let (events_tx, mut events_rx) = tokio::sync::mpsc::channel(8);
    let handle = spawn_router(RouterStartArgs {
        db,
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: model_profiles(),
        }),
    })
    .expect("spawn router");

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommandEnvelope {
            client_id: None,
            client_command_id: None,
            command: RouterCommand::EnsureTaskRuntime {
                task_id: TaskId("task-1".to_owned()),
            },
        }))
        .expect("send ensure");
    let ready = events_rx.recv().await.expect("runtime ready");
    assert_debug_contains(
        ready,
        Some(TaskId("task-1".to_owned())),
        "task runtime ready",
    );

    drop(handle.ingress_tx);

    let status = tokio::time::timeout(Duration::from_millis(50), handle.join_handle)
        .await
        .expect("router exit")
        .expect("join router");
    assert_eq!(status, RouterExitStatus::RouterMailboxClosed);
}

fn create_root(db: &DbPool, task_id: &str) {
    create_root_task_with_user_message(db, task_id, "hello", UnixTs(1));
}

fn model_profiles() -> HashMap<ModelProfileKey, ModelProviderProfile> {
    default_model_profiles()
}

fn correlation(task_id: &str) -> ApiCallCorrelation {
    ApiCallCorrelation {
        api_effect_id: ApiEffectId("api-1".to_owned()),
        task_id: TaskId(task_id.to_owned()),
        model_run_id: ModelRunId("model-1".to_owned()),
    }
}

fn tool_result(task_id: &str) -> ToolExecutionResult {
    ToolExecutionResult {
        task_id: TaskId(task_id.to_owned()),
        tool_execution_run_id: ToolExecutionRunId("tool-1".to_owned()),
        function_call_node_id: HistoryNodeId(1),
        function_call_id: FunctionCallId("call-1".to_owned()),
        tool_name: ToolName("tool".to_owned()),
        output_text: "done".to_owned(),
        is_error: false,
    }
}

fn tool_request(task_id: &str) -> ToolExecutionRequest {
    ToolExecutionRequest {
        task_id: TaskId(task_id.to_owned()),
        tool_execution_run_id: ToolExecutionRunId("tool-1".to_owned()),
        function_call_node_id: HistoryNodeId(1),
        function_call_id: FunctionCallId("call-1".to_owned()),
        tool_name: ToolName("tool".to_owned()),
        arguments: Vec::new(),
    }
}

fn assert_debug_contains(event: EventIngress, task_id: Option<TaskId>, message: &str) {
    let EventIngress::Raw(RawEvent::Debug(debug)) = event else {
        panic!("unexpected event ingress");
    };
    assert_eq!(debug.task_id, task_id);
    assert!(debug.message_text.contains(message));
}

async fn finish_stop(control: TaskRuntimeControl) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(1);
    while !control.is_stopping() {
        assert!(tokio::time::Instant::now() < deadline, "runtime stopping");
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    control
        .finish_stop(selvedge_command_model::TaskRuntimeStopResult)
        .await;
}

struct NoopToolSpawner;

impl ToolExecutionSpawner for NoopToolSpawner {
    fn spawn_tool_execution(
        &self,
        _request: ToolExecutionRequest,
        _router_tx: selvedge_command_model::RouterIngressWeakSender,
    ) -> Result<tokio::task::JoinHandle<()>, ToolExecutionSpawnError> {
        Ok(tokio::spawn(async {}))
    }
}

struct FailingToolSpawner;

impl ToolExecutionSpawner for FailingToolSpawner {
    fn spawn_tool_execution(
        &self,
        _request: ToolExecutionRequest,
        _router_tx: selvedge_command_model::RouterIngressWeakSender,
    ) -> Result<tokio::task::JoinHandle<()>, ToolExecutionSpawnError> {
        Err(ToolExecutionSpawnError::TokioSpawnFailed)
    }
}

#[derive(Default)]
struct CapturingToolSpawner {
    requests: Mutex<Vec<ToolExecutionRequest>>,
}

impl CapturingToolSpawner {
    fn request_count(&self) -> usize {
        self.requests.lock().expect("lock requests").len()
    }

    async fn wait_request(&self) -> ToolExecutionRequest {
        let deadline = tokio::time::Instant::now() + Duration::from_secs(1);
        loop {
            {
                let mut requests = self.requests.lock().expect("lock requests");
                if let Some(request) = requests.pop() {
                    return request;
                }
            }
            assert!(
                tokio::time::Instant::now() < deadline,
                "tool execution request"
            );
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    }
}

impl ToolExecutionSpawner for CapturingToolSpawner {
    fn spawn_tool_execution(
        &self,
        request: ToolExecutionRequest,
        _router_tx: selvedge_command_model::RouterIngressWeakSender,
    ) -> Result<tokio::task::JoinHandle<()>, ToolExecutionSpawnError> {
        let mut requests = self
            .requests
            .lock()
            .map_err(|_| ToolExecutionSpawnError::ToolExecutorUnavailable)?;
        requests.push(request);
        Ok(tokio::spawn(async {}))
    }
}

fn verbose_subscription() -> ClientSubscription {
    ClientSubscription {
        task_scope: TaskScope::AllTasks,
        detail_level: DetailLevel::Verbose,
        snapshot_mode: selvedge_command_model::SnapshotMode::CurrentState,
        include_model_call_status: true,
        include_tool_execution_status: true,
        include_debug_notices: true,
    }
}

#[derive(Default)]
struct CapturingRuntimeSpawner {
    receivers: Mutex<HashMap<TaskId, tokio::sync::mpsc::Receiver<TaskRuntimeCommand>>>,
    controls: Mutex<HashMap<TaskId, TaskRuntimeControl>>,
}

impl CapturingRuntimeSpawner {
    async fn wait_receiver(
        &self,
        task_id: &str,
    ) -> tokio::sync::mpsc::Receiver<TaskRuntimeCommand> {
        let task_id = TaskId(task_id.to_owned());
        let deadline = tokio::time::Instant::now() + Duration::from_secs(1);
        loop {
            {
                let mut receivers = self.receivers.lock().expect("lock receivers");
                if let Some(receiver) = receivers.remove(&task_id) {
                    return receiver;
                }
            }
            assert!(tokio::time::Instant::now() < deadline, "runtime receiver");
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    }

    async fn wait_control(&self, task_id: &str) -> TaskRuntimeControl {
        let task_id = TaskId(task_id.to_owned());
        let deadline = tokio::time::Instant::now() + Duration::from_secs(1);
        loop {
            {
                let mut controls = self.controls.lock().expect("lock controls");
                if let Some(control) = controls.remove(&task_id) {
                    return control;
                }
            }
            assert!(tokio::time::Instant::now() < deadline, "runtime control");
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    }

    async fn finish_stop(&self, task_id: &str) {
        let control = self.wait_control(task_id).await;
        finish_stop(control).await;
    }
}

impl TaskRuntimeSpawner for CapturingRuntimeSpawner {
    fn spawn_task_runtime(
        &self,
        args: SpawnTaskRuntimeArgs,
    ) -> Result<SpawnedTaskRuntime, SpawnTaskRuntimeError> {
        let (task_runtime_tx, task_runtime_rx) = tokio::sync::mpsc::channel(8);
        let task_runtime_control = TaskRuntimeControl::new();
        let mut receivers = self
            .receivers
            .lock()
            .map_err(|_| SpawnTaskRuntimeError::TokioSpawnFailed)?;
        receivers.insert(args.task_id.clone(), task_runtime_rx);
        let mut controls = self
            .controls
            .lock()
            .map_err(|_| SpawnTaskRuntimeError::TokioSpawnFailed)?;
        controls.insert(args.task_id.clone(), task_runtime_control.clone());
        Ok(SpawnedTaskRuntime {
            task_id: args.task_id,
            task_runtime_tx,
            task_runtime_control,
        })
    }
}
