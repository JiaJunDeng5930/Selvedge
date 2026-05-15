use std::collections::HashMap;

use selvedge_command_model::{ClientSnapshot, DetailLevel, TaskScope};
use selvedge_db::{
    CreateRootTaskInput, DbPool, HistoryNodeId, MessageRole, ModelProfileKey, NewHistoryNode,
    NewHistoryNodeContent, NewMessageNodeContent, OpenDbOptions, ReasoningEffort, TaskId, TaskRow,
    UnixTs, create_history_node, create_root_task, open_db,
};
use selvedge_domain_model::ModelProviderProfile;

// @behavior selvedge.testsupport.db Database test support creates shared in-memory database, task, profile, and snapshot fixtures.
// @behavior selvedge.testsupport.db.memory Downstream tests can open an in-memory Selvedge database with the current schema.
pub fn open_memory_db() -> DbPool {
    open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
    })
    .expect("open db")
}

// @behavior selvedge.testsupport.db.message_node Downstream tests can create one message history node with caller-selected parent, role, text, and timestamp.
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
    // @behavior selvedge.testsupport.db.message_node.fail Fast fixture setup fails the calling test when the history node cannot be created.
    .expect("create history node")
}

// @behavior selvedge.testsupport.db.root_task Downstream tests can create a root task with caller-selected task identity and cursor node.
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
    // @behavior selvedge.testsupport.db.root_task.fail Fast fixture setup fails the calling test when the root task cannot be created.
    .expect("create root task")
}

// @behavior selvedge.testsupport.db.root_user_task Downstream tests can create a root task whose cursor is a user message node.
pub fn create_root_task_with_user_message(
    db: &DbPool,
    task_id: &str,
    message_text: &str,
    now: UnixTs,
) -> TaskRow {
    let cursor_node_id = create_message_node(db, None, MessageRole::User, message_text, now);
    create_root_task_fixture(db, task_id, cursor_node_id, now)
}

// @behavior selvedge.testsupport.db.model_profiles Downstream tests can use a default model profile map keyed by the database default profile key.
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

// @behavior selvedge.testsupport.db.empty_snapshot Downstream tests can create an empty client snapshot with a stable timestamp.
pub fn empty_client_snapshot() -> ClientSnapshot {
    ClientSnapshot {
        generated_at: UnixTs(1),
        tasks: Vec::new(),
        task_parent_edges: Vec::new(),
        history_nodes: Vec::new(),
        task_versions: Vec::new(),
    }
}

// @behavior selvedge.testsupport.db.summary_subscription Downstream tests can create a summary subscription covering all tasks.
pub fn summary_all_tasks_subscription() -> selvedge_command_model::ClientSubscription {
    selvedge_command_model::ClientSubscription {
        task_scope: TaskScope::AllTasks,
        detail_level: DetailLevel::Summary,
        include_model_call_status: false,
        include_tool_execution_status: false,
        include_debug_notices: false,
    }
}
