#![doc = include_str!("../README.md")]

use std::sync::{Arc, Mutex, MutexGuard};
use std::{error::Error, fmt};

use rusqlite::{Connection, OptionalExtension, TransactionBehavior, params};
pub use selvedge_domain_model::{
    Conversation, ConversationItem, FunctionCallId, HistoryNodeId, JsonObject, MessageRole,
    ModelProfileKey, ReasoningEffort, TaskId, ToolManifest, ToolName, ToolSpec, UnixTs,
};

const SCHEMA_VERSION: &str = "json-tool-foundation-v6";
const PREVIOUS_SCHEMA_VERSION: &str = "harness-persistence-v5";
pub const MAX_TASK_HISTORY_PAGE_SIZE: u32 = 100;

#[derive(Clone)]
pub struct DbPool {
    connection: Arc<Mutex<Connection>>,
}

pub struct DbConnection;
pub struct DbTransaction;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DbError {
    NotFound,
    TaskNotActive,
    StaleFunctionCall,
    HistoryCursorNotOnTask,
    Constraint(String),
    Storage(String),
    SchemaMismatch {
        expected: String,
        actual: Option<String>,
    },
}

impl fmt::Display for DbError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            DbError::NotFound => write!(formatter, "row was not found"),
            DbError::TaskNotActive => write!(formatter, "task is not active"),
            DbError::StaleFunctionCall => {
                write!(formatter, "fork function call is not open on the task path")
            }
            DbError::HistoryCursorNotOnTask => {
                write!(formatter, "history cursor is not on the task path")
            }
            DbError::Constraint(message) => write!(formatter, "constraint failed: {message}"),
            DbError::Storage(message) => write!(formatter, "storage failed: {message}"),
            DbError::SchemaMismatch { expected, actual } => {
                write!(
                    formatter,
                    "schema mismatch: expected {expected}, actual {actual:?}"
                )
            }
        }
    }
}

