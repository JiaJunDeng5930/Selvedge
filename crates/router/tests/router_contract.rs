use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

use selvedge_command_model::{
    ClientCommand, ClientCommandEnvelope, ClientCommandId, ClientId, ClientSubscription,
    CoreOutputEnvelope, CoreOutputMessage, CreatedRuntimeKind, DetailLevel, DomainEvent,
    DomainEventPublishRequest, EventControlMessage, EventIngress, FactoryFailureKind,
    FactoryOutput, FactoryOutputEnvelope, FactoryScanOutput, FactoryTaskFailure,
    HistoryNodeProjectionBody, ModelCallDispatchRequest, RawEvent, RefreshClientSnapshot,
    RuntimeInventoryQuery, RuntimeInventoryResponse, StopTaskRuntime, SubmitUserInput, TaskId,
    TaskRuntimeCommand, TaskRuntimeCreated, TaskRuntimeHandle, TaskRuntimeToken, TaskScope,
    ToolExecutionRequest,
};
use selvedge_db::{
    CreateRootTaskInput, ModelProfileKey, NewHistoryNode, NewHistoryNodeContent,
    NewMessageNodeContent, OpenDbOptions, ReasoningEffort, UnixTs,
    append_user_message_and_move_cursor, create_history_node, create_root_task, open_db,
};
use selvedge_router::{
    ApiExecutor, FactoryExecutor, FactorySpawnRequest, RouterStartArgs, SpawnApiEffectError,
    SpawnRouterError, SpawnToolEffectError, ToolExecutor, spawn_router,
};
use selvedge_task_runtime_factory::{FactoryCommand, SpawnFactoryEffectError};

#[test]
fn spawn_router_rejects_zero_ingress_capacity() {
    let error = spawn_router(start_args(0, 8)).expect_err("invalid ingress capacity");

    assert_eq!(error, SpawnRouterError::InvalidIngressCapacity);
}

#[tokio::test]
async fn factory_runtime_created_registers_runtime_and_answers_inventory() {
    let factory = Arc::new(RecordingFactoryExecutor::default());
    let handle =
        spawn_router(start_args_with_factory(8, 8, factory.clone())).expect("spawn router");
    let (task_runtime_tx, mut task_runtime_rx) = tokio::sync::mpsc::channel(8);
    handle
        .router_tx
        .send(selvedge_command_model::RouterIngressMessage::Client(
            ClientCommandEnvelope {
                client_id: Some(ClientId("client-1".to_owned())),
                command_id: ClientCommandId("command-1".to_owned()),
                command: ClientCommand::EnsureTaskRuntime(
                    selvedge_command_model::EnsureTaskRuntime {
                        task_id: TaskId("task-1".to_owned()),
                    },
                ),
            },
        ))
        .await
        .expect("send ensure command");
    let command = factory.take_one_command().await;
    let FactoryCommand::EnsureTaskRuntime(command) = command else {
        panic!("unexpected factory command");
    };

    handle
        .router_tx
        .send(selvedge_command_model::RouterIngressMessage::Factory(
            FactoryOutputEnvelope {
                effect_id: command.effect_id,
                output: FactoryOutput::RuntimeCreated(TaskRuntimeCreated {
                    task_id: TaskId("task-1".to_owned()),
                    runtime: TaskRuntimeHandle {
                        runtime_token: TaskRuntimeToken("runtime-1".to_owned()),
                        task_runtime_tx,
                    },
                    created_runtime_kind: CreatedRuntimeKind::ExistingTaskRuntime,
                }),
            },
        ))
        .await
        .expect("send factory output");

    assert!(matches!(
        task_runtime_rx.recv().await.expect("start command"),
        TaskRuntimeCommand::Start
    ));

    let inventory = query_inventory(&handle.router_tx).await;
    assert_eq!(
        inventory.live_task_runtimes,
        vec![TaskId("task-1".to_owned())]
    );
    assert!(inventory.pending_task_runtime_effects.is_empty());

    shutdown(handle).await;
}

