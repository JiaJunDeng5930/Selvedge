use std::collections::HashMap;
use std::time::Duration;

use selvedge_command_model::{
    ApiCallCorrelation, ApiOutputEnvelope, CoreOutputMessage, DomainEvent,
    ModelCallDispatchRequest, ModelCallError, ModelCallErrorKind, ModelRunId, RouterIngressMessage,
    RouterIngressSender, SendUserInputOutcome, TaskCommandError, TaskRuntimeCommand,
    TaskRuntimeExitReason, ToolExecutionBranch, ToolExecutionBranchTarget, ToolExecutionResult,
    send_user_input_response_channel,
};
use selvedge_core::{SpawnTaskRuntimeArgs, TaskRuntimeConfig, spawn_task_runtime};
use selvedge_db::{
    CommitToolResultBranchesInput, CreateRootTaskInput, FunctionCallId, NewFunctionCallNodeContent,
    NewHistoryNode, NewHistoryNodeContent, NewMessageNodeContent, ReasoningEffort, TaskId,
    TaskToolSpec, ToolExecutionSource, ToolName, ToolRecoveryPolicy, ToolResultBranch,
    ToolResultBranchTarget, UnixTs, append_assistant_message_and_drain_queue,
    append_model_reply_with_tool_calls_and_move_cursor, append_user_message_and_move_cursor,
    commit_tool_result_branches, create_history_node, create_root_task, load_runtime_task,
    queue_user_input, read_conversation_for_task, read_open_function_calls_for_task,
    read_task_tool_state, reconcile_task_tool_availability, transition_task_status,
};
use selvedge_domain_model::{
    CallableTools, FUNCTION_CALL_CONTENT_TYPE, FUNCTION_OUTPUT_CONTENT_TYPE, JsonObject,
    ModelFinishReason, ModelReply, TaskLifecycleEvent, TaskStatus, ToolCallProposal, ToolSpec,
};
use selvedge_test_support::db::{
    create_root_task_with_user_message, default_model_profiles, open_memory_db,
    open_memory_db_with_max_task_descendants,
};
use serde_json::{Value, json};

#[tokio::test]
async fn task_runtime_starts_and_requests_model_call_from_system_cursor() {
    let db = open_memory_db();
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            cursor_node_id: create_history_node(
                &db,
                NewHistoryNode {
                    parent_node_id: None,
                    content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                        message_role: selvedge_db::MessageRole::System,
                        message_text: "system".to_owned(),
                    }),
                    created_at: UnixTs(1),
                },
            )
            .expect("create cursor node"),
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: Vec::new(),
            now: UnixTs(1),
        },
    )
    .expect("create task");

    let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db,
        router_tx: router_tx.downgrade(),
        config: TaskRuntimeConfig {
            model_profiles: model_profiles(),
        },
    })
    .expect("spawn runtime");

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::Start)
        .expect("send start");
    let ready = router_rx.recv().await.expect("ready");
    assert!(matches!(
        ready,
        RouterIngressMessage::Core(envelope)
            if matches!(envelope.message, CoreOutputMessage::RuntimeReady)
    ));

    let request = router_rx.recv().await.expect("model request");
    assert!(matches!(
        request,
        RouterIngressMessage::Core(envelope)
            if matches!(envelope.message, CoreOutputMessage::RequestModelCall(_))
    ));
}

#[tokio::test]
async fn task_runtime_start_requests_model_from_user_cursor_without_draining_queue() {
    let db = open_memory_db();
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            cursor_node_id: create_history_node(
                &db,
                NewHistoryNode {
                    parent_node_id: None,
                    content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                        message_role: selvedge_db::MessageRole::System,
                        message_text: "system".to_owned(),
                    }),
                    created_at: UnixTs(1),
                },
            )
            .expect("create cursor node"),
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: Vec::new(),
            now: UnixTs(1),
        },
    )
    .expect("create task");
    append_user_message_and_move_cursor(
        &db,
        &TaskId("task-1".to_owned()),
        "current".to_owned(),
        UnixTs(2),
    )
    .expect("append user cursor");
    queue_user_input(
        &db,
        &TaskId("task-1".to_owned()),
        "queued".to_owned(),
        UnixTs(3),
    )
    .expect("queue input");

    let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db: db.clone(),
        router_tx: router_tx.downgrade(),
        config: TaskRuntimeConfig {
            model_profiles: model_profiles(),
        },
    })
    .expect("spawn runtime");

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::Start)
        .expect("send start");
    let _ready = router_rx.recv().await.expect("ready");
    let request = tokio::time::timeout(
        Duration::from_millis(50),
        recv_model_request(&mut router_rx),
    )
    .await
    .expect("model request from user cursor");

    let last_text = request
        .conversation
        .messages
        .last()
        .and_then(|message| message.content.as_str());
    assert_eq!(last_text, Some("current"));
    assert_eq!(
        load_runtime_task(&db, &TaskId("task-1".to_owned()))
            .expect("load task")
            .queued_inputs
            .len(),
        1
    );
}

#[tokio::test]
async fn task_runtime_start_promotes_queue_before_awaiting_user_input() {
    let db = open_memory_db();
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            cursor_node_id: create_history_node(
                &db,
                NewHistoryNode {
                    parent_node_id: None,
                    content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                        message_role: selvedge_db::MessageRole::Assistant,
                        message_text: "assistant".to_owned(),
                    }),
                    created_at: UnixTs(1),
                },
            )
            .expect("create cursor node"),
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: Vec::new(),
            now: UnixTs(1),
        },
    )
    .expect("create task");
    queue_user_input(
        &db,
        &TaskId("task-1".to_owned()),
        "queued".to_owned(),
        UnixTs(2),
    )
    .expect("queue input");

    let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db: db.clone(),
        router_tx: router_tx.downgrade(),
        config: TaskRuntimeConfig {
            model_profiles: model_profiles(),
        },
    })
    .expect("spawn runtime");

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::Start)
        .expect("send start");
    let _ready = router_rx.recv().await.expect("ready");
    let request = recv_model_request(&mut router_rx).await;
    let last_text = request
        .conversation
        .messages
        .last()
        .and_then(|message| message.content.as_str());

    assert_eq!(last_text, Some("queued"));
    assert!(
        load_runtime_task(&db, &TaskId("task-1".to_owned()))
            .expect("load task")
            .queued_inputs
            .is_empty()
    );
}

#[tokio::test]
async fn task_runtime_start_dispatches_tool_from_function_call_cursor() {
    let db = open_memory_db();
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            cursor_node_id: create_history_node(
                &db,
                NewHistoryNode {
                    parent_node_id: None,
                    content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                        message_role: selvedge_db::MessageRole::System,
                        message_text: "system".to_owned(),
                    }),
                    created_at: UnixTs(1),
                },
            )
            .expect("create cursor node"),
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: vec![task_tool(tool_spec("search"))],
            now: UnixTs(1),
        },
    )
    .expect("create task");
    append_model_reply_with_tool_calls_and_move_cursor(
        &db,
        &TaskId("task-1".to_owned()),
        None,
        vec![NewFunctionCallNodeContent {
            function_call_id: FunctionCallId("call-1".to_owned()),
            tool_name: ToolName("search".to_owned()),
            arguments: JsonObject::new(),
        }],
        UnixTs(2),
    )
    .expect("append function call");

    let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db,
        router_tx: router_tx.downgrade(),
        config: TaskRuntimeConfig {
            model_profiles: model_profiles(),
        },
    })
    .expect("spawn runtime");

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::Start)
        .expect("send start");
    let _ready = router_rx.recv().await.expect("ready");
    let request =
        tokio::time::timeout(Duration::from_millis(50), recv_tool_request(&mut router_rx))
            .await
            .expect("tool request");

    assert_eq!(request.function_call_id.0, "call-1");
    assert_eq!(request.tool_name.0, "search");
}

