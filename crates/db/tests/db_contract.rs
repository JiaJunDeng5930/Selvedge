use selvedge_db::{
    CreateChildTaskInput, CreateRootTaskInput, HistoryContentKindRow, MessageRole, NewHistoryNode,
    NewHistoryNodeContent, NewMessageNodeContent, OpenDbOptions, ReasoningEffort, TaskId,
    TaskStatusRow, UnixTs, append_history_node_and_move_cursor, archive_task, create_child_task,
    create_root_task, load_active_task, open_db, queue_user_input,
};

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
            initial_node: NewHistoryNode {
                parent_node_id: None,
                content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                    message_role: MessageRole::User,
                    message_text: "hello".to_owned(),
                }),
                created_at: UnixTs(10),
            },
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
    assert_eq!(
        loaded.cursor_node.content_kind,
        HistoryContentKindRow::Message
    );
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
            initial_node: NewHistoryNode {
                parent_node_id: None,
                content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                    message_role: MessageRole::User,
                    message_text: "hello".to_owned(),
                }),
                created_at: UnixTs(10),
            },
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
    let task = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            initial_node: NewHistoryNode {
                parent_node_id: None,
                content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                    message_role: MessageRole::User,
                    message_text: "hello".to_owned(),
                }),
                created_at: UnixTs(4_102_444_800),
            },
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(4_102_444_800),
        },
    )
    .expect("create root task");

    selvedge_db::append_history_node_and_move_cursor(
        &db,
        &TaskId("task-1".to_owned()),
        NewHistoryNode {
            parent_node_id: Some(task.cursor_node_id),
            content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                message_role: MessageRole::User,
                message_text: "future append".to_owned(),
            }),
            created_at: UnixTs(4_102_444_801),
        },
    )
    .expect("append history");
}

#[test]
fn append_history_rejects_stale_parent_cursor() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
    })
    .expect("open db");
    let task = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("task-1".to_owned()),
            initial_node: NewHistoryNode {
                parent_node_id: None,
                content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                    message_role: MessageRole::User,
                    message_text: "hello".to_owned(),
                }),
                created_at: UnixTs(10),
            },
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(10),
        },
    )
    .expect("create root task");
    append_history_node_and_move_cursor(
        &db,
        &TaskId("task-1".to_owned()),
        NewHistoryNode {
            parent_node_id: Some(task.cursor_node_id),
            content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                message_role: MessageRole::User,
                message_text: "first append".to_owned(),
            }),
            created_at: UnixTs(11),
        },
    )
    .expect("append once");

    let error = append_history_node_and_move_cursor(
        &db,
        &TaskId("task-1".to_owned()),
        NewHistoryNode {
            parent_node_id: Some(task.cursor_node_id),
            content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                message_role: MessageRole::User,
                message_text: "stale append".to_owned(),
            }),
            created_at: UnixTs(12),
        },
    )
    .expect_err("stale append");

    assert!(matches!(error, selvedge_db::DbError::Constraint(_)));
}

#[test]
fn create_child_task_rejects_cursor_outside_parent_chain() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
    })
    .expect("open db");
    let parent = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("parent".to_owned()),
            initial_node: NewHistoryNode {
                parent_node_id: None,
                content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                    message_role: MessageRole::User,
                    message_text: "parent".to_owned(),
                }),
                created_at: UnixTs(10),
            },
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(10),
        },
    )
    .expect("create parent");
    let foreign = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("foreign".to_owned()),
            initial_node: NewHistoryNode {
                parent_node_id: None,
                content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                    message_role: MessageRole::User,
                    message_text: "foreign".to_owned(),
                }),
                created_at: UnixTs(10),
            },
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(10),
        },
    )
    .expect("create foreign");
    assert_ne!(parent.cursor_node_id, foreign.cursor_node_id);

    let error = create_child_task(
        &db,
        CreateChildTaskInput {
            parent_task_id: TaskId("parent".to_owned()),
            child_task_id: TaskId("child".to_owned()),
            cursor_node_id: foreign.cursor_node_id,
            now: UnixTs(11),
        },
    )
    .expect_err("foreign cursor rejected");

    assert!(matches!(error, selvedge_db::DbError::Constraint(_)));
}
