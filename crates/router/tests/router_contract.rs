use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::time::timeout;

use selvedge_api::ApiExecutorConfig;
use selvedge_command_model::{
    ApiCallCorrelation, ApiEffectId, ApiOutputEnvelope, ClientCommandId, ClientEvent, ClientId,
    ClientSessionIdentity, CoreOutputEnvelope, CoreOutputMessage, DetachReason, DomainEvent,
    DomainEventPublishRequest, EventClientReservationResult, EventControlMessage, EventIngress,
    ModelCallDispatchRequest, ModelCallError, ModelCallErrorKind, ModelRunId,
    RouterAttachAdmissionResult, RouterCommand, RouterIngressMessage, SendUserInputOutcome,
    TaskCommandError, TaskRuntimeCommand, TaskRuntimeControl, TaskRuntimeExitNotice,
    TaskRuntimeExitReason, TaskStatusChangeOutcome, ToolExecutionBranch, ToolExecutionBranchTarget,
    ToolExecutionRequest, ToolExecutionResult, ToolExecutionRunId,
    send_user_input_response_channel, task_status_change_response_channel,
};
use selvedge_core::{
    SpawnTaskRuntimeArgs, SpawnTaskRuntimeError, SpawnedTaskRuntime, TaskRuntimeConfig,
    TaskRuntimeSpawnDeps, TaskRuntimeSpawner,
};
use selvedge_db::{
    DbPool, ModelProfileKey, TaskId, UnixTs, read_task_status, transition_task_status,
};
use selvedge_domain_model::{
    CallableTools, Conversation, ConversationMessage, FunctionCallId, HistoryNodeId, JsonObject,
    MessageRole, ModelProviderProfile, ResponsePreference, TaskLifecycleEvent, TaskStatus,
    ToolName,
};
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
            model_profiles: HashMap::new(),
        }),
    });

    let (admission_tx, admission_rx) = tokio::sync::oneshot::channel();
    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommand::AttachClient {
            session: ClientSessionIdentity::new(
                ClientId("client-1".to_owned()),
                ClientCommandId("attach-1".to_owned()),
            ),

            admission_tx,
        }))
        .expect("send command");

    let event = events_rx.recv().await.expect("events ingress");
    let EventIngress::Control(EventControlMessage::ReserveClientSession(reservation)) = event
    else {
        panic!("unexpected events ingress");
    };
    assert_eq!(
        *reservation.session.client_id(),
        ClientId("client-1".to_owned())
    );
    assert_eq!(
        *reservation.session.attach_command_id(),
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
            model_profiles: HashMap::new(),
        }),
    });

    let (admission_tx, admission_rx) = tokio::sync::oneshot::channel();
    drop(admission_rx);
    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommand::AttachClient {
            session: ClientSessionIdentity::new(
                ClientId("client-1".to_owned()),
                ClientCommandId("attach-1".to_owned()),
            ),

            admission_tx,
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
    assert_eq!(*detach.session.client_id(), ClientId("client-1".to_owned()));
    assert_eq!(
        *detach.session.attach_command_id(),
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
async fn task_local_command_creates_runtime_before_delivering_user_input() {
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
                model_profiles: model_profiles(),
            },
            spawner.clone(),
        ),
    });

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(
            RouterCommand::SendUserInput {
                task_id: TaskId("task-1".to_owned()),
                message_text: "hello".to_owned(),
                responder: send_user_input_response_channel().0,
            },
        ))
        .expect("send command");

    let mut runtime_rx = spawner.wait_receiver("task-1").await;
    let start = runtime_rx.recv().await.expect("start command");
    assert!(matches!(start, TaskRuntimeCommand::Start));
    let input = runtime_rx.recv().await.expect("user input command");
    let TaskRuntimeCommand::UserInput { message_text, .. } = input else {
        panic!("unexpected task runtime command");
    };
    assert_eq!(message_text, "hello");

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    spawner.finish_shutdown("task-1").await;
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
}

