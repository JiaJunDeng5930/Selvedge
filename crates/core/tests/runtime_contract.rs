use std::collections::BTreeMap;

use selvedge_command_model::{
    ApiCallCorrelation, ApiOutputEnvelope, CoreOutputMessage, ModelCallDispatchRequest,
    ModelCallError, ModelCallErrorKind, ModelRunId, RouterIngressMessage, TaskRuntimeCommand,
    TaskRuntimeExitReason, ToolExecutionResult,
};
use selvedge_core::{SpawnTaskRuntimeArgs, TaskRuntimeConfig, spawn_task_runtime};
use selvedge_db::{
    CreateRootTaskInput, NewHistoryNode, NewHistoryNodeContent, NewMessageNodeContent,
    OpenDbOptions, ReasoningEffort, TaskId, ToolArgumentValue, UnixTs, create_root_task, open_db,
    register_tool,
};
use selvedge_domain_model::{
    ModelFinishReason, ModelReply, StructuredPayload, ToolCallProposal, ToolParameter,
    ToolParameterType, ToolSpec,
};

#[tokio::test]
async fn task_runtime_starts_and_requests_model_call_for_user_input() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
    })
    .expect("open db");
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            initial_node: NewHistoryNode {
                parent_node_id: None,
                content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                    message_role: selvedge_db::MessageRole::System,
                    message_text: "system".to_owned(),
                }),
                created_at: UnixTs(1),
            },
            model_profile_key: selvedge_db::ModelProfileKey("provider/model".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(1),
        },
    )
    .expect("create task");

    let (router_tx, mut router_rx) = tokio::sync::mpsc::channel(8);
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db,
        router_tx,
        config: TaskRuntimeConfig {
            mailbox_capacity: 8,
        },
    })
    .expect("spawn runtime");

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::Start)
        .await
        .expect("send start");
    let ready = router_rx.recv().await.expect("ready");
    assert!(matches!(
        ready,
        RouterIngressMessage::Core(envelope)
            if matches!(envelope.message, CoreOutputMessage::RuntimeReady { .. })
    ));

    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::UserInput {
            message_text: "hello".to_owned(),
        })
        .await
        .expect("send input");

    let request = router_rx.recv().await.expect("model request");
    assert!(matches!(
        request,
        RouterIngressMessage::Core(envelope)
            if matches!(envelope.message, CoreOutputMessage::RequestModelCall(_))
    ));
}

#[tokio::test]
async fn task_runtime_resolves_model_profile_key_into_provider_and_model() {
    let (runtime, mut router_rx) = spawn_runtime_with_task(vec![]).await;

    let request = start_and_recv_model_request(&runtime, &mut router_rx).await;

    assert_eq!(request.provider.provider_name, "provider");
    assert_eq!(request.provider.model_name, "model");
}

#[tokio::test]
async fn task_runtime_dispatches_all_tool_calls_before_next_model_call() {
    let (runtime, mut router_rx) = spawn_runtime_with_task(vec![ToolSpec {
        name: "search".to_owned(),
        description: "search".to_owned(),
        parameters: Vec::new(),
    }])
    .await;
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
                            arguments: StructuredPayload::Object(BTreeMap::new()),
                        },
                        ToolCallProposal {
                            call_id: "call-2".to_owned(),
                            tool_name: "search".to_owned(),
                            arguments: StructuredPayload::Object(BTreeMap::new()),
                        },
                    ],
                    usage: None,
                    finish_reason: ModelFinishReason::ToolCalls,
                },
            },
        ))
        .await
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
            output_text: "first".to_owned(),
            is_error: false,
        }))
        .await
        .expect("send first tool result");

    let second_tool_request = recv_tool_request(&mut router_rx).await;
    assert_eq!(second_tool_request.function_call_id.0, "call-2");
}

#[tokio::test]
async fn task_runtime_uses_tool_parameter_type_for_integer_arguments() {
    let (runtime, mut router_rx) = spawn_runtime_with_task(vec![ToolSpec {
        name: "repeat".to_owned(),
        description: "repeat".to_owned(),
        parameters: vec![ToolParameter {
            name: "count".to_owned(),
            parameter_type: ToolParameterType::Integer,
            description: "count".to_owned(),
            required: true,
        }],
    }])
    .await;
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
                        tool_name: "repeat".to_owned(),
                        arguments: StructuredPayload::Object(BTreeMap::from([(
                            "count".to_owned(),
                            StructuredPayload::Number(1.0),
                        )])),
                    }],
                    usage: None,
                    finish_reason: ModelFinishReason::ToolCalls,
                },
            },
        ))
        .await
        .expect("send model reply");

    let tool_request = recv_tool_request(&mut router_rx).await;
    assert_eq!(
        tool_request.arguments[0].value,
        ToolArgumentValue::Integer(1)
    );
}

#[tokio::test]
async fn task_runtime_rejects_tool_calls_outside_enabled_manifest() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
    })
    .expect("open db");
    register_tool(
        &db,
        ToolSpec {
            name: "disabled".to_owned(),
            description: "disabled".to_owned(),
            parameters: Vec::new(),
        },
    )
    .expect("register disabled tool");
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            initial_node: NewHistoryNode {
                parent_node_id: None,
                content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                    message_role: selvedge_db::MessageRole::System,
                    message_text: "system".to_owned(),
                }),
                created_at: UnixTs(1),
            },
            model_profile_key: selvedge_db::ModelProfileKey("provider/model".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(1),
        },
    )
    .expect("create task");
    let (router_tx, mut router_rx) = tokio::sync::mpsc::channel(16);
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db,
        router_tx,
        config: TaskRuntimeConfig {
            mailbox_capacity: 16,
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
                        arguments: StructuredPayload::Object(BTreeMap::new()),
                    }],
                    usage: None,
                    finish_reason: ModelFinishReason::ToolCalls,
                },
            },
        ))
        .await
        .expect("send model reply");

    assert_internal_exit(&mut router_rx).await;
}

