use super::*;
use selvedge_domain_model::{FunctionCallId, ToolName, UnixTs};

#[test]
fn every_success_projection_has_stable_json() {
    let cases = [
        (
            HarnessSuccess::ReadTask(read_success(TaskStatus::Active)),
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
        assert_eq!(success_json(&success).to_string(), expected);
    }
}

#[test]
fn read_task_encodes_each_durable_status() {
    for (status, expected) in [
        (TaskStatus::Active, "active"),
        (TaskStatus::Frozen, "frozen"),
        (TaskStatus::Stopped, "stopped"),
        (TaskStatus::Archived, "archived"),
    ] {
        let json = success_json(&HarnessSuccess::ReadTask(read_success(status))).to_string();
        assert_eq!(
            serde_json::from_str::<Value>(&json)
                .expect("valid success JSON")
                .get("status"),
            Some(&Value::String(expected.to_owned()))
        );
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
                        arguments: JsonObject::from_iter(vec![
                            ("task_id".to_owned(), Value::from("task-2")),
                            ("limit".to_owned(), Value::from(10)),
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
                        output: serde_json::json!({"ok": true}),
                        is_error: false,
                    },
                ),
            ],
            next_after_node_id: None,
            has_more: false,
        },
        ..read_success(TaskStatus::Archived)
    });

    assert_eq!(
        success_json(&success).to_string(),
        r#"{"cursor_node_id":4,"history":{"has_more":false,"next_after_node_id":null,"nodes":[{"created_at":10,"kind":"reasoning","node_id":1,"parent_node_id":null,"text":"thinking"},{"arguments":{"limit":10,"options":{"include":["reasoning",null]},"task_id":"task-2"},"created_at":10,"function_call_id":"call-1","kind":"function_call","node_id":2,"parent_node_id":null,"tool_name":"read_task"},{"created_at":10,"function_call_id":"call-1","function_call_node_id":2,"is_error":false,"kind":"function_output","node_id":3,"output":{"ok":true},"parent_node_id":null,"tool_name":"read_task"}]},"parent_task_id":"parent","queued_message_count":2,"state_version":7,"status":"archived","task_id":"task-1"}"#
    );
}

fn read_success(status: TaskStatus) -> ReadTaskSuccess {
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