#[tokio::test]
async fn missing_runtime_user_input_settles_after_the_runtime_sqlite_transition() {
    let db = open_memory_db();
    create_root(&db, "task-1");
    let (events_tx, _events_rx) = tokio::sync::mpsc::channel(8);
    let handle = spawn_router(RouterStartArgs {
        db: db.clone(),
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            model_profiles: model_profiles(),
        }),
    });

    let (responder, response) = send_user_input_response_channel();
    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(
            RouterCommand::SendUserInput {
                task_id: TaskId("task-1".to_owned()),
                message_text: "input for missing runtime".to_owned(),
                responder,
            },
        ))
        .expect("send input");
    assert_eq!(
        response.await.expect("input response"),
        Ok(SendUserInputOutcome::Queued)
    );

    // The actor can promote the queue before this observation; both locations must
    // contain exactly one durable input in the same database snapshot.
    let persisted = selvedge_db::read_task(
        &db,
        selvedge_db::ReadTaskInput {
            task_id: TaskId("task-1".to_owned()),
            after_node_id: None,
            limit: 100,
        },
    )
    .expect("durable input snapshot");
    assert!(!persisted.has_more);
    let committed_count = persisted.history_nodes.iter().filter(|node| matches!(node,
        selvedge_db::HistoryNode::Message { message_text, .. } if message_text == "input for missing runtime"
    )).count();
    assert_eq!(
        persisted.queued_input_count + u64::try_from(committed_count).expect("history count"),
        1
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
async fn missing_and_archived_tasks_reject_user_input() {
    let db = open_memory_db();
    create_root(&db, "archived");
    transition_task_status(
        &db,
        &TaskId("archived".to_owned()),
        TaskLifecycleEvent::Archive,
        UnixTs(2),
    )
    .expect("archive task");
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
            model_profiles: model_profiles(),
        }),
    });

    let (invalid_responder, invalid_response) = send_user_input_response_channel();
    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(
            RouterCommand::SendUserInput {
                task_id: TaskId("missing".to_owned()),
                message_text: " ".to_owned(),
                responder: invalid_responder,
            },
        ))
        .expect("send invalid input");
    assert_eq!(
        invalid_response.await.expect("invalid response"),
        Err(TaskCommandError::InvalidCommand)
    );

    let (missing_responder, missing_response) = send_user_input_response_channel();
    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(
            RouterCommand::SendUserInput {
                task_id: TaskId("missing".to_owned()),
                message_text: "hello".to_owned(),
                responder: missing_responder,
            },
        ))
        .expect("send missing input");
    assert_eq!(
        missing_response.await.expect("missing response"),
        Err(TaskCommandError::TaskMissing)
    );

    let (archived_responder, archived_response) = send_user_input_response_channel();
    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(
            RouterCommand::SendUserInput {
                task_id: TaskId("archived".to_owned()),
                message_text: "hello".to_owned(),
                responder: archived_responder,
            },
        ))
        .expect("send archived input");
    assert_eq!(
        archived_response.await.expect("archived response"),
        Err(TaskCommandError::TaskArchived)
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
async fn factory_and_runtime_mailbox_failures_settle_commands() {
    for spawner in [
        Arc::new(FailingRuntimeSpawner) as Arc<dyn TaskRuntimeSpawner>,
        Arc::new(ClosedMailboxRuntimeSpawner) as Arc<dyn TaskRuntimeSpawner>,
    ] {
        let db = open_memory_db();
        create_root(&db, "task-1");
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
                    model_profiles: model_profiles(),
                },
                spawner,
            ),
        });

        let (responder, response) = send_user_input_response_channel();
        handle
            .ingress_tx
            .send(RouterIngressMessage::Command(
                RouterCommand::SendUserInput {
                    task_id: TaskId("task-1".to_owned()),
                    message_text: "hello".to_owned(),
                    responder,
                },
            ))
            .expect("send input");
        assert_eq!(
            response.await.expect("input response"),
            Err(TaskCommandError::RuntimeUnavailable)
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
}

#[tokio::test]
async fn router_shutdown_settles_commands_queued_behind_stop() {
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
            model_profiles: model_profiles(),
        }),
    });
    let (responder, response) = send_user_input_response_channel();

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    let _ = handle.ingress_tx.send(RouterIngressMessage::Command(
        RouterCommand::SendUserInput {
            task_id: TaskId("task-1".to_owned()),
            message_text: "after stop".to_owned(),
            responder,
        },
    ));
    assert_eq!(
        response.await.expect("shutdown response"),
        Err(TaskCommandError::RuntimeUnavailable)
    );
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
}

#[tokio::test]
async fn api_and_tool_outputs_are_routed_to_live_runtime() {
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
                model_profiles: model_profiles(),
            },
            spawner.clone(),
        ),
    });

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(
            RouterCommand::EnsureTaskRuntime {
                task_id: TaskId("task-1".to_owned()),
            },
        ))
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
    spawner.finish_shutdown("task-1").await;
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
}

#[tokio::test]
async fn stop_task_persists_status_and_keeps_the_runtime_live() {
    let db = open_memory_db();
    create_root(&db, "task-1");
    let spawner = Arc::new(CapturingRuntimeSpawner::default());
    let (events_tx, _events_rx) = tokio::sync::mpsc::channel(8);

    let handle = spawn_router(RouterStartArgs {
        db: db.clone(),
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::with_spawner(
            TaskRuntimeConfig {
                model_profiles: model_profiles(),
            },
            spawner.clone(),
        ),
    });

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(
            RouterCommand::EnsureTaskRuntime {
                task_id: TaskId("task-1".to_owned()),
            },
        ))
        .expect("send ensure");
    let mut runtime_rx = spawner.wait_receiver("task-1").await;
    assert!(matches!(
        runtime_rx.recv().await.expect("start command"),
        TaskRuntimeCommand::Start
    ));

    let (responder, response) = task_status_change_response_channel();
    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommand::StopTask {
            task_id: TaskId("task-1".to_owned()),
            responder,
        }))
        .expect("send stop");
    assert_eq!(
        response.await.expect("stop response"),
        Ok(TaskStatusChangeOutcome {
            status: TaskStatus::Stopped,
        })
    );
    assert_eq!(
        read_task_status(&db, &TaskId("task-1".to_owned())).expect("read status"),
        TaskStatus::Stopped
    );

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(
            RouterCommand::SendUserInput {
                task_id: TaskId("task-1".to_owned()),
                message_text: "after stop".to_owned(),
                responder: send_user_input_response_channel().0,
            },
        ))
        .expect("send user input");
    let TaskRuntimeCommand::UserInput { message_text, .. } =
        runtime_rx.recv().await.expect("user input")
    else {
        panic!("unexpected task runtime command");
    };
    assert_eq!(message_text, "after stop");

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    spawner.finish_shutdown("task-1").await;
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
}