#[tokio::test]
async fn submit_user_input_without_runtime_starts_factory_and_flushes_waiting_command() {
    let factory = Arc::new(RecordingFactoryExecutor::default());
    let handle =
        spawn_router(start_args_with_factory(8, 8, factory.clone())).expect("spawn router");

    handle
        .router_tx
        .send(selvedge_command_model::RouterIngressMessage::Client(
            ClientCommandEnvelope {
                client_id: Some(ClientId("client-1".to_owned())),
                command_id: ClientCommandId("command-1".to_owned()),
                command: ClientCommand::SubmitUserInput(SubmitUserInput {
                    task_id: TaskId("task-1".to_owned()),
                    message_text: "hello".to_owned(),
                }),
            },
        ))
        .await
        .expect("send client command");

    let command = factory.take_one_command().await;
    let FactoryCommand::EnsureTaskRuntime(command) = command else {
        panic!("unexpected factory command");
    };
    assert_eq!(command.task_id, TaskId("task-1".to_owned()));

    let inventory = query_inventory(&handle.router_tx).await;
    assert_eq!(
        inventory.pending_task_runtime_effects,
        vec![TaskId("task-1".to_owned())]
    );
    let self_inventory =
        query_inventory_for_effect(&handle.router_tx, command.effect_id.clone()).await;
    assert!(self_inventory.pending_task_runtime_effects.is_empty());

    let (task_runtime_tx, mut task_runtime_rx) = tokio::sync::mpsc::channel(8);
    handle
        .router_tx
        .send(selvedge_command_model::RouterIngressMessage::Factory(
            FactoryOutputEnvelope {
                effect_id: command.effect_id,
                output: FactoryOutput::RuntimeCreated(TaskRuntimeCreated {
                    task_id: TaskId("task-1".to_owned()),
                    runtime: TaskRuntimeHandle {
                        runtime_token: TaskRuntimeToken("runtime-1".to_owned()),
                        task_runtime_tx,
                    },
                    created_runtime_kind: CreatedRuntimeKind::ExistingTaskRuntime,
                }),
            },
        ))
        .await
        .expect("send factory output");

    assert!(matches!(
        task_runtime_rx.recv().await.expect("start command"),
        TaskRuntimeCommand::Start
    ));
    match task_runtime_rx.recv().await.expect("waiting command") {
        TaskRuntimeCommand::UserInput { message_text } => assert_eq!(message_text, "hello"),
        _ => panic!("unexpected task runtime command"),
    }

    shutdown(handle).await;
}

#[tokio::test]
async fn queued_stop_after_pending_creation_skips_start() {
    let factory = Arc::new(RecordingFactoryExecutor::default());
    let handle =
        spawn_router(start_args_with_factory(8, 8, factory.clone())).expect("spawn router");

    handle
        .router_tx
        .send(selvedge_command_model::RouterIngressMessage::Client(
            ClientCommandEnvelope {
                client_id: Some(ClientId("client-1".to_owned())),
                command_id: ClientCommandId("ensure-1".to_owned()),
                command: ClientCommand::EnsureTaskRuntime(
                    selvedge_command_model::EnsureTaskRuntime {
                        task_id: TaskId("task-1".to_owned()),
                    },
                ),
            },
        ))
        .await
        .expect("send ensure");
    let command = factory.take_one_command().await;
    let FactoryCommand::EnsureTaskRuntime(command) = command else {
        panic!("unexpected factory command");
    };

    handle
        .router_tx
        .send(selvedge_command_model::RouterIngressMessage::Client(
            ClientCommandEnvelope {
                client_id: Some(ClientId("client-1".to_owned())),
                command_id: ClientCommandId("stop-1".to_owned()),
                command: ClientCommand::StopTaskRuntime(StopTaskRuntime {
                    task_id: TaskId("task-1".to_owned()),
                }),
            },
        ))
        .await
        .expect("send stop");

    let (task_runtime_tx, mut task_runtime_rx) = tokio::sync::mpsc::channel(8);
    handle
        .router_tx
        .send(selvedge_command_model::RouterIngressMessage::Factory(
            FactoryOutputEnvelope {
                effect_id: command.effect_id,
                output: FactoryOutput::RuntimeCreated(TaskRuntimeCreated {
                    task_id: TaskId("task-1".to_owned()),
                    runtime: TaskRuntimeHandle {
                        runtime_token: TaskRuntimeToken("runtime-1".to_owned()),
                        task_runtime_tx,
                    },
                    created_runtime_kind: CreatedRuntimeKind::ExistingTaskRuntime,
                }),
            },
        ))
        .await
        .expect("send factory output");

    assert!(matches!(
        task_runtime_rx.recv().await.expect("stop command"),
        TaskRuntimeCommand::Stop
    ));
    tokio::time::timeout(std::time::Duration::from_millis(25), task_runtime_rx.recv())
        .await
        .expect_err("no start command");

    shutdown(handle).await;
}

