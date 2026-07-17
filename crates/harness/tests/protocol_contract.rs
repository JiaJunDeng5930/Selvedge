use selvedge_command_model::{
    HistoryNodeProjection, HistoryNodeProjectionBody, TaskProjectionStatus, ToolExecutionRequest,
    ToolExecutionRunId,
};
use selvedge_domain_model::{
    FunctionCallId, HistoryNodeId, MessageRole, TaskId, ToolArgumentValue, ToolCallArgument,
    ToolName, ToolParameter, ToolParameterName, ToolParameterType, ToolSpec, UnixTs,
};
use selvedge_harness::{
    ARCHIVE_TASK_TOOL_NAME, ArchiveTaskInvocation, ArchiveTaskSuccess, FORK_TASK_TOOL_NAME,
    ForkTaskInvocation, ForkTaskSuccess, HarnessError, HarnessErrorCode, HarnessInvocation,
    HarnessSuccess, HistoryPage, MessageDisposition, READ_TASK_TOOL_NAME, ReadTaskInvocation,
    ReadTaskSuccess, SEND_MESSAGE_TO_TASK_TOOL_NAME, SendMessageToTaskInvocation,
    SendMessageToTaskSuccess, encode_tool_execution_result, parse_invocation, tool_manifest,
};

#[test]
fn manifest_defines_exactly_the_four_harness_tools() {
    assert_eq!(
        tool_manifest().tools,
        vec![
            ToolSpec {
                name: "fork_task".to_owned(),
                description:
                    "Create an active child task from the calling task and give it an initial prompt."
                        .to_owned(),
                parameters: vec![string_parameter(
                    "prompt",
                    "Initial prompt for the child task.",
                    true,
                )],
            },
            ToolSpec {
                name: "read_task".to_owned(),
                description:
                    "Read task state and a page of history. Omit task_id to read the calling task."
                        .to_owned(),
                parameters: vec![
                    string_parameter(
                        "task_id",
                        "Task to read; omit it to read the calling task.",
                        false,
                    ),
                    integer_parameter(
                        "after_node_id",
                        "Return history nodes after this node ID.",
                        false,
                    ),
                    integer_parameter(
                        "limit",
                        "Maximum history nodes to return, from 1 through 100.",
                        false,
                    ),
                ],
            },
            ToolSpec {
                name: "send_message_to_task".to_owned(),
                description:
                    "Send a message to an active task and report whether it was committed or queued."
                        .to_owned(),
                parameters: vec![
                    string_parameter("task_id", "Task that should receive the message.", true),
                    string_parameter("message", "Message to send to the task.", true),
                ],
            },
            ToolSpec {
                name: "archive_task".to_owned(),
                description: "Archive another active task.".to_owned(),
                parameters: vec![string_parameter("task_id", "Task to archive.", true)],
            },
        ]
    );
}

#[test]
fn valid_requests_parse_to_typed_invocations() {
    let cases = [
        (
            request(
                FORK_TASK_TOOL_NAME,
                vec![string_argument("prompt", "investigate")],
            ),
            HarnessInvocation::ForkTask(ForkTaskInvocation {
                prompt: "investigate".to_owned(),
            }),
        ),
        (
            request(READ_TASK_TOOL_NAME, Vec::new()),
            HarnessInvocation::ReadTask(ReadTaskInvocation {
                task_id: None,
                after_node_id: None,
                limit: None,
            }),
        ),
        (
            request(READ_TASK_TOOL_NAME, vec![integer_argument("limit", 1)]),
            HarnessInvocation::ReadTask(ReadTaskInvocation {
                task_id: None,
                after_node_id: None,
                limit: Some(1),
            }),
        ),
        (
            request(
                READ_TASK_TOOL_NAME,
                vec![
                    string_argument("task_id", "task-2"),
                    integer_argument("after_node_id", 17),
                    integer_argument("limit", 100),
                ],
            ),
            HarnessInvocation::ReadTask(ReadTaskInvocation {
                task_id: Some(TaskId("task-2".to_owned())),
                after_node_id: Some(HistoryNodeId(17)),
                limit: Some(100),
            }),
        ),
        (
            request(
                SEND_MESSAGE_TO_TASK_TOOL_NAME,
                vec![
                    string_argument("task_id", "task-2"),
                    string_argument("message", "continue"),
                ],
            ),
            HarnessInvocation::SendMessageToTask(SendMessageToTaskInvocation {
                task_id: TaskId("task-2".to_owned()),
                message: "continue".to_owned(),
            }),
        ),
        (
            request(
                ARCHIVE_TASK_TOOL_NAME,
                vec![string_argument("task_id", "task-2")],
            ),
            HarnessInvocation::ArchiveTask(ArchiveTaskInvocation {
                task_id: TaskId("task-2".to_owned()),
            }),
        ),
    ];

    for (request, expected) in cases {
        assert_eq!(parse_invocation(&request), Ok(expected));
    }
}

