use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use selvedge_api::{ApiExecutorConfig, ModelProviderAdapter, ModelProviderRegistry};
use selvedge_command_model::{
    ApiCallCorrelation, ApiEffectId, ApiOutputEnvelope, BeginClientHydration, ClientCommandId,
    ClientId, ClientSubscription, CoreOutputEnvelope, CoreOutputMessage, DetailLevel,
    EventControlMessage, EventIngress, ModelCallError, ModelCallErrorKind, ModelRunId, RawEvent,
    RouterCommand, RouterCommandEnvelope, RouterIngressMessage, TaskRuntimeCommand, TaskScope,
    ToolExecutionRequest, ToolExecutionResult, ToolExecutionRunId,
};
use selvedge_core::{
    SpawnTaskRuntimeArgs, SpawnTaskRuntimeError, SpawnedTaskRuntime, TaskRuntimeConfig,
    TaskRuntimeSpawnDeps, TaskRuntimeSpawner,
};
use selvedge_db::{
    CreateRootTaskInput, DbPool, MessageRole, ModelProfileKey, NewHistoryNode,
    NewHistoryNodeContent, NewMessageNodeContent, OpenDbOptions, ReasoningEffort, TaskId, UnixTs,
    create_history_node, create_root_task, open_db,
};
use selvedge_domain_model::{FunctionCallId, HistoryNodeId, ModelProviderProfile, ToolName};
use selvedge_router::{
    RouterExitStatus, RouterStartArgs, SpawnRouterError, ToolExecutionSpawnError,
    ToolExecutionSpawner, spawn_router,
};

#[tokio::test]
async fn attach_client_command_is_forwarded_to_events() {
    let db = open_memory_db();
    let (events_tx, mut events_rx) = tokio::sync::mpsc::channel(8);

    let handle = spawn_router(RouterStartArgs {
        db,
        events_tx,
        api_provider_registry: Arc::new(EmptyProviderRegistry),
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: HashMap::new(),
        }),
        router_mailbox_capacity: 8,
    })
    .expect("spawn router");

    let (outbound, _outbound_rx) = tokio::sync::mpsc::channel(4);
    let subscription = ClientSubscription {
        task_scope: TaskScope::AllTasks,
        detail_level: DetailLevel::Verbose,
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
            },
        }))
        .await
        .expect("send command");

    let event = events_rx.recv().await.expect("events ingress");
    let EventIngress::Control(EventControlMessage::BeginClientHydration(BeginClientHydration {
        client_id,
        client_command_id,
        subscription: received_subscription,
        ..
    })) = event
    else {
        panic!("unexpected events ingress");
    };
    assert_eq!(client_id, ClientId("client-1".to_owned()));
    assert_eq!(client_command_id, ClientCommandId("attach-1".to_owned()));
    assert_eq!(received_subscription, subscription);

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .await
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
        api_provider_registry: Arc::new(EmptyProviderRegistry),
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
        router_mailbox_capacity: 8,
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
        .await
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
        .await
        .expect("stop router");
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
        api_provider_registry: Arc::new(EmptyProviderRegistry),
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
        router_mailbox_capacity: 8,
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
        .await
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
        .await
        .expect("send api output");
    let api_command = runtime_rx.recv().await.expect("api command");
    assert!(matches!(api_command, TaskRuntimeCommand::ApiModelReply(_)));

    handle
        .ingress_tx
        .send(RouterIngressMessage::Tool(tool_result("task-1")))
        .await
        .expect("send tool output");
    let tool_command = runtime_rx.recv().await.expect("tool command");
    assert!(matches!(tool_command, TaskRuntimeCommand::ToolResult(_)));

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .await
        .expect("stop router");
    assert!(matches!(
        runtime_rx.recv().await.expect("stop command"),
        TaskRuntimeCommand::Stop
    ));
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
        api_provider_registry: Arc::new(EmptyProviderRegistry),
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: model_profiles(),
        }),
        router_mailbox_capacity: 8,
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
        .await
        .expect("send api output");
    let stale_api = events_rx.recv().await.expect("stale api debug");
    assert_debug_contains(stale_api, Some(TaskId("missing".to_owned())), "stale api");

    handle
        .ingress_tx
        .send(RouterIngressMessage::Tool(tool_result("missing")))
        .await
        .expect("send tool output");
    let stale_tool = events_rx.recv().await.expect("stale tool debug");
    assert_debug_contains(stale_tool, Some(TaskId("missing".to_owned())), "stale tool");

    handle
        .ingress_tx
        .send(RouterIngressMessage::Core(CoreOutputEnvelope {
            task_id: TaskId("task-ready".to_owned()),
            message: CoreOutputMessage::RuntimeReady,
        }))
        .await
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
        .await
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
        api_provider_registry: Arc::new(EmptyProviderRegistry),
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: tool_spawner.clone(),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: model_profiles(),
        }),
        router_mailbox_capacity: 8,
    })
    .expect("spawn router");

    handle
        .ingress_tx
        .send(RouterIngressMessage::Core(CoreOutputEnvelope {
            task_id: TaskId("task-1".to_owned()),
            message: CoreOutputMessage::RequestToolExecution(tool_request("task-1")),
        }))
        .await
        .expect("send core tool request");

    let request = tool_spawner.wait_request().await;
    assert_eq!(request.task_id, TaskId("task-1".to_owned()));
    assert_eq!(request.tool_name, ToolName("tool".to_owned()));

    handle
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .await
        .expect("stop router");
    assert_eq!(
        handle.join_handle.await.expect("join router"),
        RouterExitStatus::Stopped
    );
}