#[tokio::test]
async fn task_runtime_start_reconstructs_open_batched_tool_calls_from_history() {
    let db = open_memory_db();
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            cursor_node_id: create_history_node(
                &db,
                NewHistoryNode {
                    parent_node_id: None,
                    content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                        message_role: selvedge_db::MessageRole::System,
                        message_text: "system".to_owned(),
                    }),
                    created_at: UnixTs(1),
                },
            )
            .expect("create cursor node"),
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: vec![task_tool(tool_spec("search"))],
            now: UnixTs(1),
        },
    )
    .expect("create task");
    append_model_reply_with_tool_calls_and_move_cursor(
        &db,
        &TaskId("task-1".to_owned()),
        None,
        vec![
            NewFunctionCallNodeContent {
                function_call_id: FunctionCallId("call-1".to_owned()),
                tool_name: ToolName("search".to_owned()),
                arguments: JsonObject::new(),
            },
            NewFunctionCallNodeContent {
                function_call_id: FunctionCallId("call-2".to_owned()),
                tool_name: ToolName("search".to_owned()),
                arguments: JsonObject::new(),
            },
        ],
        UnixTs(2),
    )
    .expect("append batched calls");

    let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db,
        router_tx: router_tx.downgrade(),
        config: TaskRuntimeConfig {
            model_profiles: model_profiles(),
        },
    })
    .expect("spawn runtime");

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::Start)
        .expect("send start");
    let _ready = router_rx.recv().await.expect("ready");
    let first_tool_request = recv_tool_request(&mut router_rx).await;

    assert_eq!(first_tool_request.function_call_id.0, "call-1");
}

#[tokio::test]
async fn task_runtime_resolves_model_profile_key_into_provider_and_model() {
    let (runtime, mut router_rx, _router_tx) = spawn_runtime_with_task(vec![]).await;

    let request = start_and_recv_model_request(&runtime, &mut router_rx).await;

    assert_eq!(request.provider.provider_name, "provider");
    assert_eq!(request.provider.model_name, "model");
}

#[tokio::test]
async fn task_runtime_dispatches_all_tool_calls_before_next_model_call() {
    let (runtime, mut router_rx, _router_tx) =
        spawn_runtime_with_task(vec![tool_spec("search")]).await;
    let correlation = start_and_request_model(&runtime, &mut router_rx).await;

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ApiModelReply(
            ApiOutputEnvelope::Success {
                correlation,
                reply: ModelReply {
                    content: None,
                    tool_calls: vec![
                        ToolCallProposal {
                            call_id: "call-1".to_owned(),
                            tool_name: "search".to_owned(),
                            arguments: JsonObject::new(),
                        },
                        ToolCallProposal {
                            call_id: "call-2".to_owned(),
                            tool_name: "search".to_owned(),
                            arguments: JsonObject::new(),
                        },
                    ],
                    usage: None,
                    finish_reason: ModelFinishReason::ToolCalls,
                },
            },
        ))
        .expect("send model reply");

    let first_tool_request = recv_tool_request(&mut router_rx).await;
    assert_eq!(first_tool_request.function_call_id.0, "call-1");

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ToolResult(ToolExecutionResult {
            task_id: TaskId("task-1".to_owned()),
            tool_execution_run_id: first_tool_request.tool_execution_run_id,
            function_call_node_id: first_tool_request.function_call_node_id,
            function_call_id: first_tool_request.function_call_id,
            tool_name: first_tool_request.tool_name,
            branches: calling_tool_result_branches(json!("first"), false),
        }))
        .expect("send first tool result");

    let second_tool_request = recv_tool_request(&mut router_rx).await;
    assert_eq!(second_tool_request.function_call_id.0, "call-2");
}

#[tokio::test]
async fn task_runtime_ensures_child_runtimes_after_branch_commit() {
    let (runtime, mut router_rx, _router_tx) =
        spawn_runtime_with_task(vec![tool_spec("fork_task")]).await;
    let correlation = start_and_request_model(&runtime, &mut router_rx).await;
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ApiModelReply(
            ApiOutputEnvelope::Success {
                correlation,
                reply: ModelReply {
                    content: None,
                    tool_calls: vec![ToolCallProposal {
                        call_id: "fork-call".to_owned(),
                        tool_name: "fork_task".to_owned(),
                        arguments: JsonObject::new(),
                    }],
                    usage: None,
                    finish_reason: ModelFinishReason::ToolCalls,
                },
            },
        ))
        .expect("send fork call");
    let request = recv_tool_request(&mut router_rx).await;
    let child_task_id = TaskId("child-1".to_owned());

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ToolResult(ToolExecutionResult {
            task_id: TaskId("task-1".to_owned()),
            tool_execution_run_id: request.tool_execution_run_id,
            function_call_node_id: request.function_call_node_id,
            function_call_id: request.function_call_id,
            tool_name: request.tool_name,
            branches: vec![
                ToolExecutionBranch {
                    target: ToolExecutionBranchTarget::CallingTask,
                    output: json!(0),
                    is_error: false,
                    messages: Vec::new(),
                },
                ToolExecutionBranch {
                    target: ToolExecutionBranchTarget::NewChildTask {
                        task_id: child_task_id.clone(),
                    },
                    output: json!(1),
                    is_error: false,
                    messages: vec!["child work".to_owned()],
                },
            ],
        }))
        .expect("send fork result");

    assert!(matches!(
        router_rx.recv().await.expect("ensure child runtimes"),
        RouterIngressMessage::Core(envelope)
            if matches!(
                &envelope.message,
                CoreOutputMessage::EnsureTaskRuntimes { task_ids }
                    if task_ids.as_slice() == std::slice::from_ref(&child_task_id)
            )
    ));
    let _next_model_request = recv_model_request(&mut router_rx).await;
}

#[tokio::test]
async fn task_runtime_commits_descendant_limit_as_a_model_visible_tool_error() {
    let (runtime, mut router_rx, _router_tx) =
        spawn_runtime_with_task_and_descendant_limit(vec![tool_spec("fork_task")], 1).await;
    let correlation = start_and_request_model(&runtime, &mut router_rx).await;
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ApiModelReply(
            ApiOutputEnvelope::Success {
                correlation,
                reply: ModelReply {
                    content: None,
                    tool_calls: vec![ToolCallProposal {
                        call_id: "fork-call".to_owned(),
                        tool_name: "fork_task".to_owned(),
                        arguments: JsonObject::new(),
                    }],
                    usage: None,
                    finish_reason: ModelFinishReason::ToolCalls,
                },
            },
        ))
        .expect("send fork call");
    let request = recv_tool_request(&mut router_rx).await;

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ToolResult(ToolExecutionResult {
            task_id: TaskId("task-1".to_owned()),
            tool_execution_run_id: request.tool_execution_run_id,
            function_call_node_id: request.function_call_node_id,
            function_call_id: request.function_call_id,
            tool_name: request.tool_name,
            branches: vec![
                ToolExecutionBranch {
                    target: ToolExecutionBranchTarget::CallingTask,
                    output: json!(0),
                    is_error: false,
                    messages: Vec::new(),
                },
                ToolExecutionBranch {
                    target: ToolExecutionBranchTarget::NewChildTask {
                        task_id: TaskId("child-1".to_owned()),
                    },
                    output: json!(1),
                    is_error: false,
                    messages: Vec::new(),
                },
                ToolExecutionBranch {
                    target: ToolExecutionBranchTarget::NewChildTask {
                        task_id: TaskId("child-2".to_owned()),
                    },
                    output: json!(2),
                    is_error: false,
                    messages: Vec::new(),
                },
            ],
        }))
        .expect("send oversized fork result");

    let next_model_request = recv_model_request(&mut router_rx).await;
    let output = next_model_request
        .conversation
        .messages
        .last()
        .expect("tool output");
    assert_eq!(output.function_output_is_error(), Some(true));
    assert_eq!(
        output.function_output_value().expect("output")["error"]["code"],
        "task_descendant_limit_exceeded"
    );
}

