use selvedge_db::{
    CommitToolResultBranchesInput, CreateRootTaskInput, DbError, DbPool, FunctionCallId,
    HistoryNode, HistoryNodeId, JsonObject, McpToolRegistration, MessageRole, ModelProfileKey,
    NewFunctionCallNodeContent, NewFunctionOutputNodeContent, NewHistoryNode,
    NewHistoryNodeContent, NewMessageNodeContent, OpenDbOptions, ReadTaskInput, ReasoningEffort,
    TaskId, TaskStatusRow, ToolExecutionSource, ToolManifest, ToolName, ToolResultBranch,
    ToolResultBranchTarget, ToolSpec, UnixTs, append_model_reply_with_tool_calls_and_move_cursor,
    append_user_message_and_move_cursor, archive_task, commit_tool_result_branches,
    create_history_node, create_root_task, load_active_task, open_db, queue_user_input,
    read_conversation_for_task, read_task, read_task_parent_edges, read_tool_execution_source,
    read_tool_manifest_for_task, register_global_tool, register_tool, replace_global_mcp_tools,
    unpublish_global_tool,
};
use serde_json::Value;

fn json_object(value: serde_json::Value) -> JsonObject {
    match value {
        serde_json::Value::Object(object) => object,
        _ => panic!("test JSON value must be an object"),
    }
}

fn create_message_node(
    db: &DbPool,
    parent_node_id: Option<HistoryNodeId>,
    message_role: MessageRole,
    message_text: &str,
    created_at: UnixTs,
) -> HistoryNodeId {
    create_history_node(
        db,
        NewHistoryNode {
            parent_node_id,
            content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                message_role,
                message_text: message_text.to_owned(),
            }),
            created_at,
        },
    )
    .expect("create history node")
}

fn create_task_without_tools(db: &DbPool, task_id: &str) -> TaskId {
    create_root_task(
        db,
        CreateRootTaskInput {
            task_id: TaskId(task_id.to_owned()),
            cursor_node_id: create_message_node(db, None, MessageRole::User, "run", UnixTs(10)),
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(10),
        },
    )
    .expect("create task")
    .task_id
}

fn tool_spec(name: &str, description: &str) -> ToolSpec {
    ToolSpec {
        name: name.to_owned(),
        description: description.to_owned(),
        input_schema: JsonObject::new(),
    }
}

fn mcp_registration(
    name: &str,
    description: &str,
    server_id: &str,
    remote_tool_name: &str,
) -> McpToolRegistration {
    McpToolRegistration {
        tool: tool_spec(name, description),
        server_id: server_id.to_owned(),
        remote_tool_name: remote_tool_name.to_owned(),
    }
}

fn function_call(call_id: &str, tool_name: &str) -> NewFunctionCallNodeContent {
    NewFunctionCallNodeContent {
        function_call_id: FunctionCallId(call_id.to_owned()),
        tool_name: ToolName(tool_name.to_owned()),
        arguments: JsonObject::new(),
    }
}

fn history_message_texts(nodes: &[HistoryNode]) -> Vec<&str> {
    nodes
        .iter()
        .filter_map(|node| match node {
            HistoryNode::Message { message_text, .. } => Some(message_text.as_str()),
            _ => None,
        })
        .collect()
}

fn fork_one_child(
    db: &DbPool,
    parent_task_id: &TaskId,
    call_id: &str,
    child_task_id: &str,
    now: i64,
) -> Result<(), DbError> {
    let call_node_id = append_model_reply_with_tool_calls_and_move_cursor(
        db,
        parent_task_id,
        None,
        vec![function_call(call_id, "fork_task")],
        UnixTs(now),
    )?[0];
    commit_tool_result_branches(
        db,
        CommitToolResultBranchesInput {
            calling_task_id: parent_task_id.clone(),
            function_call_node_id: call_node_id,
            function_call_id: FunctionCallId(call_id.to_owned()),
            tool_name: ToolName("fork_task".to_owned()),
            branches: vec![
                ToolResultBranch {
                    target: ToolResultBranchTarget::CallingTask,
                    output: Value::from(0),
                    is_error: false,
                    user_messages: Vec::new(),
                },
                ToolResultBranch {
                    target: ToolResultBranchTarget::NewChildTask(TaskId(child_task_id.to_owned())),
                    output: Value::from(1),
                    is_error: false,
                    user_messages: Vec::new(),
                },
            ],
            now: UnixTs(now + 1),
        },
    )?;
    Ok(())
}

#[test]
fn open_db_creates_schema_and_root_task_transaction_moves_cursor() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_task_descendants: 20,
    })
    .expect("open db");

    let task = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            cursor_node_id: create_message_node(&db, None, MessageRole::User, "hello", UnixTs(10)),
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(10),
        },
    )
    .expect("create root task");

    assert_eq!(task.task_status, TaskStatusRow::Active);
    assert_eq!(task.state_version, 0);

    let loaded = load_active_task(&db, &TaskId("task-1".to_owned())).expect("load active task");
    assert_eq!(loaded.task.cursor_node_id, task.cursor_node_id);
    assert!(matches!(loaded.cursor_node, HistoryNode::Message { .. }));
}