#[test]
fn spawn_router_rejects_zero_mailbox_capacity() {
    let db = open_memory_db();
    let (events_tx, _events_rx) = tokio::sync::mpsc::channel(8);
    let result = spawn_router(RouterStartArgs {
        db,
        events_tx,
        api_provider_registry: Arc::new(EmptyProviderRegistry),
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolSpawner),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: model_profiles(),
        }),
        router_mailbox_capacity: 0,
    });
    let Err(error) = result else {
        panic!("expected invalid mailbox capacity");
    };
    assert_eq!(error, SpawnRouterError::InvalidMailboxCapacity);
}

fn open_memory_db() -> DbPool {
    open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
    })
    .expect("open db")
}

fn create_root(db: &DbPool, task_id: &str) {
    let cursor_node_id = create_history_node(
        db,
        NewHistoryNode {
            parent_node_id: None,
            content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                message_role: MessageRole::User,
                message_text: "hello".to_owned(),
            }),
            created_at: UnixTs(1),
        },
    )
    .expect("create message node");
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

fn model_profiles() -> HashMap<ModelProfileKey, ModelProviderProfile> {
    HashMap::from([(
        ModelProfileKey("default".to_owned()),
        ModelProviderProfile {
            provider_name: "provider".to_owned(),
            model_name: "model".to_owned(),
            temperature: None,
            max_output_tokens: None,
        },
    )])
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

struct EmptyProviderRegistry;

impl ModelProviderRegistry for EmptyProviderRegistry {
    fn resolve(&self, _provider_name: &str) -> Option<Arc<dyn ModelProviderAdapter>> {
        None
    }
}

struct NoopToolSpawner;

impl ToolExecutionSpawner for NoopToolSpawner {
    fn spawn_tool_execution(
        &self,
        _request: ToolExecutionRequest,
        _router_tx: selvedge_command_model::RouterIngressSender,
    ) -> Result<tokio::task::JoinHandle<()>, ToolExecutionSpawnError> {
        Ok(tokio::spawn(async {}))
    }
}

#[derive(Default)]
struct CapturingToolSpawner {
    requests: Mutex<Vec<ToolExecutionRequest>>,
}

impl CapturingToolSpawner {
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
        _router_tx: selvedge_command_model::RouterIngressSender,
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
    receivers: Mutex<HashMap<TaskId, tokio::sync::mpsc::Receiver<TaskRuntimeCommand>>>,
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
}

impl TaskRuntimeSpawner for CapturingRuntimeSpawner {
    fn spawn_task_runtime(
        &self,
        args: SpawnTaskRuntimeArgs,
    ) -> Result<SpawnedTaskRuntime, SpawnTaskRuntimeError> {
        let (task_runtime_tx, task_runtime_rx) = tokio::sync::mpsc::channel(8);
        let mut receivers = self
            .receivers
            .lock()
            .map_err(|_| SpawnTaskRuntimeError::TokioSpawnFailed)?;
        receivers.insert(args.task_id.clone(), task_runtime_rx);
        Ok(SpawnedTaskRuntime {
            task_id: args.task_id,
            task_runtime_tx,
        })
    }
}
