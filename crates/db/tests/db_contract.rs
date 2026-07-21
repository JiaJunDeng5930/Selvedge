use selvedge_db::{
    CommitToolResultBranchesInput, CreateRootTaskInput, DbError, DbPool, FunctionCallId,
    HistoryNode, HistoryNodeId, JsonObject, MessageRole, ModelProfileKey,
    NewFunctionCallNodeContent, NewFunctionOutputNodeContent, NewHistoryNode,
    NewHistoryNodeContent, NewMessageNodeContent, OpenDbOptions, ReadTaskInput, ReasoningEffort,
    TaskId, TaskLifecycleEvent, TaskStatus, TaskToolSpec, ToolExecutionSource, ToolManifest,
    ToolName, ToolRecoveryPolicy, ToolResultBranch, ToolResultBranchTarget, ToolSpec, UnixTs,
    append_assistant_message_and_drain_queue, append_model_reply_with_tool_calls_and_move_cursor,
    append_user_message_and_move_cursor, commit_tool_result_branches, create_history_node,
    create_root_task, list_runtime_tasks, load_runtime_task, open_db, queue_user_input,
    read_conversation_for_task, read_task, read_task_parent_edges, read_task_status,
    read_task_tool_state, read_tool_execution_source, read_tool_manifest_for_task,
    reconcile_task_tool_availability, transition_task_status,
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
            tools: Vec::new(),
            now: UnixTs(10),
        },
    )
    .expect("create task")
    .task_id
}

fn create_task_with_status(db: &DbPool, task_id: &str, status: TaskStatus) -> TaskId {
    let task_id = create_task_without_tools(db, task_id);
    let event = match status {
        TaskStatus::Active => return task_id,
        TaskStatus::Frozen => TaskLifecycleEvent::Freeze,
        TaskStatus::Stopped => TaskLifecycleEvent::Stop,
        TaskStatus::Archived => TaskLifecycleEvent::Archive,
    };
    transition_task_status(db, &task_id, event, UnixTs(11)).expect("prepare task status");
    task_id
}

fn tool_spec(name: &str, description: &str) -> ToolSpec {
    ToolSpec {
        name: name.to_owned(),
        description: description.to_owned(),
        input_schema: JsonObject::new(),
    }
}

fn mcp_tool(
    name: &str,
    description: &str,
    server_id: &str,
    remote_tool_name: &str,
) -> TaskToolSpec {
    TaskToolSpec {
        tool: tool_spec(name, description),
        execution_source: ToolExecutionSource::Mcp {
            server_id: server_id.to_owned(),
            remote_tool_name: remote_tool_name.to_owned(),
        },
        recovery_policy: ToolRecoveryPolicy::OutcomeUnknown,
    }
}

fn harness_tool(tool: ToolSpec) -> TaskToolSpec {
    TaskToolSpec {
        tool,
        execution_source: ToolExecutionSource::Harness,
        recovery_policy: ToolRecoveryPolicy::RetrySafe,
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
        max_children_per_fork: 5,
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
            tools: Vec::new(),
            now: UnixTs(10),
        },
    )
    .expect("create root task");

    assert_eq!(task.task_status, TaskStatus::Active);
    assert_eq!(task.state_version, 0);

    let loaded = load_runtime_task(&db, &TaskId("task-1".to_owned())).expect("load runtime task");
    assert_eq!(loaded.task.cursor_node_id, task.cursor_node_id);
    assert!(matches!(loaded.cursor_node, HistoryNode::Message { .. }));
}

#[test]
fn descendant_limit_is_enforced_for_every_ancestor_in_the_commit_transaction() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_children_per_fork: 2,
        max_task_descendants: 2,
    })
    .expect("open db");
    let root = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("root".to_owned()),
            cursor_node_id: create_message_node(&db, None, MessageRole::User, "root", UnixTs(10)),
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: vec![harness_tool(tool_spec("fork_task", "Fork tasks"))],
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
        load_runtime_task(&db, &TaskId("rejected".to_owned())),
        Err(DbError::NotFound)
    ));
}

#[test]
fn archive_task_preserves_queued_inputs() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_children_per_fork: 5,
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
            tools: Vec::new(),
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

    transition_task_status(
        &db,
        &TaskId("task-1".to_owned()),
        TaskLifecycleEvent::Archive,
        UnixTs(12),
    )
    .expect("archive task");
    let archived = read_task(
        &db,
        ReadTaskInput {
            task_id: TaskId("task-1".to_owned()),
            after_node_id: None,
            limit: 10,
        },
    )
    .expect("read archived task");
    assert_eq!(archived.task_status, TaskStatus::Archived);
    assert_eq!(archived.queued_input_count, 1);
}