#[tokio::test]
async fn task_runtime_exits_after_archived_status_notification() {
    let db = open_memory_db();
    create_root_task_with_user_message(&db, "task-1", "hello", UnixTs(1));
    transition_task_status(
        &db,
        &TaskId("task-1".to_owned()),
        TaskLifecycleEvent::Freeze,
        UnixTs(2),
    )
    .expect("freeze task");
    let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db: db.clone(),
        router_tx: router_tx.downgrade(),
        config: TaskRuntimeConfig {
            model_profiles: model_profiles(),
        },
    })
    .expect("spawn runtime");
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::Start)
        .expect("send start");
    assert!(matches!(
        router_rx.recv().await,
        Some(RouterIngressMessage::Core(envelope))
            if matches!(envelope.message, CoreOutputMessage::RuntimeReady)
    ));

    let (responder, response) = send_user_input_response_channel();
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::UserInput {
            message_text: "pending while frozen".to_owned(),
            responder,
        })
        .expect("send frozen input");

    transition_task_status(
        &db,
        &TaskId("task-1".to_owned()),
        TaskLifecycleEvent::Archive,
        UnixTs(3),
    )
    .expect("archive task");
    runtime.task_runtime_control.notify_status_changed();

    let message = router_rx.recv().await.expect("runtime exit");
    assert!(matches!(
        message,
        RouterIngressMessage::RuntimeExit(notice)
            if matches!(notice.reason, TaskRuntimeExitReason::Archived)
    ));
    assert_eq!(
        response.await.expect("archived input response"),
        Err(TaskCommandError::TaskArchived)
    );

    tokio::time::timeout(
        Duration::from_millis(50),
        runtime.task_runtime_control.wait_for_shutdown(),
    )
    .await
    .expect("stop completed");
}

#[tokio::test]
async fn model_call_not_started_during_freeze_resumes_after_unfreeze() {
    let db = open_memory_db();
    create_root_task_with_user_message(&db, "task-1", "current", UnixTs(1));
    let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db: db.clone(),
        router_tx: router_tx.downgrade(),
        config: TaskRuntimeConfig {
            model_profiles: model_profiles(),
        },
    })
    .expect("spawn runtime");
    let first_correlation = start_and_request_model(&runtime, &mut router_rx).await;

    transition_task_status(
        &db,
        &TaskId("task-1".to_owned()),
        TaskLifecycleEvent::Freeze,
        UnixTs(2),
    )
    .expect("freeze task");
    runtime.task_runtime_control.notify_status_changed();
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ModelCallNotStarted {
            correlation: first_correlation.clone(),
        })
        .expect("return undispatched model call");
    assert!(
        tokio::time::timeout(Duration::from_millis(25), router_rx.recv())
            .await
            .is_err()
    );

    transition_task_status(
        &db,
        &TaskId("task-1".to_owned()),
        TaskLifecycleEvent::Unfreeze,
        UnixTs(3),
    )
    .expect("unfreeze task");
    runtime.task_runtime_control.notify_status_changed();

    let resumed = recv_model_request(&mut router_rx).await;
    assert_ne!(
        resumed.correlation.model_run_id,
        first_correlation.model_run_id
    );
    assert_eq!(
        resumed
            .conversation
            .messages
            .last()
            .and_then(|message| message.content.as_str()),
        Some("current")
    );
}

#[tokio::test]
async fn frozen_runtime_leaves_mailbox_untouched_until_unfreeze() {
    let db = open_memory_db();
    create_root_task_with_user_message(&db, "task-1", "current", UnixTs(1));
    transition_task_status(
        &db,
        &TaskId("task-1".to_owned()),
        TaskLifecycleEvent::Freeze,
        UnixTs(2),
    )
    .expect("freeze task");
    let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db: db.clone(),
        router_tx: router_tx.downgrade(),
        config: TaskRuntimeConfig {
            model_profiles: model_profiles(),
        },
    })
    .expect("spawn runtime");
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::Start)
        .expect("send start");
    assert!(matches!(
        router_rx.recv().await,
        Some(RouterIngressMessage::Core(envelope))
            if matches!(envelope.message, CoreOutputMessage::RuntimeReady)
    ));

    let (responder, mut response) = send_user_input_response_channel();
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::UserInput {
            message_text: "queued in mailbox".to_owned(),
            responder,
        })
        .expect("send input");
    assert!(
        tokio::time::timeout(Duration::from_millis(25), &mut response)
            .await
            .is_err()
    );
    assert!(
        tokio::time::timeout(Duration::from_millis(25), router_rx.recv())
            .await
            .is_err()
    );

    transition_task_status(
        &db,
        &TaskId("task-1".to_owned()),
        TaskLifecycleEvent::Unfreeze,
        UnixTs(3),
    )
    .expect("unfreeze task");
    runtime.task_runtime_control.notify_status_changed();

    let request = recv_model_request(&mut router_rx).await;
    assert_eq!(
        request
            .conversation
            .messages
            .last()
            .and_then(|message| message.content.as_str()),
        Some("current")
    );
    assert_eq!(
        response.await.expect("input response after unfreeze"),
        Ok(SendUserInputOutcome::Queued)
    );
}

