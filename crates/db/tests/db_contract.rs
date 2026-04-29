use selvedge_db::{
    CreateRootTaskInput, HistoryContentKindRow, MessageRole, NewHistoryNode, NewHistoryNodeContent,
    NewMessageNodeContent, OpenDbOptions, ReasoningEffort, TaskId, TaskStatusRow, UnixTs,
    create_root_task, load_active_task, open_db,
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