#[test]
fn task_status_transitions_are_strict_and_runtime_queries_exclude_archived_tasks() {
    let cases = [
        (
            TaskStatus::Active,
            TaskLifecycleEvent::Freeze,
            Some(TaskStatus::Frozen),
        ),
        (TaskStatus::Active, TaskLifecycleEvent::Unfreeze, None),
        (
            TaskStatus::Active,
            TaskLifecycleEvent::Stop,
            Some(TaskStatus::Stopped),
        ),
        (
            TaskStatus::Active,
            TaskLifecycleEvent::Archive,
            Some(TaskStatus::Archived),
        ),
        (TaskStatus::Frozen, TaskLifecycleEvent::Freeze, None),
        (
            TaskStatus::Frozen,
            TaskLifecycleEvent::Unfreeze,
            Some(TaskStatus::Active),
        ),
        (TaskStatus::Frozen, TaskLifecycleEvent::Stop, None),
        (
            TaskStatus::Frozen,
            TaskLifecycleEvent::Archive,
            Some(TaskStatus::Archived),
        ),
        (TaskStatus::Stopped, TaskLifecycleEvent::Freeze, None),
        (TaskStatus::Stopped, TaskLifecycleEvent::Unfreeze, None),
        (TaskStatus::Stopped, TaskLifecycleEvent::Stop, None),
        (
            TaskStatus::Stopped,
            TaskLifecycleEvent::Archive,
            Some(TaskStatus::Archived),
        ),
        (TaskStatus::Archived, TaskLifecycleEvent::Freeze, None),
        (TaskStatus::Archived, TaskLifecycleEvent::Unfreeze, None),
        (TaskStatus::Archived, TaskLifecycleEvent::Stop, None),
        (TaskStatus::Archived, TaskLifecycleEvent::Archive, None),
    ];

    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_children_per_fork: 5,
        max_task_descendants: 20,
    })
    .expect("open db");

    for (index, (initial, event, expected)) in cases.into_iter().enumerate() {
        let task_id = create_task_with_status(&db, &format!("case-{index}"), initial);
        let version_before = read_task(
            &db,
            ReadTaskInput {
                task_id: task_id.clone(),
                after_node_id: None,
                limit: 1,
            },
        )
        .expect("read task before transition")
        .state_version;
        let result = transition_task_status(&db, &task_id, event, UnixTs(12));
        match expected {
            Some(status) => {
                let transitioned = result.expect("valid transition");
                assert_eq!(transitioned.task_status, status);
                assert_eq!(transitioned.state_version, version_before + 1);
            }
            None => assert_eq!(result, Err(DbError::InvalidTaskStatus { status: initial })),
        }
    }

    let runtime_statuses = list_runtime_tasks(&db)
        .expect("list runtime tasks")
        .into_iter()
        .map(|task| task.task_status)
        .collect::<Vec<_>>();
    assert!(runtime_statuses.contains(&TaskStatus::Active));
    assert!(runtime_statuses.contains(&TaskStatus::Frozen));
    assert!(runtime_statuses.contains(&TaskStatus::Stopped));
    assert!(!runtime_statuses.contains(&TaskStatus::Archived));

    let archived_task_id = TaskId("case-12".to_owned());
    assert_eq!(
        load_runtime_task(&db, &archived_task_id),
        Err(DbError::InvalidTaskStatus {
            status: TaskStatus::Archived,
        })
    );
    assert_eq!(
        read_task_status(&db, &archived_task_id),
        Ok(TaskStatus::Archived)
    );
}