#[test]
fn invalid_requests_are_rejected_without_backend_state() {
    let cases = [
        (
            request("other_tool", Vec::new()),
            HarnessErrorCode::UnknownTool,
            "unknown tool 'other_tool'",
        ),
        (
            request(FORK_TASK_TOOL_NAME, Vec::new()),
            HarnessErrorCode::InvalidArguments,
            "missing required argument 'prompt'",
        ),
        (
            request(FORK_TASK_TOOL_NAME, vec![string_argument("extra", "value")]),
            HarnessErrorCode::InvalidArguments,
            "unexpected argument 'extra'",
        ),
        (
            request(
                FORK_TASK_TOOL_NAME,
                vec![
                    string_argument("prompt", "one"),
                    string_argument("prompt", "two"),
                ],
            ),
            HarnessErrorCode::InvalidArguments,
            "duplicate argument 'prompt'",
        ),
        (
            request(FORK_TASK_TOOL_NAME, vec![integer_argument("prompt", 1)]),
            HarnessErrorCode::InvalidArguments,
            "argument 'prompt' must be a string",
        ),
        (
            request(FORK_TASK_TOOL_NAME, vec![string_argument("prompt", "  ")]),
            HarnessErrorCode::InvalidArguments,
            "argument 'prompt' must not be empty",
        ),
        (
            request(READ_TASK_TOOL_NAME, vec![string_argument("task_id", "")]),
            HarnessErrorCode::InvalidArguments,
            "argument 'task_id' must not be empty",
        ),
        (
            request(
                SEND_MESSAGE_TO_TASK_TOOL_NAME,
                vec![
                    string_argument("task_id", "task-2"),
                    string_argument("message", ""),
                ],
            ),
            HarnessErrorCode::InvalidArguments,
            "argument 'message' must not be empty",
        ),
        (
            request(
                ARCHIVE_TASK_TOOL_NAME,
                vec![string_argument("task_id", " ")],
            ),
            HarnessErrorCode::InvalidArguments,
            "argument 'task_id' must not be empty",
        ),
        (
            request(
                ARCHIVE_TASK_TOOL_NAME,
                vec![string_argument("task_id", "task-1")],
            ),
            HarnessErrorCode::CannotArchiveCurrentTask,
            "cannot archive the calling task",
        ),
        (
            request(READ_TASK_TOOL_NAME, vec![integer_argument("limit", 0)]),
            HarnessErrorCode::InvalidArguments,
            "argument 'limit' must be between 1 and 100",
        ),
        (
            request(READ_TASK_TOOL_NAME, vec![integer_argument("limit", 101)]),
            HarnessErrorCode::InvalidArguments,
            "argument 'limit' must be between 1 and 100",
        ),
    ];

    for (request, code, message) in cases {
        assert_eq!(
            parse_invocation(&request),
            Err(HarnessError::new(code, message))
        );
    }
}