impl Error for DbError {}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TaskStatusRow {
    Active,
    Archived,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum HistoryContentKindRow {
    Message,
    Reasoning,
    FunctionCall,
    FunctionOutput,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OpenDbOptions {
    pub sqlite_path: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ToolExecutionSource {
    Harness,
    Mcp {
        server_id: String,
        remote_tool_name: String,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TaskRow {
    pub task_id: TaskId,
    pub task_status: TaskStatusRow,
    pub cursor_node_id: HistoryNodeId,
    pub model_profile_key: ModelProfileKey,
    pub reasoning_effort: ReasoningEffort,
    pub state_version: u64,
    pub created_at: UnixTs,
    pub updated_at: UnixTs,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TaskToolRow {
    pub task_id: TaskId,
    pub tool_name: ToolName,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TaskParentEdgeRow {
    pub parent_task_id: TaskId,
    pub child_task_id: TaskId,
    pub created_at: UnixTs,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct QueuedUserInputRow {
    pub task_id: TaskId,
    pub seq_no: u64,
    pub message_text: String,
    pub queued_at: UnixTs,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HistoryNodeRow {
    pub node_id: HistoryNodeId,
    pub parent_node_id: Option<HistoryNodeId>,
    pub content_kind: HistoryContentKindRow,
    pub created_at: UnixTs,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HistoryMessageNodeRow {
    pub node_id: HistoryNodeId,
    pub message_role: MessageRole,
    pub message_text: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HistoryReasoningNodeRow {
    pub node_id: HistoryNodeId,
    pub reasoning_text: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HistoryFunctionCallNodeRow {
    pub node_id: HistoryNodeId,
    pub function_call_id: FunctionCallId,
    pub tool_name: ToolName,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HistoryFunctionOutputNodeRow {
    pub node_id: HistoryNodeId,
    pub function_call_node_id: HistoryNodeId,
    pub function_call_id: FunctionCallId,
    pub tool_name: ToolName,
    pub output_text: String,
    pub is_error: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct OpenFunctionCall {
    pub function_call_node_id: HistoryNodeId,
    pub function_call_id: FunctionCallId,
    pub tool_name: ToolName,
    pub arguments: JsonObject,
}

#[derive(Clone, Debug, PartialEq)]
pub enum HistoryNode {
    Message {
        node_id: HistoryNodeId,
        parent_node_id: Option<HistoryNodeId>,
        created_at: UnixTs,
        message_role: MessageRole,
        message_text: String,
    },
    Reasoning {
        node_id: HistoryNodeId,
        parent_node_id: Option<HistoryNodeId>,
        created_at: UnixTs,
        reasoning_text: String,
    },
    FunctionCall {
        node_id: HistoryNodeId,
        parent_node_id: Option<HistoryNodeId>,
        created_at: UnixTs,
        function_call_id: FunctionCallId,
        tool_name: ToolName,
        arguments: JsonObject,
    },
    FunctionOutput {
        node_id: HistoryNodeId,
        parent_node_id: Option<HistoryNodeId>,
        created_at: UnixTs,
        function_call_node_id: HistoryNodeId,
        function_call_id: FunctionCallId,
        tool_name: ToolName,
        output_text: String,
        is_error: bool,
    },
}

impl HistoryNode {
    pub fn node_id(&self) -> HistoryNodeId {
        match self {
            HistoryNode::Message { node_id, .. }
            | HistoryNode::Reasoning { node_id, .. }
            | HistoryNode::FunctionCall { node_id, .. }
            | HistoryNode::FunctionOutput { node_id, .. } => *node_id,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct CreateRootTaskInput {
    pub task_id: TaskId,
    pub cursor_node_id: HistoryNodeId,
    pub model_profile_key: ModelProfileKey,
    pub reasoning_effort: ReasoningEffort,
    pub enabled_tools: Vec<ToolName>,
    pub now: UnixTs,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ForkTaskInput {
    pub parent_task_id: TaskId,
    pub child_task_id: TaskId,
    pub function_call_node_id: HistoryNodeId,
    pub function_call_id: FunctionCallId,
    pub tool_name: ToolName,
    pub child_user_prompt: String,
    pub now: UnixTs,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ReadTaskInput {
    pub task_id: TaskId,
    pub after_node_id: Option<HistoryNodeId>,
    pub limit: u32,
}

#[derive(Clone, Debug, PartialEq)]
pub struct TaskRead {
    pub task_id: TaskId,
    pub task_status: TaskStatusRow,
    pub state_version: u64,
    pub cursor_node_id: HistoryNodeId,
    pub parent_task_id: Option<TaskId>,
    pub queued_input_count: u64,
    pub history_nodes: Vec<HistoryNode>,
    pub has_more: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct LoadedActiveTask {
    pub task: TaskRow,
    pub cursor_node: HistoryNode,
    pub tool_manifest: ToolManifest,
    pub queued_inputs: Vec<QueuedUserInputRow>,
}

#[derive(Clone, Debug, PartialEq)]
pub enum NewHistoryNodeContent {
    Message(NewMessageNodeContent),
    Reasoning(NewReasoningNodeContent),
    FunctionCall(NewFunctionCallNodeContent),
    FunctionOutput(NewFunctionOutputNodeContent),
}

#[derive(Clone, Debug, PartialEq)]
pub struct NewHistoryNode {
    pub parent_node_id: Option<HistoryNodeId>,
    pub content: NewHistoryNodeContent,
    pub created_at: UnixTs,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NewMessageNodeContent {
    pub message_role: MessageRole,
    pub message_text: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NewReasoningNodeContent {
    pub reasoning_text: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct NewFunctionCallNodeContent {
    pub function_call_id: FunctionCallId,
    pub tool_name: ToolName,
    pub arguments: JsonObject,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NewFunctionOutputNodeContent {
    pub function_call_node_id: HistoryNodeId,
    pub function_call_id: FunctionCallId,
    pub tool_name: ToolName,
    pub output_text: String,
    pub is_error: bool,
}

pub fn open_db(options: OpenDbOptions) -> Result<DbPool, DbError> {
    let mut connection = Connection::open(&options.sqlite_path).map_err(map_error)?;
    connection
        .pragma_update(None, "foreign_keys", "ON")
        .map_err(map_error)?;

    if database_is_empty(&connection)? {
        connection
            .execute_batch(include_str!("schema.sql"))
            .map_err(map_error)?;
    } else {
        migrate_schema(&mut connection)?;
    }

    let db = DbPool {
        connection: Arc::new(Mutex::new(connection)),
    };
    verify_schema(&db)?;
    Ok(db)
}

pub fn verify_schema(db: &DbPool) -> Result<(), DbError> {
    let connection = db.connection()?;
    let actual: Option<String> = connection
        .query_row(
            "SELECT schema_value FROM schema_metadata WHERE schema_key = 'selvedge_schema_version'",
            [],
            |row| row.get(0),
        )
        .optional()
        .map_err(map_error)?;

    if actual.as_deref() == Some(SCHEMA_VERSION) {
        Ok(())
    } else {
        Err(DbError::SchemaMismatch {
            expected: SCHEMA_VERSION.to_owned(),
            actual,
        })
    }
}

pub fn register_tool(db: &DbPool, tool: ToolSpec) -> Result<(), DbError> {
    let mut connection = db.connection()?;
    let tx = connection.transaction().map_err(map_error)?;
    insert_tool_in_tx(&tx, tool, ToolExecutionSource::Harness, false)?;
    tx.commit().map_err(map_error)
}

pub fn register_global_tool(db: &DbPool, tool: ToolSpec) -> Result<(), DbError> {
    let mut connection = db.connection()?;
    let tx = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(map_error)?;
    match read_tool_definition_in_connection(&tx, &tool.name)? {
        Some((stored, source, _)) if stored != tool || source != ToolExecutionSource::Harness => {
            return Err(DbError::Constraint(format!(
                "global harness tool conflicts with stored tool: {}",
                tool.name
            )));
        }
        Some((_, _, true)) => {}
        Some((_, _, false)) => {
            tx.execute(
                "UPDATE tools SET is_global = 1 WHERE tool_name = ?1",
                params![tool.name],
            )
            .map_err(map_error)?;
        }
        None => insert_tool_in_tx(&tx, tool, ToolExecutionSource::Harness, true)?,
    }
    tx.commit().map_err(map_error)
}

pub fn unpublish_global_tool(db: &DbPool, tool_name: &ToolName) -> Result<(), DbError> {
    let mut connection = db.connection()?;
    let tx = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(map_error)?;
    let changed = tx
        .execute(
            "UPDATE tools SET is_global = 0 WHERE tool_name = ?1",
            params![tool_name.0],
        )
        .map_err(map_error)?;
    if changed == 0 {
        return Err(DbError::NotFound);
    }
    tx.commit().map_err(map_error)
}

pub fn read_tool_execution_source(
    db: &DbPool,
    tool_name: &ToolName,
) -> Result<ToolExecutionSource, DbError> {
    let connection = db.connection()?;
    connection
        .query_row(
            "SELECT execution_source_kind, mcp_server_id, remote_tool_name
             FROM tools
             WHERE tool_name = ?1",
            params![tool_name.0],
            |row| {
                decode_tool_execution_source(&row.get::<_, String>(0)?, row.get(1)?, row.get(2)?)
                    .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))
            },
        )
        .optional()
        .map_err(map_error)?
        .ok_or(DbError::NotFound)
}

pub fn create_history_node(db: &DbPool, node: NewHistoryNode) -> Result<HistoryNodeId, DbError> {
    let mut connection = db.connection()?;
    let tx = connection.transaction().map_err(map_error)?;
    let node_id = insert_history_node(&tx, node)?;
    tx.commit().map_err(map_error)?;
    Ok(node_id)
}

pub fn create_root_task(db: &DbPool, input: CreateRootTaskInput) -> Result<TaskRow, DbError> {
    let task_id = input.task_id.clone();
    {
        let mut connection = db.connection()?;
        let tx = connection.transaction().map_err(map_error)?;
        tx.execute(
            "INSERT INTO tasks
             (task_id, task_status, cursor_node_id, model_profile_key, reasoning_effort, state_version, created_at, updated_at)
             VALUES (?1, 'active', ?2, ?3, ?4, 0, ?5, ?5)",
            params![
                input.task_id.0,
                input.cursor_node_id.0,
                input.model_profile_key.0,
                reasoning_effort_to_db(&input.reasoning_effort),
                input.now.0
            ],
        )
        .map_err(map_error)?;
        for tool_name in input.enabled_tools {
            tx.execute(
                "INSERT INTO task_tools (task_id, tool_name) VALUES (?1, ?2)",
                params![task_id.0, tool_name.0],
            )
            .map_err(map_error)?;
        }
        tx.commit().map_err(map_error)?;
    }
    read_task_row(db, &task_id)
}

pub fn fork_task_from_function_call(db: &DbPool, input: ForkTaskInput) -> Result<TaskRow, DbError> {
    if input.child_user_prompt.is_empty() {
        return Err(DbError::Constraint(
            "forked task user prompt cannot be empty".to_owned(),
        ));
    }

    let mut connection = db.connection()?;
    let tx = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(map_error)?;
    let parent = read_task_in_tx(&tx, &input.parent_task_id)?;
    if parent.task_status != TaskStatusRow::Active {
        return Err(DbError::TaskNotActive);
    }
    let safe_parent_node_id = safe_fork_parent_for_open_call_in_tx(&tx, &parent, &input)?;
    let child_prompt_node_id = insert_history_node(
        &tx,
        NewHistoryNode {
            parent_node_id: safe_parent_node_id,
            content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                message_role: MessageRole::User,
                message_text: input.child_user_prompt,
            }),
            created_at: input.now,
        },
    )?;
    tx.execute(
        "INSERT INTO tasks
         (task_id, task_status, cursor_node_id, model_profile_key, reasoning_effort, state_version, created_at, updated_at)
         VALUES (?1, 'active', ?2, ?3, ?4, 0, ?5, ?5)",
        params![
            input.child_task_id.0,
            child_prompt_node_id.0,
            parent.model_profile_key.0,
            reasoning_effort_to_db(&parent.reasoning_effort),
            input.now.0
        ],
    )
    .map_err(map_error)?;
    tx.execute(
        "INSERT INTO task_tools (task_id, tool_name)
         SELECT ?1, tool_name FROM task_tools WHERE task_id = ?2",
        params![input.child_task_id.0, input.parent_task_id.0],
    )
    .map_err(map_error)?;
    tx.execute(
        "INSERT INTO task_parent_edges (parent_task_id, child_task_id, created_at)
         VALUES (?1, ?2, ?3)",
        params![input.parent_task_id.0, input.child_task_id.0, input.now.0],
    )
    .map_err(map_error)?;
    let child = read_task_in_tx(&tx, &input.child_task_id)?;
    tx.commit().map_err(map_error)?;
    Ok(child)
}

pub fn load_active_task(db: &DbPool, task_id: &TaskId) -> Result<LoadedActiveTask, DbError> {
    let task = read_task_row(db, task_id)?;
    if task.task_status != TaskStatusRow::Active {
        return Err(DbError::TaskNotActive);
    }
    let cursor_node = read_history_node(db, &task.cursor_node_id)?;
    let tool_manifest = read_tool_manifest_for_task(db, task_id)?;
    let queued_inputs = list_queued_inputs(db, task_id)?;
    Ok(LoadedActiveTask {
        task,
        cursor_node,
        tool_manifest,
        queued_inputs,
    })
}

pub fn append_user_message_and_move_cursor(
    db: &DbPool,
    task_id: &TaskId,
    message_text: String,
    created_at: UnixTs,
) -> Result<HistoryNodeId, DbError> {
    append_history_node_and_move_cursor(
        db,
        task_id,
        NewHistoryNode {
            parent_node_id: None,
            content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                message_role: MessageRole::User,
                message_text,
            }),
            created_at,
        },
    )
}

pub fn append_model_reply_with_tool_calls_and_move_cursor(
    db: &DbPool,
    task_id: &TaskId,
    assistant_message_text: Option<String>,
    tool_calls: Vec<NewFunctionCallNodeContent>,
    created_at: UnixTs,
) -> Result<Vec<HistoryNodeId>, DbError> {
    if tool_calls.is_empty() {
        return Err(DbError::Constraint(
            "model reply tool call commit requires at least one function call".to_owned(),
        ));
    }
    let mut connection = db.connection()?;
    let tx = connection.transaction().map_err(map_error)?;
    ensure_active_task_in_tx(&tx, task_id)?;
    if let Some(message_text) = assistant_message_text {
        append_node_to_current_cursor_in_tx(
            &tx,
            task_id,
            NewHistoryNodeContent::Message(NewMessageNodeContent {
                message_role: MessageRole::Assistant,
                message_text,
            }),
            created_at,
        )?;
    }
    let mut function_call_node_ids = Vec::with_capacity(tool_calls.len());
    for tool_call in tool_calls {
        let node_id = append_node_to_current_cursor_in_tx(
            &tx,
            task_id,
            NewHistoryNodeContent::FunctionCall(tool_call),
            created_at,
        )?;
        function_call_node_ids.push(node_id);
    }
    tx.commit().map_err(map_error)?;
    Ok(function_call_node_ids)
}

pub fn append_assistant_message_and_drain_queue(
    db: &DbPool,
    task_id: &TaskId,
    message_text: String,
    created_at: UnixTs,
) -> Result<HistoryNodeId, DbError> {
    let mut connection = db.connection()?;
    let tx = connection.transaction().map_err(map_error)?;
    ensure_active_task_in_tx(&tx, task_id)?;
    let mut last_node_id = append_node_to_current_cursor_in_tx(
        &tx,
        task_id,
        NewHistoryNodeContent::Message(NewMessageNodeContent {
            message_role: MessageRole::Assistant,
            message_text,
        }),
        created_at,
    )?;
    if let Some(node_id) = append_all_queued_user_inputs_in_tx(&tx, task_id, created_at)? {
        last_node_id = node_id;
    }
    tx.commit().map_err(map_error)?;
    Ok(last_node_id)
}

pub fn append_function_output_and_drain_queue(
    db: &DbPool,
    task_id: &TaskId,
    output: NewFunctionOutputNodeContent,
    created_at: UnixTs,
) -> Result<HistoryNodeId, DbError> {
    let mut connection = db.connection()?;
    let tx = connection.transaction().map_err(map_error)?;
    ensure_active_task_in_tx(&tx, task_id)?;
    let current_cursor_node_id = current_cursor_node_id_in_tx(&tx, task_id)?;
    ensure_current_path_contains_open_function_call(&tx, current_cursor_node_id, &output)?;
    let mut last_node_id = append_node_to_current_cursor_in_tx(
        &tx,
        task_id,
        NewHistoryNodeContent::FunctionOutput(output),
        created_at,
    )?;
    if let Some(node_id) = append_all_queued_user_inputs_in_tx(&tx, task_id, created_at)? {
        last_node_id = node_id;
    }
    tx.commit().map_err(map_error)?;
    Ok(last_node_id)
}

pub fn drain_queued_user_inputs_and_move_cursor(
    db: &DbPool,
    task_id: &TaskId,
    created_at: UnixTs,
) -> Result<Option<HistoryNodeId>, DbError> {
    let mut connection = db.connection()?;
    let tx = connection.transaction().map_err(map_error)?;
    ensure_active_task_in_tx(&tx, task_id)?;
    let last_node_id = append_all_queued_user_inputs_in_tx(&tx, task_id, created_at)?;
    tx.commit().map_err(map_error)?;
    Ok(last_node_id)
}

pub fn read_open_function_calls_for_task(
    db: &DbPool,
    task_id: &TaskId,
) -> Result<Vec<OpenFunctionCall>, DbError> {
    let task = load_active_task(db, task_id)?.task;
    let connection = db.connection()?;
    let mut nodes = Vec::new();
    let mut next_node_id = Some(task.cursor_node_id);
    while let Some(node_id) = next_node_id {
        let node = read_history_node_concrete_in_connection(&connection, &node_id)?;
        next_node_id = match &node {
            HistoryNode::Message { parent_node_id, .. }
            | HistoryNode::Reasoning { parent_node_id, .. }
            | HistoryNode::FunctionCall { parent_node_id, .. }
            | HistoryNode::FunctionOutput { parent_node_id, .. } => *parent_node_id,
        };
        nodes.push(node);
    }
    nodes.reverse();

    let mut open_calls = Vec::<OpenFunctionCall>::new();
    for node in nodes {
        match node {
            HistoryNode::FunctionCall {
                node_id,
                function_call_id,
                tool_name,
                arguments,
                ..
            } => {
                open_calls.push(OpenFunctionCall {
                    function_call_node_id: node_id,
                    function_call_id,
                    tool_name,
                    arguments,
                });
            }
            HistoryNode::FunctionOutput {
                function_call_node_id,
                function_call_id,
                tool_name,
                ..
            } => {
                if let Some(index) = open_calls.iter().position(|call| {
                    call.function_call_node_id == function_call_node_id
                        && call.function_call_id == function_call_id
                        && call.tool_name == tool_name
                }) {
                    open_calls.remove(index);
                } else {
                    return Err(DbError::Constraint(
                        "function output must reference a prior open function call".to_owned(),
                    ));
                }
            }
            HistoryNode::Message { .. } | HistoryNode::Reasoning { .. } => {}
        }
    }
    Ok(open_calls)
}

fn append_history_node_and_move_cursor(
    db: &DbPool,
    task_id: &TaskId,
    mut node: NewHistoryNode,
) -> Result<HistoryNodeId, DbError> {
    let mut connection = db.connection()?;
    let tx = connection.transaction().map_err(map_error)?;
    ensure_active_task_in_tx(&tx, task_id)?;
    let current_cursor_node_id = current_cursor_node_id_in_tx(&tx, task_id)?;

    // Task edges and history edges are separate models. Append means the DB
    // reads the task cursor, creates a child history node under that cursor,
    // and moves the task cursor in one transaction. Runtime cursor caches are
    // hints for request building, not a second source of truth.
    node.parent_node_id = Some(HistoryNodeId(current_cursor_node_id));

    if let NewHistoryNodeContent::FunctionOutput(content) = &node.content {
        ensure_current_path_contains_open_function_call(&tx, current_cursor_node_id, content)?;
    }

    let updated_at = node.created_at;
    let node_id = insert_history_node(&tx, node)?;
    let changed = tx
        .execute(
            "UPDATE tasks
             SET cursor_node_id = ?1, updated_at = ?2, state_version = state_version + 1
             WHERE task_id = ?3 AND task_status = 'active'",
            params![node_id.0, updated_at.0, task_id.0],
        )
        .map_err(map_error)?;
    if changed == 0 {
        return Err(DbError::TaskNotActive);
    }
    tx.commit().map_err(map_error)?;
    Ok(node_id)
}

fn current_cursor_node_id_in_tx(
    tx: &rusqlite::Transaction<'_>,
    task_id: &TaskId,
) -> Result<i64, DbError> {
    tx.query_row(
        "SELECT cursor_node_id FROM tasks WHERE task_id = ?1 AND task_status = 'active'",
        params![task_id.0],
        |row| row.get(0),
    )
    .map_err(map_error)
}

fn append_node_to_current_cursor_in_tx(
    tx: &rusqlite::Transaction<'_>,
    task_id: &TaskId,
    content: NewHistoryNodeContent,
    created_at: UnixTs,
) -> Result<HistoryNodeId, DbError> {
    let current_cursor_node_id = current_cursor_node_id_in_tx(tx, task_id)?;
    let node_id = insert_history_node(
        tx,
        NewHistoryNode {
            parent_node_id: Some(HistoryNodeId(current_cursor_node_id)),
            content,
            created_at,
        },
    )?;
    update_task_cursor_in_tx(tx, task_id, node_id, created_at)?;
    Ok(node_id)
}

fn append_all_queued_user_inputs_in_tx(
    tx: &rusqlite::Transaction<'_>,
    task_id: &TaskId,
    created_at: UnixTs,
) -> Result<Option<HistoryNodeId>, DbError> {
    let queued_inputs = {
        let mut statement = tx
            .prepare(
                "SELECT task_id, seq_no, message_text, queued_at
                 FROM queued_user_inputs
                 WHERE task_id = ?1
                 ORDER BY seq_no ASC",
            )
            .map_err(map_error)?;
        statement
            .query_map(params![task_id.0], map_queued_user_input_row)
            .map_err(map_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(map_error)?
    };

    let mut last_node_id = None;
    for queued in queued_inputs {
        let node_id = append_node_to_current_cursor_in_tx(
            tx,
            task_id,
            NewHistoryNodeContent::Message(NewMessageNodeContent {
                message_role: MessageRole::User,
                message_text: queued.message_text,
            }),
            created_at,
        )?;
        tx.execute(
            "DELETE FROM queued_user_inputs WHERE task_id = ?1 AND seq_no = ?2",
            params![queued.task_id.0, u64_to_i64(queued.seq_no)?],
        )
        .map_err(map_error)?;
        last_node_id = Some(node_id);
    }
    Ok(last_node_id)
}

fn update_task_cursor_in_tx(
    tx: &rusqlite::Transaction<'_>,
    task_id: &TaskId,
    node_id: HistoryNodeId,
    updated_at: UnixTs,
) -> Result<(), DbError> {
    let changed = tx
        .execute(
            "UPDATE tasks
             SET cursor_node_id = ?1, updated_at = ?2, state_version = state_version + 1
             WHERE task_id = ?3 AND task_status = 'active'",
            params![node_id.0, updated_at.0, task_id.0],
        )
        .map_err(map_error)?;
    if changed == 0 {
        Err(DbError::TaskNotActive)
    } else {
        Ok(())
    }
}

pub fn queue_user_input(
    db: &DbPool,
    task_id: &TaskId,
    message_text: String,
    queued_at: UnixTs,
) -> Result<QueuedUserInputRow, DbError> {
    let mut connection = db.connection()?;
    let tx = connection.transaction().map_err(map_error)?;
    ensure_active_task_in_tx(&tx, task_id)?;
    let next_seq_no: i64 = tx
        .query_row(
            "SELECT COALESCE(MAX(seq_no), 0) + 1 FROM queued_user_inputs WHERE task_id = ?1",
            params![task_id.0],
            |row| row.get(0),
        )
        .map_err(map_error)?;
    tx.execute(
        "INSERT INTO queued_user_inputs (task_id, seq_no, message_text, queued_at)
         VALUES (?1, ?2, ?3, ?4)",
        params![task_id.0, next_seq_no, message_text, queued_at.0],
    )
    .map_err(map_error)?;
    tx.commit().map_err(map_error)?;
    Ok(QueuedUserInputRow {
        task_id: task_id.clone(),
        seq_no: i64_to_u64(next_seq_no)?,
        message_text,
        queued_at,
    })
}

pub fn consume_next_queued_user_input(
    db: &DbPool,
    task_id: &TaskId,
) -> Result<Option<QueuedUserInputRow>, DbError> {
    let mut connection = db.connection()?;
    let tx = connection.transaction().map_err(map_error)?;
    ensure_active_task_in_tx(&tx, task_id)?;
    let queued = tx
        .query_row(
            "SELECT task_id, seq_no, message_text, queued_at
             FROM queued_user_inputs
             WHERE task_id = ?1
             ORDER BY seq_no ASC
             LIMIT 1",
            params![task_id.0],
            map_queued_user_input_row,
        )
        .optional()
        .map_err(map_error)?;
    if let Some(queued) = &queued {
        tx.execute(
            "DELETE FROM queued_user_inputs WHERE task_id = ?1 AND seq_no = ?2",
            params![queued.task_id.0, u64_to_i64(queued.seq_no)?],
        )
        .map_err(map_error)?;
    }
    tx.commit().map_err(map_error)?;
    Ok(queued)
}

pub fn append_next_queued_user_input_and_move_cursor(
    db: &DbPool,
    task_id: &TaskId,
    created_at: UnixTs,
) -> Result<Option<HistoryNodeId>, DbError> {
    let mut connection = db.connection()?;
    let tx = connection.transaction().map_err(map_error)?;
    ensure_active_task_in_tx(&tx, task_id)?;
    let queued = tx
        .query_row(
            "SELECT task_id, seq_no, message_text, queued_at
             FROM queued_user_inputs
             WHERE task_id = ?1
             ORDER BY seq_no ASC
             LIMIT 1",
            params![task_id.0],
            map_queued_user_input_row,
        )
        .optional()
        .map_err(map_error)?;
    let Some(queued) = queued else {
        tx.commit().map_err(map_error)?;
        return Ok(None);
    };
    let current_cursor_node_id: i64 = tx
        .query_row(
            "SELECT cursor_node_id FROM tasks WHERE task_id = ?1 AND task_status = 'active'",
            params![task_id.0],
            |row| row.get(0),
        )
        .map_err(map_error)?;
    let node_id = insert_history_node(
        &tx,
        NewHistoryNode {
            parent_node_id: Some(HistoryNodeId(current_cursor_node_id)),
            content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                message_role: MessageRole::User,
                message_text: queued.message_text,
            }),
            created_at,
        },
    )?;
    let changed = tx
        .execute(
            "UPDATE tasks
         SET cursor_node_id = ?1, updated_at = ?2, state_version = state_version + 1
         WHERE task_id = ?3 AND task_status = 'active' AND cursor_node_id = ?4",
            params![node_id.0, created_at.0, task_id.0, current_cursor_node_id],
        )
        .map_err(map_error)?;
    if changed == 0 {
        return Err(DbError::Constraint(
            "queued input append cursor changed before update".to_owned(),
        ));
    }
    tx.execute(
        "DELETE FROM queued_user_inputs WHERE task_id = ?1 AND seq_no = ?2",
        params![queued.task_id.0, u64_to_i64(queued.seq_no)?],
    )
    .map_err(map_error)?;
    tx.commit().map_err(map_error)?;
    Ok(Some(node_id))
}

pub fn archive_task(db: &DbPool, task_id: &TaskId, now: UnixTs) -> Result<(), DbError> {
    let mut connection = db.connection()?;
    let tx = connection.transaction().map_err(map_error)?;
    ensure_active_task_in_tx(&tx, task_id)?;
    tx.execute(
        "DELETE FROM queued_user_inputs WHERE task_id = ?1",
        params![task_id.0],
    )
    .map_err(map_error)?;
    let changed = tx
        .execute(
            "UPDATE tasks
             SET task_status = 'archived', updated_at = ?1, state_version = state_version + 1
             WHERE task_id = ?2 AND task_status = 'active'",
            params![now.0, task_id.0],
        )
        .map_err(map_error)?;
    if changed == 0 {
        Err(DbError::TaskNotActive)
    } else {
        tx.commit().map_err(map_error)?;
        Ok(())
    }
}

pub fn list_active_tasks(db: &DbPool) -> Result<Vec<TaskRow>, DbError> {
    let connection = db.connection()?;
    let mut statement = connection
        .prepare(
            "SELECT task_id, task_status, cursor_node_id, model_profile_key, reasoning_effort, state_version, created_at, updated_at
             FROM tasks
             WHERE task_status = 'active'
             ORDER BY updated_at DESC, task_id ASC",
        )
        .map_err(map_error)?;
    let rows = statement
        .query_map([], map_task_row)
        .map_err(map_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(map_error)?;
    Ok(rows)
}

pub fn read_task_parent_edges(db: &DbPool) -> Result<Vec<TaskParentEdgeRow>, DbError> {
    let connection = db.connection()?;
    let mut statement = connection
        .prepare(
            "SELECT parent_task_id, child_task_id, created_at
             FROM task_parent_edges
             ORDER BY parent_task_id ASC, child_task_id ASC",
        )
        .map_err(map_error)?;
    statement
        .query_map([], |row| {
            Ok(TaskParentEdgeRow {
                parent_task_id: TaskId(row.get(0)?),
                child_task_id: TaskId(row.get(1)?),
                created_at: UnixTs(row.get(2)?),
            })
        })
        .map_err(map_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(map_error)
}

pub fn read_task(db: &DbPool, input: ReadTaskInput) -> Result<TaskRead, DbError> {
    if input.limit == 0 || input.limit > MAX_TASK_HISTORY_PAGE_SIZE {
        return Err(DbError::Constraint(format!(
            "task history page limit must be between 1 and {MAX_TASK_HISTORY_PAGE_SIZE}"
        )));
    }

    let mut connection = db.connection()?;
    let tx = connection.transaction().map_err(map_error)?;
    let task = read_task_in_tx(&tx, &input.task_id)?;
    if let Some(after_node_id) = input.after_node_id {
        ensure_task_path_contains_node_in_tx(&tx, task.cursor_node_id, after_node_id)?;
    }
    let mut node_ids = read_history_page_node_ids_in_tx(
        &tx,
        task.cursor_node_id,
        input.after_node_id,
        input.limit + 1,
    )?;
    let has_more = node_ids.len() > input.limit as usize;
    node_ids.truncate(input.limit as usize);
    let mut history_nodes = Vec::with_capacity(node_ids.len());
    for node_id in node_ids {
        history_nodes.push(read_history_node_concrete_in_connection(&tx, &node_id)?);
    }
    let parent_task_id = tx
        .query_row(
            "SELECT parent_task_id
             FROM task_parent_edges
             WHERE child_task_id = ?1",
            params![input.task_id.0],
            |row| row.get::<_, String>(0).map(TaskId),
        )
        .optional()
        .map_err(map_error)?;
    let queued_input_count: i64 = tx
        .query_row(
            "SELECT COUNT(*) FROM queued_user_inputs WHERE task_id = ?1",
            params![input.task_id.0],
            |row| row.get(0),
        )
        .map_err(map_error)?;
    let result = TaskRead {
        task_id: task.task_id,
        task_status: task.task_status,
        state_version: task.state_version,
        cursor_node_id: task.cursor_node_id,
        parent_task_id,
        queued_input_count: i64_to_u64(queued_input_count)?,
        history_nodes,
        has_more,
    };
    tx.commit().map_err(map_error)?;
    Ok(result)
}

pub fn read_tool_manifest_for_task(db: &DbPool, task_id: &TaskId) -> Result<ToolManifest, DbError> {
    let connection = db.connection()?;
    ensure_task_exists(&connection, task_id)?;
    let mut statement = connection
        .prepare(
            "SELECT t.tool_name, t.description_text, t.input_schema_json
             FROM tools t
             LEFT JOIN task_tools tt
               ON tt.tool_name = t.tool_name
              AND tt.task_id = ?1
             WHERE t.is_global = 1 OR tt.task_id IS NOT NULL
             ORDER BY t.tool_name ASC",
        )
        .map_err(map_error)?;
    let tools = statement
        .query_map(params![task_id.0], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
            ))
        })
        .map_err(map_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(map_error)?;

    let mut manifest_tools = Vec::with_capacity(tools.len());
    for (name, description, input_schema_json) in tools {
        manifest_tools.push(ToolSpec {
            name,
            description,
            input_schema: decode_json_object(&input_schema_json)?,
        });
    }
    Ok(ToolManifest {
        tools: manifest_tools,
    })
}

pub fn read_conversation_for_task(db: &DbPool, task_id: &TaskId) -> Result<Conversation, DbError> {
    let task = load_active_task(db, task_id)?.task;
    let connection = db.connection()?;
    let mut nodes = Vec::new();
    let mut next_node_id = Some(task.cursor_node_id);
    while let Some(node_id) = next_node_id {
        let node = read_history_node_in_connection(&connection, &node_id)?;
        next_node_id = node.parent_node_id;
        nodes.push(node);
    }
    nodes.reverse();

    let mut items = Vec::with_capacity(nodes.len());
    for node in nodes {
        match node.content_kind {
            HistoryContentKindRow::Message => {
                let row = read_message_node(&connection, &node.node_id)?;
                items.push(ConversationItem::Message {
                    role: row.message_role,
                    text: row.message_text,
                });
            }
            HistoryContentKindRow::FunctionCall => {
                let row = read_function_call_node(&connection, &node.node_id)?;
                items.push(ConversationItem::FunctionCall {
                    function_call_id: row.function_call_id,
                    tool_name: row.tool_name,
                    arguments: read_function_call_arguments(&connection, &node.node_id)?,
                });
            }
            HistoryContentKindRow::FunctionOutput => {
                let row = read_function_output_node(&connection, &node.node_id)?;
                items.push(ConversationItem::FunctionOutput {
                    function_call_id: row.function_call_id,
                    tool_name: row.tool_name,
                    output_text: row.output_text,
                    is_error: row.is_error,
                });
            }
            HistoryContentKindRow::Reasoning => {}
        }
    }

    Ok(Conversation { items })
}

impl DbPool {
    fn connection(&self) -> Result<MutexGuard<'_, Connection>, DbError> {
        self.connection
            .lock()
            .map_err(|error| DbError::Storage(format!("database mutex is poisoned: {error}")))
    }
}

fn migrate_schema(connection: &mut Connection) -> Result<(), DbError> {
    let tx = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(map_error)?;
    let actual: Option<String> = tx
        .query_row(
            "SELECT schema_value
             FROM schema_metadata
             WHERE schema_key = 'selvedge_schema_version'",
            [],
            |row| row.get(0),
        )
        .optional()
        .map_err(map_error)?;
    if actual.as_deref() != Some(PREVIOUS_SCHEMA_VERSION) {
        tx.rollback().map_err(map_error)?;
        return Ok(());
    }

    tx.execute_batch(
        "ALTER TABLE tools
             ADD COLUMN input_schema_json TEXT NOT NULL DEFAULT '{}'
             CHECK (json_valid(input_schema_json) AND json_type(input_schema_json) = 'object');
         ALTER TABLE tools ADD COLUMN mcp_server_id TEXT;
         ALTER TABLE tools ADD COLUMN remote_tool_name TEXT;
         ALTER TABLE tools
             ADD COLUMN execution_source_kind TEXT NOT NULL DEFAULT 'harness'
             CHECK (
                 (
                     execution_source_kind = 'harness'
                     AND mcp_server_id IS NULL
                     AND remote_tool_name IS NULL
                 )
                 OR
                 (
                     execution_source_kind = 'mcp'
                     AND mcp_server_id IS NOT NULL
                     AND remote_tool_name IS NOT NULL
                     AND length(mcp_server_id) > 0
                     AND length(remote_tool_name) > 0
                 )
             );
         ALTER TABLE history_function_call_nodes
             ADD COLUMN arguments_json TEXT NOT NULL DEFAULT '{}'
             CHECK (json_valid(arguments_json) AND json_type(arguments_json) = 'object');",
    )
    .map_err(map_error)?;

    let tool_names = {
        let mut statement = tx
            .prepare("SELECT tool_name FROM tools ORDER BY tool_name ASC")
            .map_err(map_error)?;
        statement
            .query_map([], |row| row.get::<_, String>(0))
            .map_err(map_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(map_error)?
    };
    for tool_name in tool_names {
        let parameters = {
            let mut statement = tx
                .prepare(
                    "SELECT parameter_name, parameter_type, description_text, is_required
                     FROM tool_parameters
                     WHERE tool_name = ?1
                     ORDER BY parameter_name ASC",
                )
                .map_err(map_error)?;
            statement
                .query_map(params![tool_name], |row| {
                    Ok(LegacyToolParameter {
                        name: row.get(0)?,
                        parameter_type: row.get(1)?,
                        description: row.get(2)?,
                        required: row.get::<_, i64>(3)? == 1,
                    })
                })
                .map_err(map_error)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(map_error)?
        };
        let input_schema_json = encode_json_object(&legacy_input_schema(parameters)?)?;
        tx.execute(
            "UPDATE tools SET input_schema_json = ?1 WHERE tool_name = ?2",
            params![input_schema_json, tool_name],
        )
        .map_err(map_error)?;
    }

    let function_call_node_ids = {
        let mut statement = tx
            .prepare("SELECT node_id FROM history_function_call_nodes ORDER BY node_id ASC")
            .map_err(map_error)?;
        statement
            .query_map([], |row| row.get::<_, i64>(0))
            .map_err(map_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(map_error)?
    };
    for node_id in function_call_node_ids {
        let arguments = {
            let mut statement = tx
                .prepare(
                    "SELECT argument_name, value_type, string_value, integer_value,
                            number_value, boolean_value
                     FROM history_function_call_arguments
                     WHERE function_call_node_id = ?1
                     ORDER BY argument_name ASC",
                )
                .map_err(map_error)?;
            let rows = statement
                .query_map(params![node_id], |row| {
                    Ok(LegacyArgument {
                        name: row.get(0)?,
                        value_type: row.get(1)?,
                        string_value: row.get(2)?,
                        integer_value: row.get(3)?,
                        number_value: row.get(4)?,
                        boolean_value: row.get(5)?,
                    })
                })
                .map_err(map_error)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(map_error)?;
            legacy_arguments(rows)?
        };
        tx.execute(
            "UPDATE history_function_call_nodes
             SET arguments_json = ?1
             WHERE node_id = ?2",
            params![encode_json_object(&arguments)?, node_id],
        )
        .map_err(map_error)?;
    }

    tx.execute_batch(
        "DROP TABLE history_function_call_arguments;
         DROP TABLE tool_parameters;",
    )
    .map_err(map_error)?;
    tx.execute(
        "UPDATE schema_metadata
         SET schema_value = ?1
         WHERE schema_key = 'selvedge_schema_version'",
        params![SCHEMA_VERSION],
    )
    .map_err(map_error)?;
    tx.commit().map_err(map_error)
}

fn database_is_empty(connection: &Connection) -> Result<bool, DbError> {
    let count: i64 = connection
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
            [],
            |row| row.get(0),
        )
        .map_err(map_error)?;
    Ok(count == 0)
}

fn read_task_row(db: &DbPool, task_id: &TaskId) -> Result<TaskRow, DbError> {
    let connection = db.connection()?;
    connection
        .query_row(
            "SELECT task_id, task_status, cursor_node_id, model_profile_key, reasoning_effort, state_version, created_at, updated_at
             FROM tasks
             WHERE task_id = ?1",
            params![task_id.0],
            map_task_row,
        )
        .optional()
        .map_err(map_error)?
        .ok_or(DbError::NotFound)
}

fn read_task_in_tx(tx: &rusqlite::Transaction<'_>, task_id: &TaskId) -> Result<TaskRow, DbError> {
    tx.query_row(
        "SELECT task_id, task_status, cursor_node_id, model_profile_key, reasoning_effort, state_version, created_at, updated_at
         FROM tasks
         WHERE task_id = ?1",
        params![task_id.0],
        map_task_row,
    )
    .optional()
    .map_err(map_error)?
    .ok_or(DbError::NotFound)
}

fn safe_fork_parent_for_open_call_in_tx(
    tx: &rusqlite::Transaction<'_>,
    parent: &TaskRow,
    input: &ForkTaskInput,
) -> Result<Option<HistoryNodeId>, DbError> {
    let safe_parent_node_id = tx
        .query_row(
            "WITH RECURSIVE current_path(node_id, parent_node_id) AS (
                SELECT node_id, parent_node_id
                FROM history_nodes
                WHERE node_id = ?1
                UNION ALL
                SELECT parent.node_id, parent.parent_node_id
                FROM history_nodes parent
                JOIN current_path child ON parent.node_id = child.parent_node_id
             ),
             target_call(node_id, parent_node_id) AS (
                SELECT path.node_id, path.parent_node_id
                FROM current_path path
                JOIN history_function_call_nodes calls ON calls.node_id = path.node_id
                LEFT JOIN history_function_output_nodes outputs
                  ON outputs.function_call_node_id = calls.node_id
                WHERE calls.node_id = ?2
                  AND calls.function_call_id = ?3
                  AND calls.tool_name = ?4
                  AND outputs.node_id IS NULL
             ),
             call_batch(node_id, parent_node_id, depth) AS (
                SELECT node_id, parent_node_id, 0
                FROM target_call
                UNION ALL
                SELECT parent.node_id, parent.parent_node_id, batch.depth + 1
                FROM history_nodes parent
                JOIN call_batch batch ON parent.node_id = batch.parent_node_id
                WHERE parent.content_kind = 'function_call'
             )
             SELECT parent_node_id
             FROM call_batch
             ORDER BY depth DESC
             LIMIT 1",
            params![
                parent.cursor_node_id.0,
                input.function_call_node_id.0,
                input.function_call_id.0,
                input.tool_name.0
            ],
            |row| row.get::<_, Option<i64>>(0),
        )
        .optional()
        .map_err(map_error)?;

    safe_parent_node_id
        .map(|node_id| node_id.map(HistoryNodeId))
        .ok_or(DbError::StaleFunctionCall)
}

fn ensure_task_path_contains_node_in_tx(
    tx: &rusqlite::Transaction<'_>,
    cursor_node_id: HistoryNodeId,
    node_id: HistoryNodeId,
) -> Result<(), DbError> {
    let exists: bool = tx
        .query_row(
            "WITH RECURSIVE current_path(node_id, parent_node_id) AS (
                SELECT node_id, parent_node_id
                FROM history_nodes
                WHERE node_id = ?1
                UNION ALL
                SELECT parent.node_id, parent.parent_node_id
                FROM history_nodes parent
                JOIN current_path child ON parent.node_id = child.parent_node_id
             )
             SELECT EXISTS(
                SELECT 1 FROM current_path WHERE node_id = ?2
             )",
            params![cursor_node_id.0, node_id.0],
            |row| row.get(0),
        )
        .map_err(map_error)?;
    if exists {
        Ok(())
    } else {
        Err(DbError::HistoryCursorNotOnTask)
    }
}

fn read_history_page_node_ids_in_tx(
    tx: &rusqlite::Transaction<'_>,
    cursor_node_id: HistoryNodeId,
    after_node_id: Option<HistoryNodeId>,
    limit: u32,
) -> Result<Vec<HistoryNodeId>, DbError> {
    let mut statement = tx
        .prepare(
            "WITH RECURSIVE current_path(node_id, parent_node_id, depth) AS (
                SELECT node_id, parent_node_id, 0
                FROM history_nodes
                WHERE node_id = ?1
                UNION ALL
                SELECT parent.node_id, parent.parent_node_id, child.depth + 1
                FROM history_nodes parent
                JOIN current_path child ON parent.node_id = child.parent_node_id
             )
             SELECT node_id
             FROM current_path
             WHERE ?2 IS NULL
                OR depth < (
                    SELECT depth FROM current_path WHERE node_id = ?2
                )
             ORDER BY depth DESC
             LIMIT ?3",
        )
        .map_err(map_error)?;
    statement
        .query_map(
            params![
                cursor_node_id.0,
                after_node_id.map(|node_id| node_id.0),
                i64::from(limit)
            ],
            |row| row.get::<_, i64>(0).map(HistoryNodeId),
        )
        .map_err(map_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(map_error)
}

fn ensure_current_path_contains_open_function_call(
    tx: &rusqlite::Transaction<'_>,
    current_cursor_node_id: i64,
    output: &NewFunctionOutputNodeContent,
) -> Result<(), DbError> {
    // Provider APIs pair tool results with prior tool calls by call id. A
    // model turn may contain several tool calls, so the matching call can be
    // earlier in the current conversation path while later sibling calls are
    // still waiting for results. The DB checks that the output references a
    // real call on the active path and that this call has a single output.
    let exists: bool = tx
        .query_row(
            "WITH RECURSIVE current_path(node_id, parent_node_id) AS (
                SELECT node_id, parent_node_id
                FROM history_nodes
                WHERE node_id = ?1
                UNION ALL
                SELECT parent.node_id, parent.parent_node_id
                FROM history_nodes parent
                JOIN current_path child ON parent.node_id = child.parent_node_id
             )
             SELECT EXISTS(
                SELECT 1
                FROM current_path path
                JOIN history_function_call_nodes calls ON calls.node_id = path.node_id
                WHERE calls.node_id = ?2
                  AND calls.function_call_id = ?3
                  AND calls.tool_name = ?4
             )",
            params![
                current_cursor_node_id,
                output.function_call_node_id.0,
                output.function_call_id.0,
                output.tool_name.0
            ],
            |row| row.get(0),
        )
        .map_err(map_error)?;

    if !exists {
        return Err(DbError::Constraint(
            "function output must reference an open function call id and tool".to_owned(),
        ));
    }

    let output_exists: bool = tx
        .query_row(
            "SELECT EXISTS(
                SELECT 1
                FROM history_function_call_nodes
                JOIN history_function_output_nodes
                  ON history_function_output_nodes.function_call_node_id = history_function_call_nodes.node_id
                WHERE history_function_call_nodes.node_id = ?1
                  AND history_function_call_nodes.function_call_id = ?2
                  AND history_function_call_nodes.tool_name = ?3
             )",
            params![
                output.function_call_node_id.0,
                output.function_call_id.0,
                output.tool_name.0
            ],
            |row| row.get(0),
        )
        .map_err(map_error)?;

    if output_exists {
        Err(DbError::Constraint(
            "function output already exists for function call id and tool".to_owned(),
        ))
    } else {
        Ok(())
    }
}

fn read_history_node(db: &DbPool, node_id: &HistoryNodeId) -> Result<HistoryNode, DbError> {
    let connection = db.connection()?;
    read_history_node_concrete_in_connection(&connection, node_id)
}

fn read_history_node_concrete_in_connection(
    connection: &Connection,
    node_id: &HistoryNodeId,
) -> Result<HistoryNode, DbError> {
    let base = read_history_node_in_connection(connection, node_id)?;
    match base.content_kind {
        HistoryContentKindRow::Message => {
            let row = read_message_node(connection, &base.node_id)?;
            Ok(HistoryNode::Message {
                node_id: base.node_id,
                parent_node_id: base.parent_node_id,
                created_at: base.created_at,
                message_role: row.message_role,
                message_text: row.message_text,
            })
        }
        HistoryContentKindRow::Reasoning => {
            let row = read_reasoning_node(connection, &base.node_id)?;
            Ok(HistoryNode::Reasoning {
                node_id: base.node_id,
                parent_node_id: base.parent_node_id,
                created_at: base.created_at,
                reasoning_text: row.reasoning_text,
            })
        }
        HistoryContentKindRow::FunctionCall => {
            let row = read_function_call_node(connection, &base.node_id)?;
            Ok(HistoryNode::FunctionCall {
                node_id: base.node_id,
                parent_node_id: base.parent_node_id,
                created_at: base.created_at,
                function_call_id: row.function_call_id,
                tool_name: row.tool_name,
                arguments: read_function_call_arguments(connection, &base.node_id)?,
            })
        }
        HistoryContentKindRow::FunctionOutput => {
            let row = read_function_output_node(connection, &base.node_id)?;
            Ok(HistoryNode::FunctionOutput {
                node_id: base.node_id,
                parent_node_id: base.parent_node_id,
                created_at: base.created_at,
                function_call_node_id: row.function_call_node_id,
                function_call_id: row.function_call_id,
                tool_name: row.tool_name,
                output_text: row.output_text,
                is_error: row.is_error,
            })
        }
    }
}

fn read_history_node_in_connection(
    connection: &Connection,
    node_id: &HistoryNodeId,
) -> Result<HistoryNodeRow, DbError> {
    connection
        .query_row(
            "SELECT node_id, parent_node_id, content_kind, created_at
             FROM history_nodes
             WHERE node_id = ?1",
            params![node_id.0],
            map_history_node_row,
        )
        .optional()
        .map_err(map_error)?
        .ok_or(DbError::NotFound)
}

fn list_queued_inputs(db: &DbPool, task_id: &TaskId) -> Result<Vec<QueuedUserInputRow>, DbError> {
    let connection = db.connection()?;
    let mut statement = connection
        .prepare(
            "SELECT task_id, seq_no, message_text, queued_at
             FROM queued_user_inputs
             WHERE task_id = ?1
             ORDER BY seq_no ASC",
        )
        .map_err(map_error)?;
    statement
        .query_map(params![task_id.0], map_queued_user_input_row)
        .map_err(map_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(map_error)
}

fn insert_tool_in_tx(
    tx: &rusqlite::Transaction<'_>,
    tool: ToolSpec,
    execution_source: ToolExecutionSource,
    is_global: bool,
) -> Result<(), DbError> {
    let (execution_source_kind, mcp_server_id, remote_tool_name) =
        encode_tool_execution_source(execution_source);
    tx.execute(
        "INSERT INTO tools
         (tool_name, description_text, input_schema_json, execution_source_kind,
          mcp_server_id, remote_tool_name, is_global)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![
            tool.name,
            tool.description,
            encode_json_object(&tool.input_schema)?,
            execution_source_kind,
            mcp_server_id,
            remote_tool_name,
            bool_to_i64(is_global)
        ],
    )
    .map_err(map_error)?;
    Ok(())
}

fn read_tool_definition_in_connection(
    connection: &Connection,
    tool_name: &str,
) -> Result<Option<(ToolSpec, ToolExecutionSource, bool)>, DbError> {
    let stored = connection
        .query_row(
            "SELECT description_text, input_schema_json, execution_source_kind,
                    mcp_server_id, remote_tool_name, is_global
             FROM tools
             WHERE tool_name = ?1",
            params![tool_name],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    decode_tool_execution_source(
                        &row.get::<_, String>(2)?,
                        row.get(3)?,
                        row.get(4)?,
                    )
                    .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?,
                    row.get::<_, i64>(5)? == 1,
                ))
            },
        )
        .optional()
        .map_err(map_error)?;
    let Some((description, input_schema_json, execution_source, is_global)) = stored else {
        return Ok(None);
    };
    Ok(Some((
        ToolSpec {
            name: tool_name.to_owned(),
            description,
            input_schema: decode_json_object(&input_schema_json)?,
        },
        execution_source,
        is_global,
    )))
}

fn insert_history_node(
    tx: &rusqlite::Transaction<'_>,
    node: NewHistoryNode,
) -> Result<HistoryNodeId, DbError> {
    let content_kind = content_kind_to_db(&node.content);
    tx.execute(
        "INSERT INTO history_nodes (parent_node_id, content_kind, created_at)
         VALUES (?1, ?2, ?3)",
        params![
            node.parent_node_id.map(|node_id| node_id.0),
            content_kind,
            node.created_at.0
        ],
    )
    .map_err(map_error)?;
    let node_id = HistoryNodeId(tx.last_insert_rowid());
    match node.content {
        NewHistoryNodeContent::Message(content) => insert_message_node(tx, node_id, content)?,
        NewHistoryNodeContent::Reasoning(content) => insert_reasoning_node(tx, node_id, content)?,
        NewHistoryNodeContent::FunctionCall(content) => {
            insert_function_call_node(tx, node_id, content)?
        }
        NewHistoryNodeContent::FunctionOutput(content) => {
            insert_function_output_node(tx, node_id, content)?
        }
    }
    Ok(node_id)
}

fn insert_message_node(
    tx: &rusqlite::Transaction<'_>,
    node_id: HistoryNodeId,
    content: NewMessageNodeContent,
) -> Result<(), DbError> {
    let Some(message_role) = message_role_to_db(&content.message_role) else {
        return Err(DbError::Constraint(
            "message role cannot be persisted as a history message".to_owned(),
        ));
    };
    tx.execute(
        "INSERT INTO history_message_nodes (node_id, message_role, message_text)
         VALUES (?1, ?2, ?3)",
        params![node_id.0, message_role, content.message_text],
    )
    .map_err(map_error)?;
    Ok(())
}

fn insert_reasoning_node(
    tx: &rusqlite::Transaction<'_>,
    node_id: HistoryNodeId,
    content: NewReasoningNodeContent,
) -> Result<(), DbError> {
    tx.execute(
        "INSERT INTO history_reasoning_nodes (node_id, reasoning_text)
         VALUES (?1, ?2)",
        params![node_id.0, content.reasoning_text],
    )
    .map_err(map_error)?;
    Ok(())
}

fn insert_function_call_node(
    tx: &rusqlite::Transaction<'_>,
    node_id: HistoryNodeId,
    content: NewFunctionCallNodeContent,
) -> Result<(), DbError> {
    tx.execute(
        "INSERT INTO history_function_call_nodes
         (node_id, function_call_id, tool_name, arguments_json)
         VALUES (?1, ?2, ?3, ?4)",
        params![
            node_id.0,
            content.function_call_id.0,
            content.tool_name.0,
            encode_json_object(&content.arguments)?
        ],
    )
    .map_err(map_error)?;
    Ok(())
}

fn insert_function_output_node(
    tx: &rusqlite::Transaction<'_>,
    node_id: HistoryNodeId,
    content: NewFunctionOutputNodeContent,
) -> Result<(), DbError> {
    tx.execute(
        "INSERT INTO history_function_output_nodes
         (node_id, function_call_node_id, function_call_id, tool_name, output_text, is_error)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![
            node_id.0,
            content.function_call_node_id.0,
            content.function_call_id.0,
            content.tool_name.0,
            content.output_text,
            bool_to_i64(content.is_error)
        ],
    )
    .map_err(map_error)?;
    Ok(())
}

fn ensure_task_exists(connection: &Connection, task_id: &TaskId) -> Result<(), DbError> {
    let exists: bool = connection
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM tasks WHERE task_id = ?1)",
            params![task_id.0],
            |row| row.get(0),
        )
        .map_err(map_error)?;
    if exists {
        Ok(())
    } else {
        Err(DbError::NotFound)
    }
}

fn ensure_active_task_in_tx(
    tx: &rusqlite::Transaction<'_>,
    task_id: &TaskId,
) -> Result<(), DbError> {
    let status: Option<String> = tx
        .query_row(
            "SELECT task_status FROM tasks WHERE task_id = ?1",
            params![task_id.0],
            |row| row.get(0),
        )
        .optional()
        .map_err(map_error)?;
    match status.as_deref() {
        Some("active") => Ok(()),
        Some(_) => Err(DbError::TaskNotActive),
        None => Err(DbError::NotFound),
    }
}

fn read_message_node(
    connection: &Connection,
    node_id: &HistoryNodeId,
) -> Result<HistoryMessageNodeRow, DbError> {
    connection
        .query_row(
            "SELECT node_id, message_role, message_text FROM history_message_nodes WHERE node_id = ?1",
            params![node_id.0],
            |row| {
                Ok(HistoryMessageNodeRow {
                    node_id: HistoryNodeId(row.get(0)?),
                    message_role: message_role_from_db(&row.get::<_, String>(1)?)
                        .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?,
                    message_text: row.get(2)?,
                })
            },
        )
        .map_err(map_error)
}

fn read_reasoning_node(
    connection: &Connection,
    node_id: &HistoryNodeId,
) -> Result<HistoryReasoningNodeRow, DbError> {
    connection
        .query_row(
            "SELECT node_id, reasoning_text FROM history_reasoning_nodes WHERE node_id = ?1",
            params![node_id.0],
            |row| {
                Ok(HistoryReasoningNodeRow {
                    node_id: HistoryNodeId(row.get(0)?),
                    reasoning_text: row.get(1)?,
                })
            },
        )
        .map_err(map_error)
}

fn read_function_call_node(
    connection: &Connection,
    node_id: &HistoryNodeId,
) -> Result<HistoryFunctionCallNodeRow, DbError> {
    connection
        .query_row(
            "SELECT node_id, function_call_id, tool_name FROM history_function_call_nodes WHERE node_id = ?1",
            params![node_id.0],
            |row| {
                Ok(HistoryFunctionCallNodeRow {
                    node_id: HistoryNodeId(row.get(0)?),
                    function_call_id: FunctionCallId(row.get(1)?),
                    tool_name: ToolName(row.get(2)?),
                })
            },
        )
        .map_err(map_error)
}

fn read_function_call_arguments(
    connection: &Connection,
    node_id: &HistoryNodeId,
) -> Result<JsonObject, DbError> {
    let arguments_json = connection
        .query_row(
            "SELECT arguments_json
             FROM history_function_call_nodes
             WHERE node_id = ?1",
            params![node_id.0],
            |row| row.get::<_, String>(0),
        )
        .map_err(map_error)?;
    decode_json_object(&arguments_json)
}

fn read_function_output_node(
    connection: &Connection,
    node_id: &HistoryNodeId,
) -> Result<HistoryFunctionOutputNodeRow, DbError> {
    connection
        .query_row(
            "SELECT node_id, function_call_node_id, function_call_id, tool_name, output_text, is_error
             FROM history_function_output_nodes
             WHERE node_id = ?1",
            params![node_id.0],
            |row| {
                Ok(HistoryFunctionOutputNodeRow {
                    node_id: HistoryNodeId(row.get(0)?),
                    function_call_node_id: HistoryNodeId(row.get(1)?),
                    function_call_id: FunctionCallId(row.get(2)?),
                    tool_name: ToolName(row.get(3)?),
                    output_text: row.get(4)?,
                    is_error: row.get::<_, i64>(5)? == 1,
                })
            },
        )
        .map_err(map_error)
}

fn map_task_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<TaskRow> {
    Ok(TaskRow {
        task_id: TaskId(row.get(0)?),
        task_status: task_status_from_db(&row.get::<_, String>(1)?)
            .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?,
        cursor_node_id: HistoryNodeId(row.get(2)?),
        model_profile_key: ModelProfileKey(row.get(3)?),
        reasoning_effort: reasoning_effort_from_db(&row.get::<_, String>(4)?)
            .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?,
        state_version: i64_to_u64(row.get(5)?)
            .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?,
        created_at: UnixTs(row.get(6)?),
        updated_at: UnixTs(row.get(7)?),
    })
}

fn map_history_node_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<HistoryNodeRow> {
    let parent_node_id: Option<i64> = row.get(1)?;
    Ok(HistoryNodeRow {
        node_id: HistoryNodeId(row.get(0)?),
        parent_node_id: parent_node_id.map(HistoryNodeId),
        content_kind: content_kind_from_db(&row.get::<_, String>(2)?)
            .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?,
        created_at: UnixTs(row.get(3)?),
    })
}

fn map_queued_user_input_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<QueuedUserInputRow> {
    Ok(QueuedUserInputRow {
        task_id: TaskId(row.get(0)?),
        seq_no: i64_to_u64(row.get(1)?)
            .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?,
        message_text: row.get(2)?,
        queued_at: UnixTs(row.get(3)?),
    })
}

fn content_kind_to_db(content: &NewHistoryNodeContent) -> &'static str {
    match content {
        NewHistoryNodeContent::Message(_) => "message",
        NewHistoryNodeContent::Reasoning(_) => "reasoning",
        NewHistoryNodeContent::FunctionCall(_) => "function_call",
        NewHistoryNodeContent::FunctionOutput(_) => "function_output",
    }
}

fn content_kind_from_db(value: &str) -> Result<HistoryContentKindRow, DbError> {
    match value {
        "message" => Ok(HistoryContentKindRow::Message),
        "reasoning" => Ok(HistoryContentKindRow::Reasoning),
        "function_call" => Ok(HistoryContentKindRow::FunctionCall),
        "function_output" => Ok(HistoryContentKindRow::FunctionOutput),
        other => Err(DbError::Storage(format!(
            "unknown history content kind: {other}"
        ))),
    }
}

fn task_status_from_db(value: &str) -> Result<TaskStatusRow, DbError> {
    match value {
        "active" => Ok(TaskStatusRow::Active),
        "archived" => Ok(TaskStatusRow::Archived),
        other => Err(DbError::Storage(format!("unknown task status: {other}"))),
    }
}

fn message_role_to_db(role: &MessageRole) -> Option<&'static str> {
    match role {
        MessageRole::System => Some("system"),
        MessageRole::Developer => Some("developer"),
        MessageRole::User => Some("user"),
        MessageRole::Assistant => Some("assistant"),
        MessageRole::Tool => None,
    }
}

fn message_role_from_db(value: &str) -> Result<MessageRole, DbError> {
    match value {
        "system" => Ok(MessageRole::System),
        "developer" => Ok(MessageRole::Developer),
        "user" => Ok(MessageRole::User),
        "assistant" => Ok(MessageRole::Assistant),
        other => Err(DbError::Storage(format!("unknown message role: {other}"))),
    }
}

fn reasoning_effort_to_db(value: &ReasoningEffort) -> &'static str {
    match value {
        ReasoningEffort::Minimal => "minimal",
        ReasoningEffort::Low => "low",
        ReasoningEffort::Medium => "medium",
        ReasoningEffort::High => "high",
    }
}

fn reasoning_effort_from_db(value: &str) -> Result<ReasoningEffort, DbError> {
    match value {
        "minimal" => Ok(ReasoningEffort::Minimal),
        "low" => Ok(ReasoningEffort::Low),
        "medium" => Ok(ReasoningEffort::Medium),
        "high" => Ok(ReasoningEffort::High),
        other => Err(DbError::Storage(format!(
            "unknown reasoning effort: {other}"
        ))),
    }
}

struct LegacyToolParameter {
    name: String,
    parameter_type: String,
    description: String,
    required: bool,
}

struct LegacyArgument {
    name: String,
    value_type: String,
    string_value: Option<String>,
    integer_value: Option<i64>,
    number_value: Option<f64>,
    boolean_value: Option<i64>,
}

fn legacy_input_schema(parameters: Vec<LegacyToolParameter>) -> Result<JsonObject, DbError> {
    let mut properties = JsonObject::new();
    let mut required = Vec::new();
    for parameter in parameters {
        if !matches!(
            parameter.parameter_type.as_str(),
            "string" | "integer" | "number" | "boolean"
        ) {
            return Err(DbError::Storage(format!(
                "unknown tool parameter type: {}",
                parameter.parameter_type
            )));
        }
        properties.insert(
            parameter.name.clone(),
            serde_json::Value::Object(JsonObject::from_iter([
                (
                    "type".to_owned(),
                    serde_json::Value::String(parameter.parameter_type),
                ),
                (
                    "description".to_owned(),
                    serde_json::Value::String(parameter.description),
                ),
            ])),
        );
        if parameter.required {
            required.push(serde_json::Value::String(parameter.name));
        }
    }

    Ok(JsonObject::from_iter([
        (
            "type".to_owned(),
            serde_json::Value::String("object".to_owned()),
        ),
        (
            "properties".to_owned(),
            serde_json::Value::Object(properties),
        ),
        ("required".to_owned(), serde_json::Value::Array(required)),
        (
            "additionalProperties".to_owned(),
            serde_json::Value::Bool(false),
        ),
    ]))
}

fn legacy_arguments(arguments: Vec<LegacyArgument>) -> Result<JsonObject, DbError> {
    arguments
        .into_iter()
        .map(|argument| {
            let value = match argument.value_type.as_str() {
                "string" => argument
                    .string_value
                    .map(serde_json::Value::String)
                    .ok_or_else(|| {
                        DbError::Storage("string argument value is missing".to_owned())
                    })?,
                "integer" => argument
                    .integer_value
                    .map(|value| serde_json::Value::Number(value.into()))
                    .ok_or_else(|| {
                        DbError::Storage("integer argument value is missing".to_owned())
                    })?,
                "number" => argument
                    .number_value
                    .and_then(serde_json::Number::from_f64)
                    .map(serde_json::Value::Number)
                    .ok_or_else(|| {
                        DbError::Storage("number argument value is missing or invalid".to_owned())
                    })?,
                "boolean" => match argument.boolean_value {
                    Some(0) => serde_json::Value::Bool(false),
                    Some(1) => serde_json::Value::Bool(true),
                    _ => {
                        return Err(DbError::Storage(
                            "boolean argument value is missing or invalid".to_owned(),
                        ));
                    }
                },
                other => {
                    return Err(DbError::Storage(format!(
                        "unknown argument value type: {other}"
                    )));
                }
            };
            Ok((argument.name, value))
        })
        .collect()
}

fn encode_json_object(object: &JsonObject) -> Result<String, DbError> {
    serde_json::to_string(object)
        .map_err(|error| DbError::Storage(format!("could not encode JSON object: {error}")))
}

fn decode_json_object(json: &str) -> Result<JsonObject, DbError> {
    serde_json::from_str(json)
        .map_err(|error| DbError::Storage(format!("stored JSON object is invalid: {error}")))
}

fn encode_tool_execution_source(
    source: ToolExecutionSource,
) -> (&'static str, Option<String>, Option<String>) {
    match source {
        ToolExecutionSource::Harness => ("harness", None, None),
        ToolExecutionSource::Mcp {
            server_id,
            remote_tool_name,
        } => ("mcp", Some(server_id), Some(remote_tool_name)),
    }
}

fn decode_tool_execution_source(
    kind: &str,
    server_id: Option<String>,
    remote_tool_name: Option<String>,
) -> Result<ToolExecutionSource, DbError> {
    match (kind, server_id, remote_tool_name) {
        ("harness", None, None) => Ok(ToolExecutionSource::Harness),
        ("mcp", Some(server_id), Some(remote_tool_name))
            if !server_id.is_empty() && !remote_tool_name.is_empty() =>
        {
            Ok(ToolExecutionSource::Mcp {
                server_id,
                remote_tool_name,
            })
        }
        (other, _, _) => Err(DbError::Storage(format!(
            "invalid tool execution source: {other}"
        ))),
    }
}

fn bool_to_i64(value: bool) -> i64 {
    if value { 1 } else { 0 }
}

fn i64_to_u64(value: i64) -> Result<u64, DbError> {
    u64::try_from(value).map_err(|_| DbError::Storage(format!("negative integer: {value}")))
}

fn u64_to_i64(value: u64) -> Result<i64, DbError> {
    i64::try_from(value).map_err(|_| DbError::Storage(format!("integer is too large: {value}")))
}

fn map_error(error: rusqlite::Error) -> DbError {
    match error {
        rusqlite::Error::QueryReturnedNoRows => DbError::NotFound,
        rusqlite::Error::SqliteFailure(failure, message) => {
            if failure.extended_code == rusqlite::ffi::SQLITE_CONSTRAINT_FOREIGNKEY
                || failure.extended_code == rusqlite::ffi::SQLITE_CONSTRAINT_PRIMARYKEY
                || failure.extended_code == rusqlite::ffi::SQLITE_CONSTRAINT_UNIQUE
                || failure.extended_code == rusqlite::ffi::SQLITE_CONSTRAINT_CHECK
                || failure.code == rusqlite::ErrorCode::ConstraintViolation
            {
                DbError::Constraint(message.unwrap_or_else(|| failure.to_string()))
            } else {
                DbError::Storage(message.unwrap_or_else(|| failure.to_string()))
            }
        }
        other => DbError::Storage(other.to_string()),
    }
}