#[tokio::test]
async fn factory_spawn_failure_preserves_existing_effects() {
    let factory = Arc::new(RecordingFactoryExecutor::default());
    let handle =
        spawn_router(start_args_with_factory(8, 8, factory.clone())).expect("spawn router");

    handle
        .router_tx
        .send(selvedge_command_model::RouterIngressMessage::Client(
            ClientCommandEnvelope {
                client_id: None,
                command_id: ClientCommandId("ensure-1".to_owned()),
                command: ClientCommand::EnsureTaskRuntime(
                    selvedge_command_model::EnsureTaskRuntime {
                        task_id: TaskId("task-1".to_owned()),
                    },
                ),
            },
        ))
        .await
        .expect("send first ensure");
    let first = factory.take_one_command().await;
    let FactoryCommand::EnsureTaskRuntime(first) = first else {
        panic!("unexpected factory command");
    };

    factory.fail_next_spawn();
    handle
        .router_tx
        .send(selvedge_command_model::RouterIngressMessage::Client(
            ClientCommandEnvelope {
                client_id: None,
                command_id: ClientCommandId("ensure-2".to_owned()),
                command: ClientCommand::EnsureTaskRuntime(
                    selvedge_command_model::EnsureTaskRuntime {
                        task_id: TaskId("task-2".to_owned()),
                    },
                ),
            },
        ))
        .await
        .expect("send second ensure");

    let (task_runtime_tx, mut task_runtime_rx) = tokio::sync::mpsc::channel(8);
    handle
        .router_tx
        .send(selvedge_command_model::RouterIngressMessage::Factory(
            FactoryOutputEnvelope {
                effect_id: first.effect_id,
                output: FactoryOutput::RuntimeCreated(TaskRuntimeCreated {
                    task_id: TaskId("task-1".to_owned()),
                    runtime: TaskRuntimeHandle {
                        runtime_token: TaskRuntimeToken("runtime-1".to_owned()),
                        task_runtime_tx,
                    },
                    created_runtime_kind: CreatedRuntimeKind::ExistingTaskRuntime,
                }),
            },
        ))
        .await
        .expect("send first factory output");

    assert!(matches!(
        task_runtime_rx.recv().await.expect("start command"),
        TaskRuntimeCommand::Start
    ));

    shutdown(handle).await;
}

