use super::*;
use selvedge_command_model::{ToolExecutionRequest, ToolExecutionRunId};
use selvedge_config_model::HarnessConfig;
use selvedge_db::ToolRecoveryPolicy;
use selvedge_domain_model::{FunctionCallId, HistoryNodeId, JsonObject, TaskId, ToolName};
use serde_json::Value;

#[test]
fn manifest_defines_closed_schemas_with_required_typed_properties() {
    let manifest = harness_tool_catalog(&HarnessConfig::default());
    let expected = [
        (
            "fork_task",
            vec!["child_count"],
            vec![
                ("child_count", "integer"),
                ("environment", "string"),
                ("messages", "array"),
            ],
        ),
        (
            "read_task",
            vec![],
            vec![
                ("after_node_id", "integer"),
                ("limit", "integer"),
                ("task_id", "string"),
            ],
        ),
        (
            "send_message_to_task",
            vec!["message", "task_id"],
            vec![("message", "string"), ("task_id", "string")],
        ),
        ("archive_task", vec!["task_id"], vec![("task_id", "string")]),
        (
            "bash",
            vec!["command"],
            vec![("command", "string"), ("timeout_ms", "integer")],
        ),
        ("exec_cmd", vec!["code"], vec![("code", "string")]),
    ];
    assert_eq!(manifest.len(), expected.len());
    for (tool, (name, required, properties)) in manifest.iter().zip(expected) {
        let tool = &tool.tool;
        assert_eq!(tool.name, name);
        assert!(!tool.description.trim().is_empty());
        let schema = &tool.input_schema;
        assert_eq!(schema["type"], "object");
        assert_eq!(schema["additionalProperties"], false);
        assert_eq!(schema["required"], serde_json::json!(required));
        let actual = schema["properties"].as_object().expect("property map");
        assert_eq!(actual.len(), properties.len());
        for (key, kind) in properties {
            assert_eq!(actual[key]["type"], kind);
            assert!(
                !actual[key]["description"]
                    .as_str()
                    .expect("description")
                    .trim()
                    .is_empty()
            );
        }
    }
    let fork = &manifest[0].tool.input_schema["properties"];
    assert_eq!(fork["child_count"]["minimum"], 1);
    assert_eq!(fork["child_count"]["maximum"], 5);
    assert_eq!(fork["messages"]["items"]["type"], "string");
    assert_eq!(fork["messages"]["minItems"], 1);
    assert_eq!(fork["messages"]["maxItems"], 5);
    let read = &manifest[1].tool.input_schema["properties"]["limit"];
    assert_eq!(read["minimum"], 1);
    assert_eq!(read["maximum"], 100);
    let bash = &manifest[4].tool.input_schema["properties"]["timeout_ms"];
    assert_eq!(bash["minimum"], 100);
    assert_eq!(bash["maximum"], 120000);
}

#[test]
fn catalog_freezes_builtin_recovery_policies() {
    let policies = harness_tool_catalog(&HarnessConfig::default())
        .into_iter()
        .map(|tool| (tool.tool.name, tool.recovery_policy))
        .collect::<std::collections::BTreeMap<_, _>>();

    assert_eq!(
        policies,
        std::collections::BTreeMap::from([
            (EXEC_CMD_TOOL_NAME.to_owned(), ToolRecoveryPolicy::RetrySafe),
            (
                ARCHIVE_TASK_TOOL_NAME.to_owned(),
                ToolRecoveryPolicy::OutcomeUnknown
            ),
            (
                BASH_TOOL_NAME.to_owned(),
                ToolRecoveryPolicy::OutcomeUnknown
            ),
            (
                FORK_TASK_TOOL_NAME.to_owned(),
                ToolRecoveryPolicy::RetrySafe
            ),
            (
                READ_TASK_TOOL_NAME.to_owned(),
                ToolRecoveryPolicy::RetrySafe
            ),
            (
                SEND_MESSAGE_TO_TASK_TOOL_NAME.to_owned(),
                ToolRecoveryPolicy::OutcomeUnknown,
            ),
        ])
    );
}

