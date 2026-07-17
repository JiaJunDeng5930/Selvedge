use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use selvedge_api::ApiExecutorConfig;
use selvedge_command_model::{
    ArchiveTaskOutcome, RouterCommand, RouterCommandEnvelope, RouterIngressMessage,
    SendUserInputOutcome, TaskCommandError, TaskRuntimeCommand, TaskRuntimeControl,
    TaskRuntimeStopResult, ToolExecutionRequest, ToolExecutionResult, ToolExecutionRunId,
};
use selvedge_core::{
    SpawnTaskRuntimeArgs, SpawnTaskRuntimeError, SpawnedTaskRuntime, TaskRuntimeConfig,
    TaskRuntimeSpawnDeps, TaskRuntimeSpawner,
};
use selvedge_db::{
    CreateRootTaskInput, DbError, DbPool, FunctionCallId, HistoryNodeId, ModelProfileKey,
    NewFunctionCallNodeContent, NewFunctionOutputNodeContent, ReadTaskInput, ReasoningEffort,
    TaskId, TaskStatusRow, ToolArgumentValue, ToolCallArgument, ToolName, ToolParameterName,
    UnixTs, append_function_output_and_drain_queue,
    append_model_reply_with_tool_calls_and_move_cursor, append_user_message_and_move_cursor,
    archive_task, create_root_task, read_task, register_global_tool,
};
use selvedge_harness::{
    ARCHIVE_TASK_TOOL_NAME, BASH_TOOL_NAME, FORK_TASK_TOOL_NAME, HarnessToolExecutor,
    READ_TASK_TOOL_NAME, SEND_MESSAGE_TO_TASK_TOOL_NAME, tool_manifest,
};
use selvedge_router::{RouterExitStatus, RouterStartArgs, ToolExecutionSpawner, spawn_router};
use selvedge_test_support::db::{create_message_node, open_memory_db};
use tokio::sync::mpsc;
use tokio::time::timeout;