#[tokio::test]
async fn stopped_runtime_commits_tool_result_without_calling_model_until_user_input() {
    let db = open_memory_db();
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            cursor_node_id: create_history_node(
                &db,
                NewHistoryNode {
                    parent_node_id: None,
                    content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                        message_role: selvedge_db::MessageRole::System,
                        message_text: "system".to_owned(),
                    }),
                    created_at: UnixTs(1),
                },
            )
            .expect("create cursor node"),
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: vec![task_tool(tool_spec("search"))],
            now: UnixTs(1),
        },
    )
    .expect("create task");
    let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db: db.clone(),
        router_tx: router_tx.downgrade(),
        config: TaskRuntimeConfig {
            model_profiles: model_profiles(),
        },
    })
    .expect("spawn runtime");
    let correlation = start_and_request_model(&runtime, &mut router_rx).await;
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ApiModelReply(
            ApiOutputEnvelope::Success {
                correlation,
                reply: ModelReply {
                    content: None,
                    tool_calls: vec![ToolCallProposal {
                        call_id: "call-1".to_owned(),
                        tool_name: "search".to_owned(),
                        arguments: JsonObject::new(),
                    }],
                    usage: None,
                    finish_reason: ModelFinishReason::ToolCalls,
                },
            },
        ))
        .expect("send model reply");
    let tool_request = recv_tool_request(&mut router_rx).await;

    transition_task_status(
        &db,
        &TaskId("task-1".to_owned()),
        TaskLifecycleEvent::Stop,
        UnixTs(2),
    )
    .expect("stop task");
    runtime.task_runtime_control.notify_status_changed();
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ToolResult(ToolExecutionResult {
            task_id: TaskId("task-1".to_owned()),
            tool_execution_run_id: tool_request.tool_execution_run_id,
            function_call_node_id: tool_request.function_call_node_id,
            function_call_id: tool_request.function_call_id,
            tool_name: tool_request.tool_name,
            branches: calling_tool_result_branches(json!("done"), false),
        }))
        .expect("send tool result");
    tokio::time::timeout(Duration::from_millis(50), async {
        loop {
            if read_open_function_calls_for_task(&db, &TaskId("task-1".to_owned()))
                .expect("read open calls")
                .is_empty()
            {
                break;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .expect("tool result committed");
    assert!(
        tokio::time::timeout(Duration::from_millis(25), router_rx.recv())
            .await
            .is_err()
    );

    let (responder, response) = send_user_input_response_channel();
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::UserInput {
            message_text: "continue".to_owned(),
            responder,
        })
        .expect("send user input");
    assert!(matches!(
        response.await.expect("user input response"),
        Ok(SendUserInputOutcome::Committed { .. })
    ));
    assert_eq!(
        load_runtime_task(&db, &TaskId("task-1".to_owned()))
            .expect("load active task")
            .task
            .task_status,
        TaskStatus::Active
    );
    let request = recv_model_request(&mut router_rx).await;
    assert_eq!(
        tool_transcript_events(&request),
        vec!["call:call-1", "output:call-1"]
    );
}

#[tokio::test]
async fn stopped_runtime_promotes_existing_queue_before_new_input() {
    let db = open_memory_db();
    create_root_task_with_user_message(&db, "task-1", "current", UnixTs(1));
    queue_user_input(
        &db,
        &TaskId("task-1".to_owned()),
        "old queued".to_owned(),
        UnixTs(2),
    )
    .expect("queue old input");
    transition_task_status(
        &db,
        &TaskId("task-1".to_owned()),
        TaskLifecycleEvent::Stop,
        UnixTs(3),
    )
    .expect("stop task");

    let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db: db.clone(),
        router_tx: router_tx.downgrade(),
        config: TaskRuntimeConfig {
            model_profiles: model_profiles(),
        },
    })
    .expect("spawn runtime");
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::Start)
        .expect("send start");
    assert!(matches!(
        router_rx.recv().await,
        Some(RouterIngressMessage::Core(envelope))
            if matches!(envelope.message, CoreOutputMessage::RuntimeReady)
    ));
    assert!(
        tokio::time::timeout(Duration::from_millis(25), router_rx.recv())
            .await
            .is_err()
    );

    let (responder, response) = send_user_input_response_channel();
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::UserInput {
            message_text: "new input".to_owned(),
            responder,
        })
        .expect("send new input");
    assert!(matches!(
        response.await.expect("input response"),
        Ok(SendUserInputOutcome::Committed { .. })
    ));

    let request = recv_model_request(&mut router_rx).await;
    let user_messages = request
        .conversation
        .messages
        .iter()
        .filter(|message| message.role == selvedge_db::MessageRole::User)
        .filter_map(|message| message.content.as_str())
        .collect::<Vec<_>>();
    assert_eq!(user_messages, vec!["current", "old queued", "new input"]);
}

#[tokio::test]
async fn task_runtime_shutdown_completes_when_router_ingress_is_not_drained() {
    let (runtime, _router_rx, _router_tx) = spawn_runtime_with_task(Vec::new()).await;

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::Start)
        .expect("send start");
    tokio::task::yield_now().await;

    tokio::time::timeout(
        Duration::from_millis(50),
        runtime.task_runtime_control.shutdown(),
    )
    .await
    .expect("stop completed");
}

#[tokio::test]
async fn task_runtime_preserves_batched_tool_call_order_in_next_model_request() {
    let (runtime, mut router_rx, _router_tx) =
        spawn_runtime_with_task(vec![tool_spec("search")]).await;
    let correlation = start_and_request_model(&runtime, &mut router_rx).await;

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ApiModelReply(
            ApiOutputEnvelope::Success {
                correlation,
                reply: ModelReply {
                    content: None,
                    tool_calls: vec![
                        ToolCallProposal {
                            call_id: "call-1".to_owned(),
                            tool_name: "search".to_owned(),
                            arguments: JsonObject::new(),
                        },
                        ToolCallProposal {
                            call_id: "call-2".to_owned(),
                            tool_name: "search".to_owned(),
                            arguments: JsonObject::new(),
                        },
                    ],
                    usage: None,
                    finish_reason: ModelFinishReason::ToolCalls,
                },
            },
        ))
        .expect("send model reply");

    let first_tool_request = recv_tool_request(&mut router_rx).await;
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ToolResult(ToolExecutionResult {
            task_id: TaskId("task-1".to_owned()),
            tool_execution_run_id: first_tool_request.tool_execution_run_id,
            function_call_node_id: first_tool_request.function_call_node_id,
            function_call_id: first_tool_request.function_call_id,
            tool_name: first_tool_request.tool_name,
            branches: calling_tool_result_branches(json!("first"), false),
        }))
        .expect("send first tool result");

    let second_tool_request = recv_tool_request(&mut router_rx).await;
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ToolResult(ToolExecutionResult {
            task_id: TaskId("task-1".to_owned()),
            tool_execution_run_id: second_tool_request.tool_execution_run_id,
            function_call_node_id: second_tool_request.function_call_node_id,
            function_call_id: second_tool_request.function_call_id,
            tool_name: second_tool_request.tool_name,
            branches: calling_tool_result_branches(json!("second"), false),
        }))
        .expect("send second tool result");

    let request = tokio::time::timeout(
        Duration::from_millis(50),
        recv_model_request(&mut router_rx),
    )
    .await
    .expect("promoted queued model request");
    assert_eq!(
        tool_transcript_events(&request),
        vec![
            "call:call-1",
            "call:call-2",
            "output:call-1",
            "output:call-2"
        ]
    );
}

#[tokio::test]
async fn task_runtime_ignores_tool_result_with_mismatched_call_identity() {
    let db = open_memory_db();
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            cursor_node_id: create_history_node(
                &db,
                NewHistoryNode {
                    parent_node_id: None,
                    content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                        message_role: selvedge_db::MessageRole::System,
                        message_text: "system".to_owned(),
                    }),
                    created_at: UnixTs(1),
                },
            )
            .expect("create cursor node"),
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: vec![task_tool(tool_spec("search"))],
            now: UnixTs(1),
        },
    )
    .expect("create task");
    let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db: db.clone(),
        router_tx: router_tx.downgrade(),
        config: TaskRuntimeConfig {
            model_profiles: model_profiles(),
        },
    })
    .expect("spawn runtime");
    let correlation = start_and_request_model(&runtime, &mut router_rx).await;

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ApiModelReply(
            ApiOutputEnvelope::Success {
                correlation,
                reply: ModelReply {
                    content: None,
                    tool_calls: vec![
                        ToolCallProposal {
                            call_id: "call-1".to_owned(),
                            tool_name: "search".to_owned(),
                            arguments: JsonObject::new(),
                        },
                        ToolCallProposal {
                            call_id: "call-2".to_owned(),
                            tool_name: "search".to_owned(),
                            arguments: JsonObject::new(),
                        },
                    ],
                    usage: None,
                    finish_reason: ModelFinishReason::ToolCalls,
                },
            },
        ))
        .expect("send model reply");

    let first_tool_request = recv_tool_request(&mut router_rx).await;
    let call_2_node_id = load_runtime_task(&db, &TaskId("task-1".to_owned()))
        .expect("load task")
        .task
        .cursor_node_id;

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ToolResult(ToolExecutionResult {
            task_id: TaskId("task-1".to_owned()),
            tool_execution_run_id: first_tool_request.tool_execution_run_id.clone(),
            function_call_node_id: call_2_node_id,
            function_call_id: FunctionCallId("call-2".to_owned()),
            tool_name: first_tool_request.tool_name.clone(),
            branches: calling_tool_result_branches(json!("wrong"), false),
        }))
        .expect("send mismatched tool result");

    assert!(
        tokio::time::timeout(Duration::from_millis(50), router_rx.recv())
            .await
            .is_err()
    );

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ToolResult(ToolExecutionResult {
            task_id: TaskId("task-1".to_owned()),
            tool_execution_run_id: first_tool_request.tool_execution_run_id,
            function_call_node_id: first_tool_request.function_call_node_id,
            function_call_id: first_tool_request.function_call_id,
            tool_name: first_tool_request.tool_name,
            branches: calling_tool_result_branches(json!("first"), false),
        }))
        .expect("send correct tool result");

    let second_tool_request = recv_tool_request(&mut router_rx).await;
    assert_eq!(second_tool_request.function_call_id.0, "call-2");
}