#[test]
fn descendant_limit_is_enforced_for_every_ancestor_in_the_commit_transaction() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_task_descendants: 2,
    })
    .expect("open db");
    register_global_tool(&db, tool_spec("fork_task", "Fork tasks")).expect("register fork tool");
    let root = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("root".to_owned()),
            cursor_node_id: create_message_node(&db, None, MessageRole::User, "root", UnixTs(10)),
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(10),
        },
    )
    .expect("create root");

    fork_one_child(&db, &root.task_id, "fork-root", "child", 11).expect("create child");
    let child = TaskId("child".to_owned());
    fork_one_child(&db, &child, "fork-child-1", "grandchild", 13)
        .expect("fill root descendant capacity");
    let edges_before = read_task_parent_edges(&db).expect("read edges");

    let error = fork_one_child(&db, &child, "fork-child-2", "rejected", 15)
        .expect_err("root limit must reject a nested fork");

    assert_eq!(
        error,
        DbError::TaskDescendantLimitExceeded {
            task_id: root.task_id,
            limit: 2,
        }
    );
    assert_eq!(
        read_task_parent_edges(&db).expect("read unchanged edges"),
        edges_before
    );
    assert!(matches!(
        load_active_task(&db, &TaskId("rejected".to_owned())),
        Err(DbError::NotFound)
    ));
}

#[test]
fn archive_task_clears_queued_inputs_before_status_update() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_task_descendants: 20,
    })
    .expect("open db");
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            cursor_node_id: create_message_node(&db, None, MessageRole::User, "hello", UnixTs(10)),
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(10),
        },
    )
    .expect("create root task");
    queue_user_input(
        &db,
        &TaskId("task-1".to_owned()),
        "queued".to_owned(),
        UnixTs(11),
    )
    .expect("queue input");

    archive_task(&db, &TaskId("task-1".to_owned()), UnixTs(12)).expect("archive task");
}

#[test]
fn append_history_uses_new_node_timestamp_for_task_updated_at() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_task_descendants: 20,
    })
    .expect("open db");
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            cursor_node_id: create_message_node(
                &db,
                None,
                MessageRole::User,
                "hello",
                UnixTs(4_102_444_800),
            ),
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(4_102_444_800),
        },
    )
    .expect("create root task");

    append_user_message_and_move_cursor(
        &db,
        &TaskId("task-1".to_owned()),
        "future append".to_owned(),
        UnixTs(4_102_444_801),
    )
    .expect("append history");
}

#[test]
fn append_history_uses_database_cursor_as_parent() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_task_descendants: 20,
    })
    .expect("open db");
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            cursor_node_id: create_message_node(&db, None, MessageRole::User, "hello", UnixTs(10)),
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(10),
        },
    )
    .expect("create root task");
    append_user_message_and_move_cursor(
        &db,
        &TaskId("task-1".to_owned()),
        "first append".to_owned(),
        UnixTs(11),
    )
    .expect("append once");

    append_user_message_and_move_cursor(
        &db,
        &TaskId("task-1".to_owned()),
        "stale append".to_owned(),
        UnixTs(12),
    )
    .expect("append uses database cursor");

    let conversation =
        read_conversation_for_task(&db, &TaskId("task-1".to_owned())).expect("conversation");
    let messages = conversation
        .messages
        .into_iter()
        .filter_map(|message| message.content.as_str().map(str::to_owned))
        .collect::<Vec<_>>();
    assert_eq!(messages, vec!["hello", "first append", "stale append"]);
}