#[tokio::test]
async fn freeze_and_unfreeze_notify_the_same_runtime() {
    let db = open_memory_db();
    create_root(&db, "task-1");
    let spawner = Arc::new(CapturingRuntimeSpawner::default());
    let (events_tx, _events_rx) = tokio::sync::mpsc::channel(8);
    let handle = spawn_router(RouterStartArgs {
        db: db.clone(),
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::with_spawner(
            TaskRuntimeConfig {
                model_profiles: model_profiles(),
            },
            spawner.clone(),
        ),
    });

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(
            RouterCommand::EnsureTaskRuntime {
                task_id: TaskId("task-1".to_owned()),
            },
        ))
        .expect("send ensure");
    let mut runtime_rx = spawner.wait_receiver("task-1").await;
    let runtime_control = spawner.wait_control("task-1").await;
    assert!(matches!(
        runtime_rx.recv().await.expect("start command"),
        TaskRuntimeCommand::Start
    ));

    for (command, expected_status) in [
        (TaskLifecycleEvent::Freeze, TaskStatus::Frozen),
        (TaskLifecycleEvent::Unfreeze, TaskStatus::Active),
    ] {
        let (responder, response) = task_status_change_response_channel();
        let command = match command {
            TaskLifecycleEvent::Freeze => RouterCommand::FreezeTask {
                task_id: TaskId("task-1".to_owned()),
                responder,
            },
            TaskLifecycleEvent::Unfreeze => RouterCommand::UnfreezeTask {
                task_id: TaskId("task-1".to_owned()),
                responder,
            },
            _ => unreachable!(),
        };
        let status_wait = tokio::spawn({
            let runtime_control = runtime_control.clone();
            async move { runtime_control.wait_for_control_change().await }
        });
        handle
            .ingress_tx
            .send(RouterIngressMessage::Command(command))
            .expect("send status command");
        assert_eq!(
            response.await.expect("status response"),
            Ok(TaskStatusChangeOutcome {
                status: expected_status,
            })
        );
        tokio::time::timeout(Duration::from_secs(1), status_wait)
            .await
            .expect("status notification timeout")
            .expect("join status waiter");
        assert_eq!(
            read_task_status(&db, &TaskId("task-1".to_owned())).expect("read status"),
            expected_status
        );
    }

    let (responder, response) = task_status_change_response_channel();
    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommand::UnfreezeTask {
            task_id: TaskId("task-1".to_owned()),
            responder,
        }))
        .expect("send invalid unfreeze");
    assert_eq!(
        response.await.expect("invalid unfreeze response"),
        Err(TaskCommandError::InvalidTaskStatus {
            status: TaskStatus::Active,
        })
    );

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    finish_shutdown(runtime_control).await;
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
                model_profiles: model_profiles(),
            },
            spawner.clone(),
        ),
    });

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(
            RouterCommand::EnsureTaskRuntime {
                task_id: TaskId("task-1".to_owned()),
            },
        ))
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
            task_runtime_control: first_runtime_control.clone(),
            reason: TaskRuntimeExitReason::Shutdown,
        }))
        .expect("send first runtime exit");

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(
            RouterCommand::SendUserInput {
                task_id: TaskId("task-1".to_owned()),
                message_text: "after stop".to_owned(),
                responder: send_user_input_response_channel().0,
            },
        ))
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
            task_runtime_control: first_runtime_control,
            reason: TaskRuntimeExitReason::Shutdown,
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
    spawner.finish_shutdown("task-1").await;
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
                model_profiles: model_profiles(),
            },
            spawner.clone(),
        ),
    });

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(
            RouterCommand::EnsureTaskRuntime {
                task_id: TaskId("task-1".to_owned()),
            },
        ))
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
            reason: TaskRuntimeExitReason::Shutdown,
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
        .send(RouterIngressMessage::Command(
            RouterCommand::EnsureTaskRuntime {
                task_id: TaskId("task-1".to_owned()),
            },
        ))
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
    spawner.finish_shutdown("task-1").await;
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
}

#[tokio::test]
async fn archive_persists_status_and_shuts_down_the_runtime() {
    let db = open_memory_db();
    create_root(&db, "task-1");
    let spawner = Arc::new(CapturingRuntimeSpawner::default());
    let (events_tx, _events_rx) = tokio::sync::mpsc::channel(8);

    let handle = spawn_router(RouterStartArgs {
        db: db.clone(),
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::with_spawner(
            TaskRuntimeConfig {
                model_profiles: model_profiles(),
            },
            spawner.clone(),
        ),
    });

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(
            RouterCommand::EnsureTaskRuntime {
                task_id: TaskId("task-1".to_owned()),
            },
        ))
        .expect("send ensure");
    let mut runtime_rx = spawner.wait_receiver("task-1").await;
    let runtime_control = spawner.wait_control("task-1").await;
    assert!(matches!(
        runtime_rx.recv().await.expect("start command"),
        TaskRuntimeCommand::Start
    ));

    let (responder, response) = task_status_change_response_channel();
    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommand::ArchiveTask {
            task_id: TaskId("task-1".to_owned()),
            responder,
        }))
        .expect("send archive");
    assert_eq!(
        response.await.expect("archive response"),
        Ok(TaskStatusChangeOutcome {
            status: TaskStatus::Archived,
        })
    );
    assert_eq!(
        read_task_status(&db, &TaskId("task-1".to_owned())).expect("read status"),
        TaskStatus::Archived
    );
    runtime_control
        .finish_shutdown(selvedge_command_model::TaskRuntimeShutdownResult)
        .await;

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
async fn stopped_task_model_request_is_returned_without_api_dispatch() {
    let db = open_memory_db();
    create_root(&db, "task-1");
    transition_task_status(
        &db,
        &TaskId("task-1".to_owned()),
        TaskLifecycleEvent::Stop,
        UnixTs(2),
    )
    .expect("stop task");
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
                model_profiles: model_profiles(),
            },
            spawner.clone(),
        ),
    });

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(
            RouterCommand::EnsureTaskRuntime {
                task_id: TaskId("task-1".to_owned()),
            },
        ))
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
            message: CoreOutputMessage::RequestModelCall(model_request("task-1")),
        }))
        .expect("send model request");
    let TaskRuntimeCommand::ModelCallNotStarted { correlation } =
        runtime_rx.recv().await.expect("undispatched model reply")
    else {
        panic!("unexpected task runtime command");
    };
    assert_eq!(correlation.task_id, TaskId("task-1".to_owned()));

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    spawner.finish_shutdown("task-1").await;
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
            model_profiles: model_profiles(),
        }),
    });

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
            model_profiles: model_profiles(),
        }),
    });

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
    create_root(&db, "task-1");
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
            model_profiles: model_profiles(),
        }),
    });

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
async fn router_shutdown_cancels_and_joins_in_flight_tool_execution() {
    let db = open_memory_db();
    create_root(&db, "task-1");
    let (events_tx, _events_rx) = tokio::sync::mpsc::channel(8);
    let tool_spawner = Arc::new(BlockingToolSpawner::default());

    let handle = spawn_router(RouterStartArgs {
        db,
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: tool_spawner.clone(),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            model_profiles: model_profiles(),
        }),
    });

    handle
        .ingress_tx
        .send(RouterIngressMessage::Core(CoreOutputEnvelope {
            task_id: TaskId("task-1".to_owned()),
            message: CoreOutputMessage::RequestToolExecution(tool_request("task-1")),
        }))
        .expect("send core tool request");
    tool_spawner.wait_started().await;
    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");

    assert_eq!(
        tokio::time::timeout(Duration::from_secs(1), handle.join_handle)
            .await
            .expect("router shutdown timeout")
            .expect("join router"),
        RouterExitStatus::Stopped
    );
    assert!(
        tool_spawner.dropped.load(Ordering::SeqCst),
        "router reported stopped before the execution future was dropped"
    );
}