#[tokio::test]
async fn task_runtime_rejects_duplicate_tool_call_ids_in_one_model_reply() {
    let (runtime, mut router_rx, _router_tx) =
        spawn_runtime_with_task(vec![tool_spec("search"), tool_spec("lookup")]).await;
    let correlation = start_and_request_model(&runtime, &mut router_rx).await;

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ApiModelReply(
            ApiOutputEnvelope::Success {
                correlation,
                reply: ModelReply {
                    content: None,
                    tool_calls: vec![
                        ToolCallProposal {
                            call_id: "call-1".to_owned(),
                            tool_name: "search".to_owned(),
                            arguments: JsonObject::new(),
                        },
                        ToolCallProposal {
                            call_id: "call-1".to_owned(),
                            tool_name: "lookup".to_owned(),
                            arguments: JsonObject::new(),
                        },
                    ],
                    usage: None,
                    finish_reason: ModelFinishReason::ToolCalls,
                },
            },
        ))
        .expect("send model reply");

    assert_internal_exit(&mut router_rx).await;
}

#[tokio::test]
async fn task_runtime_validates_tool_reply_against_sent_callable_snapshot() {
    let db = open_memory_db();
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            cursor_node_id: create_history_node(
                &db,
                NewHistoryNode {
                    parent_node_id: None,
                    content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                        message_role: selvedge_db::MessageRole::System,
                        message_text: "system".to_owned(),
                    }),
                    created_at: UnixTs(1),
                },
            )
            .expect("create cursor node"),
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: vec![task_tool(required_integer_tool_spec("repeat"))],
            now: UnixTs(1),
        },
    )
    .expect("create task");

    let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db: db.clone(),
        router_tx: router_tx.downgrade(),
        config: TaskRuntimeConfig {
            model_profiles: model_profiles(),
        },
    })
    .expect("spawn runtime");
    let request = start_and_recv_model_request(&runtime, &mut router_rx).await;
    assert_eq!(
        request
            .tool_manifest
            .as_ref()
            .expect("sent manifest")
            .tools
            .len(),
        1
    );

    reconcile_task_tool_availability(&db, Vec::new()).expect("mark tool unavailable");
    let current_tools =
        read_task_tool_state(&db, &TaskId("task-1".to_owned())).expect("read current tools");
    assert_eq!(current_tools.manifest.tools.len(), 1);
    assert_eq!(
        current_tools.unavailable_tools,
        vec![ToolName("repeat".to_owned())]
    );

    let arguments = json_object(json!({
        "count": null,
        "nested": {"items": [1, true, null]},
        "large": 9007199254740993_u64
    }));

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ApiModelReply(
            ApiOutputEnvelope::Success {
                correlation: request.correlation,
                reply: ModelReply {
                    content: None,
                    tool_calls: vec![ToolCallProposal {
                        call_id: "call-1".to_owned(),
                        tool_name: "repeat".to_owned(),
                        arguments: arguments.clone(),
                    }],
                    usage: None,
                    finish_reason: ModelFinishReason::ToolCalls,
                },
            },
        ))
        .expect("send model reply");

    let tool_request = recv_tool_request(&mut router_rx).await;
    assert_eq!(tool_request.arguments, arguments);

    let conversation =
        read_conversation_for_task(&db, &TaskId("task-1".to_owned())).expect("read conversation");
    let persisted = conversation.messages.last().expect("function call message");
    assert_eq!(persisted.content_type(), Some(FUNCTION_CALL_CONTENT_TYPE));
    assert_eq!(persisted.function_call_id(), Some("call-1"));
    assert_eq!(persisted.tool_name(), Some("repeat"));
    assert_eq!(persisted.function_call_arguments(), Some(&arguments));

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ToolResult(ToolExecutionResult {
            task_id: tool_request.task_id,
            tool_execution_run_id: tool_request.tool_execution_run_id,
            function_call_node_id: tool_request.function_call_node_id,
            function_call_id: tool_request.function_call_id,
            tool_name: tool_request.tool_name,
            branches: calling_tool_result_branches(json!("done"), false),
        }))
        .expect("send tool result");

    let next_request = recv_model_request(&mut router_rx).await;
    assert_eq!(next_request.callable_tools, CallableTools::Only(Vec::new()));
}

#[tokio::test]
async fn task_runtime_rejects_tool_calls_outside_enabled_manifest() {
    let db = open_memory_db();
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            cursor_node_id: create_history_node(
                &db,
                NewHistoryNode {
                    parent_node_id: None,
                    content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                        message_role: selvedge_db::MessageRole::System,
                        message_text: "system".to_owned(),
                    }),
                    created_at: UnixTs(1),
                },
            )
            .expect("create cursor node"),
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: Vec::new(),
            now: UnixTs(1),
        },
    )
    .expect("create task");
    let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db,
        router_tx: router_tx.downgrade(),
        config: TaskRuntimeConfig {
            model_profiles: model_profiles(),
        },
    })
    .expect("spawn runtime");
    let correlation = start_and_request_model(&runtime, &mut router_rx).await;

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ApiModelReply(
            ApiOutputEnvelope::Success {
                correlation,
                reply: ModelReply {
                    content: None,
                    tool_calls: vec![ToolCallProposal {
                        call_id: "call-1".to_owned(),
                        tool_name: "disabled".to_owned(),
                        arguments: JsonObject::new(),
                    }],
                    usage: None,
                    finish_reason: ModelFinishReason::ToolCalls,
                },
            },
        ))
        .expect("send model reply");

    assert_internal_exit(&mut router_rx).await;
}

#[tokio::test]
async fn task_runtime_validates_all_tool_calls_before_dispatching_any() {
    let (runtime, mut router_rx, _router_tx) =
        spawn_runtime_with_task(vec![tool_spec("enabled")]).await;
    let correlation = start_and_request_model(&runtime, &mut router_rx).await;

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ApiModelReply(
            ApiOutputEnvelope::Success {
                correlation,
                reply: ModelReply {
                    content: None,
                    tool_calls: vec![
                        ToolCallProposal {
                            call_id: "call-1".to_owned(),
                            tool_name: "enabled".to_owned(),
                            arguments: JsonObject::new(),
                        },
                        ToolCallProposal {
                            call_id: "call-2".to_owned(),
                            tool_name: "disabled".to_owned(),
                            arguments: JsonObject::new(),
                        },
                    ],
                    usage: None,
                    finish_reason: ModelFinishReason::ToolCalls,
                },
            },
        ))
        .expect("send model reply");

    assert_internal_exit(&mut router_rx).await;
}

#[tokio::test]
async fn task_runtime_ignores_unrelated_validation_failure_while_waiting() {
    let (runtime, mut router_rx, _router_tx) = spawn_runtime_with_task(vec![]).await;
    let correlation = start_and_request_model(&runtime, &mut router_rx).await;
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::UserInput {
            message_text: "queued".to_owned(),
            responder: send_user_input_response_channel().0,
        })
        .expect("queue while waiting");

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ApiModelReply(
            ApiOutputEnvelope::Failure {
                correlation: ApiCallCorrelation {
                    api_effect_id: selvedge_command_model::ApiEffectId("other".to_owned()),
                    task_id: TaskId("other-task".to_owned()),
                    model_run_id: ModelRunId("other-run".to_owned()),
                },
                error: ModelCallError {
                    kind: ModelCallErrorKind::Validation,
                    message: "unrelated".to_owned(),
                },
            },
        ))
        .expect("send unrelated failure");

    assert!(
        tokio::time::timeout(std::time::Duration::from_millis(25), router_rx.recv())
            .await
            .is_err()
    );

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ApiModelReply(
            ApiOutputEnvelope::Success {
                correlation,
                reply: ModelReply {
                    content: Some("done".to_owned()),
                    tool_calls: Vec::new(),
                    usage: None,
                    finish_reason: ModelFinishReason::Stop,
                },
            },
        ))
        .expect("send current reply");

    let next_model_request = router_rx.recv().await.expect("queued model request");
    assert!(matches!(
        next_model_request,
        RouterIngressMessage::Core(envelope)
            if matches!(envelope.message, CoreOutputMessage::RequestModelCall(_))
    ));
}