#[test]
fn tool_result_commit_creates_sibling_branches_with_independent_cursors() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_task_descendants: 20,
    })
    .expect("open db");
    let global_fork_tool = tool_spec("fork_task", "Fork a child task");
    let task_tool = tool_spec("search", "Search local state");
    register_global_tool(&db, global_fork_tool.clone()).expect("register global tool");
    register_tool(&db, task_tool.clone()).expect("register task tool");

    let parent = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("parent".to_owned()),
            cursor_node_id: create_message_node(&db, None, MessageRole::User, "parent", UnixTs(10)),
            model_profile_key: ModelProfileKey("parent-profile".to_owned()),
            reasoning_effort: ReasoningEffort::High,
            enabled_tools: vec![ToolName("search".to_owned())],
            now: UnixTs(10),
        },
    )
    .expect("create parent");
    let call_node_ids = append_model_reply_with_tool_calls_and_move_cursor(
        &db,
        &parent.task_id,
        Some("I will split this work.".to_owned()),
        vec![
            function_call("search-1", "search"),
            function_call("fork-1", "fork_task"),
            function_call("search-2", "search"),
        ],
        UnixTs(11),
    )
    .expect("append batched calls");
    let branch_parent_node_id = call_node_ids[2];
    let sibling_task = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("sibling".to_owned()),
            cursor_node_id: branch_parent_node_id,
            model_profile_key: ModelProfileKey("sibling-profile".to_owned()),
            reasoning_effort: ReasoningEffort::Low,
            enabled_tools: Vec::new(),
            now: UnixTs(11),
        },
    )
    .expect("create task on the still-open sibling path");
    queue_user_input(
        &db,
        &parent.task_id,
        "queued caller message".to_owned(),
        UnixTs(12),
    )
    .expect("queue caller input");

    let commit = commit_tool_result_branches(
        &db,
        CommitToolResultBranchesInput {
            calling_task_id: parent.task_id.clone(),
            function_call_node_id: call_node_ids[1],
            function_call_id: FunctionCallId("fork-1".to_owned()),
            tool_name: ToolName("fork_task".to_owned()),
            branches: vec![
                ToolResultBranch {
                    target: ToolResultBranchTarget::CallingTask,
                    output: serde_json::json!({
                        "task_ids": ["child-with-message", "child-output-only"]
                    }),
                    is_error: false,
                    user_messages: vec!["caller branch message".to_owned()],
                },
                ToolResultBranch {
                    target: ToolResultBranchTarget::NewChildTask(TaskId(
                        "child-with-message".to_owned(),
                    )),
                    output: serde_json::json!({"task_id": "child-with-message"}),
                    is_error: false,
                    user_messages: vec!["Investigate the persistence slice.".to_owned()],
                },
                ToolResultBranch {
                    target: ToolResultBranchTarget::NewChildTask(TaskId(
                        "child-output-only".to_owned(),
                    )),
                    output: Value::Array(Vec::new()),
                    is_error: true,
                    user_messages: Vec::new(),
                },
            ],
            now: UnixTs(12),
        },
    )
    .expect("commit tool result branches");
    assert_eq!(
        commit.created_child_task_ids,
        vec![
            TaskId("child-with-message".to_owned()),
            TaskId("child-output-only".to_owned())
        ]
    );

    let child = load_active_task(&db, &TaskId("child-with-message".to_owned()))
        .expect("load child")
        .task;
    assert_eq!(child.model_profile_key, parent.model_profile_key);
    assert_eq!(child.reasoning_effort, ReasoningEffort::High);
    assert_eq!(child.state_version, 0);
    let child_manifest =
        read_tool_manifest_for_task(&db, &child.task_id).expect("read child manifest");
    assert_eq!(
        child_manifest,
        ToolManifest {
            tools: vec![global_fork_tool, task_tool],
        }
    );

    let child_read = read_task(
        &db,
        ReadTaskInput {
            task_id: child.task_id.clone(),
            after_node_id: None,
            limit: 100,
        },
    )
    .expect("read child");
    assert_eq!(child_read.parent_task_id, Some(parent.task_id.clone()));
    assert_eq!(child_read.queued_input_count, 0);
    assert_eq!(
        history_message_texts(&child_read.history_nodes),
        vec![
            "parent",
            "I will split this work.",
            "Investigate the persistence slice."
        ]
    );
    let child_output_index = child_read
        .history_nodes
        .iter()
        .position(|node| matches!(node, HistoryNode::FunctionOutput { .. }))
        .expect("child output node");
    assert_eq!(
        child_read.history_nodes[child_output_index - 1].node_id(),
        branch_parent_node_id
    );
    assert_eq!(
        child_read.history_nodes[child_output_index + 1].node_id(),
        child_read.cursor_node_id
    );

    let output_only = read_task(
        &db,
        ReadTaskInput {
            task_id: TaskId("child-output-only".to_owned()),
            after_node_id: None,
            limit: 100,
        },
    )
    .expect("read output-only child");
    assert!(matches!(
        output_only.history_nodes.last(),
        Some(HistoryNode::FunctionOutput {
            output: Value::Array(values),
            is_error: true,
            ..
        }) if values.is_empty()
    ));
    assert_eq!(
        output_only.cursor_node_id,
        output_only
            .history_nodes
            .last()
            .expect("output-only cursor node")
            .node_id()
    );
    let output_only_conversation =
        read_conversation_for_task(&db, &TaskId("child-output-only".to_owned()))
            .expect("read output-only conversation");
    let projected_output = output_only_conversation
        .messages
        .last()
        .expect("projected output");
    assert_eq!(projected_output.role, MessageRole::Tool);
    assert_eq!(
        projected_output.content,
        serde_json::json!({
            "type": "function_output",
            "function_call_id": "fork-1",
            "tool_name": "fork_task",
            "output": [],
            "is_error": true
        })
    );
    assert_eq!(
        projected_output
            .source_node_id
            .as_ref()
            .map(|id| id.0.clone()),
        Some(output_only.cursor_node_id.0.to_string())
    );

    let parent_read = read_task(
        &db,
        ReadTaskInput {
            task_id: parent.task_id.clone(),
            after_node_id: None,
            limit: 100,
        },
    )
    .expect("read caller");
    assert_eq!(
        history_message_texts(&parent_read.history_nodes),
        vec![
            "parent",
            "I will split this work.",
            "caller branch message",
            "queued caller message"
        ]
    );
    assert_eq!(parent_read.queued_input_count, 0);
    assert_eq!(
        parent_read.cursor_node_id,
        parent_read
            .history_nodes
            .last()
            .expect("caller cursor node")
            .node_id()
    );

    let edges = read_task_parent_edges(&db).expect("read parent edges");
    assert_eq!(edges.len(), 2);
    assert!(
        edges
            .iter()
            .all(|edge| edge.parent_task_id == parent.task_id)
    );

    let sibling_commit = commit_tool_result_branches(
        &db,
        CommitToolResultBranchesInput {
            calling_task_id: sibling_task.task_id.clone(),
            function_call_node_id: call_node_ids[1],
            function_call_id: FunctionCallId("fork-1".to_owned()),
            tool_name: ToolName("fork_task".to_owned()),
            branches: vec![ToolResultBranch {
                target: ToolResultBranchTarget::CallingTask,
                output: Value::from(0),
                is_error: false,
                user_messages: Vec::new(),
            }],
            now: UnixTs(13),
        },
    );
    assert!(
        sibling_commit.is_ok(),
        "an output on another sibling path must not close this task's call"
    );

    let duplicate_on_caller_path = create_history_node(
        &db,
        NewHistoryNode {
            parent_node_id: Some(parent_read.cursor_node_id),
            content: NewHistoryNodeContent::FunctionOutput(NewFunctionOutputNodeContent {
                function_call_node_id: call_node_ids[1],
                function_call_id: FunctionCallId("fork-1".to_owned()),
                tool_name: ToolName("fork_task".to_owned()),
                output: Value::from(1),
                is_error: false,
            }),
            created_at: UnixTs(14),
        },
    );
    assert!(
        matches!(duplicate_on_caller_path, Err(DbError::Constraint(_))),
        "the schema must reject a second output on the same history path"
    );
}