#[tokio::test]
async fn task_runtime_rejects_tool_calls_missing_required_arguments() {
    let (runtime, mut router_rx) = spawn_runtime_with_task(vec![ToolSpec {
        name: "repeat".to_owned(),
        description: "repeat".to_owned(),
        parameters: vec![ToolParameter {
            name: "count".to_owned(),
            parameter_type: ToolParameterType::Integer,
            description: "count".to_owned(),
            required: true,
        }],
    }])
    .await;
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
                        tool_name: "repeat".to_owned(),
                        arguments: StructuredPayload::Object(BTreeMap::new()),
                    }],
                    usage: None,
                    finish_reason: ModelFinishReason::ToolCalls,
                },
            },
        ))
        .await
        .expect("send model reply");

    assert_internal_exit(&mut router_rx).await;
}

#[tokio::test]
async fn task_runtime_ignores_unrelated_validation_failure_while_waiting() {
    let (runtime, mut router_rx) = spawn_runtime_with_task(vec![]).await;
    let correlation = start_and_request_model(&runtime, &mut router_rx).await;
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::UserInput {
            message_text: "queued".to_owned(),
        })
        .await
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
        .await
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
        .await
        .expect("send current reply");

    let next_model_request = router_rx.recv().await.expect("queued model request");
    assert!(matches!(
        next_model_request,
        RouterIngressMessage::Core(envelope)
            if matches!(envelope.message, CoreOutputMessage::RequestModelCall(_))
    ));
}

#[tokio::test]
async fn task_runtime_rejects_unconvertible_required_arguments() {
    let (runtime, mut router_rx) = spawn_runtime_with_task(vec![ToolSpec {
        name: "repeat".to_owned(),
        description: "repeat".to_owned(),
        parameters: vec![ToolParameter {
            name: "count".to_owned(),
            parameter_type: ToolParameterType::Integer,
            description: "count".to_owned(),
            required: true,
        }],
    }])
    .await;
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
                        tool_name: "repeat".to_owned(),
                        arguments: StructuredPayload::Object(BTreeMap::from([(
                            "count".to_owned(),
                            StructuredPayload::Null,
                        )])),
                    }],
                    usage: None,
                    finish_reason: ModelFinishReason::ToolCalls,
                },
            },
        ))
        .await
        .expect("send model reply");

    assert_internal_exit(&mut router_rx).await;
}

async fn spawn_runtime_with_task(
    tools: Vec<ToolSpec>,
) -> (
    selvedge_core::SpawnedTaskRuntime,
    tokio::sync::mpsc::Receiver<RouterIngressMessage>,
) {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
    })
    .expect("open db");
    let enabled_tools = tools
        .iter()
        .map(|tool| selvedge_db::ToolName(tool.name.clone()))
        .collect();
    for tool in tools {
        register_tool(&db, tool).expect("register tool");
    }
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            initial_node: NewHistoryNode {
                parent_node_id: None,
                content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                    message_role: selvedge_db::MessageRole::System,
                    message_text: "system".to_owned(),
                }),
                created_at: UnixTs(1),
            },
            model_profile_key: selvedge_db::ModelProfileKey("provider/model".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools,
            now: UnixTs(1),
        },
    )
    .expect("create task");

    let (router_tx, router_rx) = tokio::sync::mpsc::channel(16);
    let runtime = spawn_task_runtime(SpawnTaskRuntimeArgs {
        task_id: TaskId("task-1".to_owned()),
        db,
        router_tx,
        config: TaskRuntimeConfig {
            mailbox_capacity: 16,
        },
    })
    .expect("spawn runtime");
    (runtime, router_rx)
}

async fn start_and_request_model(
    runtime: &selvedge_core::SpawnedTaskRuntime,
    router_rx: &mut tokio::sync::mpsc::Receiver<RouterIngressMessage>,
) -> ApiCallCorrelation {
    start_and_recv_model_request(runtime, router_rx)
        .await
        .correlation
}

async fn start_and_recv_model_request(
    runtime: &selvedge_core::SpawnedTaskRuntime,
    router_rx: &mut tokio::sync::mpsc::Receiver<RouterIngressMessage>,
) -> ModelCallDispatchRequest {
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::Start)
        .await
        .expect("send start");
    let ready = router_rx.recv().await.expect("ready");
    assert!(matches!(
        ready,
        RouterIngressMessage::Core(envelope)
            if matches!(envelope.message, CoreOutputMessage::RuntimeReady { .. })
    ));
    runtime
        .task_runtime_tx
        .send(TaskRuntimeCommand::UserInput {
            message_text: "hello".to_owned(),
        })
        .await
        .expect("send input");
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
    router_rx: &mut tokio::sync::mpsc::Receiver<RouterIngressMessage>,
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

async fn assert_internal_exit(router_rx: &mut tokio::sync::mpsc::Receiver<RouterIngressMessage>) {
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
