use selvedge_db::{
    CreateRootTaskInput, DbError, DbPool, ForkTaskInput, FunctionCallId, HistoryNode,
    HistoryNodeId, MessageRole, ModelProfileKey, NewFunctionCallNodeContent,
    NewFunctionOutputNodeContent, NewHistoryNode, NewHistoryNodeContent, NewMessageNodeContent,
    OpenDbOptions, ReadTaskInput, ReasoningEffort, TaskId, TaskStatusRow, ToolManifest, ToolName,
    ToolParameterType, ToolSpec, UnixTs, append_function_output_and_drain_queue,
    append_model_reply_with_tool_calls_and_move_cursor, append_user_message_and_move_cursor,
    archive_task, create_history_node, create_root_task, fork_task_from_function_call,
    load_active_task, open_db, queue_user_input, read_conversation_for_task, read_task,
    read_tool_manifest_for_task, register_global_tool, register_tool,
};
use selvedge_domain_model::ConversationItem;
use selvedge_domain_model::ToolParameter;

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

fn tool_spec(name: &str, description: &str) -> ToolSpec {
    ToolSpec {
        name: name.to_owned(),
        description: description.to_owned(),
        parameters: Vec::new(),
    }
}

fn function_call(call_id: &str, tool_name: &str) -> NewFunctionCallNodeContent {
    NewFunctionCallNodeContent {
        function_call_id: FunctionCallId(call_id.to_owned()),
        tool_name: ToolName(tool_name.to_owned()),
        arguments: Vec::new(),
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

#[test]
fn open_db_creates_schema_and_root_task_transaction_moves_cursor() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
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
fn archive_task_clears_queued_inputs_before_status_update() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
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
        .items
        .into_iter()
        .filter_map(|item| match item {
            ConversationItem::Message { text, .. } => Some(text),
            _ => None,
        })
        .collect::<Vec<_>>();
    assert_eq!(messages, vec!["hello", "first append", "stale append"]);
}

#[test]
fn fork_from_open_batched_call_uses_safe_history_base_and_copies_parent_settings() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
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

    let child = fork_task_from_function_call(
        &db,
        ForkTaskInput {
            parent_task_id: TaskId("parent".to_owned()),
            child_task_id: TaskId("child".to_owned()),
            function_call_node_id: call_node_ids[1],
            function_call_id: FunctionCallId("fork-1".to_owned()),
            tool_name: ToolName("fork_task".to_owned()),
            child_user_prompt: "Investigate the persistence slice.".to_owned(),
            now: UnixTs(12),
        },
    )
    .expect("fork child task");

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
    assert!(
        child_read
            .history_nodes
            .iter()
            .all(|node| !matches!(node, HistoryNode::FunctionCall { .. }))
    );
    assert_eq!(
        load_active_task(&db, &parent.task_id)
            .expect("load parent")
            .task
            .cursor_node_id,
        call_node_ids[2]
    );
}

#[test]
fn create_history_node_accepts_strategy_parent_and_root_task_uses_existing_cursor() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
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
    assert_eq!(conversation.items.len(), 2);
}