#[test]
fn create_history_node_accepts_strategy_parent_and_root_task_uses_existing_cursor() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_task_descendants: 20,
    })
    .expect("open db");
    let existing_node_id =
        create_message_node(&db, None, MessageRole::User, "existing", UnixTs(10));
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("existing".to_owned()),
            cursor_node_id: existing_node_id,
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(10),
        },
    )
    .expect("create existing");
    let root_node_id = create_message_node(
        &db,
        Some(existing_node_id),
        MessageRole::User,
        "root",
        UnixTs(11),
    );

    let root = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("root".to_owned()),
            cursor_node_id: root_node_id,
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(11),
        },
    )
    .expect("create root with strategy parent");

    let conversation =
        read_conversation_for_task(&db, &TaskId("root".to_owned())).expect("conversation");
    assert_eq!(root.task_id, TaskId("root".to_owned()));
    assert_eq!(conversation.messages.len(), 2);
}

#[test]
fn global_tool_registration_is_exactly_idempotent_and_merges_with_task_tools() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_task_descendants: 20,
    })
    .expect("open db");
    let task_tool = tool_spec("local_search", "Search this task");
    register_tool(&db, task_tool.clone()).expect("register task tool");
    let task = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task".to_owned()),
            cursor_node_id: create_message_node(&db, None, MessageRole::User, "hello", UnixTs(10)),
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: vec![ToolName("local_search".to_owned())],
            now: UnixTs(10),
        },
    )
    .expect("create task before global registration");

    let global_tool = ToolSpec {
        name: "read_task".to_owned(),
        description: "Read durable task state".to_owned(),
        input_schema: serde_json::json!({
            "type": "object",
            "properties": {
                "task_id": {
                    "type": "string",
                    "description": "Task identifier"
                }
            },
            "required": ["task_id"],
            "additionalProperties": false
        })
        .as_object()
        .expect("object schema")
        .clone(),
    };
    register_global_tool(&db, global_tool.clone()).expect("register global tool");
    register_global_tool(&db, global_tool.clone()).expect("repeat exact registration");

    assert_eq!(
        read_tool_manifest_for_task(&db, &task.task_id).expect("read merged manifest"),
        ToolManifest {
            tools: vec![task_tool, global_tool.clone()],
        }
    );

    let mut conflicting = global_tool.clone();
    conflicting.description = "Different durable semantics".to_owned();
    assert!(matches!(
        register_global_tool(&db, conflicting),
        Err(DbError::Constraint(_))
    ));
    assert_eq!(
        read_tool_manifest_for_task(&db, &task.task_id)
            .expect("conflict leaves original manifest")
            .tools[1],
        global_tool
    );

    let no_specific_tools = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("other".to_owned()),
            cursor_node_id: create_message_node(&db, None, MessageRole::User, "other", UnixTs(11)),
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(11),
        },
    )
    .expect("create task after global registration");
    assert_eq!(
        read_tool_manifest_for_task(&db, &no_specific_tools.task_id)
            .expect("read global-only manifest")
            .tools,
        vec![global_tool]
    );
}