#[tokio::test]
async fn executor_closes_fork_send_read_and_archive_through_router_and_sqlite() {
    let db = open_memory_db();
    for tool in tool_manifest().tools {
        register_global_tool(&db, tool).expect("register harness tool");
    }
    let parent_task_id = TaskId("parent".to_owned());
    let root_node_id = create_message_node(
        &db,
        None,
        selvedge_db::MessageRole::User,
        "parent prompt",
        UnixTs(1),
    );
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: parent_task_id.clone(),
            cursor_node_id: root_node_id,
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(1),
        },
    )
    .expect("create parent task");

    let (started_tx, mut started_rx) = mpsc::unbounded_channel();
    let (tool_result_tx, mut tool_result_rx) = mpsc::unbounded_channel();
    let spawner = Arc::new(CommittingRuntimeSpawner {
        started_tx,
        tool_result_tx,
    });
    let (events_tx, _events_rx) = mpsc::channel(32);
    let executor = Arc::new(HarnessToolExecutor::new(db.clone()));
    let router = spawn_router(RouterStartArgs {
        db: db.clone(),
        events_tx,
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: executor.clone(),
        core_spawn_deps: TaskRuntimeSpawnDeps::with_spawner(
            TaskRuntimeConfig {
                mailbox_capacity: 8,
                model_profiles: HashMap::new(),
            },
            spawner,
        ),
    })
    .expect("spawn router");

    router
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommandEnvelope {
            client_id: None,
            client_command_id: None,
            command: RouterCommand::EnsureTaskRuntime {
                task_id: parent_task_id.clone(),
            },
        }))
        .expect("ensure parent runtime");
    assert_eq!(
        recv_timeout(&mut started_rx).await,
        parent_task_id,
        "parent runtime must be registered and started"
    );

    let fork_call_node_id = append_tool_call(
        &db,
        &parent_task_id,
        "fork-call",
        FORK_TASK_TOOL_NAME,
        vec![string_argument("prompt", "child prompt")],
    );
    let fork_request = tool_request(
        &parent_task_id,
        "run-fork",
        fork_call_node_id,
        "fork-call",
        FORK_TASK_TOOL_NAME,
        vec![string_argument("prompt", "child prompt")],
    );
    let fork_result = execute_and_receive(
        executor.as_ref(),
        fork_request.clone(),
        router.ingress_tx.downgrade(),
        &mut tool_result_rx,
    )
    .await;
    assert_eq!(
        result_correlation(&fork_result),
        result_correlation_from_request(&fork_request)
    );
    assert!(!fork_result.is_error);
    let fork_json: serde_json::Value =
        serde_json::from_str(&fork_result.output_text).expect("decode fork output");
    let child_task_id = TaskId(
        fork_json["task_id"]
            .as_str()
            .expect("fork output child id")
            .to_owned(),
    );
    assert_eq!(
        recv_timeout(&mut started_rx).await,
        child_task_id,
        "child runtime must start before fork reports success"
    );
    let child = read_task(
        &db,
        ReadTaskInput {
            task_id: child_task_id.clone(),
            after_node_id: None,
            limit: 100,
        },
    )
    .expect("read durable child");
    assert_eq!(child.parent_task_id, Some(parent_task_id.clone()));
    assert!(child.history_nodes.iter().any(|node| {
        matches!(
            node,
            selvedge_db::HistoryNode::Message { message_text, .. }
                if message_text == "child prompt"
        )
    }));

    let send_call_node_id = append_tool_call(
        &db,
        &parent_task_id,
        "send-call",
        SEND_MESSAGE_TO_TASK_TOOL_NAME,
        vec![
            string_argument("task_id", &child_task_id.0),
            string_argument("message", "continue"),
        ],
    );
    let send_result = execute_and_receive(
        executor.as_ref(),
        tool_request(
            &parent_task_id,
            "run-send",
            send_call_node_id,
            "send-call",
            SEND_MESSAGE_TO_TASK_TOOL_NAME,
            vec![
                string_argument("task_id", &child_task_id.0),
                string_argument("message", "continue"),
            ],
        ),
        router.ingress_tx.downgrade(),
        &mut tool_result_rx,
    )
    .await;
    assert!(
        !send_result.is_error,
        "send failed: {}",
        send_result.output_text
    );
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&send_result.output_text)
            .expect("decode send output")["disposition"],
        "committed"
    );

    let read_call_node_id = append_tool_call(
        &db,
        &parent_task_id,
        "read-call",
        READ_TASK_TOOL_NAME,
        vec![string_argument("task_id", &child_task_id.0)],
    );
    let read_result = execute_and_receive(
        executor.as_ref(),
        tool_request(
            &parent_task_id,
            "run-read",
            read_call_node_id,
            "read-call",
            READ_TASK_TOOL_NAME,
            vec![string_argument("task_id", &child_task_id.0)],
        ),
        router.ingress_tx.downgrade(),
        &mut tool_result_rx,
    )
    .await;
    assert!(!read_result.is_error);
    let read_json: serde_json::Value =
        serde_json::from_str(&read_result.output_text).expect("decode read output");
    assert_eq!(read_json["status"], "active");
    assert!(
        read_json["history"]["nodes"]
            .as_array()
            .expect("history array")
            .iter()
            .any(|node| node["text"] == "continue")
    );

    let archive_call_node_id = append_tool_call(
        &db,
        &parent_task_id,
        "archive-call",
        ARCHIVE_TASK_TOOL_NAME,
        vec![string_argument("task_id", &child_task_id.0)],
    );
    let archive_result = execute_and_receive(
        executor.as_ref(),
        tool_request(
            &parent_task_id,
            "run-archive",
            archive_call_node_id,
            "archive-call",
            ARCHIVE_TASK_TOOL_NAME,
            vec![string_argument("task_id", &child_task_id.0)],
        ),
        router.ingress_tx.downgrade(),
        &mut tool_result_rx,
    )
    .await;
    assert!(!archive_result.is_error);
    assert_eq!(
        read_task(
            &db,
            ReadTaskInput {
                task_id: child_task_id,
                after_node_id: None,
                limit: 100,
            },
        )
        .expect("read archived child")
        .task_status,
        TaskStatusRow::Archived
    );

    let bash_call_node_id = append_tool_call(
        &db,
        &parent_task_id,
        "bash-call",
        BASH_TOOL_NAME,
        vec![string_argument("command", "printf integrated")],
    );
    let bash_request = tool_request(
        &parent_task_id,
        "run-bash",
        bash_call_node_id,
        "bash-call",
        BASH_TOOL_NAME,
        vec![string_argument("command", "printf integrated")],
    );
    let bash_result = execute_and_receive(
        executor.as_ref(),
        bash_request.clone(),
        router.ingress_tx.downgrade(),
        &mut tool_result_rx,
    )
    .await;
    assert_eq!(
        result_correlation(&bash_result),
        result_correlation_from_request(&bash_request)
    );
    assert!(!bash_result.is_error);
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&bash_result.output_text)
            .expect("decode bash output")["stdout"],
        "integrated"
    );

    let parent = read_task(
        &db,
        ReadTaskInput {
            task_id: parent_task_id,
            after_node_id: None,
            limit: 100,
        },
    )
    .expect("read parent results");
    assert_eq!(
        parent
            .history_nodes
            .iter()
            .filter(|node| matches!(node, selvedge_db::HistoryNode::FunctionOutput { .. }))
            .count(),
        5
    );

    router
        .ingress_tx
        .send(RouterIngressMessage::StopRouter)
        .expect("stop router");
    assert_eq!(
        timeout(Duration::from_secs(1), router.join_handle)
            .await
            .expect("router stop timeout")
            .expect("router join"),
        RouterExitStatus::Stopped
    );
}

