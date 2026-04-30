#![doc = include_str!("../README.md")]

use std::collections::HashSet;
use std::sync::{Arc, Mutex, MutexGuard};
use std::{error::Error, fmt};

use rusqlite::{Connection, OptionalExtension, params};
pub use selvedge_domain_model::{
    Conversation, ConversationItem, FunctionCallId, HistoryNodeId, MessageRole, ModelProfileKey,
    ReasoningEffort, TaskId, ToolArgumentValue, ToolCallArgument, ToolManifest, ToolName,
    ToolParameterName, ToolParameterType, ToolSpec, UnixTs,
};

const SCHEMA_VERSION: &str = "router-mediated-redesign-v4";

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
pub struct ToolRow {
    pub tool_name: ToolName,
    pub description_text: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ToolParameterRow {
    pub tool_name: ToolName,
    pub parameter_name: ToolParameterName,
    pub parameter_type: ToolParameterType,
    pub description_text: String,
    pub is_required: bool,
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

#[derive(Clone, Debug, PartialEq)]
pub struct HistoryFunctionCallArgumentRow {
    pub function_call_node_id: HistoryNodeId,
    pub tool_name: ToolName,
    pub argument_name: ToolParameterName,
    pub value: ToolArgumentValue,
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
    pub arguments: Vec<ToolCallArgument>,
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
        arguments: Vec<ToolCallArgument>,
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
    /// Cursor ownership stays at the task layer. The caller selects an
    /// already-persisted history node; task creation records that pointer.
    pub cursor_node_id: HistoryNodeId,
    pub model_profile_key: ModelProfileKey,
    pub reasoning_effort: ReasoningEffort,
    pub enabled_tools: Vec<ToolName>,
    pub now: UnixTs,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CreateChildTaskInput {
    pub parent_task_id: TaskId,
    pub child_task_id: TaskId,
    pub cursor_node_id: HistoryNodeId,
    pub now: UnixTs,
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
    pub arguments: Vec<ToolCallArgument>,
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
    let connection = Connection::open(&options.sqlite_path).map_err(map_error)?;
    connection
        .pragma_update(None, "foreign_keys", "ON")
        .map_err(map_error)?;

    if database_is_empty(&connection)? {
        connection
            .execute_batch(include_str!("schema.sql"))
            .map_err(map_error)?;
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
    tx.execute(
        "INSERT INTO tools (tool_name, description_text) VALUES (?1, ?2)",
        params![tool.name, tool.description],
    )
    .map_err(map_error)?;
    for parameter in tool.parameters {
        tx.execute(
            "INSERT INTO tool_parameters (tool_name, parameter_name, parameter_type, description_text, is_required)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![
                tool.name,
                parameter.name,
                tool_parameter_type_to_db(&parameter.parameter_type),
                parameter.description,
                bool_to_i64(parameter.required)
            ],
        )
        .map_err(map_error)?;
    }
    tx.commit().map_err(map_error)
}

/// Insert one history node and leave task rows unchanged.
///
/// History is a standalone graph. A task may point at any existing node chosen
/// by the caller's creation strategy; this write only materializes that node.
pub fn create_history_node(db: &DbPool, node: NewHistoryNode) -> Result<HistoryNodeId, DbError> {
    let mut connection = db.connection()?;
    let tx = connection.transaction().map_err(map_error)?;
    let node_id = insert_history_node(&tx, node)?;
    tx.commit().map_err(map_error)?;
    Ok(node_id)
}

/// Insert one root task whose cursor points at an existing history node.
///
/// Task relations and history relations are separate graphs. Creating a task
/// records the task-layer cursor pointer and tool manifest only.
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
    read_task(db, &task_id)
}

pub fn create_child_task(db: &DbPool, input: CreateChildTaskInput) -> Result<TaskRow, DbError> {
    let child_task_id = input.child_task_id.clone();
    {
        let mut connection = db.connection()?;
        let tx = connection.transaction().map_err(map_error)?;
        let parent = read_task_in_tx(&tx, &input.parent_task_id)?;
        if parent.task_status != TaskStatusRow::Active {
            return Err(DbError::TaskNotActive);
        }
        tx.execute(
            "INSERT INTO tasks
             (task_id, task_status, cursor_node_id, model_profile_key, reasoning_effort, state_version, created_at, updated_at)
             VALUES (?1, 'active', ?2, ?3, ?4, 0, ?5, ?5)",
            params![
                input.child_task_id.0,
                input.cursor_node_id.0,
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
        tx.commit().map_err(map_error)?;
    }
    read_task(db, &child_task_id)
}

pub fn load_active_task(db: &DbPool, task_id: &TaskId) -> Result<LoadedActiveTask, DbError> {
    let task = read_task(db, task_id)?;
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

pub fn read_tool_manifest_for_task(db: &DbPool, task_id: &TaskId) -> Result<ToolManifest, DbError> {
    let connection = db.connection()?;
    ensure_active_task(&connection, task_id)?;
    let mut statement = connection
        .prepare(
            "SELECT t.tool_name, t.description_text
             FROM tools t
             INNER JOIN task_tools tt ON tt.tool_name = t.tool_name
             WHERE tt.task_id = ?1
             ORDER BY t.tool_name ASC",
        )
        .map_err(map_error)?;
    let tools = statement
        .query_map(params![task_id.0], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })
        .map_err(map_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(map_error)?;

    let mut manifest_tools = Vec::with_capacity(tools.len());
    for (name, description) in tools {
        let mut parameter_statement = connection
            .prepare(
                "SELECT parameter_name, parameter_type, description_text, is_required
                 FROM tool_parameters
                 WHERE tool_name = ?1
                 ORDER BY parameter_name ASC",
            )
            .map_err(map_error)?;
        let parameters = parameter_statement
            .query_map(params![name], |row| {
                Ok(selvedge_domain_model::ToolParameter {
                    name: row.get(0)?,
                    parameter_type: tool_parameter_type_from_db(&row.get::<_, String>(1)?)
                        .map_err(|error| {
                            rusqlite::Error::ToSqlConversionFailure(Box::new(error))
                        })?,
                    description: row.get(2)?,
                    required: row.get::<_, i64>(3)? == 1,
                })
            })
            .map_err(map_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(map_error)?;
        manifest_tools.push(ToolSpec {
            name,
            description,
            parameters,
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

pub fn read_task(db: &DbPool, task_id: &TaskId) -> Result<TaskRow, DbError> {
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

pub fn read_history_node(db: &DbPool, node_id: &HistoryNodeId) -> Result<HistoryNode, DbError> {
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
    let argument_names = content
        .arguments
        .iter()
        .map(|argument| argument.name.0.as_str())
        .collect::<HashSet<_>>();
    let required_parameters = {
        let mut statement = tx
            .prepare(
                "SELECT parameter_name
                 FROM tool_parameters
                 WHERE tool_name = ?1 AND is_required = 1
                 ORDER BY parameter_name ASC",
            )
            .map_err(map_error)?;
        statement
            .query_map(params![content.tool_name.0], |row| row.get::<_, String>(0))
            .map_err(map_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(map_error)?
    };
    for parameter_name in required_parameters {
        if !argument_names.contains(parameter_name.as_str()) {
            return Err(DbError::Constraint(format!(
                "required tool argument is missing: {}.{}",
                content.tool_name.0, parameter_name
            )));
        }
    }

    tx.execute(
        "INSERT INTO history_function_call_nodes (node_id, function_call_id, tool_name)
         VALUES (?1, ?2, ?3)",
        params![node_id.0, content.function_call_id.0, content.tool_name.0],
    )
    .map_err(map_error)?;
    for argument in content.arguments {
        let (value_type, string_value, integer_value, number_value, boolean_value) =
            tool_argument_value_to_db(argument.value);
        tx.execute(
            "INSERT INTO history_function_call_arguments
             (function_call_node_id, tool_name, argument_name, value_type, string_value, integer_value, number_value, boolean_value)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                node_id.0,
                content.tool_name.0,
                argument.name.0,
                value_type,
                string_value,
                integer_value,
                number_value,
                boolean_value
            ],
        )
        .map_err(map_error)?;
    }
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

fn ensure_active_task(connection: &Connection, task_id: &TaskId) -> Result<(), DbError> {
    let status: Option<String> = connection
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
) -> Result<Vec<ToolCallArgument>, DbError> {
    let mut statement = connection
        .prepare(
            "SELECT argument_name, value_type, string_value, integer_value, number_value, boolean_value
             FROM history_function_call_arguments
             WHERE function_call_node_id = ?1
             ORDER BY argument_name ASC",
        )
        .map_err(map_error)?;
    statement
        .query_map(params![node_id.0], |row| {
            let value_type: String = row.get(1)?;
            Ok(ToolCallArgument {
                name: ToolParameterName(row.get(0)?),
                value: tool_argument_value_from_db(
                    &value_type,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                    row.get(5)?,
                )
                .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?,
            })
        })
        .map_err(map_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(map_error)
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

fn tool_parameter_type_to_db(value: &ToolParameterType) -> &'static str {
    match value {
        ToolParameterType::String => "string",
        ToolParameterType::Integer => "integer",
        ToolParameterType::Number => "number",
        ToolParameterType::Boolean => "boolean",
    }
}

fn tool_parameter_type_from_db(value: &str) -> Result<ToolParameterType, DbError> {
    match value {
        "string" => Ok(ToolParameterType::String),
        "integer" => Ok(ToolParameterType::Integer),
        "number" => Ok(ToolParameterType::Number),
        "boolean" => Ok(ToolParameterType::Boolean),
        other => Err(DbError::Storage(format!(
            "unknown tool parameter type: {other}"
        ))),
    }
}

type DbArgumentValue = (
    &'static str,
    Option<String>,
    Option<i64>,
    Option<f64>,
    Option<i64>,
);

fn tool_argument_value_to_db(value: ToolArgumentValue) -> DbArgumentValue {
    match value {
        ToolArgumentValue::String(value) => ("string", Some(value), None, None, None),
        ToolArgumentValue::Integer(value) => ("integer", None, Some(value), None, None),
        ToolArgumentValue::Number(value) => ("number", None, None, Some(value), None),
        ToolArgumentValue::Boolean(value) => {
            ("boolean", None, None, None, Some(bool_to_i64(value)))
        }
    }
}

fn tool_argument_value_from_db(
    value_type: &str,
    string_value: Option<String>,
    integer_value: Option<i64>,
    number_value: Option<f64>,
    boolean_value: Option<i64>,
) -> Result<ToolArgumentValue, DbError> {
    match value_type {
        "string" => string_value
            .map(ToolArgumentValue::String)
            .ok_or_else(|| DbError::Storage("string argument value is missing".to_owned())),
        "integer" => integer_value
            .map(ToolArgumentValue::Integer)
            .ok_or_else(|| DbError::Storage("integer argument value is missing".to_owned())),
        "number" => number_value
            .map(ToolArgumentValue::Number)
            .ok_or_else(|| DbError::Storage("number argument value is missing".to_owned())),
        "boolean" => boolean_value
            .map(|value| ToolArgumentValue::Boolean(value == 1))
            .ok_or_else(|| DbError::Storage("boolean argument value is missing".to_owned())),
        other => Err(DbError::Storage(format!(
            "unknown argument value type: {other}"
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