#[test]
fn read_task_pages_active_and_archived_cursor_paths_and_rejects_invalid_bounds() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_task_descendants: 20,
    })
    .expect("open db");
    let root_node_id = create_message_node(&db, None, MessageRole::User, "root", UnixTs(10));
    let task = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task".to_owned()),
            cursor_node_id: root_node_id,
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(10),
        },
    )
    .expect("create task");
    let first =
        append_user_message_and_move_cursor(&db, &task.task_id, "first".to_owned(), UnixTs(11))
            .expect("append first");
    let second =
        append_user_message_and_move_cursor(&db, &task.task_id, "second".to_owned(), UnixTs(12))
            .expect("append second");
    queue_user_input(&db, &task.task_id, "queued".to_owned(), UnixTs(13)).expect("queue input");

    let first_page = read_task(
        &db,
        ReadTaskInput {
            task_id: task.task_id.clone(),
            after_node_id: None,
            limit: 2,
        },
    )
    .expect("read first page");
    assert_eq!(first_page.task_status, TaskStatusRow::Active);
    assert_eq!(first_page.state_version, 2);
    assert_eq!(first_page.cursor_node_id, second);
    assert_eq!(first_page.parent_task_id, None);
    assert_eq!(first_page.queued_input_count, 1);
    assert_eq!(
        history_message_texts(&first_page.history_nodes),
        vec!["root", "first"]
    );

    let second_page = read_task(
        &db,
        ReadTaskInput {
            task_id: task.task_id.clone(),
            after_node_id: Some(first),
            limit: 2,
        },
    )
    .expect("read second page");
    assert_eq!(
        history_message_texts(&second_page.history_nodes),
        vec!["second"]
    );
    assert!(
        read_task(
            &db,
            ReadTaskInput {
                task_id: task.task_id.clone(),
                after_node_id: Some(second),
                limit: 100,
            },
        )
        .expect("read after cursor")
        .history_nodes
        .is_empty()
    );

    let foreign_node_id = create_message_node(&db, None, MessageRole::User, "foreign", UnixTs(13));
    assert!(matches!(
        read_task(
            &db,
            ReadTaskInput {
                task_id: task.task_id.clone(),
                after_node_id: Some(foreign_node_id),
                limit: 1,
            },
        ),
        Err(DbError::HistoryCursorNotOnTask)
    ));
    assert!(matches!(
        read_task(
            &db,
            ReadTaskInput {
                task_id: task.task_id.clone(),
                after_node_id: None,
                limit: 101,
            },
        ),
        Err(DbError::Constraint(_))
    ));

    archive_task(&db, &task.task_id, UnixTs(14)).expect("archive task");
    let archived = read_task(
        &db,
        ReadTaskInput {
            task_id: task.task_id,
            after_node_id: Some(root_node_id),
            limit: 100,
        },
    )
    .expect("read archived task");
    assert_eq!(archived.task_status, TaskStatusRow::Archived);
    assert_eq!(archived.state_version, 3);
    assert_eq!(archived.queued_input_count, 0);
    assert_eq!(
        history_message_texts(&archived.history_nodes),
        vec!["first", "second"]
    );
}

#[test]
fn tool_result_branch_failure_rolls_back_tasks_edges_history_and_queue_drain() {
    let directory = tempfile::tempdir().expect("temp directory");
    let sqlite_path = directory.path().join("branch-atomicity.sqlite");
    let sqlite_path_text = sqlite_path.to_string_lossy().into_owned();
    let db = open_db(OpenDbOptions {
        sqlite_path: sqlite_path_text.clone(),
        max_task_descendants: 20,
    })
    .expect("open db");
    register_global_tool(&db, tool_spec("fork_task", "Fork a child task"))
        .expect("register fork tool");

    let parent = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("parent".to_owned()),
            cursor_node_id: create_message_node(&db, None, MessageRole::User, "parent", UnixTs(10)),
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(10),
        },
    )
    .expect("create parent");
    let call_node_id = append_model_reply_with_tool_calls_and_move_cursor(
        &db,
        &parent.task_id,
        None,
        vec![function_call("fork", "fork_task")],
        UnixTs(11),
    )
    .expect("append open fork call")[0];
    queue_user_input(
        &db,
        &parent.task_id,
        "must remain queued".to_owned(),
        UnixTs(12),
    )
    .expect("queue caller input");
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("occupied-child".to_owned()),
            cursor_node_id: create_message_node(
                &db,
                None,
                MessageRole::User,
                "occupied",
                UnixTs(12),
            ),
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(12),
        },
    )
    .expect("create occupied child id");

    let durable_counts = || {
        let connection = rusqlite::Connection::open(&sqlite_path_text).expect("open raw database");
        let tasks = connection
            .query_row("SELECT COUNT(*) FROM tasks", [], |row| row.get::<_, i64>(0))
            .expect("count tasks");
        let history = connection
            .query_row("SELECT COUNT(*) FROM history_nodes", [], |row| {
                row.get::<_, i64>(0)
            })
            .expect("count history");
        let edges = connection
            .query_row("SELECT COUNT(*) FROM task_parent_edges", [], |row| {
                row.get::<_, i64>(0)
            })
            .expect("count parent edges");
        let queued = connection
            .query_row("SELECT COUNT(*) FROM queued_user_inputs", [], |row| {
                row.get::<_, i64>(0)
            })
            .expect("count queued inputs");
        (tasks, history, edges, queued)
    };
    let before_failure = durable_counts();
    let cursor_before_failure = call_node_id;
    assert!(matches!(
        commit_tool_result_branches(
            &db,
            CommitToolResultBranchesInput {
                calling_task_id: parent.task_id.clone(),
                function_call_node_id: call_node_id,
                function_call_id: FunctionCallId("fork".to_owned()),
                tool_name: ToolName("fork_task".to_owned()),
                branches: vec![
                    ToolResultBranch {
                        target: ToolResultBranchTarget::CallingTask,
                        output: Value::Null,
                        is_error: false,
                        user_messages: Vec::new(),
                    },
                    ToolResultBranch {
                        target: ToolResultBranchTarget::NewChildTask(TaskId(
                            "new-child".to_owned(),
                        )),
                        output: Value::Bool(true),
                        is_error: false,
                        user_messages: vec!["new child".to_owned()],
                    },
                    ToolResultBranch {
                        target: ToolResultBranchTarget::NewChildTask(TaskId(
                            "occupied-child".to_owned(),
                        )),
                        output: Value::Bool(false),
                        is_error: true,
                        user_messages: Vec::new(),
                    },
                ],
                now: UnixTs(13),
            },
        ),
        Err(DbError::Constraint(_))
    ));
    assert_eq!(durable_counts(), before_failure);
    assert_eq!(
        load_active_task(&db, &parent.task_id)
            .expect("reload parent")
            .task
            .cursor_node_id,
        cursor_before_failure
    );
    assert!(matches!(
        read_task(
            &db,
            ReadTaskInput {
                task_id: TaskId("new-child".to_owned()),
                after_node_id: None,
                limit: 1,
            },
        ),
        Err(DbError::NotFound)
    ));
}