#[test]
fn global_tool_registration_is_exactly_idempotent_and_merges_with_task_tools() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
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
        parameters: vec![ToolParameter {
            name: "task_id".to_owned(),
            parameter_type: ToolParameterType::String,
            description: "Task identifier".to_owned(),
            required: true,
        }],
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
fn fork_failures_leave_no_child_or_orphan_history() {
    let directory = tempfile::tempdir().expect("temp directory");
    let sqlite_path = directory.path().join("fork-atomicity.sqlite");
    let sqlite_path_text = sqlite_path.to_string_lossy().into_owned();
    let db = open_db(OpenDbOptions {
        sqlite_path: sqlite_path_text.clone(),
    })
    .expect("open db");
    register_global_tool(&db, tool_spec("fork_task", "Fork a child task"))
        .expect("register fork tool");

    let create_parent_with_open_call = |task_id: &str, call_id: &str, timestamp: i64| {
        let task = create_root_task(
            &db,
            CreateRootTaskInput {
                task_id: TaskId(task_id.to_owned()),
                cursor_node_id: create_message_node(
                    &db,
                    None,
                    MessageRole::User,
                    task_id,
                    UnixTs(timestamp),
                ),
                model_profile_key: ModelProfileKey("default".to_owned()),
                reasoning_effort: ReasoningEffort::Medium,
                enabled_tools: Vec::new(),
                now: UnixTs(timestamp),
            },
        )
        .expect("create parent");
        let call_node_id = append_model_reply_with_tool_calls_and_move_cursor(
            &db,
            &task.task_id,
            None,
            vec![function_call(call_id, "fork_task")],
            UnixTs(timestamp + 1),
        )
        .expect("append open fork call")[0];
        (task.task_id, call_node_id)
    };
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
        (tasks, history)
    };
    let assert_child_missing = |task_id: &str| {
        assert!(matches!(
            read_task(
                &db,
                ReadTaskInput {
                    task_id: TaskId(task_id.to_owned()),
                    after_node_id: None,
                    limit: 1,
                },
            ),
            Err(DbError::NotFound)
        ));
    };

    let (missing_parent, _) = create_parent_with_open_call("missing-parent", "missing", 10);
    let before_missing = durable_counts();
    assert!(matches!(
        fork_task_from_function_call(
            &db,
            ForkTaskInput {
                parent_task_id: missing_parent,
                child_task_id: TaskId("missing-child".to_owned()),
                function_call_node_id: HistoryNodeId(999_999),
                function_call_id: FunctionCallId("missing".to_owned()),
                tool_name: ToolName("fork_task".to_owned()),
                child_user_prompt: "missing".to_owned(),
                now: UnixTs(12),
            },
        ),
        Err(DbError::StaleFunctionCall)
    ));
    assert_eq!(durable_counts(), before_missing);
    assert_child_missing("missing-child");

    let (archived_parent, archived_call) =
        create_parent_with_open_call("archived-parent", "archived", 20);
    archive_task(&db, &archived_parent, UnixTs(22)).expect("archive parent");
    let before_archived = durable_counts();
    assert_eq!(
        fork_task_from_function_call(
            &db,
            ForkTaskInput {
                parent_task_id: archived_parent,
                child_task_id: TaskId("archived-child".to_owned()),
                function_call_node_id: archived_call,
                function_call_id: FunctionCallId("archived".to_owned()),
                tool_name: ToolName("fork_task".to_owned()),
                child_user_prompt: "archived".to_owned(),
                now: UnixTs(23),
            },
        ),
        Err(DbError::TaskNotActive)
    );
    assert_eq!(durable_counts(), before_archived);
    assert_child_missing("archived-child");

    let (stale_parent, stale_call) = create_parent_with_open_call("stale-parent", "stale", 30);
    append_function_output_and_drain_queue(
        &db,
        &stale_parent,
        NewFunctionOutputNodeContent {
            function_call_node_id: stale_call,
            function_call_id: FunctionCallId("stale".to_owned()),
            tool_name: ToolName("fork_task".to_owned()),
            output_text: "already completed".to_owned(),
            is_error: false,
        },
        UnixTs(32),
    )
    .expect("close stale call");
    let before_stale = durable_counts();
    assert!(matches!(
        fork_task_from_function_call(
            &db,
            ForkTaskInput {
                parent_task_id: stale_parent,
                child_task_id: TaskId("stale-child".to_owned()),
                function_call_node_id: stale_call,
                function_call_id: FunctionCallId("stale".to_owned()),
                tool_name: ToolName("fork_task".to_owned()),
                child_user_prompt: "stale".to_owned(),
                now: UnixTs(33),
            },
        ),
        Err(DbError::StaleFunctionCall)
    ));
    assert_eq!(durable_counts(), before_stale);
    assert_child_missing("stale-child");

    let (collision_parent, collision_call) =
        create_parent_with_open_call("collision-parent", "collision", 40);
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("occupied-child".to_owned()),
            cursor_node_id: create_message_node(
                &db,
                None,
                MessageRole::User,
                "occupied",
                UnixTs(42),
            ),
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(42),
        },
    )
    .expect("create occupied child id");
    let before_collision = durable_counts();
    assert!(matches!(
        fork_task_from_function_call(
            &db,
            ForkTaskInput {
                parent_task_id: collision_parent,
                child_task_id: TaskId("occupied-child".to_owned()),
                function_call_node_id: collision_call,
                function_call_id: FunctionCallId("collision".to_owned()),
                tool_name: ToolName("fork_task".to_owned()),
                child_user_prompt: "must roll back".to_owned(),
                now: UnixTs(43),
            },
        ),
        Err(DbError::Constraint(_))
    ));
    assert_eq!(durable_counts(), before_collision);
}

#[test]
fn open_db_migrates_v4_tool_rows_to_non_global_before_global_registration() {
    let directory = tempfile::tempdir().expect("temp directory");
    let sqlite_path = directory.path().join("migration.sqlite");
    let v4_schema = include_str!("../src/schema.sql")
        .replace("harness-persistence-v5", "router-mediated-redesign-v4")
        .replace(
            ",\n    is_global INTEGER NOT NULL DEFAULT 0 CHECK (is_global IN (0, 1))",
            "",
        )
        .replace(
            "CREATE INDEX idx_tools_global_name\n    ON tools(is_global, tool_name);\n\n",
            "",
        );
    assert!(!v4_schema.contains("is_global"));
    rusqlite::Connection::open(&sqlite_path)
        .expect("open v4 database")
        .execute_batch(&v4_schema)
        .expect("create v4 schema");

    let db = open_db(OpenDbOptions {
        sqlite_path: sqlite_path.to_string_lossy().into_owned(),
    })
    .expect("migrate database");
    let global_tool = tool_spec("read_task", "Read durable task state");
    register_global_tool(&db, global_tool.clone()).expect("register after migration");
    let task = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task".to_owned()),
            cursor_node_id: create_message_node(&db, None, MessageRole::User, "hello", UnixTs(10)),
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(10),
        },
    )
    .expect("create task");
    assert_eq!(
        read_tool_manifest_for_task(&db, &task.task_id)
            .expect("read migrated manifest")
            .tools,
        vec![global_tool]
    );
}