#[tokio::test]
async fn task_runtime_reports_current_model_call_failure() {
    let (runtime, mut router_rx, _router_tx) = spawn_runtime_with_task(vec![]).await;
    let correlation = start_and_request_model(&runtime, &mut router_rx).await;

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ApiModelReply(
            ApiOutputEnvelope::Failure {
                correlation,
                error: ModelCallError {
                    kind: ModelCallErrorKind::ProviderNetwork,
                    message: "network failed".to_owned(),
                },
            },
        ))
        .expect("send failure");

    let event = tokio::time::timeout(std::time::Duration::from_millis(25), router_rx.recv())
        .await
        .expect("error event timeout")
        .expect("error event");
    assert!(matches!(
        &event,
        RouterIngressMessage::Core(envelope)
            if matches!(
                &envelope.message,
                CoreOutputMessage::PublishDomainEvent(request)
                    if matches!(&request.event, DomainEvent::ErrorNotice { .. })
            )
    ));
}

#[tokio::test]
async fn task_runtime_promotes_queued_input_after_model_failure() {
    let (runtime, mut router_rx, _router_tx) = spawn_runtime_with_task(vec![]).await;
    let correlation = start_and_request_model(&runtime, &mut router_rx).await;
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::UserInput {
            message_text: "queued".to_owned(),
            responder: send_user_input_response_channel().0,
        })
        .expect("queue input");

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ApiModelReply(
            ApiOutputEnvelope::Failure {
                correlation,
                error: ModelCallError {
                    kind: ModelCallErrorKind::ProviderNetwork,
                    message: "network".to_owned(),
                },
            },
        ))
        .expect("send model failure");

    let event = router_rx.recv().await.expect("error event");
    assert!(matches!(
        event,
        RouterIngressMessage::Core(envelope)
            if matches!(&envelope.message, CoreOutputMessage::PublishDomainEvent(_))
    ));
    let request = recv_model_request(&mut router_rx).await;
    let last_text = request
        .conversation
        .messages
        .last()
        .and_then(|message| message.content.as_str());
    assert_eq!(last_text, Some("queued"));
}

#[tokio::test]
async fn user_input_response_distinguishes_committed_and_queued_transitions() {
    let (runtime, mut router_rx, _router_tx) = spawn_runtime_with_task(vec![]).await;
    let correlation = start_and_request_model(&runtime, &mut router_rx).await;
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ApiModelReply(
            ApiOutputEnvelope::Failure {
                correlation,
                error: ModelCallError {
                    kind: ModelCallErrorKind::ProviderNetwork,
                    message: "network".to_owned(),
                },
            },
        ))
        .expect("send model failure");
    let _error_event = router_rx.recv().await.expect("error event");

    let (committed_responder, committed_response) = send_user_input_response_channel();
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::UserInput {
            message_text: "committed".to_owned(),
            responder: committed_responder,
        })
        .expect("send committed input");
    let Ok(SendUserInputOutcome::Committed { node_id }) =
        committed_response.await.expect("committed response")
    else {
        panic!("unexpected committed response");
    };
    assert!(node_id.0 > 0);
    let request = recv_model_request(&mut router_rx).await;
    assert!(
        request
            .conversation
            .messages
            .iter()
            .any(|message| message.content.as_str() == Some("committed"))
    );

    let (queued_responder, queued_response) = send_user_input_response_channel();
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::UserInput {
            message_text: "queued".to_owned(),
            responder: queued_responder,
        })
        .expect("send queued input");
    assert_eq!(
        queued_response.await.expect("queued response"),
        Ok(SendUserInputOutcome::Queued)
    );
}

#[tokio::test]
async fn task_runtime_rejects_empty_idle_user_input_before_append() {
    let db = open_memory_db();
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            cursor_node_id: create_history_node(
                &db,
                NewHistoryNode {
                    parent_node_id: None,
                    content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                        message_role: selvedge_db::MessageRole::Assistant,
                        message_text: "assistant".to_owned(),
                    }),
                    created_at: UnixTs(1),
                },
            )
            .expect("create cursor node"),
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: Vec::new(),
            now: UnixTs(1),
        },
    )
    .expect("create task");
    let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db,
        router_tx: router_tx.downgrade(),
        config: TaskRuntimeConfig {
            model_profiles: model_profiles(),
        },
    })
    .expect("spawn runtime");
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::Start)
        .expect("send start");
    let _ready = router_rx.recv().await.expect("ready");

    let (responder, response) = send_user_input_response_channel();
    let (late_responder, late_response) = send_user_input_response_channel();
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::UserInput {
            message_text: String::new(),
            responder,
        })
        .expect("send empty input");
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::UserInput {
            message_text: "after runtime failure".to_owned(),
            responder: late_responder,
        })
        .expect("send late input");
    assert_eq!(
        response.await.expect("input response"),
        Err(TaskCommandError::InvalidCommand)
    );
    assert_eq!(
        late_response.await.expect("late response"),
        Err(TaskCommandError::RuntimeUnavailable)
    );

    assert_internal_exit(&mut router_rx).await;
}

#[tokio::test]
async fn task_runtime_ignores_replayed_start_after_model_request() {
    let (runtime, mut router_rx, _router_tx) = spawn_runtime_with_task(vec![]).await;
    let _correlation = start_and_request_model(&runtime, &mut router_rx).await;

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::Start)
        .expect("send replayed start");

    assert!(
        tokio::time::timeout(std::time::Duration::from_millis(25), router_rx.recv())
            .await
            .is_err()
    );
}

#[tokio::test]
async fn task_runtime_preserves_model_wait_state_for_stray_tool_result() {
    let (runtime, mut router_rx, _router_tx) = spawn_runtime_with_task(vec![]).await;
    let _correlation = start_and_request_model(&runtime, &mut router_rx).await;

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::ToolResult(ToolExecutionResult {
            task_id: TaskId("task-1".to_owned()),
            tool_execution_run_id: selvedge_command_model::ToolExecutionRunId("stray".to_owned()),
            function_call_node_id: selvedge_db::HistoryNodeId(1),
            function_call_id: selvedge_db::FunctionCallId("call".to_owned()),
            tool_name: selvedge_db::ToolName("tool".to_owned()),
            branches: calling_tool_result_branches(json!("stray"), false),
        }))
        .expect("send stray tool result");
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::UserInput {
            message_text: "queued".to_owned(),
            responder: send_user_input_response_channel().0,
        })
        .expect("queue input");

    assert!(
        tokio::time::timeout(std::time::Duration::from_millis(25), router_rx.recv())
            .await
            .is_err()
    );
}

#[tokio::test]
async fn task_runtime_uses_fresh_model_run_ids_after_respawn() {
    let db = open_memory_db();
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            cursor_node_id: create_history_node(
                &db,
                NewHistoryNode {
                    parent_node_id: None,
                    content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                        message_role: selvedge_db::MessageRole::System,
                        message_text: "system".to_owned(),
                    }),
                    created_at: UnixTs(1),
                },
            )
            .expect("create cursor node"),
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: Vec::new(),
            now: UnixTs(1),
        },
    )
    .expect("create task");

    let first_model_run_id = spawn_runtime_and_start_one_model_call(db.clone()).await;
    let second_model_run_id = spawn_runtime_and_start_one_model_call(db).await;

    assert_ne!(first_model_run_id, second_model_run_id);
}