#[test]
fn valid_requests_parse_to_typed_invocations() {
    let cases = [
        (
            request(
                FORK_TASK_TOOL_NAME,
                vec![
                    integer_argument("child_count", 2),
                    string_array_argument("messages", &["investigate", "review"]),
                ],
            ),
            HarnessInvocation::ForkTask(ForkTaskInvocation {
                environment: selvedge_domain_model::CommandEnvironmentMode::Shared,
                child_count: 2,
                messages: Some(vec!["investigate".to_owned(), "review".to_owned()]),
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
        assert_eq!(
            parse_invocation(&request, &HarnessConfig::default()),
            Ok(expected)
        );
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
            "missing required argument 'child_count'",
        ),
        (
            request(FORK_TASK_TOOL_NAME, vec![string_argument("extra", "value")]),
            HarnessErrorCode::InvalidArguments,
            "unexpected argument 'extra'",
        ),
        (
            request(
                FORK_TASK_TOOL_NAME,
                vec![string_argument("child_count", "1")],
            ),
            HarnessErrorCode::InvalidArguments,
            "argument 'child_count' must be an integer",
        ),
        (
            request(
                FORK_TASK_TOOL_NAME,
                vec![integer_argument("child_count", 0)],
            ),
            HarnessErrorCode::InvalidArguments,
            "argument 'child_count' must be between 1 and 5",
        ),
        (
            request(
                FORK_TASK_TOOL_NAME,
                vec![integer_argument("child_count", 6)],
            ),
            HarnessErrorCode::InvalidArguments,
            "argument 'child_count' must be between 1 and 5",
        ),
        (
            request(
                FORK_TASK_TOOL_NAME,
                vec![
                    integer_argument("child_count", 2),
                    string_array_argument("messages", &["only one"]),
                ],
            ),
            HarnessErrorCode::InvalidArguments,
            "argument 'messages' length must equal 'child_count'",
        ),
        (
            request(
                FORK_TASK_TOOL_NAME,
                vec![
                    integer_argument("child_count", 1),
                    ("messages".to_owned(), Value::Array(vec![Value::from(1)])),
                ],
            ),
            HarnessErrorCode::InvalidArguments,
            "argument 'messages' must be an array of strings",
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
            parse_invocation(&request, &HarnessConfig::default()),
            Err(HarnessError::new(code, message))
        );
    }
}

#[test]
fn errors_use_the_stable_envelope() {
    assert_eq!(
        error_json(&HarnessError::new(
            HarnessErrorCode::InvalidArguments,
            "failure"
        ))
        .to_string(),
        r#"{"error":{"code":"invalid_arguments","message":"failure"}}"#
    );
}

#[test]
fn error_codes_keep_their_wire_names() {
    let samples = [
        (HarnessErrorCode::InvalidArguments, "invalid_arguments"),
        (HarnessErrorCode::UnknownTool, "unknown_tool"),
        (HarnessErrorCode::TaskNotFound, "task_not_found"),
        (HarnessErrorCode::TaskArchived, "task_archived"),
        (
            HarnessErrorCode::HistoryCursorNotOnTask,
            "history_cursor_not_on_task",
        ),
        (
            HarnessErrorCode::CannotArchiveCurrentTask,
            "cannot_archive_current_task",
        ),
        (HarnessErrorCode::OperationCancelled, "operation_cancelled"),
        (HarnessErrorCode::RouterUnavailable, "router_unavailable"),
        (HarnessErrorCode::StorageError, "storage_error"),
        (HarnessErrorCode::ResourceExhausted, "resource_exhausted"),
        (HarnessErrorCode::ExecutorPanicked, "executor_panicked"),
        (HarnessErrorCode::CommandSpawnFailed, "command_spawn_failed"),
        (HarnessErrorCode::CommandIoFailed, "command_io_failed"),
        (HarnessErrorCode::CommandWaitFailed, "command_wait_failed"),
        (HarnessErrorCode::CommandTimedOut, "command_timed_out"),
        (
            HarnessErrorCode::McpRouteUnavailable,
            "mcp_route_unavailable",
        ),
        (HarnessErrorCode::ToolUnavailable, "tool_unavailable"),
        (HarnessErrorCode::McpCallFailed, "mcp_call_failed"),
        (HarnessErrorCode::McpCallTimedOut, "mcp_call_timed_out"),
        (
            HarnessErrorCode::McpResultEncodingFailed,
            "mcp_result_encoding_failed",
        ),
    ];
    for (code, expected) in samples {
        assert_eq!(code.as_str(), expected);
    }
}

fn request(tool_name: &str, arguments: Vec<(String, Value)>) -> ToolExecutionRequest {
    ToolExecutionRequest {
        execution_mode: selvedge_domain_model::ToolExecutionMode::Normal,
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

fn string_array_argument(name: &str, values: &[&str]) -> (String, Value) {
    (
        name.to_owned(),
        Value::Array(
            values
                .iter()
                .map(|value| Value::String((*value).to_owned()))
                .collect(),
        ),
    )
}

fn json_number_argument(name: &str, value: &str) -> (String, Value) {
    let value = serde_json::from_str(value).expect("parse JSON number");
    assert!(matches!(value, Value::Number(_)));
    (name.to_owned(), value)
}