#[tokio::test]
async fn archived_task_rejects_new_tool_execution() {
    let db = open_memory_db();
    create_root(&db, "task-1");
    transition_task_status(
        &db,
        &TaskId("task-1".to_owned()),
        TaskLifecycleEvent::Archive,
        UnixTs(2),
    )
    .expect("archive task");
    let (events_tx, mut events_rx) = tokio::sync::mpsc::channel(8);
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
            model_profiles: model_profiles(),
        }),
    });

    handle
        .ingress_tx
        .send(RouterIngressMessage::Core(CoreOutputEnvelope {
            task_id: TaskId("task-1".to_owned()),
            message: CoreOutputMessage::RequestToolExecution(tool_request("task-1")),
        }))
        .expect("send core tool request");
    assert_debug_contains(
        events_rx.recv().await.expect("tool rejection debug"),
        Some(TaskId("task-1".to_owned())),
        "task is archived",
    );
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
async fn mismatched_core_tool_task_id_is_ignored() {
    let db = open_memory_db();
    create_root(&db, "task-1");
    create_root(&db, "task-2");
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
            model_profiles: model_profiles(),
        }),
    });

    handle
        .ingress_tx
        .send(RouterIngressMessage::Core(CoreOutputEnvelope {
            task_id: TaskId("task-1".to_owned()),
            message: CoreOutputMessage::RequestToolExecution(tool_request("task-2")),
        }))
        .expect("send core tool request");

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
    assert_eq!(tool_spawner.request_count(), 0);
}

#[tokio::test]
async fn core_ensure_task_runtimes_starts_each_committed_task() {
    let db = open_memory_db();
    create_root(&db, "child-1");
    create_root(&db, "child-2");
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
                model_profiles: model_profiles(),
            },
            spawner.clone(),
        ),
    });

    handle
        .ingress_tx
        .send(RouterIngressMessage::Core(CoreOutputEnvelope {
            task_id: TaskId("parent".to_owned()),
            message: CoreOutputMessage::EnsureTaskRuntimes {
                task_ids: vec![TaskId("child-1".to_owned()), TaskId("child-2".to_owned())],
            },
        }))
        .expect("ensure committed child runtimes");

    let mut child_1_rx = spawner.wait_receiver("child-1").await;
    let mut child_2_rx = spawner.wait_receiver("child-2").await;
    assert!(matches!(
        child_1_rx.recv().await.expect("child 1 start"),
        TaskRuntimeCommand::Start
    ));
    assert!(matches!(
        child_2_rx.recv().await.expect("child 2 start"),
        TaskRuntimeCommand::Start
    ));

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    tokio::join!(
        spawner.finish_shutdown("child-1"),
        spawner.finish_shutdown("child-2")
    );
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
                model_profiles: model_profiles(),
            },
            spawner.clone(),
        ),
    });

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(
            RouterCommand::EnsureTaskRuntime {
                task_id: TaskId("task-1".to_owned()),
            },
        ))
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
    assert_eq!(result.branches.len(), 1);
    assert!(result.branches[0].is_error);
    assert_eq!(
        result.branches[0].output,
        serde_json::json!("tool execution spawn failed")
    );

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    spawner.finish_shutdown("task-1").await;
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
            model_profiles: model_profiles(),
        }),
    });

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
            model_profiles: model_profiles(),
        }),
    });

    handle
        .ingress_tx
        .send(RouterIngressMessage::Command(
            RouterCommand::EnsureTaskRuntime {
                task_id: TaskId("task-1".to_owned()),
            },
        ))
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