#[derive(Clone)]
struct CommittingRuntimeSpawner {
    started_tx: mpsc::UnboundedSender<TaskId>,
    tool_result_tx: mpsc::UnboundedSender<ToolExecutionResult>,
}

impl TaskRuntimeSpawner for CommittingRuntimeSpawner {
    fn spawn_task_runtime(
        &self,
        args: SpawnTaskRuntimeArgs,
    ) -> Result<SpawnedTaskRuntime, SpawnTaskRuntimeError> {
        let (task_runtime_tx, mut task_runtime_rx) =
            mpsc::channel(args.config.mailbox_capacity.max(1));
        let control = TaskRuntimeControl::new();
        let actor_control = control.clone();
        let task_id = args.task_id.clone();
        let actor_task_id = task_id.clone();
        let db = args.db;
        let started_tx = self.started_tx.clone();
        let tool_result_tx = self.tool_result_tx.clone();
        tokio::spawn(async move {
            loop {
                tokio::select! {
                    _ = actor_control.wait_for_control_change() => {
                        if actor_control.is_stopping() {
                            break;
                        }
                    }
                    command = task_runtime_rx.recv() => {
                        let Some(command) = command else {
                            break;
                        };
                        match command {
                            TaskRuntimeCommand::Start => {
                                let _ = started_tx.send(actor_task_id.clone());
                            }
                            TaskRuntimeCommand::UserInput { message_text, responder } => {
                                let db = db.clone();
                                let task_id = actor_task_id.clone();
                                let now = now();
                                let result = tokio::task::spawn_blocking(move || {
                                    append_user_message_and_move_cursor(
                                        &db,
                                        &task_id,
                                        message_text,
                                        now,
                                    )
                                })
                                .await;
                                responder.settle(match result {
                                    Ok(Ok(node_id)) => Ok(SendUserInputOutcome::Committed { node_id }),
                                    Ok(Err(DbError::TaskNotActive)) => Err(TaskCommandError::TaskArchived),
                                    Ok(Err(DbError::NotFound)) => Err(TaskCommandError::TaskMissing),
                                    Ok(Err(_)) | Err(_) => Err(TaskCommandError::PersistenceFailed),
                                });
                            }
                            TaskRuntimeCommand::Archive { responder } => {
                                let db = db.clone();
                                let task_id = actor_task_id.clone();
                                let now = now();
                                let result = tokio::task::spawn_blocking(move || {
                                    archive_task(&db, &task_id, now)
                                })
                                .await;
                                responder.settle(match result {
                                    Ok(Ok(())) => Ok(ArchiveTaskOutcome::Archived),
                                    Ok(Err(DbError::TaskNotActive)) => Err(TaskCommandError::TaskArchived),
                                    Ok(Err(DbError::NotFound)) => Err(TaskCommandError::TaskMissing),
                                    Ok(Err(_)) | Err(_) => Err(TaskCommandError::PersistenceFailed),
                                });
                            }
                            TaskRuntimeCommand::ToolResult(result) => {
                                let db = db.clone();
                                let task_id = actor_task_id.clone();
                                let persisted_result = result.clone();
                                let persisted = tokio::task::spawn_blocking(move || {
                                    append_function_output_and_drain_queue(
                                        &db,
                                        &task_id,
                                        NewFunctionOutputNodeContent {
                                            function_call_node_id: persisted_result.function_call_node_id,
                                            function_call_id: persisted_result.function_call_id,
                                            tool_name: persisted_result.tool_name,
                                            output_text: persisted_result.output_text,
                                            is_error: persisted_result.is_error,
                                        },
                                        UnixTs(40),
                                    )
                                })
                                .await;
                                assert!(matches!(persisted, Ok(Ok(_))));
                                let _ = tool_result_tx.send(result);
                            }
                            TaskRuntimeCommand::ApiModelReply(_) => {}
                        }
                    }
                }
            }
            actor_control.finish_stop(TaskRuntimeStopResult).await;
        });
        Ok(SpawnedTaskRuntime {
            task_id,
            task_runtime_tx,
            task_runtime_control: control,
        })
    }
}