#[tokio::test]
async fn scan_finished_reports_per_task_failures() {
    let factory = Arc::new(RecordingFactoryExecutor::default());
    let (events_tx, mut events_rx) = tokio::sync::mpsc::channel(8);
    let handle = spawn_router(RouterStartArgs {
        db: open_test_db(),
        events_tx,
        factory_executor: factory.clone(),
        api_executor: Arc::new(NoopApiExecutor),
        tool_executor: Arc::new(NoopToolExecutor),
        ingress_capacity: 8,
        pending_task_command_limit: 8,
    })
    .expect("spawn router");

    handle
        .router_tx
        .send(selvedge_command_model::RouterIngressMessage::Client(
            ClientCommandEnvelope {
                client_id: None,
                command_id: ClientCommandId("scan-1".to_owned()),
                command: ClientCommand::EnsureMissingTaskRuntimes(
                    selvedge_command_model::EnsureMissingTaskRuntimes,
                ),
            },
        ))
        .await
        .expect("send scan");
    let command = factory.take_one_command().await;
    let FactoryCommand::EnsureMissingTaskRuntimes(command) = command else {
        panic!("unexpected factory command");
    };

    handle
        .router_tx
        .send(selvedge_command_model::RouterIngressMessage::Factory(
            FactoryOutputEnvelope {
                effect_id: command.effect_id,
                output: FactoryOutput::ScanFinished(FactoryScanOutput {
                    created: Vec::new(),
                    skipped: Vec::new(),
                    failed: vec![FactoryTaskFailure {
                        task_id: TaskId("task-failed".to_owned()),
                        kind: FactoryFailureKind::CoreSpawnFailed,
                        message: "spawn failed".to_owned(),
                    }],
                }),
            },
        ))
        .await
        .expect("send scan output");

    let event = tokio::time::timeout(std::time::Duration::from_millis(50), events_rx.recv())
        .await
        .expect("scan failure notice")
        .expect("scan failure event");
    match event {
        EventIngress::Raw(RawEvent::Debug(event)) => {
            assert_eq!(event.task_id, Some(TaskId("task-failed".to_owned())));
            assert!(event.message_text.contains("CoreSpawnFailed"));
            assert!(event.message_text.contains("spawn failed"));
        }
        _ => panic!("unexpected event ingress"),
    }

    shutdown(handle).await;
}

#[tokio::test]
async fn domain_history_commit_emits_typed_history_event() {
    let db = open_test_db();
    create_root(&db, "task-1");
    let node_id = append_user_message_and_move_cursor(
        &db,
        &TaskId("task-1".to_owned()),
        "hello".to_owned(),
        UnixTs(2),
    )
    .expect("append user message");
    let (events_tx, mut events_rx) = tokio::sync::mpsc::channel(8);
    let handle = spawn_router(RouterStartArgs {
        db,
        events_tx,
        factory_executor: Arc::new(RecordingFactoryExecutor::default()),
        api_executor: Arc::new(NoopApiExecutor),
        tool_executor: Arc::new(NoopToolExecutor),
        ingress_capacity: 8,
        pending_task_command_limit: 8,
    })
    .expect("spawn router");

    handle
        .router_tx
        .send(selvedge_command_model::RouterIngressMessage::Core(
            CoreOutputEnvelope {
                task_id: TaskId("task-1".to_owned()),
                message: CoreOutputMessage::PublishDomainEvent(DomainEventPublishRequest {
                    task_id: TaskId("task-1".to_owned()),
                    event: DomainEvent::UserMessageCommitted { node_id },
                }),
            },
        ))
        .await
        .expect("send domain event");

    let event = tokio::time::timeout(std::time::Duration::from_millis(50), events_rx.recv())
        .await
        .expect("typed event")
        .expect("typed event message");
    match event {
        EventIngress::Raw(RawEvent::HistoryAppended(event)) => {
            assert_eq!(event.task_id, TaskId("task-1".to_owned()));
            assert_eq!(event.task_state_version, 1);
            assert_eq!(event.appended_nodes.len(), 1);
            assert!(matches!(
                event.appended_nodes[0].body,
                HistoryNodeProjectionBody::Message { .. }
            ));
        }
        _ => panic!("unexpected event ingress"),
    }

    shutdown(handle).await;
}