fn model_request(task_id: &str) -> ModelCallDispatchRequest {
    ModelCallDispatchRequest {
        model_config: Arc::new(
            selvedge_domain_model::TaskModelConfig::new(
                ModelProfileKey("default".to_owned()),
                selvedge_domain_model::ReasoningEffort::Medium,
            )
            .expect("model config"),
        ),
        correlation: correlation(task_id),
        provider: ModelProviderProfile {
            provider_name: "provider".to_owned(),
            model_name: "model".to_owned(),
            temperature: None,
            max_output_tokens: None,
        },
        conversation: Conversation {
            messages: vec![ConversationMessage::text(MessageRole::User, "hello", None)],
        },
        tool_manifest: None,
        callable_tools: CallableTools::All,
        response_preference: ResponsePreference::PlainTextOrToolCalls,
    }
}

fn tool_result(task_id: &str) -> ToolExecutionResult {
    ToolExecutionResult {
        completion: selvedge_command_model::ToolExecutionCompletion::ordinary(),
        task_id: TaskId(task_id.to_owned()),
        tool_execution_run_id: ToolExecutionRunId("tool-1".to_owned()),
        function_call_node_id: HistoryNodeId(1),
        function_call_id: FunctionCallId("call-1".to_owned()),
        tool_name: ToolName("tool".to_owned()),
        branches: vec![ToolExecutionBranch {
            target: ToolExecutionBranchTarget::CallingTask,
            output: serde_json::json!("done"),
            is_error: false,
            messages: Vec::new(),
        }],
    }
}

fn tool_request(task_id: &str) -> ToolExecutionRequest {
    ToolExecutionRequest {
        execution_mode: selvedge_domain_model::ToolExecutionMode::Normal,
        task_id: TaskId(task_id.to_owned()),
        tool_execution_run_id: ToolExecutionRunId("tool-1".to_owned()),
        function_call_node_id: HistoryNodeId(1),
        function_call_id: FunctionCallId("call-1".to_owned()),
        tool_name: ToolName("tool".to_owned()),
        arguments: JsonObject::new(),
    }
}

fn assert_debug_contains(event: EventIngress, task_id: Option<TaskId>, message: &str) {
    let EventIngress::Publish(ClientEvent::DebugNotice(debug)) = event else {
        panic!("unexpected event ingress");
    };
    assert_eq!(debug.task_id, task_id);
    assert!(debug.message_text.contains(message));
}