#[test]
fn stopped_user_input_reactivates_in_the_input_transaction() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_children_per_fork: 5,
        max_task_descendants: 20,
    })
    .expect("open db");
    let direct = create_task_with_status(&db, "direct", TaskStatus::Stopped);
    assert!(matches!(
        transition_task_status(&db, &direct, TaskLifecycleEvent::UserInput, UnixTs(12),),
        Err(DbError::Constraint(_))
    ));
    assert_eq!(read_task_status(&db, &direct), Ok(TaskStatus::Stopped));
    let node_id =
        append_user_message_and_move_cursor(&db, &direct, "resume directly".to_owned(), UnixTs(12))
            .expect("append user input");
    let direct_read = read_task(
        &db,
        ReadTaskInput {
            task_id: direct,
            after_node_id: None,
            limit: 10,
        },
    )
    .expect("read directly resumed task");
    assert_eq!(direct_read.task_status, TaskStatus::Active);
    assert_eq!(direct_read.state_version, 2);
    assert_eq!(direct_read.cursor_node_id, node_id);
    assert_eq!(
        history_message_texts(&direct_read.history_nodes),
        vec!["run", "resume directly"]
    );

    let queued = create_task_with_status(&db, "queued", TaskStatus::Stopped);
    queue_user_input(&db, &queued, "resume queued".to_owned(), UnixTs(12))
        .expect("queue user input");
    let queued_read = read_task(
        &db,
        ReadTaskInput {
            task_id: queued,
            after_node_id: None,
            limit: 10,
        },
    )
    .expect("read queued resumed task");
    assert_eq!(queued_read.task_status, TaskStatus::Active);
    assert_eq!(queued_read.state_version, 2);
    assert_eq!(queued_read.queued_input_count, 1);
}

#[test]
fn non_archived_tasks_accept_runtime_commits_and_archived_tasks_reject_them() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_children_per_fork: 5,
        max_task_descendants: 20,
    })
    .expect("open db");
    let frozen = create_task_with_status(&db, "frozen", TaskStatus::Frozen);
    append_assistant_message_and_drain_queue(
        &db,
        &frozen,
        "completed while frozen".to_owned(),
        UnixTs(12),
    )
    .expect("commit frozen history");
    assert_eq!(read_task_status(&db, &frozen), Ok(TaskStatus::Frozen));

    let stopped = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("stopped".to_owned()),
            cursor_node_id: create_message_node(&db, None, MessageRole::User, "run", UnixTs(10)),
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: vec![harness_tool(tool_spec("search", "Search"))],
            now: UnixTs(10),
        },
    )
    .expect("create stopped task");
    let call_node_id = append_model_reply_with_tool_calls_and_move_cursor(
        &db,
        &stopped.task_id,
        None,
        vec![function_call("search-1", "search")],
        UnixTs(11),
    )
    .expect("append function call")[0];
    transition_task_status(&db, &stopped.task_id, TaskLifecycleEvent::Stop, UnixTs(12))
        .expect("stop task");
    commit_tool_result_branches(
        &db,
        CommitToolResultBranchesInput {
            calling_task_id: stopped.task_id.clone(),
            function_call_node_id: call_node_id,
            function_call_id: FunctionCallId("search-1".to_owned()),
            tool_name: ToolName("search".to_owned()),
            branches: vec![ToolResultBranch {
                target: ToolResultBranchTarget::CallingTask,
                output: Value::String("done".to_owned()),
                is_error: false,
                user_messages: Vec::new(),
            }],
            now: UnixTs(13),
        },
    )
    .expect("commit stopped tool result");
    assert_eq!(
        read_task_status(&db, &stopped.task_id),
        Ok(TaskStatus::Stopped)
    );

    let archived = create_task_with_status(&db, "archived", TaskStatus::Archived);
    assert_eq!(
        append_assistant_message_and_drain_queue(&db, &archived, "rejected".to_owned(), UnixTs(12),),
        Err(DbError::InvalidTaskStatus {
            status: TaskStatus::Archived,
        })
    );
}

#[test]
fn append_history_uses_new_node_timestamp_for_task_updated_at() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_children_per_fork: 5,
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
            tools: Vec::new(),
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
        max_children_per_fork: 5,
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
            tools: Vec::new(),
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
        max_children_per_fork: 5,
        max_task_descendants: 20,
    })
    .expect("open db");
    let fork_tool = tool_spec("fork_task", "Fork a child task");
    let task_tool = tool_spec("search", "Search local state");

    let parent = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("parent".to_owned()),
            cursor_node_id: create_message_node(&db, None, MessageRole::User, "parent", UnixTs(10)),
            model_profile_key: ModelProfileKey("parent-profile".to_owned()),
            reasoning_effort: ReasoningEffort::High,
            tools: vec![
                harness_tool(fork_tool.clone()),
                harness_tool(task_tool.clone()),
            ],
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
            tools: Vec::new(),
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

    let child = load_runtime_task(&db, &TaskId("child-with-message".to_owned()))
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
            tools: vec![fork_tool, task_tool],
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
        matches!(duplicate_on_caller_path, Err(DbError::StaleFunctionCall)),
        "the shared output insertion path must reject a second output on the same history path"
    );
}

