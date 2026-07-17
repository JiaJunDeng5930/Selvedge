use selvedge_command_model::{
    HistoryNodeProjection, HistoryNodeProjectionBody, TaskProjectionStatus, ToolExecutionRequest,
    ToolExecutionRunId,
};
use selvedge_domain_model::{
    FunctionCallId, HistoryNodeId, JsonObject, MessageRole, TaskId, ToolName, ToolSpec, UnixTs,
};
use selvedge_harness::{
    ARCHIVE_TASK_TOOL_NAME, ArchiveTaskInvocation, ArchiveTaskSuccess, BASH_TOOL_NAME,
    BashInvocation, BashSuccess, DEFAULT_BASH_TIMEOUT_MS, FORK_TASK_TOOL_NAME, ForkTaskInvocation,
    ForkTaskSuccess, HarnessError, HarnessErrorCode, HarnessInvocation, HarnessSuccess,
    HistoryPage, MAX_BASH_TIMEOUT_MS, MIN_BASH_TIMEOUT_MS, MessageDisposition, READ_TASK_TOOL_NAME,
    ReadTaskInvocation, ReadTaskSuccess, SEND_MESSAGE_TO_TASK_TOOL_NAME,
    SendMessageToTaskInvocation, SendMessageToTaskSuccess, encode_tool_execution_result,
    parse_invocation, tool_manifest,
};
use serde_json::Value;