#[test]
fn every_success_projection_has_stable_json() {
    let cases = [
        (
            HarnessSuccess::ForkTask(ForkTaskSuccess {
                task_id: TaskId("child".to_owned()),
            }),
            r#"{"status":"active","task_id":"child"}"#,
        ),
        (
            HarnessSuccess::ReadTask(read_success(TaskProjectionStatus::Active)),
            r#"{"cursor_node_id":4,"history":{"has_more":true,"next_after_node_id":4,"nodes":[{"created_at":10,"kind":"message","node_id":4,"parent_node_id":null,"role":"user","text":"hello"}]},"parent_task_id":"parent","queued_message_count":2,"state_version":7,"status":"active","task_id":"task-1"}"#,
        ),
        (
            HarnessSuccess::SendMessageToTask(SendMessageToTaskSuccess {
                task_id: TaskId("task-2".to_owned()),
                disposition: MessageDisposition::Committed {
                    node_id: HistoryNodeId(8),
                },
            }),
            r#"{"disposition":"committed","node_id":8,"task_id":"task-2"}"#,
        ),
        (
            HarnessSuccess::SendMessageToTask(SendMessageToTaskSuccess {
                task_id: TaskId("task-2".to_owned()),
                disposition: MessageDisposition::Queued,
            }),
            r#"{"disposition":"queued","task_id":"task-2"}"#,
        ),
        (
            HarnessSuccess::ArchiveTask(ArchiveTaskSuccess {
                task_id: TaskId("task-2".to_owned()),
            }),
            r#"{"status":"archived","task_id":"task-2"}"#,
        ),
    ];

    for (success, expected) in cases {
        assert_eq!(success.to_stable_json(), expected);
    }
}

#[test]
fn read_history_encodes_each_existing_history_body_shape() {
    let success = HarnessSuccess::ReadTask(ReadTaskSuccess {
        history: HistoryPage {
            nodes: vec![
                history_node(
                    1,
                    HistoryNodeProjectionBody::Reasoning {
                        text: "thinking".to_owned(),
                    },
                ),
                history_node(
                    2,
                    HistoryNodeProjectionBody::FunctionCall {
                        function_call_id: FunctionCallId("call-1".to_owned()),
                        tool_name: ToolName("read_task".to_owned()),
                        arguments: vec![
                            string_argument("task_id", "task-2"),
                            integer_argument("limit", 10),
                        ],
                    },
                ),
                history_node(
                    3,
                    HistoryNodeProjectionBody::FunctionOutput {
                        function_call_node_id: HistoryNodeId(2),
                        function_call_id: FunctionCallId("call-1".to_owned()),
                        tool_name: ToolName("read_task".to_owned()),
                        output_text: "{}".to_owned(),
                        is_error: false,
                    },
                ),
            ],
            next_after_node_id: None,
            has_more: false,
        },
        ..read_success(TaskProjectionStatus::Archived)
    });

    assert_eq!(
        success.to_stable_json(),
        r#"{"cursor_node_id":4,"history":{"has_more":false,"next_after_node_id":null,"nodes":[{"created_at":10,"kind":"reasoning","node_id":1,"parent_node_id":null,"text":"thinking"},{"arguments":[{"name":"task_id","value":"task-2"},{"name":"limit","value":10}],"created_at":10,"function_call_id":"call-1","kind":"function_call","node_id":2,"parent_node_id":null,"tool_name":"read_task"},{"created_at":10,"function_call_id":"call-1","function_call_node_id":2,"is_error":false,"kind":"function_output","node_id":3,"output_text":"{}","parent_node_id":null,"tool_name":"read_task"}]},"parent_task_id":"parent","queued_message_count":2,"state_version":7,"status":"archived","task_id":"task-1"}"#
    );
}

#[test]
fn every_error_code_uses_the_unified_stable_envelope() {
    let codes = [
        HarnessErrorCode::InvalidArguments,
        HarnessErrorCode::UnknownTool,
        HarnessErrorCode::TaskNotFound,
        HarnessErrorCode::TaskArchived,
        HarnessErrorCode::StaleToolCall,
        HarnessErrorCode::HistoryCursorNotOnTask,
        HarnessErrorCode::CannotArchiveCurrentTask,
        HarnessErrorCode::OperationCancelled,
        HarnessErrorCode::RouterUnavailable,
        HarnessErrorCode::RuntimeStartFailed,
        HarnessErrorCode::StorageError,
        HarnessErrorCode::ExecutorPanicked,
    ];

    for code in codes {
        let error = HarnessError::new(code, "failure");
        assert_eq!(
            error.to_stable_json(),
            format!(
                r#"{{"error":{{"code":"{}","message":"failure"}}}}"#,
                code.as_str()
            )
        );
    }
}