async fn finish_shutdown(control: TaskRuntimeControl) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(1);
    while !control.is_shutdown_requested() {
        assert!(tokio::time::Instant::now() < deadline, "runtime shutdown");
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    control
        .finish_shutdown(selvedge_command_model::TaskRuntimeShutdownResult)
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
struct BlockingToolSpawner {
    started: Arc<AtomicBool>,
    dropped: Arc<AtomicBool>,
}

impl BlockingToolSpawner {
    async fn wait_started(&self) {
        let deadline = tokio::time::Instant::now() + Duration::from_secs(1);
        while !self.started.load(Ordering::SeqCst) {
            assert!(
                tokio::time::Instant::now() < deadline,
                "tool execution did not start"
            );
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    }
}

struct ExecutionDropMarker(Arc<AtomicBool>);

impl Drop for ExecutionDropMarker {
    fn drop(&mut self) {
        self.0.store(true, Ordering::SeqCst);
    }
}

impl ToolExecutionSpawner for BlockingToolSpawner {
    fn spawn_tool_execution(
        &self,
        _request: ToolExecutionRequest,
        _router_tx: selvedge_command_model::RouterIngressWeakSender,
    ) -> Result<tokio::task::JoinHandle<()>, ToolExecutionSpawnError> {
        let started = self.started.clone();
        let dropped = self.dropped.clone();
        Ok(tokio::spawn(async move {
            let _drop_marker = ExecutionDropMarker(dropped);
            started.store(true, Ordering::SeqCst);
            std::future::pending::<()>().await;
        }))
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

#[derive(Default)]
struct CapturingRuntimeSpawner {
    receivers: Mutex<HashMap<TaskId, tokio::sync::mpsc::UnboundedReceiver<TaskRuntimeCommand>>>,
    controls: Mutex<HashMap<TaskId, TaskRuntimeControl>>,
}

impl CapturingRuntimeSpawner {
    async fn wait_receiver(
        &self,
        task_id: &str,
    ) -> tokio::sync::mpsc::UnboundedReceiver<TaskRuntimeCommand> {
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

    async fn finish_shutdown(&self, task_id: &str) {
        let control = self.wait_control(task_id).await;
        finish_shutdown(control).await;
    }
}

impl TaskRuntimeSpawner for CapturingRuntimeSpawner {
    fn spawn_task_runtime(
        &self,
        args: SpawnTaskRuntimeArgs,
    ) -> Result<SpawnedTaskRuntime, SpawnTaskRuntimeError> {
        let (task_runtime_tx, task_runtime_rx) = tokio::sync::mpsc::unbounded_channel();
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

struct FailingRuntimeSpawner;

impl TaskRuntimeSpawner for FailingRuntimeSpawner {
    fn spawn_task_runtime(
        &self,
        _args: SpawnTaskRuntimeArgs,
    ) -> Result<SpawnedTaskRuntime, SpawnTaskRuntimeError> {
        Err(SpawnTaskRuntimeError::TokioSpawnFailed)
    }
}

struct ClosedMailboxRuntimeSpawner;

impl TaskRuntimeSpawner for ClosedMailboxRuntimeSpawner {
    fn spawn_task_runtime(
        &self,
        args: SpawnTaskRuntimeArgs,
    ) -> Result<SpawnedTaskRuntime, SpawnTaskRuntimeError> {
        let (task_runtime_tx, task_runtime_rx) = tokio::sync::mpsc::unbounded_channel();
        drop(task_runtime_rx);
        Ok(SpawnedTaskRuntime {
            task_id: args.task_id,
            task_runtime_tx,
            task_runtime_control: TaskRuntimeControl::new(),
        })
    }
}

#[tokio::test]
async fn journaled_self_archive_does_not_cancel_the_outer_tool() {
    use selvedge_domain_model::{
        CommandInvocationId, CommandOperation, CommandOperationContext, CommandOperationId,
        ToolExecutionMode,
    };
    let db = open_memory_db();
    let root = create_command_task(&db, "parent");
    let call_id = FunctionCallId("call".into());
    let tool_name = ToolName("exec_cmd".into());
    let call = selvedge_db::append_model_reply_with_tool_calls_and_move_cursor(
        &db,
        &root.task_id,
        None,
        vec![selvedge_db::NewFunctionCallNodeContent {
            function_call_id: call_id.clone(),
            tool_name: tool_name.clone(),
            arguments: JsonObject::new(),
        }],
        UnixTs(2),
    )
    .expect("command operation succeeds")[0];
    let invocation = CommandInvocationId {
        task_id: root.task_id.clone(),
        function_call_node_id: call,
    };
    selvedge_db::admit_command_invocation(&db, &invocation, &call_id, &tool_name)
        .expect("command operation succeeds");
    let context = CommandOperationContext {
        caller_task_id: root.task_id.clone(),
        mode: ToolExecutionMode::Normal,
        operation: Some(CommandOperation {
            id: CommandOperationId {
                invocation,
                ordinal: 0,
            },
            command: "tasks.archive".into(),
            arguments: serde_json::json!({"task_id":"parent"}),
        }),
    };
    let spawner = Arc::new(BlockingToolSpawner::default());
    let (events_tx, _events_rx) = tokio::sync::mpsc::channel(32);
    let handle = spawn_router(RouterStartArgs {
        db: db.clone(),
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: spawner.clone(),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            model_profiles: HashMap::new(),
        }),
    });
    let mut request = tool_request("parent");
    request.function_call_node_id = call;
    request.function_call_id = call_id;
    request.tool_name = tool_name;
    handle
        .ingress_tx
        .send(RouterIngressMessage::Core(CoreOutputEnvelope {
            task_id: root.task_id.clone(),
            message: CoreOutputMessage::RequestToolExecution(request),
        }))
        .expect("command operation succeeds");
    spawner.wait_started().await;
    for _ in 0..2 {
        let (responder, response) = selvedge_command_model::command_operation_response_channel();
        handle
            .ingress_tx
            .send(RouterIngressMessage::Command(
                RouterCommand::ChangeTaskStatus {
                    task_id: root.task_id.clone(),
                    event: TaskLifecycleEvent::Archive,
                    context: context.clone(),
                    responder,
                },
            ))
            .expect("command operation succeeds");
        let result = response
            .await
            .expect("command operation succeeds")
            .expect("command operation succeeds");
        assert_eq!(result["deferred"], true);
        assert_eq!(
            read_task_status(&db, &root.task_id).expect("command operation succeeds"),
            TaskStatus::Active
        );
        assert!(!spawner.dropped.load(Ordering::SeqCst));
    }
    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("command operation succeeds");
    assert_eq!(
        handle
            .join_handle
            .await
            .expect("command operation succeeds"),
        RouterExitStatus::Stopped
    );
    assert!(spawner.dropped.load(Ordering::SeqCst));
}

#[tokio::test]
async fn scoped_send_to_frozen_task_queues_once_without_waiting_for_runtime() {
    use selvedge_domain_model::{
        CommandInvocationId, CommandOperation, CommandOperationContext, CommandOperationId,
        ToolExecutionMode,
    };
    let db = open_memory_db();
    let task = create_command_task(&db, "frozen");
    let call_id = FunctionCallId("call".into());
    let tool_name = ToolName("exec_cmd".into());
    let call = selvedge_db::append_model_reply_with_tool_calls_and_move_cursor(
        &db,
        &task.task_id,
        None,
        vec![selvedge_db::NewFunctionCallNodeContent {
            function_call_id: call_id.clone(),
            tool_name: tool_name.clone(),
            arguments: JsonObject::new(),
        }],
        UnixTs(2),
    )
    .expect("command operation succeeds")[0];
    let invocation = CommandInvocationId {
        task_id: task.task_id.clone(),
        function_call_node_id: call,
    };
    selvedge_db::admit_command_invocation(&db, &invocation, &call_id, &tool_name)
        .expect("command operation succeeds");
    transition_task_status(&db, &task.task_id, TaskLifecycleEvent::Freeze, UnixTs(3))
        .expect("command operation succeeds");
    let context = CommandOperationContext {
        caller_task_id: task.task_id.clone(),
        mode: ToolExecutionMode::Normal,
        operation: Some(CommandOperation {
            id: CommandOperationId {
                invocation,
                ordinal: 0,
            },
            command: "tasks.send".into(),
            arguments: serde_json::json!({"task_id":"frozen","message":"queued"}),
        }),
    };
    let (events_tx, _events_rx) = tokio::sync::mpsc::channel(32);
    let handle = spawn_router(RouterStartArgs {
        db: db.clone(),
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            model_profiles: HashMap::new(),
        }),
    });
    for _ in 0..2 {
        let (responder, response) = selvedge_command_model::command_operation_response_channel();
        handle
            .ingress_tx
            .send(RouterIngressMessage::Command(
                RouterCommand::SendTaskInput {
                    task_id: task.task_id.clone(),
                    message_text: "queued".into(),
                    context: context.clone(),
                    responder,
                },
            ))
            .expect("command operation succeeds");
        let result = tokio::time::timeout(Duration::from_secs(1), response)
            .await
            .expect("command operation succeeds")
            .expect("command operation succeeds")
            .expect("command operation succeeds");
        assert_eq!(result["disposition"], "queued");
    }
    assert_eq!(
        selvedge_db::load_runtime_task(&db, &task.task_id)
            .expect("command operation succeeds")
            .queued_input_count,
        1
    );
    assert_eq!(
        read_task_status(&db, &task.task_id).expect("command operation succeeds"),
        TaskStatus::Frozen
    );
    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("command operation succeeds");
    assert_eq!(
        handle
            .join_handle
            .await
            .expect("command operation succeeds"),
        RouterExitStatus::Stopped
    );
}

fn create_command_task(db: &selvedge_db::DbPool, id: &str) -> selvedge_db::TaskRow {
    selvedge_test_support::db::create_root_task_with_user_message_and_tools(
        db,
        id,
        "hello",
        vec![selvedge_db::TaskToolSpec {
            tool: selvedge_domain_model::ToolSpec {
                name: "exec_cmd".into(),
                description: "command".into(),
                input_schema: [("type".into(), "object".into())].into_iter().collect(),
            },
            execution_source: selvedge_db::ToolExecutionSource::Harness,
            recovery_policy: selvedge_db::ToolRecoveryPolicy::RetrySafe,
        }],
        UnixTs(1),
    )
}

#[derive(Default)]
struct RecordingLiveSpawner(Mutex<Vec<TaskId>>);

impl TaskRuntimeSpawner for RecordingLiveSpawner {
    fn spawn_task_runtime(
        &self,
        args: SpawnTaskRuntimeArgs,
    ) -> Result<SpawnedTaskRuntime, SpawnTaskRuntimeError> {
        self.0
            .lock()
            .expect("spawn inventory")
            .push(args.task_id.clone());
        Ok(selvedge_core::spawn_task_runtime(args))
    }
}

struct CompletingCommandSpawner(DbPool);

impl ToolExecutionSpawner for CompletingCommandSpawner {
    fn spawn_tool_execution(
        &self,
        request: ToolExecutionRequest,
        router_tx: selvedge_command_model::RouterIngressWeakSender,
    ) -> Result<tokio::task::JoinHandle<()>, ToolExecutionSpawnError> {
        let db = self.0.clone();
        Ok(tokio::spawn(async move {
            let environment = selvedge_db::read_command_environment(&db, &request.task_id)
                .expect("admitted environment");
            let prepared = selvedge_command_model::ToolExecutionCompletion::command(
                selvedge_domain_model::CommandEnvironmentCommit {
                    new_child_environment_mode:
                        selvedge_domain_model::CommandEnvironmentMode::Shared,
                    environment_id: environment.environment_id,
                    invocation: environment.admitted_invocation.expect("admitted owner"),
                    expected_revision: environment.revision,
                    checkpoint: vec![8],
                    base_checkpoint: vec![],
                },
                Arc::new(tokio::sync::Mutex::new(())).lock_owned().await,
            );
            router_tx
                .upgrade()
                .expect("live router")
                .send(RouterIngressMessage::Tool(ToolExecutionResult {
                    completion: prepared,
                    task_id: request.task_id,
                    tool_execution_run_id: request.tool_execution_run_id,
                    function_call_node_id: request.function_call_node_id,
                    function_call_id: request.function_call_id,
                    tool_name: request.tool_name,
                    branches: vec![ToolExecutionBranch {
                        target: ToolExecutionBranchTarget::CallingTask,
                        output: serde_json::json!({"recovered":true}),
                        is_error: false,
                        messages: vec![],
                    }],
                }))
                .expect("tool result");
        }))
    }
}

#[tokio::test]
async fn startup_recovers_inactive_admission_and_publishes_pending_child_without_a_waiter() {
    use selvedge_domain_model::{
        CommandEnvironmentMode, CommandInvocationId, CommandOperation, CommandOperationContext,
        CommandOperationId, ToolExecutionMode,
    };
    for event in [
        TaskLifecycleEvent::Archive,
        TaskLifecycleEvent::Freeze,
        TaskLifecycleEvent::Stop,
    ] {
        let db = open_memory_db();
        let parent = create_command_task(&db, "parent");
        let call_id = FunctionCallId("call".into());
        let tool_name = ToolName("exec_cmd".into());
        let call = selvedge_db::append_model_reply_with_tool_calls_and_move_cursor(
            &db,
            &parent.task_id,
            None,
            vec![selvedge_db::NewFunctionCallNodeContent {
                function_call_id: call_id.clone(),
                tool_name: tool_name.clone(),
                arguments: JsonObject::new(),
            }],
            UnixTs(2),
        )
        .expect("persist call")[0];
        let invocation = CommandInvocationId {
            task_id: parent.task_id.clone(),
            function_call_node_id: call,
        };
        selvedge_db::admit_command_invocation(&db, &invocation, &call_id, &tool_name)
            .expect("admit outer");
        let context = CommandOperationContext {
            caller_task_id: parent.task_id.clone(),
            mode: ToolExecutionMode::Normal,
            operation: Some(CommandOperation {
                id: CommandOperationId {
                    invocation,
                    ordinal: 0,
                },
                command: "tasks.fork".into(),
                arguments: serde_json::json!({"child_count":1}),
            }),
        };
        let child = TaskId("pending-child".into());
        selvedge_db::create_pending_command_child(
            &db,
            &context,
            child.clone(),
            CommandEnvironmentMode::Copy,
            vec![],
            UnixTs(3),
        )
        .expect("stage child");
        transition_task_status(&db, &parent.task_id, event, UnixTs(4))
            .expect("parent becomes inactive");
        let spawner = Arc::new(RecordingLiveSpawner::default());
        let (events_tx, mut events_rx) = tokio::sync::mpsc::channel(64);
        let handle = spawn_router(RouterStartArgs {
            db: db.clone(),
            events_tx,
            api_config: ApiExecutorConfig {
                request_timeout: Duration::from_secs(1),
                max_response_bytes: None,
            },
            tool_executor: Arc::new(CompletingCommandSpawner(db.clone())),
            core_spawn_deps: TaskRuntimeSpawnDeps::with_spawner(
                TaskRuntimeConfig {
                    model_profiles: HashMap::new(),
                },
                spawner.clone(),
            ),
        });
        if event == TaskLifecycleEvent::Freeze {
            handle
                .ingress_tx
                .send(RouterIngressMessage::Command(
                    RouterCommand::EnsureTaskRuntime {
                        task_id: parent.task_id.clone(),
                    },
                ))
                .expect("create frozen idle runtime");
            timeout(Duration::from_secs(1), events_rx.recv())
                .await
                .expect("frozen readiness")
                .expect("readiness event");
        }
        handle
            .ingress_tx
            .send(RouterIngressMessage::Command(
                RouterCommand::EnsureMissingTaskRuntimes,
            ))
            .expect("startup recovery");
        timeout(Duration::from_secs(2), async {
            loop {
                let started = spawner.0.lock().expect("spawn inventory").contains(&child);
                if started && !selvedge_db::task_is_pending(&db, &child).expect("pending state") {
                    break;
                }
                tokio::task::yield_now().await;
            }
        })
        .await
        .expect("inactive admission publishes and starts its child");
        assert!(
            selvedge_db::list_admitted_command_invocations(&db)
                .expect("remaining admissions")
                .is_empty()
        );
        assert_eq!(
            selvedge_db::read_command_environment(&db, &child)
                .expect("child environment")
                .checkpoint,
            vec![8]
        );
        assert_eq!(
            read_task_status(&db, &parent.task_id).expect("parent status"),
            TaskStatus::Active
                .transition(event)
                .expect("expected inactive status")
        );
        handle
            .ingress_tx
            .send(RouterIngressMessage::StopRouter)
            .expect("stop");
        assert_eq!(
            handle.join_handle.await.expect("join"),
            RouterExitStatus::Stopped
        );
    }
}

#[tokio::test]
async fn unrelated_task_send_is_rejected_before_runtime_or_cursor_execution() {
    use selvedge_domain_model::{
        CommandInvocationId, CommandOperation, CommandOperationContext, CommandOperationId,
        ToolExecutionMode,
    };
    let db = open_memory_db();
    let caller = create_command_task(&db, "caller");
    let target = create_command_task(&db, "unrelated-target");
    let mut calls = Vec::new();
    for task in [&caller, &target] {
        calls.push(
            selvedge_db::append_model_reply_with_tool_calls_and_move_cursor(
                &db,
                &task.task_id,
                None,
                vec![selvedge_db::NewFunctionCallNodeContent {
                    function_call_id: FunctionCallId(format!("{}-call", task.task_id.0)),
                    tool_name: ToolName("exec_cmd".into()),
                    arguments: JsonObject::new(),
                }],
                UnixTs(2),
            )
            .expect("persist executable cursor")[0],
        );
    }
    let invocation = CommandInvocationId {
        task_id: caller.task_id.clone(),
        function_call_node_id: calls[0],
    };
    selvedge_db::admit_command_invocation(
        &db,
        &invocation,
        &FunctionCallId("caller-call".into()),
        &ToolName("exec_cmd".into()),
    )
    .expect("admit caller script");
    let operation = CommandOperation {
        id: CommandOperationId {
            invocation,
            ordinal: 0,
        },
        command: "tasks.send".into(),
        arguments: serde_json::json!({"task_id":"unrelated-target","message":"unauthorized"}),
    };
    let runtimes = Arc::new(RecordingLiveSpawner::default());
    let tools = Arc::new(CapturingToolSpawner::default());
    let (events_tx, mut events_rx) = tokio::sync::mpsc::channel(16);
    let handle = spawn_router(RouterStartArgs {
        db: db.clone(),
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: tools.clone(),
        core_spawn_deps: TaskRuntimeSpawnDeps::with_spawner(
            TaskRuntimeConfig {
                model_profiles: default_model_profiles(),
            },
            runtimes.clone(),
        ),
    });
    for operation in [None, Some(operation)] {
        let (responder, response) = selvedge_command_model::command_operation_response_channel();
        handle
            .ingress_tx
            .send(RouterIngressMessage::Command(
                RouterCommand::SendTaskInput {
                    task_id: target.task_id.clone(),
                    message_text: "unauthorized".into(),
                    context: CommandOperationContext {
                        caller_task_id: caller.task_id.clone(),
                        mode: ToolExecutionMode::Normal,
                        operation,
                    },
                    responder,
                },
            ))
            .expect("submit task-originated send");
        assert!(
            timeout(Duration::from_secs(1), response)
                .await
                .expect("send responds")
                .expect("response channel")
                .is_err()
        );
        assert!(
            runtimes.0.lock().expect("runtime inventory").is_empty(),
            "denied send must not start a task or model turn"
        );
        assert_eq!(
            tools.request_count(),
            0,
            "denied send must not execute the target cursor"
        );
        assert!(
            events_rx.try_recv().is_err(),
            "denied send must not publish runtime or model activity"
        );
        assert_eq!(
            selvedge_db::load_runtime_task(&db, &target.task_id)
                .expect("target remains untouched")
                .task
                .cursor_node_id,
            calls[1]
        );
    }
    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
}