#[tokio::test]
async fn task_runtime_preserves_queued_input_when_append_fails() {
    let db = open_memory_db();
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            cursor_node_id: create_history_node(
                &db,
                NewHistoryNode {
                    parent_node_id: None,
                    content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                        message_role: selvedge_db::MessageRole::System,
                        message_text: "system".to_owned(),
                    }),
                    created_at: UnixTs(4_102_444_800),
                },
            )
            .expect("create cursor node"),
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: Vec::new(),
            now: UnixTs(4_102_444_800),
        },
    )
    .expect("create task");
    queue_user_input(
        &db,
        &TaskId("task-1".to_owned()),
        "queued".to_owned(),
        UnixTs(4_102_444_801),
    )
    .expect("queue input");

    let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db: db.clone(),
        router_tx: router_tx.downgrade(),
        config: TaskRuntimeConfig {
            model_profiles: model_profiles(),
        },
    })
    .expect("spawn runtime");
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::Start)
        .expect("send start");
    let _ready = router_rx.recv().await.expect("ready");
    let _exit = router_rx.recv().await.expect("db error exit");

    let loaded = load_runtime_task(&db, &TaskId("task-1".to_owned())).expect("load task");
    assert_eq!(loaded.queued_inputs.len(), 1);
}

#[tokio::test]
async fn task_runtime_recovers_open_tool_call_before_model_dispatch() {
    let db = open_memory_db();
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            cursor_node_id: create_history_node(
                &db,
                NewHistoryNode {
                    parent_node_id: None,
                    content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                        message_role: selvedge_db::MessageRole::System,
                        message_text: "system".to_owned(),
                    }),
                    created_at: UnixTs(1),
                },
            )
            .expect("create cursor node"),
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: vec![task_tool(required_integer_tool_spec("repeat"))],
            now: UnixTs(1),
        },
    )
    .expect("create task");
    append_model_reply_with_tool_calls_and_move_cursor(
        &db,
        &TaskId("task-1".to_owned()),
        None,
        vec![NewFunctionCallNodeContent {
            function_call_id: FunctionCallId("call-1".to_owned()),
            tool_name: ToolName("repeat".to_owned()),
            arguments: json_object(json!({"count": 1})),
        }],
        UnixTs(2),
    )
    .expect("append unpaired function call");
    append_assistant_message_and_drain_queue(
        &db,
        &TaskId("task-1".to_owned()),
        "assistant".to_owned(),
        UnixTs(3),
    )
    .expect("append assistant cursor after open call");
    let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db,
        router_tx: router_tx.downgrade(),
        config: TaskRuntimeConfig {
            model_profiles: model_profiles(),
        },
    })
    .expect("spawn runtime");

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::Start)
        .expect("send start");
    let _ready = router_rx.recv().await.expect("ready");
    let request = recv_tool_request(&mut router_rx).await;

    assert_eq!(request.function_call_id.0, "call-1");
}

#[tokio::test]
async fn child_runtime_synthesizes_unknown_outcome_for_inherited_open_call() {
    let db = open_memory_db();
    let root_task_id = TaskId("task-1".to_owned());
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: root_task_id.clone(),
            cursor_node_id: create_history_node(
                &db,
                NewHistoryNode {
                    parent_node_id: None,
                    content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                        message_role: selvedge_db::MessageRole::System,
                        message_text: "system".to_owned(),
                    }),
                    created_at: UnixTs(1),
                },
            )
            .expect("create cursor node"),
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: vec![
                task_tool_with_recovery(tool_spec("fork_task"), ToolRecoveryPolicy::RetrySafe),
                task_tool_with_recovery(tool_spec("bash"), ToolRecoveryPolicy::OutcomeUnknown),
            ],
            now: UnixTs(1),
        },
    )
    .expect("create task");
    let call_node_ids = append_model_reply_with_tool_calls_and_move_cursor(
        &db,
        &root_task_id,
        None,
        vec![
            NewFunctionCallNodeContent {
                function_call_id: FunctionCallId("fork-call".to_owned()),
                tool_name: ToolName("fork_task".to_owned()),
                arguments: JsonObject::new(),
            },
            NewFunctionCallNodeContent {
                function_call_id: FunctionCallId("bash-call".to_owned()),
                tool_name: ToolName("bash".to_owned()),
                arguments: json_object(json!({"command": "touch marker"})),
            },
        ],
        UnixTs(2),
    )
    .expect("append tool-call batch");
    let child_task_id = TaskId("child-1".to_owned());
    commit_tool_result_branches(
        &db,
        CommitToolResultBranchesInput {
            calling_task_id: root_task_id,
            function_call_node_id: call_node_ids[0],
            function_call_id: FunctionCallId("fork-call".to_owned()),
            tool_name: ToolName("fork_task".to_owned()),
            branches: vec![
                ToolResultBranch {
                    target: ToolResultBranchTarget::CallingTask,
                    output: json!(0),
                    is_error: false,
                    user_messages: Vec::new(),
                },
                ToolResultBranch {
                    target: ToolResultBranchTarget::NewChildTask(child_task_id.clone()),
                    output: json!(1),
                    is_error: false,
                    user_messages: vec!["continue child work".to_owned()],
                },
            ],
            now: UnixTs(3),
        },
    )
    .expect("commit fork branches");

    let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: child_task_id,
        db,
        router_tx: router_tx.downgrade(),
        config: TaskRuntimeConfig {
            model_profiles: model_profiles(),
        },
    })
    .expect("spawn child runtime");
    let request = start_and_recv_model_request(&runtime, &mut router_rx).await;
    let recovered_output = request
        .conversation
        .messages
        .iter()
        .find(|message| {
            message.content_type() == Some(FUNCTION_OUTPUT_CONTENT_TYPE)
                && message.function_call_id() == Some("bash-call")
        })
        .expect("synthetic bash output");

    assert_eq!(recovered_output.function_output_is_error(), Some(true));
    assert_eq!(
        recovered_output.function_output_value().expect("output")["error"]["code"],
        "tool_outcome_unknown"
    );
    assert!(
        recovered_output.function_output_value().expect("output")["error"]["message"]
            .as_str()
            .expect("message")
            .contains("requested together with fork_task")
    );
    let _ = runtime.task_runtime_control.shutdown().await;
}

#[tokio::test]
async fn task_runtime_allows_messages_between_tool_call_and_matching_output() {
    let db = open_memory_db();
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            cursor_node_id: create_history_node(
                &db,
                NewHistoryNode {
                    parent_node_id: None,
                    content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                        message_role: selvedge_db::MessageRole::System,
                        message_text: "system".to_owned(),
                    }),
                    created_at: UnixTs(1),
                },
            )
            .expect("create cursor node"),
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: vec![task_tool(required_integer_tool_spec("repeat"))],
            now: UnixTs(1),
        },
    )
    .expect("create task");
    let function_call_node_id = append_model_reply_with_tool_calls_and_move_cursor(
        &db,
        &TaskId("task-1".to_owned()),
        None,
        vec![NewFunctionCallNodeContent {
            function_call_id: FunctionCallId("call-1".to_owned()),
            tool_name: ToolName("repeat".to_owned()),
            arguments: json_object(json!({"count": 1})),
        }],
        UnixTs(2),
    )
    .expect("append function call")[0];
    append_user_message_and_move_cursor(
        &db,
        &TaskId("task-1".to_owned()),
        "interleaved".to_owned(),
        UnixTs(3),
    )
    .expect("append interleaved message");
    commit_tool_result_branches(
        &db,
        CommitToolResultBranchesInput {
            calling_task_id: TaskId("task-1".to_owned()),
            function_call_node_id,
            function_call_id: FunctionCallId("call-1".to_owned()),
            tool_name: ToolName("repeat".to_owned()),
            branches: vec![ToolResultBranch {
                target: ToolResultBranchTarget::CallingTask,
                output: json!("done"),
                is_error: false,
                user_messages: Vec::new(),
            }],
            now: UnixTs(4),
        },
    )
    .expect("append function output");
    let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db,
        router_tx: router_tx.downgrade(),
        config: TaskRuntimeConfig {
            model_profiles: model_profiles(),
        },
    })
    .expect("spawn runtime");

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::Start)
        .expect("send start");
    let _ready = router_rx.recv().await.expect("ready");
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::UserInput {
            message_text: "hello".to_owned(),
            responder: send_user_input_response_channel().0,
        })
        .expect("send input");

    let request = recv_model_request(&mut router_rx).await;
    assert_eq!(
        tool_transcript_events(&request),
        vec!["call:call-1", "output:call-1"]
    );
}