#[test]
fn manifest_defines_exactly_the_five_harness_tools() {
    assert_eq!(
        tool_manifest().tools,
        vec![
            ToolSpec {
                name: "fork_task".to_owned(),
                description:
                    "Create an active child task from the calling task and give it an initial prompt."
                        .to_owned(),
                input_schema: input_schema(
                    [(
                        "prompt",
                        string_property("Initial prompt for the child task."),
                    )],
                    &["prompt"],
                ),
            },
            ToolSpec {
                name: "read_task".to_owned(),
                description:
                    "Read task state and a page of history. Omit task_id to read the calling task."
                        .to_owned(),
                input_schema: input_schema(
                    [
                        (
                            "task_id",
                            string_property(
                                "Task to read; omit it to read the calling task.",
                            ),
                        ),
                        (
                            "after_node_id",
                            integer_property("Return history nodes after this node ID."),
                        ),
                        (
                            "limit",
                            integer_property(
                                "Maximum history nodes to return, from 1 through 100.",
                            ),
                        ),
                    ],
                    &[],
                ),
            },
            ToolSpec {
                name: "send_message_to_task".to_owned(),
                description:
                    "Send a message to an active task and report whether it was committed or queued."
                        .to_owned(),
                input_schema: input_schema(
                    [
                        (
                            "task_id",
                            string_property("Task that should receive the message."),
                        ),
                        ("message", string_property("Message to send to the task.")),
                    ],
                    &["message", "task_id"],
                ),
            },
            ToolSpec {
                name: "archive_task".to_owned(),
                description: "Archive another active task.".to_owned(),
                input_schema: input_schema(
                    [("task_id", string_property("Task to archive."))],
                    &["task_id"],
                ),
            },
            ToolSpec {
                name: "bash".to_owned(),
                description:
                    "Run a non-interactive Bash login command in the server process environment and working directory. Stdout and stderr are each capped at 65536 bytes."
                        .to_owned(),
                input_schema: input_schema(
                    [
                        ("command", string_property("Bash command to run.")),
                        (
                            "timeout_ms",
                            integer_property(
                                "Timeout in milliseconds; defaults to 30000, from 100 through 120000.",
                            ),
                        ),
                    ],
                    &["command"],
                ),
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
                READ_TASK_TOOL_NAME,
                vec![json_number_argument("after_node_id", "9007199254740993.0")],
            ),
            HarnessInvocation::ReadTask(ReadTaskInvocation {
                task_id: None,
                after_node_id: Some(HistoryNodeId(9_007_199_254_740_993)),
                limit: None,
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
        (
            request(
                BASH_TOOL_NAME,
                vec![string_argument("command", "printf hello")],
            ),
            HarnessInvocation::Bash(BashInvocation {
                command: "printf hello".to_owned(),
                timeout_ms: DEFAULT_BASH_TIMEOUT_MS as u64,
            }),
        ),
        (
            request(
                BASH_TOOL_NAME,
                vec![
                    string_argument("command", "true"),
                    integer_argument("timeout_ms", MIN_BASH_TIMEOUT_MS),
                ],
            ),
            HarnessInvocation::Bash(BashInvocation {
                command: "true".to_owned(),
                timeout_ms: MIN_BASH_TIMEOUT_MS as u64,
            }),
        ),
        (
            request(
                BASH_TOOL_NAME,
                vec![
                    string_argument("command", "true"),
                    integer_argument("timeout_ms", MAX_BASH_TIMEOUT_MS),
                ],
            ),
            HarnessInvocation::Bash(BashInvocation {
                command: "true".to_owned(),
                timeout_ms: MAX_BASH_TIMEOUT_MS as u64,
            }),
        ),
        (
            request(
                BASH_TOOL_NAME,
                vec![
                    string_argument("command", "true"),
                    json_number_argument("timeout_ms", "100.0"),
                ],
            ),
            HarnessInvocation::Bash(BashInvocation {
                command: "true".to_owned(),
                timeout_ms: 100,
            }),
        ),
        (
            request(
                BASH_TOOL_NAME,
                vec![
                    string_argument("command", "true"),
                    json_number_argument("timeout_ms", "1e2"),
                ],
            ),
            HarnessInvocation::Bash(BashInvocation {
                command: "true".to_owned(),
                timeout_ms: 100,
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
        (
            request(
                READ_TASK_TOOL_NAME,
                vec![json_number_argument("after_node_id", "1.5")],
            ),
            HarnessErrorCode::InvalidArguments,
            "argument 'after_node_id' must be an integer",
        ),
        (
            request(
                READ_TASK_TOOL_NAME,
                vec![json_number_argument("after_node_id", "9223372036854775808")],
            ),
            HarnessErrorCode::InvalidArguments,
            "argument 'after_node_id' must be an integer",
        ),
        (
            request(BASH_TOOL_NAME, Vec::new()),
            HarnessErrorCode::InvalidArguments,
            "missing required argument 'command'",
        ),
        (
            request(BASH_TOOL_NAME, vec![string_argument("extra", "value")]),
            HarnessErrorCode::InvalidArguments,
            "unexpected argument 'extra'",
        ),
        (
            request(BASH_TOOL_NAME, vec![string_argument("command", "  ")]),
            HarnessErrorCode::InvalidArguments,
            "argument 'command' must not be empty",
        ),
        (
            request(
                BASH_TOOL_NAME,
                vec![
                    string_argument("command", "true"),
                    string_argument("timeout_ms", "1000"),
                ],
            ),
            HarnessErrorCode::InvalidArguments,
            "argument 'timeout_ms' must be an integer",
        ),
        (
            request(
                BASH_TOOL_NAME,
                vec![
                    string_argument("command", "true"),
                    integer_argument("timeout_ms", MIN_BASH_TIMEOUT_MS - 1),
                ],
            ),
            HarnessErrorCode::InvalidArguments,
            "argument 'timeout_ms' must be between 100 and 120000",
        ),
        (
            request(
                BASH_TOOL_NAME,
                vec![
                    string_argument("command", "true"),
                    integer_argument("timeout_ms", MAX_BASH_TIMEOUT_MS + 1),
                ],
            ),
            HarnessErrorCode::InvalidArguments,
            "argument 'timeout_ms' must be between 100 and 120000",
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
        (
            HarnessSuccess::Bash(BashSuccess {
                exit_code: Some(7),
                stdout: "out".to_owned(),
                stderr: "err".to_owned(),
                stdout_truncated: true,
                stderr_truncated: false,
            }),
            r#"{"exit_code":7,"stderr":"err","stderr_truncated":false,"stdout":"out","stdout_truncated":true}"#,
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
                        arguments: argument_object(vec![
                            string_argument("task_id", "task-2"),
                            integer_argument("limit", 10),
                            (
                                "options".to_owned(),
                                Value::Object(JsonObject::from_iter([(
                                    "include".to_owned(),
                                    Value::Array(vec![
                                        Value::String("reasoning".to_owned()),
                                        Value::Null,
                                    ]),
                                )])),
                            ),
                        ]),
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
        r#"{"cursor_node_id":4,"history":{"has_more":false,"next_after_node_id":null,"nodes":[{"created_at":10,"kind":"reasoning","node_id":1,"parent_node_id":null,"text":"thinking"},{"arguments":{"limit":10,"options":{"include":["reasoning",null]},"task_id":"task-2"},"created_at":10,"function_call_id":"call-1","kind":"function_call","node_id":2,"parent_node_id":null,"tool_name":"read_task"},{"created_at":10,"function_call_id":"call-1","function_call_node_id":2,"is_error":false,"kind":"function_output","node_id":3,"output_text":"{}","parent_node_id":null,"tool_name":"read_task"}]},"parent_task_id":"parent","queued_message_count":2,"state_version":7,"status":"archived","task_id":"task-1"}"#
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
        HarnessErrorCode::CommandSpawnFailed,
        HarnessErrorCode::CommandIoFailed,
        HarnessErrorCode::CommandWaitFailed,
        HarnessErrorCode::CommandTimedOut,
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

fn request(tool_name: &str, arguments: Vec<(String, Value)>) -> ToolExecutionRequest {
    ToolExecutionRequest {
        task_id: TaskId("task-1".to_owned()),
        tool_execution_run_id: ToolExecutionRunId("execution-1".to_owned()),
        function_call_node_id: HistoryNodeId(9),
        function_call_id: FunctionCallId("call-1".to_owned()),
        tool_name: ToolName(tool_name.to_owned()),
        arguments: argument_object(arguments),
    }
}

fn argument_object(entries: Vec<(String, Value)>) -> JsonObject {
    entries.into_iter().collect()
}

fn string_argument(name: &str, value: &str) -> (String, Value) {
    (name.to_owned(), Value::String(value.to_owned()))
}

fn integer_argument(name: &str, value: i64) -> (String, Value) {
    (name.to_owned(), Value::from(value))
}

fn json_number_argument(name: &str, value: &str) -> (String, Value) {
    let value = serde_json::from_str(value).expect("parse JSON number");
    assert!(matches!(value, Value::Number(_)));
    (name.to_owned(), value)
}

fn input_schema<const N: usize>(properties: [(&str, Value); N], required: &[&str]) -> JsonObject {
    JsonObject::from_iter([
        ("type".to_owned(), Value::String("object".to_owned())),
        (
            "properties".to_owned(),
            Value::Object(
                properties
                    .into_iter()
                    .map(|(name, schema)| (name.to_owned(), schema))
                    .collect(),
            ),
        ),
        (
            "required".to_owned(),
            Value::Array(
                required
                    .iter()
                    .map(|name| Value::String((*name).to_owned()))
                    .collect(),
            ),
        ),
        ("additionalProperties".to_owned(), Value::Bool(false)),
    ])
}

fn string_property(description: &str) -> Value {
    Value::Object(JsonObject::from_iter([
        ("type".to_owned(), Value::String("string".to_owned())),
        (
            "description".to_owned(),
            Value::String(description.to_owned()),
        ),
    ]))
}

fn integer_property(description: &str) -> Value {
    Value::Object(JsonObject::from_iter([
        ("type".to_owned(), Value::String("integer".to_owned())),
        (
            "description".to_owned(),
            Value::String(description.to_owned()),
        ),
    ]))
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