async fn execute_and_receive(
    executor: &HarnessToolExecutor,
    request: ToolExecutionRequest,
    router_tx: selvedge_command_model::RouterIngressWeakSender,
    result_rx: &mut mpsc::UnboundedReceiver<ToolExecutionResult>,
) -> ToolExecutionResult {
    executor
        .spawn_tool_execution(request, router_tx)
        .expect("spawn execution")
        .await
        .expect("execution supervisor");
    recv_timeout(result_rx).await
}

async fn recv_timeout<T>(receiver: &mut mpsc::UnboundedReceiver<T>) -> T {
    timeout(Duration::from_secs(1), receiver.recv())
        .await
        .expect("receive timeout")
        .expect("sender open")
}

fn append_tool_call(
    db: &DbPool,
    task_id: &TaskId,
    function_call_id: &str,
    tool_name: &str,
    arguments: Vec<ToolCallArgument>,
) -> HistoryNodeId {
    append_model_reply_with_tool_calls_and_move_cursor(
        db,
        task_id,
        None,
        vec![NewFunctionCallNodeContent {
            function_call_id: FunctionCallId(function_call_id.to_owned()),
            tool_name: ToolName(tool_name.to_owned()),
            arguments,
        }],
        UnixTs(10),
    )
    .expect("append tool call")[0]
}

fn tool_request(
    task_id: &TaskId,
    run_id: &str,
    function_call_node_id: HistoryNodeId,
    function_call_id: &str,
    tool_name: &str,
    arguments: Vec<ToolCallArgument>,
) -> ToolExecutionRequest {
    ToolExecutionRequest {
        task_id: task_id.clone(),
        tool_execution_run_id: ToolExecutionRunId(run_id.to_owned()),
        function_call_node_id,
        function_call_id: FunctionCallId(function_call_id.to_owned()),
        tool_name: ToolName(tool_name.to_owned()),
        arguments,
    }
}

fn string_argument(name: &str, value: &str) -> ToolCallArgument {
    ToolCallArgument {
        name: ToolParameterName(name.to_owned()),
        value: ToolArgumentValue::String(value.to_owned()),
    }
}

fn result_correlation(
    result: &ToolExecutionResult,
) -> (
    TaskId,
    ToolExecutionRunId,
    HistoryNodeId,
    FunctionCallId,
    ToolName,
) {
    (
        result.task_id.clone(),
        result.tool_execution_run_id.clone(),
        result.function_call_node_id,
        result.function_call_id.clone(),
        result.tool_name.clone(),
    )
}

fn result_correlation_from_request(
    request: &ToolExecutionRequest,
) -> (
    TaskId,
    ToolExecutionRunId,
    HistoryNodeId,
    FunctionCallId,
    ToolName,
) {
    (
        request.task_id.clone(),
        request.tool_execution_run_id.clone(),
        request.function_call_node_id,
        request.function_call_id.clone(),
        request.tool_name.clone(),
    )
}

fn now() -> UnixTs {
    UnixTs(
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |duration| duration.as_secs() as i64),
    )
}