#[test]
fn global_unpublish_preserves_history_definition_and_harness_route() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_task_descendants: 20,
    })
    .expect("open db");
    let tool = ToolSpec {
        name: "nested_tool".to_owned(),
        description: "Accept nested JSON".to_owned(),
        input_schema: json_object(serde_json::json!({
            "type": "object",
            "properties": {
                "payload": {
                    "type": "object",
                    "properties": {
                        "values": { "type": "array" }
                    }
                }
            }
        })),
    };
    register_global_tool(&db, tool.clone()).expect("register global tool");
    let task = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task".to_owned()),
            cursor_node_id: create_message_node(&db, None, MessageRole::User, "run", UnixTs(10)),
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(10),
        },
    )
    .expect("create task");
    let arguments = json_object(serde_json::json!({
        "large": 9007199254740993_u64,
        "nested": {
            "values": [null, true, "text"]
        }
    }));
    append_model_reply_with_tool_calls_and_move_cursor(
        &db,
        &task.task_id,
        None,
        vec![NewFunctionCallNodeContent {
            function_call_id: FunctionCallId("call".to_owned()),
            tool_name: ToolName(tool.name.clone()),
            arguments: arguments.clone(),
        }],
        UnixTs(11),
    )
    .expect("persist function call");

    unpublish_global_tool(&db, &ToolName(tool.name.clone())).expect("unpublish tool");

    assert!(
        read_tool_manifest_for_task(&db, &task.task_id)
            .expect("read manifest after unpublish")
            .tools
            .is_empty()
    );
    assert_eq!(
        read_tool_execution_source(&db, &ToolName(tool.name.clone())).expect("read durable route"),
        ToolExecutionSource::Harness
    );
    let persisted_arguments = read_task(
        &db,
        ReadTaskInput {
            task_id: task.task_id,
            after_node_id: None,
            limit: 100,
        },
    )
    .expect("read history after unpublish")
    .history_nodes
    .into_iter()
    .find_map(|node| match node {
        HistoryNode::FunctionCall { arguments, .. } => Some(arguments),
        _ => None,
    })
    .expect("persisted function call");
    assert_eq!(persisted_arguments, arguments);

    register_global_tool(&db, tool.clone()).expect("republish exact durable definition");
    assert_eq!(
        read_tool_manifest_for_task(&db, &TaskId("task".to_owned()))
            .expect("read republished manifest")
            .tools,
        vec![tool]
    );
}

#[test]
fn execution_source_is_closed_and_harness_registration_cannot_claim_an_mcp_route() {
    let directory = tempfile::tempdir().expect("temp directory");
    let sqlite_path = directory.path().join("routes.sqlite");
    let db = open_db(OpenDbOptions {
        sqlite_path: sqlite_path.to_string_lossy().into_owned(),
        max_task_descendants: 20,
    })
    .expect("open db");
    let raw = rusqlite::Connection::open(&sqlite_path).expect("open raw database");
    assert!(
        raw.execute(
            "INSERT INTO tools
             (tool_name, description_text, input_schema_json, execution_source_kind,
              mcp_server_id, remote_tool_name, is_global)
             VALUES ('broken', 'Broken route', '{}', 'mcp', 'server', NULL, 0)",
            [],
        )
        .is_err()
    );
    raw.execute(
        "INSERT INTO tools
         (tool_name, description_text, input_schema_json, execution_source_kind,
          mcp_server_id, remote_tool_name, is_global)
         VALUES ('remote', 'Remote route', '{}', 'mcp', 'server', 'lookup', 0)",
        [],
    )
    .expect("insert complete MCP route");

    let tool_name = ToolName("remote".to_owned());
    assert_eq!(
        read_tool_execution_source(&db, &tool_name).expect("read MCP route"),
        ToolExecutionSource::Mcp {
            server_id: "server".to_owned(),
            remote_tool_name: "lookup".to_owned(),
        }
    );
    assert!(matches!(
        register_global_tool(&db, tool_spec("remote", "Remote route")),
        Err(DbError::Constraint(_))
    ));
    assert_eq!(
        read_tool_execution_source(&db, &tool_name).expect("route survives failed registration"),
        ToolExecutionSource::Mcp {
            server_id: "server".to_owned(),
            remote_tool_name: "lookup".to_owned(),
        }
    );
}

