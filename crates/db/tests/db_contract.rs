use selvedge_db::{
    CreateChildTaskInput, CreateRootTaskInput, DbPool, HistoryNode, HistoryNodeId, MessageRole,
    NewHistoryNode, NewHistoryNodeContent, NewMessageNodeContent, OpenDbOptions, ReasoningEffort,
    TaskId, TaskStatusRow, UnixTs, append_user_message_and_move_cursor, archive_task,
    create_child_task, create_history_node, create_root_task, load_active_task, open_db,
    queue_user_input, read_conversation_for_task,
};
use selvedge_domain_model::ConversationItem;

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
fn create_child_task_accepts_strategy_cursor_outside_parent_chain() {
    let db = open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
    })
    .expect("open db");
    let parent = create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("parent".to_owned()),
            cursor_node_id: create_message_node(&db, None, MessageRole::User, "parent", UnixTs(10)),
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
            cursor_node_id: create_message_node(
                &db,
                None,
                MessageRole::User,
                "foreign",
                UnixTs(10),
            ),
            model_profile_key: selvedge_db::ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(10),
        },
    )
    .expect("create foreign");
    assert_ne!(parent.cursor_node_id, foreign.cursor_node_id);

    let child = create_child_task(
        &db,
        CreateChildTaskInput {
            parent_task_id: TaskId("parent".to_owned()),
            child_task_id: TaskId("child".to_owned()),
            cursor_node_id: foreign.cursor_node_id,
            now: UnixTs(11),
        },
    )
    .expect("create child task");

    assert_eq!(child.cursor_node_id, foreign.cursor_node_id);
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