#[tokio::test]
async fn attach_client_begins_hydration_and_delivers_snapshot() {
    let db = open_test_db();
    create_root(&db, "task-1");
    assert_eq!(
        selvedge_db::list_active_tasks(&db)
            .expect("list active tasks")
            .len(),
        1
    );
    let (events_tx, mut events_rx) = tokio::sync::mpsc::channel(8);
    let handle = spawn_router(RouterStartArgs {
        db,
        events_tx,
        factory_executor: Arc::new(RecordingFactoryExecutor::default()),
        api_executor: Arc::new(NoopApiExecutor),
        tool_executor: Arc::new(NoopToolExecutor),
        ingress_capacity: 8,
        pending_task_command_limit: 8,
    })
    .expect("spawn router");
    let (output_tx, _output_rx) = tokio::sync::mpsc::channel(8);

    handle
        .router_tx
        .send(selvedge_command_model::RouterIngressMessage::Client(
            ClientCommandEnvelope {
                client_id: Some(ClientId("client-1".to_owned())),
                command_id: ClientCommandId("attach-1".to_owned()),
                command: ClientCommand::AttachClient(selvedge_command_model::AttachClient {
                    client_id: ClientId("client-1".to_owned()),
                    output_tx,
                    subscription: subscription(),
                }),
            },
        ))
        .await
        .expect("send attach");

    let begin = tokio::time::timeout(std::time::Duration::from_millis(50), events_rx.recv())
        .await
        .expect("begin hydration")
        .expect("begin hydration message");
    assert!(matches!(
        begin,
        EventIngress::Control(EventControlMessage::BeginClientHydration(_))
    ));

    let snapshot = tokio::time::timeout(std::time::Duration::from_millis(50), events_rx.recv())
        .await
        .expect("deliver snapshot")
        .expect("deliver snapshot message");
    match snapshot {
        EventIngress::Control(EventControlMessage::DeliverSnapshot(snapshot)) => {
            assert_eq!(snapshot.client_id, ClientId("client-1".to_owned()));
            assert_eq!(
                snapshot.client_command_id,
                ClientCommandId("attach-1".to_owned())
            );
            assert_eq!(snapshot.snapshot.tasks.len(), 1);
            assert_eq!(
                snapshot.snapshot.tasks[0].task_id,
                TaskId("task-1".to_owned())
            );
            assert_eq!(snapshot.snapshot.task_versions[0].state_version, 0);
        }
        _ => panic!("unexpected event ingress"),
    }

    handle
        .router_tx
        .send(selvedge_command_model::RouterIngressMessage::Client(
            ClientCommandEnvelope {
                client_id: Some(ClientId("client-1".to_owned())),
                command_id: ClientCommandId("refresh-1".to_owned()),
                command: ClientCommand::RefreshClientSnapshot(RefreshClientSnapshot {
                    client_id: ClientId("client-1".to_owned()),
                }),
            },
        ))
        .await
        .expect("send refresh");
    let snapshot = tokio::time::timeout(std::time::Duration::from_millis(50), events_rx.recv())
        .await
        .expect("deliver refresh snapshot")
        .expect("deliver refresh snapshot message");
    match snapshot {
        EventIngress::Control(EventControlMessage::DeliverSnapshot(snapshot)) => {
            assert_eq!(
                snapshot.client_command_id,
                ClientCommandId("attach-1".to_owned())
            );
        }
        _ => panic!("unexpected event ingress"),
    }

    shutdown(handle).await;
}

fn start_args(ingress_capacity: usize, pending_task_command_limit: usize) -> RouterStartArgs {
    start_args_with_factory(
        ingress_capacity,
        pending_task_command_limit,
        Arc::new(RecordingFactoryExecutor::default()),
    )
}

fn start_args_with_factory(
    ingress_capacity: usize,
    pending_task_command_limit: usize,
    factory_executor: Arc<RecordingFactoryExecutor>,
) -> RouterStartArgs {
    let (events_tx, _events_rx) = tokio::sync::mpsc::channel(8);
    RouterStartArgs {
        db: open_test_db(),
        events_tx,
        factory_executor,
        api_executor: Arc::new(NoopApiExecutor),
        tool_executor: Arc::new(NoopToolExecutor),
        ingress_capacity,
        pending_task_command_limit,
    }
}

fn open_test_db() -> selvedge_db::DbPool {
    open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
    })
    .expect("open db")
}