#[test]
fn mcp_catalog_refreshes_definitions_and_unpublishes_stale_routes() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_task_descendants: 20,
    })
    .expect("open db");
    let harness = tool_spec("bash", "Run a command");
    register_global_tool(&db, harness.clone()).expect("register harness tool");
    let active = mcp_registration("mcp__alpha__lookup", "Old lookup", "alpha", "lookup");
    let stale = mcp_registration("mcp__beta__search", "Search", "beta", "search");
    replace_global_mcp_tools(&db, vec![active, stale.clone()]).expect("publish MCP catalog");
    let task_id = create_task_without_tools(&db, "task");

    let mut refreshed = mcp_registration("mcp__alpha__lookup", "New lookup", "alpha", "lookup");
    refreshed.tool.input_schema = json_object(serde_json::json!({
        "type": "object",
        "properties": {
            "query": { "type": "string" }
        },
        "required": ["query"]
    }));
    let refreshed_tool = refreshed.tool.clone();
    replace_global_mcp_tools(&db, vec![refreshed]).expect("refresh MCP catalog");

    assert_eq!(
        read_tool_manifest_for_task(&db, &task_id)
            .expect("read refreshed manifest")
            .tools,
        vec![harness.clone(), refreshed_tool]
    );
    assert_eq!(
        read_tool_execution_source(&db, &ToolName(stale.tool.name.clone()))
            .expect("read stale durable route"),
        ToolExecutionSource::Mcp {
            server_id: stale.server_id,
            remote_tool_name: stale.remote_tool_name,
        }
    );
    assert_eq!(
        read_tool_execution_source(&db, &ToolName(harness.name))
            .expect("read unchanged harness route"),
        ToolExecutionSource::Harness
    );
}

#[test]
fn duplicate_mcp_names_roll_back_the_complete_catalog_refresh() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_task_descendants: 20,
    })
    .expect("open db");
    let original = mcp_registration("mcp__alpha__lookup", "Original", "alpha", "lookup");
    replace_global_mcp_tools(&db, vec![original.clone()]).expect("publish original catalog");
    let task_id = create_task_without_tools(&db, "task");

    let duplicate_name = original.tool.name.clone();
    assert!(matches!(
        replace_global_mcp_tools(
            &db,
            vec![
                mcp_registration(&duplicate_name, "Changed", "alpha", "lookup"),
                mcp_registration(&duplicate_name, "Duplicate", "other", "lookup"),
            ],
        ),
        Err(DbError::Constraint(_))
    ));
    assert_eq!(
        read_tool_manifest_for_task(&db, &task_id)
            .expect("read manifest after duplicate")
            .tools,
        vec![original.tool]
    );
}

#[test]
fn mcp_route_conflicts_roll_back_prior_catalog_writes() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_task_descendants: 20,
    })
    .expect("open db");
    let harness = tool_spec("bash", "Run a command");
    register_global_tool(&db, harness.clone()).expect("register harness tool");
    let original = mcp_registration("mcp__alpha__lookup", "Original", "alpha", "lookup");
    replace_global_mcp_tools(&db, vec![original.clone()]).expect("publish original catalog");
    let task_id = create_task_without_tools(&db, "task");

    let fresh_name = "mcp__beta__search";
    assert!(matches!(
        replace_global_mcp_tools(
            &db,
            vec![
                mcp_registration(fresh_name, "Search", "beta", "search"),
                mcp_registration(&original.tool.name, "Changed route", "alpha", "different",),
            ],
        ),
        Err(DbError::Constraint(_))
    ));

    assert_eq!(
        read_tool_execution_source(&db, &ToolName(fresh_name.to_owned())),
        Err(DbError::NotFound)
    );
    assert_eq!(
        read_tool_execution_source(&db, &ToolName(original.tool.name.clone()))
            .expect("read original route"),
        ToolExecutionSource::Mcp {
            server_id: original.server_id,
            remote_tool_name: original.remote_tool_name,
        }
    );
    assert_eq!(
        read_tool_manifest_for_task(&db, &task_id)
            .expect("read manifest after route conflict")
            .tools,
        vec![harness, original.tool]
    );
}

#[test]
fn empty_mcp_route_names_fail_without_changing_publication() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_task_descendants: 20,
    })
    .expect("open db");
    let original = mcp_registration("mcp__alpha__lookup", "Original", "alpha", "lookup");
    replace_global_mcp_tools(&db, vec![original.clone()]).expect("publish original catalog");
    let task_id = create_task_without_tools(&db, "task");

    for invalid in [
        mcp_registration("mcp__invalid__server", "Invalid", "", "lookup"),
        mcp_registration("mcp__invalid__tool", "Invalid", "alpha", ""),
    ] {
        assert!(matches!(
            replace_global_mcp_tools(&db, vec![invalid]),
            Err(DbError::Constraint(_))
        ));
        assert_eq!(
            read_tool_manifest_for_task(&db, &task_id)
                .expect("read unchanged manifest")
                .tools,
            vec![original.tool.clone()]
        );
    }
}