#[test]
fn runtime_start_failure_after_child_commit_preserves_the_child_identity() {
    let request = request(FORK_TASK_TOOL_NAME, Vec::new());
    let child_task_id = TaskId("child".to_owned());
    let error = HarnessError::runtime_start_failed_after_child_created(
        child_task_id.clone(),
        "runtime did not start",
    );

    assert_eq!(error.code(), HarnessErrorCode::RuntimeStartFailed);
    assert_eq!(error.created_child_task_id(), Some(&child_task_id));

    let result = encode_tool_execution_result(&request, Err(error));

    assert!(result.is_error);
    assert_eq!(result.task_id, request.task_id);
    assert_eq!(result.function_call_id, request.function_call_id);
    assert_eq!(
        result.output_text,
        r#"{"error":{"code":"runtime_start_failed","message":"runtime did not start","task_created":true,"task_id":"child"}}"#
    );
}

#[test]
fn tool_result_encoding_preserves_all_request_correlation_and_error_state() {
    let request = request(FORK_TASK_TOOL_NAME, Vec::new());
    let success = encode_tool_execution_result(
        &request,
        Ok(HarnessSuccess::ForkTask(ForkTaskSuccess {
            task_id: TaskId("child".to_owned()),
        })),
    );
    let failure = encode_tool_execution_result(
        &request,
        Err(HarnessError::new(
            HarnessErrorCode::RuntimeStartFailed,
            "runtime did not start",
        )),
    );

    for result in [&success, &failure] {
        assert_eq!(result.task_id, request.task_id);
        assert_eq!(result.tool_execution_run_id, request.tool_execution_run_id);
        assert_eq!(result.function_call_node_id, request.function_call_node_id);
        assert_eq!(result.function_call_id, request.function_call_id);
        assert_eq!(result.tool_name, request.tool_name);
    }
    assert!(!success.is_error);
    assert_eq!(
        success.output_text,
        r#"{"status":"active","task_id":"child"}"#
    );
    assert!(failure.is_error);
    assert_eq!(
        failure.output_text,
        r#"{"error":{"code":"runtime_start_failed","message":"runtime did not start"}}"#
    );
}

fn request(tool_name: &str, arguments: Vec<ToolCallArgument>) -> ToolExecutionRequest {
    ToolExecutionRequest {
        task_id: TaskId("task-1".to_owned()),
        tool_execution_run_id: ToolExecutionRunId("execution-1".to_owned()),
        function_call_node_id: HistoryNodeId(9),
        function_call_id: FunctionCallId("call-1".to_owned()),
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

fn integer_argument(name: &str, value: i64) -> ToolCallArgument {
    ToolCallArgument {
        name: ToolParameterName(name.to_owned()),
        value: ToolArgumentValue::Integer(value),
    }
}

fn string_parameter(name: &str, description: &str, required: bool) -> ToolParameter {
    ToolParameter {
        name: name.to_owned(),
        parameter_type: ToolParameterType::String,
        description: description.to_owned(),
        required,
    }
}

fn integer_parameter(name: &str, description: &str, required: bool) -> ToolParameter {
    ToolParameter {
        name: name.to_owned(),
        parameter_type: ToolParameterType::Integer,
        description: description.to_owned(),
        required,
    }
}

fn read_success(status: TaskProjectionStatus) -> ReadTaskSuccess {
    ReadTaskSuccess {
        task_id: TaskId("task-1".to_owned()),
        status,
        state_version: 7,
        cursor_node_id: HistoryNodeId(4),
        parent_task_id: Some(TaskId("parent".to_owned())),
        queued_message_count: 2,
        history: HistoryPage {
            nodes: vec![history_node(
                4,
                HistoryNodeProjectionBody::Message {
                    role: MessageRole::User,
                    text: "hello".to_owned(),
                },
            )],
            next_after_node_id: Some(HistoryNodeId(4)),
            has_more: true,
        },
    }
}

fn history_node(node_id: i64, body: HistoryNodeProjectionBody) -> HistoryNodeProjection {
    HistoryNodeProjection {
        node_id: HistoryNodeId(node_id),
        parent_node_id: None,
        created_at: UnixTs(10),
        body,
    }
}