#[test]
fn function_output_requires_its_exact_call_on_the_parent_path() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_children_per_fork: 5,
        max_task_descendants: 20,
    })
    .expect("open db");
    let root = create_message_node(&db, None, MessageRole::User, "root", UnixTs(1));
    let call = create_history_node(
        &db,
        NewHistoryNode {
            parent_node_id: Some(root),
            content: NewHistoryNodeContent::FunctionCall(function_call("call-1", "search")),
            created_at: UnixTs(2),
        },
    )
    .expect("create call branch");
    let unrelated_branch =
        create_message_node(&db, Some(root), MessageRole::User, "other", UnixTs(2));
    let output = |parent_node_id| NewHistoryNode {
        parent_node_id: Some(parent_node_id),
        content: NewHistoryNodeContent::FunctionOutput(NewFunctionOutputNodeContent {
            function_call_node_id: call,
            function_call_id: FunctionCallId("call-1".to_owned()),
            tool_name: ToolName("search".to_owned()),
            output: Value::String("done".to_owned()),
            is_error: false,
        }),
        created_at: UnixTs(3),
    };

    assert!(matches!(
        create_history_node(&db, output(unrelated_branch)),
        Err(DbError::StaleFunctionCall)
    ));
    create_history_node(&db, output(call)).expect("create output below its exact call");
}

#[test]
fn create_history_node_accepts_strategy_parent_and_root_task_uses_existing_cursor() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_children_per_fork: 5,
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
            tools: Vec::new(),
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
            tools: Vec::new(),
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
fn tool_snapshots_are_owned_and_ordered_per_task() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_children_per_fork: 5,
        max_task_descendants: 20,
    })
    .expect("open db");
    let first_tools = vec![
        tool_spec("local_search", "Search this task"),
        tool_spec("read_task", "Read durable task state"),
    ];
    let first = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("first".to_owned()),
            cursor_node_id: create_message_node(&db, None, MessageRole::User, "hello", UnixTs(10)),
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: first_tools.iter().cloned().map(harness_tool).collect(),
            now: UnixTs(10),
        },
    )
    .expect("create first task");
    let second_tool = tool_spec("read_task", "A later definition");
    let second = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("second".to_owned()),
            cursor_node_id: create_message_node(&db, None, MessageRole::User, "other", UnixTs(11)),
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: vec![harness_tool(second_tool.clone())],
            now: UnixTs(11),
        },
    )
    .expect("create second task");

    assert_eq!(
        read_tool_manifest_for_task(&db, &first.task_id).expect("read first manifest"),
        ToolManifest { tools: first_tools }
    );
    assert_eq!(
        read_tool_manifest_for_task(&db, &second.task_id).expect("read second manifest"),
        ToolManifest {
            tools: vec![second_tool],
        }
    );
}

#[test]
fn read_task_pages_active_and_archived_cursor_paths_and_rejects_invalid_bounds() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_children_per_fork: 5,
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
            tools: Vec::new(),
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
    assert_eq!(first_page.task_status, TaskStatus::Active);
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

    transition_task_status(&db, &task.task_id, TaskLifecycleEvent::Archive, UnixTs(14))
        .expect("archive task");
    let archived = read_task(
        &db,
        ReadTaskInput {
            task_id: task.task_id,
            after_node_id: Some(root_node_id),
            limit: 100,
        },
    )
    .expect("read archived task");
    assert_eq!(archived.task_status, TaskStatus::Archived);
    assert_eq!(archived.state_version, 3);
    assert_eq!(archived.queued_input_count, 1);
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
        max_children_per_fork: 5,
        max_task_descendants: 20,
    })
    .expect("open db");

    let parent = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("parent".to_owned()),
            cursor_node_id: create_message_node(&db, None, MessageRole::User, "parent", UnixTs(10)),
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: vec![harness_tool(tool_spec("fork_task", "Fork a child task"))],
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
            tools: Vec::new(),
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
        load_runtime_task(&db, &parent.task_id)
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
fn task_tool_unavailability_preserves_manifest_and_history() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_children_per_fork: 5,
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
    let task = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task".to_owned()),
            cursor_node_id: create_message_node(&db, None, MessageRole::User, "run", UnixTs(10)),
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: vec![harness_tool(tool.clone())],
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

    reconcile_task_tool_availability(&db, Vec::new()).expect("mark tool unavailable");
    let state = read_task_tool_state(&db, &task.task_id).expect("read unavailable state");
    assert_eq!(state.manifest.tools, vec![tool.clone()]);
    assert_eq!(state.unavailable_tools, vec![ToolName(tool.name.clone())]);
    assert_eq!(
        read_tool_execution_source(&db, &task.task_id, &ToolName(tool.name.clone())),
        Err(DbError::ToolUnavailable)
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

    reconcile_task_tool_availability(&db, vec![harness_tool(tool.clone())])
        .expect("restore tool availability");
    assert_eq!(
        read_tool_execution_source(&db, &TaskId("task".to_owned()), &ToolName(tool.name))
            .expect("read restored route")
            .source,
        ToolExecutionSource::Harness
    );
}