#[test]
fn open_db_migrates_v5_schemas_and_arguments_to_v7_json_storage() {
    let directory = tempfile::tempdir().expect("temp directory");
    let sqlite_path = directory.path().join("migration.sqlite");
    let legacy = rusqlite::Connection::open(&sqlite_path).expect("open v5 database");
    legacy
        .execute_batch(include_str!("fixtures/schema_v5.sql"))
        .expect("create v5 schema");
    legacy
        .execute_batch(
            "INSERT INTO tools (tool_name, description_text, is_global)
             VALUES ('legacy', 'Legacy tool', 1);
             INSERT INTO tool_parameters
             (tool_name, parameter_name, parameter_type, description_text, is_required)
             VALUES
               ('legacy', 'ratio', 'number', 'Ratio value', 1),
               ('legacy', 'query', 'string', 'Query text', 1),
               ('legacy', 'enabled', 'boolean', 'Enabled flag', 0),
               ('legacy', 'count', 'integer', 'Exact count', 1);

             INSERT INTO history_nodes (node_id, parent_node_id, content_kind, created_at)
             VALUES
               (1, NULL, 'message', 10),
               (2, 1, 'function_call', 11),
               (3, 2, 'function_call', 12),
               (4, 3, 'function_output', 13);
             INSERT INTO history_message_nodes (node_id, message_role, message_text)
             VALUES (1, 'user', 'migrate');
             INSERT INTO history_function_call_nodes
             (node_id, function_call_id, tool_name)
             VALUES
               (2, 'populated', 'legacy'),
               (3, 'empty', 'legacy');
             INSERT INTO history_function_call_arguments
             (function_call_node_id, tool_name, argument_name, value_type,
              string_value, integer_value, number_value, boolean_value)
             VALUES
               (2, 'legacy', 'ratio', 'number', NULL, NULL, 1.25, NULL),
               (2, 'legacy', 'query', 'string', 'hello', NULL, NULL, NULL),
               (2, 'legacy', 'enabled', 'boolean', NULL, NULL, NULL, 1),
               (2, 'legacy', 'count', 'integer', NULL, 9007199254740993, NULL, NULL);
             INSERT INTO history_function_output_nodes
             (node_id, function_call_node_id, function_call_id, tool_name, output_text, is_error)
             VALUES (4, 2, 'populated', 'legacy', 'legacy output', 0);
             INSERT INTO tasks
             (task_id, task_status, cursor_node_id, model_profile_key, reasoning_effort,
              state_version, created_at, updated_at)
             VALUES ('task', 'active', 4, 'default', 'medium', 0, 10, 13);",
        )
        .expect("seed v5 rows");
    drop(legacy);

    let db = open_db(OpenDbOptions {
        sqlite_path: sqlite_path.to_string_lossy().into_owned(),
        max_task_descendants: 20,
    })
    .expect("migrate database");
    let expected_tool = ToolSpec {
        name: "legacy".to_owned(),
        description: "Legacy tool".to_owned(),
        input_schema: json_object(serde_json::json!({
            "type": "object",
            "properties": {
                "count": {
                    "type": "integer",
                    "description": "Exact count"
                },
                "enabled": {
                    "type": "boolean",
                    "description": "Enabled flag"
                },
                "query": {
                    "type": "string",
                    "description": "Query text"
                },
                "ratio": {
                    "type": "number",
                    "description": "Ratio value"
                }
            },
            "required": ["count", "query", "ratio"],
            "additionalProperties": false
        })),
    };
    assert_eq!(
        read_tool_manifest_for_task(&db, &TaskId("task".to_owned()))
            .expect("read migrated manifest")
            .tools,
        vec![expected_tool]
    );
    assert_eq!(
        read_tool_execution_source(&db, &ToolName("legacy".to_owned()))
            .expect("read migrated route"),
        ToolExecutionSource::Harness
    );

    let calls = read_conversation_for_task(&db, &TaskId("task".to_owned()))
        .expect("read migrated conversation")
        .messages
        .into_iter()
        .filter_map(|message| {
            if message.content.get("type")?.as_str()? != "function_call" {
                return None;
            }
            Some((
                FunctionCallId(
                    message
                        .content
                        .get("function_call_id")?
                        .as_str()?
                        .to_owned(),
                ),
                message.content.get("arguments")?.as_object()?.clone(),
            ))
        })
        .collect::<Vec<_>>();
    assert_eq!(
        calls,
        vec![
            (
                FunctionCallId("populated".to_owned()),
                json_object(serde_json::json!({
                    "count": 9007199254740993_u64,
                    "enabled": true,
                    "query": "hello",
                    "ratio": 1.25
                }))
            ),
            (FunctionCallId("empty".to_owned()), JsonObject::new())
        ]
    );
    let migrated_output = read_conversation_for_task(&db, &TaskId("task".to_owned()))
        .expect("read migrated output")
        .messages
        .into_iter()
        .find_map(|message| message.function_output_value().cloned())
        .expect("migrated function output");
    assert_eq!(migrated_output, Value::String("legacy output".to_owned()));

    let raw = rusqlite::Connection::open(&sqlite_path).expect("open migrated database");
    let legacy_table_count = raw
        .query_row(
            "SELECT COUNT(*)
             FROM sqlite_master
             WHERE type = 'table'
               AND name IN ('tool_parameters', 'history_function_call_arguments')",
            [],
            |row| row.get::<_, i64>(0),
        )
        .expect("inspect migrated tables");
    assert_eq!(legacy_table_count, 0);
    assert_eq!(
        raw.query_row(
            "SELECT schema_value
             FROM schema_metadata
             WHERE schema_key = 'selvedge_schema_version'",
            [],
            |row| row.get::<_, String>(0),
        )
        .expect("read schema version"),
        "tool-result-branches-v7"
    );
}
