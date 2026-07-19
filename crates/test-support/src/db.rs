use std::collections::HashMap;

use selvedge_command_model::{ClientSnapshot, DetailLevel, SnapshotMode, TaskScope};
use selvedge_db::{
    CreateRootTaskInput, DbPool, HistoryNodeId, MessageRole, ModelProfileKey, NewHistoryNode,
    NewHistoryNodeContent, NewMessageNodeContent, OpenDbOptions, ReasoningEffort, TaskId, TaskRow,
    UnixTs, create_history_node, create_root_task, open_db,
};
use selvedge_domain_model::ModelProviderProfile;

pub fn open_memory_db() -> DbPool {
    open_memory_db_with_max_task_descendants(20)
}

pub fn open_memory_db_with_max_task_descendants(max_task_descendants: u32) -> DbPool {
    open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
        max_task_descendants,
    })
    .expect("open db")
}

pub fn create_message_node(
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

pub fn create_root_task_fixture(
    db: &DbPool,
    task_id: &str,
    cursor_node_id: HistoryNodeId,
    now: UnixTs,
) -> TaskRow {
    create_root_task(
        db,
        CreateRootTaskInput {
            task_id: TaskId(task_id.to_owned()),
            cursor_node_id,
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now,
        },
    )
    .expect("create root task")
}

pub fn create_root_task_with_user_message(
    db: &DbPool,
    task_id: &str,
    message_text: &str,
    now: UnixTs,
) -> TaskRow {
    let cursor_node_id = create_message_node(db, None, MessageRole::User, message_text, now);
    create_root_task_fixture(db, task_id, cursor_node_id, now)
}

pub fn default_model_profiles() -> HashMap<ModelProfileKey, ModelProviderProfile> {
    HashMap::from([(
        ModelProfileKey("default".to_owned()),
        ModelProviderProfile {
            provider_name: "provider".to_owned(),
            model_name: "model".to_owned(),
            temperature: None,
            max_output_tokens: None,
        },
    )])
}

pub fn empty_client_snapshot() -> ClientSnapshot {
    ClientSnapshot {
        generated_at: UnixTs(1),
        tasks: Vec::new(),
        task_parent_edges: Vec::new(),
        history_nodes: Vec::new(),
        task_versions: Vec::new(),
    }
}

pub fn summary_all_tasks_subscription() -> selvedge_command_model::ClientSubscription {
    selvedge_command_model::ClientSubscription {
        task_scope: TaskScope::AllTasks,
        detail_level: DetailLevel::Summary,
        snapshot_mode: SnapshotMode::CurrentState,
        include_model_call_status: false,
        include_tool_execution_status: false,
        include_debug_notices: false,
    }
}