async fn spawn_runtime_with_task(
    tools: Vec<ToolSpec>,
) -> (
    selvedge_core::SpawnedTaskRuntime,
    tokio::sync::mpsc::UnboundedReceiver<RouterIngressMessage>,
    RouterIngressSender,
) {
    spawn_runtime_with_task_and_descendant_limit(tools, 20).await
}

async fn spawn_runtime_with_task_and_descendant_limit(
    tools: Vec<ToolSpec>,
    max_task_descendants: u32,
) -> (
    selvedge_core::SpawnedTaskRuntime,
    tokio::sync::mpsc::UnboundedReceiver<RouterIngressMessage>,
    RouterIngressSender,
) {
    let db = open_memory_db_with_max_task_descendants(max_task_descendants);
    let tools = tools.into_iter().map(task_tool).collect();
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            cursor_node_id: create_history_node(
                &db,
                NewHistoryNode {
                    parent_node_id: None,
                    content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                        message_role: selvedge_db::MessageRole::System,
                        message_text: "system".to_owned(),
                    }),
                    created_at: UnixTs(1),
                },
            )
            .expect("create cursor node"),
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools,
            now: UnixTs(1),
        },
    )
    .expect("create task");

    let (router_tx, router_rx) = tokio::sync::mpsc::unbounded_channel();
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db,
        router_tx: router_tx.downgrade(),
        config: TaskRuntimeConfig {
            model_profiles: model_profiles(),
        },
    })
    .expect("spawn runtime");
    (runtime, router_rx, router_tx)
}

async fn start_and_request_model(
    runtime: &selvedge_core::SpawnedTaskRuntime,
    router_rx: &mut tokio::sync::mpsc::UnboundedReceiver<RouterIngressMessage>,
) -> ApiCallCorrelation {
    start_and_recv_model_request(runtime, router_rx)
        .await
        .correlation
}

async fn start_and_recv_model_request(
    runtime: &selvedge_core::SpawnedTaskRuntime,
    router_rx: &mut tokio::sync::mpsc::UnboundedReceiver<RouterIngressMessage>,
) -> ModelCallDispatchRequest {
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::Start)
        .expect("send start");
    let ready = router_rx.recv().await.expect("ready");
    assert!(matches!(
        ready,
        RouterIngressMessage::Core(envelope)
            if matches!(envelope.message, CoreOutputMessage::RuntimeReady)
    ));
    let request = router_rx.recv().await.expect("model request");
    match request {
        RouterIngressMessage::Core(envelope) => match envelope.message {
            CoreOutputMessage::RequestModelCall(request) => request,
            _ => panic!("unexpected core output"),
        },
        _ => panic!("unexpected router message"),
    }
}

async fn recv_tool_request(
    router_rx: &mut tokio::sync::mpsc::UnboundedReceiver<RouterIngressMessage>,
) -> selvedge_command_model::ToolExecutionRequest {
    let message = router_rx.recv().await.expect("tool request");
    match message {
        RouterIngressMessage::Core(envelope) => match envelope.message {
            CoreOutputMessage::RequestToolExecution(request) => request,
            _ => panic!("unexpected core output"),
        },
        _ => panic!("unexpected router message"),
    }
}

async fn recv_model_request(
    router_rx: &mut tokio::sync::mpsc::UnboundedReceiver<RouterIngressMessage>,
) -> ModelCallDispatchRequest {
    let message = router_rx.recv().await.expect("model request");
    match message {
        RouterIngressMessage::Core(envelope) => match envelope.message {
            CoreOutputMessage::RequestModelCall(request) => request,
            _ => panic!("unexpected core output"),
        },
        _ => panic!("unexpected router message"),
    }
}

fn tool_transcript_events(request: &ModelCallDispatchRequest) -> Vec<String> {
    request
        .conversation
        .messages
        .iter()
        .filter_map(|message| match message.content_type() {
            Some(FUNCTION_CALL_CONTENT_TYPE) => message
                .function_call_id()
                .map(|function_call_id| format!("call:{function_call_id}")),
            Some(FUNCTION_OUTPUT_CONTENT_TYPE) => message
                .function_call_id()
                .map(|function_call_id| format!("output:{function_call_id}")),
            _ => None,
        })
        .collect()
}

fn calling_tool_result_branches(output: Value, is_error: bool) -> Vec<ToolExecutionBranch> {
    vec![ToolExecutionBranch {
        target: ToolExecutionBranchTarget::CallingTask,
        output,
        is_error,
        messages: Vec::new(),
    }]
}

async fn assert_internal_exit(
    router_rx: &mut tokio::sync::mpsc::UnboundedReceiver<RouterIngressMessage>,
) {
    let message = router_rx.recv().await.expect("runtime exit");
    match message {
        RouterIngressMessage::RuntimeExit(notice) => {
            assert!(matches!(
                notice.reason,
                TaskRuntimeExitReason::InternalError(_)
            ));
        }
        _ => panic!("unexpected router message"),
    }
}

async fn spawn_runtime_and_start_one_model_call(db: selvedge_db::DbPool) -> ModelRunId {
    let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db,
        router_tx: router_tx.downgrade(),
        config: TaskRuntimeConfig {
            model_profiles: model_profiles(),
        },
    })
    .expect("spawn runtime");
    let request = start_and_recv_model_request(&runtime, &mut router_rx).await;
    let _ = runtime.task_runtime_control.shutdown().await;
    request.correlation.model_run_id
}

fn tool_spec(name: &str) -> ToolSpec {
    ToolSpec {
        name: name.to_owned(),
        description: name.to_owned(),
        input_schema: JsonObject::new(),
    }
}

fn task_tool(tool: ToolSpec) -> TaskToolSpec {
    task_tool_with_recovery(tool, ToolRecoveryPolicy::RetrySafe)
}

fn task_tool_with_recovery(tool: ToolSpec, recovery_policy: ToolRecoveryPolicy) -> TaskToolSpec {
    TaskToolSpec {
        tool,
        execution_source: ToolExecutionSource::Harness,
        recovery_policy,
    }
}

fn required_integer_tool_spec(name: &str) -> ToolSpec {
    ToolSpec {
        name: name.to_owned(),
        description: name.to_owned(),
        input_schema: json_object(json!({
            "type": "object",
            "properties": {
                "count": {"type": "integer"}
            },
            "required": ["count"]
        })),
    }
}

fn json_object(value: Value) -> JsonObject {
    match value {
        Value::Object(object) => object,
        _ => panic!("test fixture must be a JSON object"),
    }
}

fn model_profiles()
-> HashMap<selvedge_db::ModelProfileKey, selvedge_domain_model::ModelProviderProfile> {
    default_model_profiles()
}