fn create_root(db: &selvedge_db::DbPool, task_id: &str) {
    let cursor_node_id = create_history_node(
        db,
        NewHistoryNode {
            parent_node_id: None,
            content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                message_role: selvedge_db::MessageRole::System,
                message_text: "system".to_owned(),
            }),
            created_at: UnixTs(1),
        },
    )
    .expect("create history node");
    create_root_task(
        db,
        CreateRootTaskInput {
            task_id: TaskId(task_id.to_owned()),
            cursor_node_id,
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(1),
        },
    )
    .expect("create root task");
}

fn subscription() -> ClientSubscription {
    ClientSubscription {
        task_scope: TaskScope::AllTasks,
        detail_level: DetailLevel::Verbose,
        include_model_call_status: true,
        include_tool_execution_status: true,
        include_debug_notices: true,
    }
}

async fn query_inventory(
    router_tx: &selvedge_command_model::RouterIngressSender,
) -> RuntimeInventoryResponse {
    query_inventory_with_requester(router_tx, None).await
}

async fn query_inventory_for_effect(
    router_tx: &selvedge_command_model::RouterIngressSender,
    effect_id: selvedge_command_model::FactoryEffectId,
) -> RuntimeInventoryResponse {
    query_inventory_with_requester(router_tx, Some(effect_id)).await
}

async fn query_inventory_with_requester(
    router_tx: &selvedge_command_model::RouterIngressSender,
    requesting_effect_id: Option<selvedge_command_model::FactoryEffectId>,
) -> RuntimeInventoryResponse {
    let (reply_to, reply_rx) = tokio::sync::oneshot::channel();
    router_tx
        .send(
            selvedge_command_model::RouterIngressMessage::RuntimeInventoryQuery(
                RuntimeInventoryQuery {
                    requesting_effect_id,
                    reply_to,
                },
            ),
        )
        .await
        .expect("send inventory query");
    reply_rx.await.expect("inventory response")
}

async fn shutdown(handle: selvedge_router::RouterHandle) {
    handle
        .router_tx
        .send(selvedge_command_model::RouterIngressMessage::Shutdown(
            selvedge_command_model::RouterShutdown,
        ))
        .await
        .expect("send shutdown");
    handle.join_handle.await.expect("router joins");
}

#[derive(Default)]
struct RecordingFactoryExecutor {
    commands: Mutex<VecDeque<FactoryCommand>>,
    fail_next: Mutex<bool>,
    notify: tokio::sync::Notify,
}

impl RecordingFactoryExecutor {
    async fn take_one_command(&self) -> FactoryCommand {
        loop {
            if let Some(command) = self.commands.lock().expect("lock commands").pop_front() {
                return command;
            }
            self.notify.notified().await;
        }
    }

    fn fail_next_spawn(&self) {
        *self.fail_next.lock().expect("lock fail flag") = true;
    }
}

impl FactoryExecutor for RecordingFactoryExecutor {
    fn spawn_factory_effect(
        &self,
        request: FactorySpawnRequest,
    ) -> Result<tokio::task::JoinHandle<()>, SpawnFactoryEffectError> {
        let mut fail_next = self.fail_next.lock().expect("lock fail flag");
        if *fail_next {
            *fail_next = false;
            return Err(SpawnFactoryEffectError::TokioSpawnFailed);
        }
        drop(fail_next);

        self.commands
            .lock()
            .expect("lock commands")
            .push_back(request.command);
        self.notify.notify_waiters();
        Ok(tokio::spawn(async {}))
    }
}

struct NoopApiExecutor;

impl ApiExecutor for NoopApiExecutor {
    fn spawn_model_call(
        &self,
        _request: ModelCallDispatchRequest,
        _router_tx: selvedge_command_model::RouterIngressSender,
    ) -> Result<tokio::task::JoinHandle<()>, SpawnApiEffectError> {
        Ok(tokio::spawn(async {}))
    }
}

struct NoopToolExecutor;

impl ToolExecutor for NoopToolExecutor {
    fn spawn_tool_execution(
        &self,
        _request: ToolExecutionRequest,
        _router_tx: selvedge_command_model::RouterIngressSender,
    ) -> Result<tokio::task::JoinHandle<()>, SpawnToolEffectError> {
        Ok(tokio::spawn(async {}))
    }
}