#[test]
fn mcp_contract_changes_only_change_task_availability() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_children_per_fork: 5,
        max_task_descendants: 20,
    })
    .expect("open db");
    let original = mcp_tool("mcp__alpha__lookup", "Original", "alpha", "lookup");
    let stale = mcp_tool("mcp__beta__search", "Search", "beta", "search");
    let harness = harness_tool(tool_spec("bash", "Run a command"));
    let task = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task".to_owned()),
            cursor_node_id: create_message_node(&db, None, MessageRole::User, "run", UnixTs(10)),
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: vec![harness.clone(), original.clone(), stale.clone()],
            now: UnixTs(10),
        },
    )
    .expect("create task");
    let frozen_manifest =
        read_tool_manifest_for_task(&db, &task.task_id).expect("read frozen manifest");

    let mut changed = original.clone();
    changed.tool.description = "Changed".to_owned();
    reconcile_task_tool_availability(&db, vec![harness.clone(), changed])
        .expect("reconcile changed catalog");

    let state = read_task_tool_state(&db, &task.task_id).expect("read reconciled state");
    assert_eq!(state.manifest, frozen_manifest);
    assert_eq!(
        state.unavailable_tools,
        vec![
            ToolName(original.tool.name.clone()),
            ToolName(stale.tool.name.clone())
        ]
    );
    assert_eq!(
        read_tool_execution_source(&db, &task.task_id, &ToolName(harness.tool.name.clone()))
            .expect("harness remains executable")
            .source,
        ToolExecutionSource::Harness
    );

    reconcile_task_tool_availability(&db, vec![harness, original, stale])
        .expect("restore exact catalog");
    assert!(
        read_task_tool_state(&db, &task.task_id)
            .expect("read restored state")
            .unavailable_tools
            .is_empty()
    );
}

#[test]
fn execution_source_schema_rejects_incomplete_mcp_routes() {
    let directory = tempfile::tempdir().expect("temp directory");
    let sqlite_path = directory.path().join("routes.sqlite");
    let db = open_db(OpenDbOptions {
        sqlite_path: sqlite_path.to_string_lossy().into_owned(),
        max_children_per_fork: 5,
        max_task_descendants: 20,
    })
    .expect("open db");
    let task_id = create_task_without_tools(&db, "task");
    let raw = rusqlite::Connection::open(&sqlite_path).expect("open raw database");
    assert!(
        raw.execute(
            "INSERT INTO task_tools
             (task_id, tool_ordinal, tool_name, description_text, input_schema_json,
              execution_source_kind, mcp_server_id, remote_tool_name, recovery_policy)
             VALUES (?1, 0, 'broken', 'Broken route', '{}', 'mcp', 'server', NULL,
                     'outcome_unknown')",
            [task_id.0],
        )
        .is_err()
    );
}

#[test]
fn duplicate_available_names_leave_availability_unchanged() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_children_per_fork: 5,
        max_task_descendants: 20,
    })
    .expect("open db");
    let original = mcp_tool("mcp__alpha__lookup", "Original", "alpha", "lookup");
    let task = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task".to_owned()),
            cursor_node_id: create_message_node(&db, None, MessageRole::User, "run", UnixTs(10)),
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: vec![original.clone()],
            now: UnixTs(10),
        },
    )
    .expect("create task");
    reconcile_task_tool_availability(&db, Vec::new()).expect("mark unavailable");
    let duplicate_name = original.tool.name.clone();
    assert!(matches!(
        reconcile_task_tool_availability(
            &db,
            vec![
                mcp_tool(&duplicate_name, "Changed", "alpha", "lookup"),
                mcp_tool(&duplicate_name, "Duplicate", "other", "lookup"),
            ],
        ),
        Err(DbError::Constraint(_))
    ));
    assert_eq!(
        read_task_tool_state(&db, &task.task_id)
            .expect("read state after rejected reconcile")
            .unavailable_tools,
        vec![ToolName(original.tool.name)]
    );
}
