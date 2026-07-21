#![doc = include_str!("../README.md")]

use std::collections::{BTreeMap, BTreeSet};
use std::sync::{Arc, Mutex, MutexGuard};
use std::{error::Error, fmt};

use rusqlite::{Connection, OptionalExtension, TransactionBehavior, params};
pub use selvedge_domain_model::{
    Conversation, ConversationMessage, FunctionCallId, HistoryNodeId, HistoryNodeIdRef, JsonObject,
    MessageRole, ModelProfileKey, ReasoningEffort, TaskId, TaskLifecycleEvent, TaskStatus,
    ToolManifest, ToolName, ToolSpec, UnixTs,
};
use serde_json::Value;

const SCHEMA_VERSION: &str = "task-lifecycle-v10";
pub const MAX_TASK_HISTORY_PAGE_SIZE: u32 = 100;

#[derive(Clone)]
pub struct DbPool {
    connection: Arc<Mutex<Connection>>,
    new_task_max_children_per_fork: u32,
    new_task_max_descendants: u32,
}

pub struct DbConnection;
pub struct DbTransaction;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DbError {
    NotFound,
    InvalidTaskStatus {
        status: TaskStatus,
    },
    StaleFunctionCall,
    HistoryCursorNotOnTask,
    ToolUnavailable,
    TaskDescendantLimitExceeded {
        task_id: TaskId,
        limit: u32,
    },
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
            DbError::InvalidTaskStatus { status } => {
                write!(
                    formatter,
                    "task status does not permit the operation: {status:?}"
                )
            }
            DbError::StaleFunctionCall => {
                write!(formatter, "function call is not open on the task path")
            }
            DbError::HistoryCursorNotOnTask => {
                write!(formatter, "history cursor is not on the task path")
            }
            DbError::ToolUnavailable => write!(formatter, "tool is unavailable for task"),
            DbError::TaskDescendantLimitExceeded { task_id, limit } => {
                write!(
                    formatter,
                    "task '{}' cannot exceed {limit} descendants",
                    task_id.0
                )
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
pub enum HistoryContentKindRow {
    Message,
    Reasoning,
    FunctionCall,
    FunctionOutput,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OpenDbOptions {
    pub sqlite_path: String,
    pub max_children_per_fork: u32,
    pub max_task_descendants: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ToolExecutionSource {
    Harness,
    Mcp {
        server_id: String,
        remote_tool_name: String,
    },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ToolRecoveryPolicy {
    RetrySafe,
    OutcomeUnknown,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TaskToolExecution {
    pub source: ToolExecutionSource,
    pub max_children_per_fork: u32,
    pub max_task_descendants: u32,
}

#[derive(Clone, Debug, PartialEq)]
pub struct TaskToolSpec {
    pub tool: ToolSpec,
    pub execution_source: ToolExecutionSource,
    pub recovery_policy: ToolRecoveryPolicy,
}

#[derive(Clone, Debug, PartialEq)]
pub struct TaskToolState {
    pub manifest: ToolManifest,
    pub unavailable_tools: Vec<ToolName>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TaskRow {
    pub task_id: TaskId,
    pub task_status: TaskStatus,
    pub cursor_node_id: HistoryNodeId,
    pub model_profile_key: ModelProfileKey,
    pub reasoning_effort: ReasoningEffort,
    pub max_children_per_fork: u32,
    pub max_task_descendants: u32,
    pub state_version: u64,
    pub created_at: UnixTs,
    pub updated_at: UnixTs,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TaskToolRow {
    pub task_id: TaskId,
    pub tool_ordinal: u32,
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
    pub output: Value,
    pub is_error: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct OpenFunctionCall {
    pub function_call_node_id: HistoryNodeId,
    pub function_call_id: FunctionCallId,
    pub tool_name: ToolName,
    pub arguments: JsonObject,
    pub recovery_policy: ToolRecoveryPolicy,
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
        output: Value,
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
    pub tools: Vec<TaskToolSpec>,
    pub now: UnixTs,
}

#[derive(Clone, Debug, PartialEq)]
pub struct CommitToolResultBranchesInput {
    pub calling_task_id: TaskId,
    pub function_call_node_id: HistoryNodeId,
    pub function_call_id: FunctionCallId,
    pub tool_name: ToolName,
    pub branches: Vec<ToolResultBranch>,
    pub now: UnixTs,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ToolResultBranch {
    pub target: ToolResultBranchTarget,
    pub output: Value,
    pub is_error: bool,
    pub user_messages: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ToolResultBranchTarget {
    CallingTask,
    NewChildTask(TaskId),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CommitToolResultBranchesResult {
    pub created_child_task_ids: Vec<TaskId>,
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
    pub task_status: TaskStatus,
    pub state_version: u64,
    pub cursor_node_id: HistoryNodeId,
    pub parent_task_id: Option<TaskId>,
    pub queued_input_count: u64,
    pub history_nodes: Vec<HistoryNode>,
    pub has_more: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct LoadedRuntimeTask {
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
    pub output: Value,
    pub is_error: bool,
}

pub fn open_db(options: OpenDbOptions) -> Result<DbPool, DbError> {
    if options.max_children_per_fork == 0 {
        return Err(DbError::Constraint(
            "max children per fork must be greater than zero".to_owned(),
        ));
    }
    if options.max_task_descendants == 0 {
        return Err(DbError::Constraint(
            "max task descendants must be greater than zero".to_owned(),
        ));
    }
    if options.max_children_per_fork > options.max_task_descendants {
        return Err(DbError::Constraint(
            "max children per fork must not exceed max task descendants".to_owned(),
        ));
    }
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
        new_task_max_children_per_fork: options.max_children_per_fork,
        new_task_max_descendants: options.max_task_descendants,
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

pub fn reconcile_task_tool_availability(
    db: &DbPool,
    available_tools: Vec<TaskToolSpec>,
) -> Result<(), DbError> {
    let mut available_by_name = BTreeMap::new();
    for available_tool in available_tools {
        validate_task_tool_spec(&available_tool)?;
        if available_by_name
            .insert(available_tool.tool.name.clone(), available_tool)
            .is_some()
        {
            return Err(DbError::Constraint(
                "available tool names must be unique".to_owned(),
            ));
        }
    }

    let mut connection = db.connection()?;
    let tx = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(map_error)?;
    let stored_tools = read_all_task_tools_in_connection(&tx)?;
    let desired_unavailable = stored_tools
        .into_iter()
        .filter_map(|(task_id, stored_tool)| {
            let available =
                available_by_name
                    .get(&stored_tool.tool.name)
                    .is_some_and(|available_tool| {
                        stored_tool.execution_source == available_tool.execution_source
                            && match stored_tool.execution_source {
                                ToolExecutionSource::Harness => true,
                                ToolExecutionSource::Mcp { .. } => {
                                    stored_tool.tool == available_tool.tool
                                }
                            }
                    });
            (!available).then_some((task_id, ToolName(stored_tool.tool.name)))
        })
        .collect::<BTreeSet<_>>();
    let current_unavailable = read_all_unavailable_tools_in_connection(&tx)?;

    for (task_id, tool_name) in current_unavailable.difference(&desired_unavailable) {
        tx.execute(
            "DELETE FROM task_unavailable_tools WHERE task_id = ?1 AND tool_name = ?2",
            params![task_id.0, tool_name.0],
        )
        .map_err(map_error)?;
    }
    for (task_id, tool_name) in desired_unavailable.difference(&current_unavailable) {
        tx.execute(
            "INSERT INTO task_unavailable_tools (task_id, tool_name) VALUES (?1, ?2)",
            params![task_id.0, tool_name.0],
        )
        .map_err(map_error)?;
    }

    tx.commit().map_err(map_error)
}

pub fn read_tool_execution_source(
    db: &DbPool,
    task_id: &TaskId,
    tool_name: &ToolName,
) -> Result<TaskToolExecution, DbError> {
    let connection = db.connection()?;
    let stored = connection
        .query_row(
            "SELECT tt.execution_source_kind, tt.mcp_server_id, tt.remote_tool_name,
                    unavailable.tool_name IS NOT NULL, tasks.max_children_per_fork,
                    tasks.max_task_descendants
             FROM task_tools tt
             JOIN tasks ON tasks.task_id = tt.task_id
             LEFT JOIN task_unavailable_tools unavailable
               ON unavailable.task_id = tt.task_id
              AND unavailable.tool_name = tt.tool_name
             WHERE tt.task_id = ?1 AND tt.tool_name = ?2",
            params![task_id.0, tool_name.0],
            |row| {
                Ok((
                    decode_tool_execution_source(
                        &row.get::<_, String>(0)?,
                        row.get(1)?,
                        row.get(2)?,
                    )
                    .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?,
                    row.get::<_, bool>(3)?,
                    row.get::<_, u32>(4)?,
                    row.get::<_, u32>(5)?,
                ))
            },
        )
        .optional()
        .map_err(map_error)?
        .ok_or(DbError::NotFound)?;
    if stored.1 {
        Err(DbError::ToolUnavailable)
    } else {
        Ok(TaskToolExecution {
            source: stored.0,
            max_children_per_fork: stored.2,
            max_task_descendants: stored.3,
        })
    }
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
    validate_task_tool_snapshot(&input.tools)?;
    {
        let mut connection = db.connection()?;
        let tx = connection.transaction().map_err(map_error)?;
        tx.execute(
            "INSERT INTO tasks
             (task_id, task_status, cursor_node_id, model_profile_key, reasoning_effort,
              max_children_per_fork, max_task_descendants, state_version, created_at, updated_at)
             VALUES (?1, 'active', ?2, ?3, ?4, ?5, ?6, 0, ?7, ?7)",
            params![
                input.task_id.0,
                input.cursor_node_id.0,
                input.model_profile_key.0,
                reasoning_effort_to_db(&input.reasoning_effort),
                i64::from(db.new_task_max_children_per_fork),
                i64::from(db.new_task_max_descendants),
                input.now.0
            ],
        )
        .map_err(map_error)?;
        for (ordinal, tool) in input.tools.into_iter().enumerate() {
            insert_task_tool_in_tx(&tx, &task_id, ordinal, tool)?;
        }
        tx.commit().map_err(map_error)?;
    }
    read_task_row(db, &task_id)
}

pub fn commit_tool_result_branches(
    db: &DbPool,
    input: CommitToolResultBranchesInput,
) -> Result<CommitToolResultBranchesResult, DbError> {
    let calling_branch_count = input
        .branches
        .iter()
        .filter(|branch| branch.target == ToolResultBranchTarget::CallingTask)
        .count();
    if calling_branch_count != 1 {
        return Err(DbError::Constraint(
            "tool result commit requires exactly one calling-task branch".to_owned(),
        ));
    }
    let child_task_ids = input
        .branches
        .iter()
        .filter_map(|branch| match &branch.target {
            ToolResultBranchTarget::CallingTask => None,
            ToolResultBranchTarget::NewChildTask(task_id) => Some(task_id),
        })
        .collect::<Vec<_>>();
    for (index, child_task_id) in child_task_ids.iter().enumerate() {
        if **child_task_id == input.calling_task_id
            || child_task_ids[..index].contains(child_task_id)
        {
            return Err(DbError::Constraint(
                "new child task ids must be unique and differ from the calling task".to_owned(),
            ));
        }
    }
    if input
        .branches
        .iter()
        .flat_map(|branch| &branch.user_messages)
        .any(String::is_empty)
    {
        return Err(DbError::Constraint(
            "tool result branch user messages cannot be empty".to_owned(),
        ));
    }

    let mut connection = db.connection()?;
    let tx = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(map_error)?;
    let calling_task = read_task_in_tx(&tx, &input.calling_task_id)?;
    if !calling_task.task_status.accepts_history_writes() {
        return Err(DbError::InvalidTaskStatus {
            status: calling_task.task_status,
        });
    }
    let branch_parent_node_id = calling_task.cursor_node_id;
    let output_identity = NewFunctionOutputNodeContent {
        function_call_node_id: input.function_call_node_id,
        function_call_id: input.function_call_id,
        tool_name: input.tool_name,
        output: Value::Null,
        is_error: false,
    };
    if !child_task_ids.is_empty() {
        ensure_task_descendant_capacity_in_tx(&tx, &input.calling_task_id, child_task_ids.len())?;
    }

    let mut created_child_task_ids = Vec::with_capacity(child_task_ids.len());
    for branch in input.branches {
        let branch_cursor_node_id = insert_tool_result_branch_in_tx(
            &tx,
            branch_parent_node_id,
            &output_identity,
            branch.output,
            branch.is_error,
            branch.user_messages,
            input.now,
        )?;
        match branch.target {
            ToolResultBranchTarget::CallingTask => {
                update_task_cursor_in_tx(
                    &tx,
                    &input.calling_task_id,
                    branch_cursor_node_id,
                    input.now,
                )?;
                append_all_queued_user_inputs_in_tx(&tx, &input.calling_task_id, input.now)?;
            }
            ToolResultBranchTarget::NewChildTask(child_task_id) => {
                tx.execute(
                    "INSERT INTO tasks
                     (task_id, task_status, cursor_node_id, model_profile_key, reasoning_effort,
                      max_children_per_fork, max_task_descendants, state_version, created_at,
                      updated_at)
                     VALUES (?1, 'active', ?2, ?3, ?4, ?5, ?6, 0, ?7, ?7)",
                    params![
                        child_task_id.0,
                        branch_cursor_node_id.0,
                        calling_task.model_profile_key.0,
                        reasoning_effort_to_db(&calling_task.reasoning_effort),
                        i64::from(calling_task.max_children_per_fork),
                        i64::from(calling_task.max_task_descendants),
                        input.now.0
                    ],
                )
                .map_err(map_error)?;
                tx.execute(
                    "INSERT INTO task_tools
                     (task_id, tool_ordinal, tool_name, description_text, input_schema_json,
                      mcp_server_id, remote_tool_name, execution_source_kind, recovery_policy)
                     SELECT ?1, tool_ordinal, tool_name, description_text, input_schema_json,
                            mcp_server_id, remote_tool_name, execution_source_kind, recovery_policy
                     FROM task_tools
                     WHERE task_id = ?2",
                    params![child_task_id.0, input.calling_task_id.0],
                )
                .map_err(map_error)?;
                tx.execute(
                    "INSERT INTO task_unavailable_tools (task_id, tool_name)
                     SELECT ?1, tool_name
                     FROM task_unavailable_tools
                     WHERE task_id = ?2",
                    params![child_task_id.0, input.calling_task_id.0],
                )
                .map_err(map_error)?;
                tx.execute(
                    "INSERT INTO task_parent_edges (parent_task_id, child_task_id, created_at)
                     VALUES (?1, ?2, ?3)",
                    params![input.calling_task_id.0, child_task_id.0, input.now.0],
                )
                .map_err(map_error)?;
                created_child_task_ids.push(child_task_id);
            }
        }
    }

    tx.commit().map_err(map_error)?;
    Ok(CommitToolResultBranchesResult {
        created_child_task_ids,
    })
}

fn ensure_task_descendant_capacity_in_tx(
    tx: &rusqlite::Transaction<'_>,
    calling_task_id: &TaskId,
    new_child_count: usize,
) -> Result<(), DbError> {
    let violating_task = tx
        .query_row(
            "WITH RECURSIVE
                 ancestors(task_id) AS (
                     SELECT ?1
                     UNION ALL
                     SELECT edge.parent_task_id
                     FROM task_parent_edges AS edge
                     JOIN ancestors ON edge.child_task_id = ancestors.task_id
                 ),
                 descendants(ancestor_task_id, descendant_task_id) AS (
                     SELECT ancestors.task_id, edge.child_task_id
                     FROM ancestors
                     JOIN task_parent_edges AS edge
                       ON edge.parent_task_id = ancestors.task_id
                     UNION ALL
                     SELECT descendants.ancestor_task_id, edge.child_task_id
                     FROM descendants
                     JOIN task_parent_edges AS edge
                       ON edge.parent_task_id = descendants.descendant_task_id
                 )
             SELECT ancestors.task_id, tasks.max_task_descendants
             FROM ancestors
             JOIN tasks ON tasks.task_id = ancestors.task_id
             LEFT JOIN descendants
               ON descendants.ancestor_task_id = ancestors.task_id
             GROUP BY ancestors.task_id, tasks.max_task_descendants
             HAVING COUNT(descendants.descendant_task_id) + ?2 > tasks.max_task_descendants
             LIMIT 1",
            params![
                calling_task_id.0,
                i64::try_from(new_child_count).map_err(|_| {
                    DbError::Constraint("new child task count exceeds database range".to_owned())
                })?
            ],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, u32>(1)?)),
        )
        .optional()
        .map_err(map_error)?;

    match violating_task {
        Some((task_id, limit)) => Err(DbError::TaskDescendantLimitExceeded {
            task_id: TaskId(task_id),
            limit,
        }),
        None => Ok(()),
    }
}

pub fn load_runtime_task(db: &DbPool, task_id: &TaskId) -> Result<LoadedRuntimeTask, DbError> {
    let task = read_task_row(db, task_id)?;
    if !task.task_status.has_runtime() {
        return Err(DbError::InvalidTaskStatus {
            status: task.task_status,
        });
    }
    let cursor_node = read_history_node(db, &task.cursor_node_id)?;
    let tool_manifest = read_tool_manifest_for_task(db, task_id)?;
    let queued_inputs = list_queued_inputs(db, task_id)?;
    Ok(LoadedRuntimeTask {
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
    let mut connection = db.connection()?;
    let tx = connection.transaction().map_err(map_error)?;
    let task = read_task_in_tx(&tx, task_id)?;
    let next_status = task
        .task_status
        .transition(TaskLifecycleEvent::UserInput)
        .ok_or(DbError::InvalidTaskStatus {
            status: task.task_status,
        })?;
    let node_id = insert_history_node(
        &tx,
        NewHistoryNode {
            parent_node_id: Some(task.cursor_node_id),
            content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                message_role: MessageRole::User,
                message_text,
            }),
            created_at,
        },
    )?;
    let changed = tx
        .execute(
            "UPDATE tasks
             SET task_status = ?1, cursor_node_id = ?2, updated_at = ?3,
                 state_version = state_version + 1
             WHERE task_id = ?4 AND task_status = ?5 AND cursor_node_id = ?6",
            params![
                task_status_to_db(next_status),
                node_id.0,
                created_at.0,
                task_id.0,
                task_status_to_db(task.task_status),
                task.cursor_node_id.0
            ],
        )
        .map_err(map_error)?;
    if changed == 0 {
        return Err(DbError::Constraint(
            "user input task state changed before commit".to_owned(),
        ));
    }
    tx.commit().map_err(map_error)?;
    Ok(node_id)
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
    ensure_history_writable_task_in_tx(&tx, task_id)?;
    for tool_call in &tool_calls {
        let belongs_to_task = tx
            .query_row(
                "SELECT 1 FROM task_tools WHERE task_id = ?1 AND tool_name = ?2",
                params![task_id.0, tool_call.tool_name.0],
                |_| Ok(()),
            )
            .optional()
            .map_err(map_error)?
            .is_some();
        if !belongs_to_task {
            return Err(DbError::Constraint(format!(
                "tool is not defined for task: {}",
                tool_call.tool_name.0
            )));
        }
    }
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
    ensure_history_writable_task_in_tx(&tx, task_id)?;
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

pub fn drain_queued_user_inputs_and_move_cursor(
    db: &DbPool,
    task_id: &TaskId,
    created_at: UnixTs,
) -> Result<Option<HistoryNodeId>, DbError> {
    let mut connection = db.connection()?;
    let tx = connection.transaction().map_err(map_error)?;
    ensure_history_writable_task_in_tx(&tx, task_id)?;
    let last_node_id = append_all_queued_user_inputs_in_tx(&tx, task_id, created_at)?;
    tx.commit().map_err(map_error)?;
    Ok(last_node_id)
}

pub fn read_open_function_calls_for_task(
    db: &DbPool,
    task_id: &TaskId,
) -> Result<Vec<OpenFunctionCall>, DbError> {
    let task = load_runtime_task(db, task_id)?.task;
    let connection = db.connection()?;
    let recovery_policies = read_task_tool_recovery_policies_in_connection(&connection, task_id)?;
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
                let recovery_policy =
                    recovery_policies
                        .get(&tool_name.0)
                        .copied()
                        .ok_or_else(|| {
                            DbError::Storage(format!(
                                "history references tool '{}' outside the task tool snapshot",
                                tool_name.0
                            ))
                        })?;
                open_calls.push(OpenFunctionCall {
                    function_call_node_id: node_id,
                    function_call_id,
                    tool_name,
                    arguments,
                    recovery_policy,
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

fn current_cursor_node_id_in_tx(
    tx: &rusqlite::Transaction<'_>,
    task_id: &TaskId,
) -> Result<i64, DbError> {
    let task = read_task_in_tx(tx, task_id)?;
    if task.task_status.accepts_history_writes() {
        Ok(task.cursor_node_id.0)
    } else {
        Err(DbError::InvalidTaskStatus {
            status: task.task_status,
        })
    }
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

fn insert_tool_result_branch_in_tx(
    tx: &rusqlite::Transaction<'_>,
    branch_parent_node_id: HistoryNodeId,
    output_identity: &NewFunctionOutputNodeContent,
    output: Value,
    is_error: bool,
    user_messages: Vec<String>,
    created_at: UnixTs,
) -> Result<HistoryNodeId, DbError> {
    let mut last_node_id = insert_history_node(
        tx,
        NewHistoryNode {
            parent_node_id: Some(branch_parent_node_id),
            content: NewHistoryNodeContent::FunctionOutput(NewFunctionOutputNodeContent {
                function_call_node_id: output_identity.function_call_node_id,
                function_call_id: output_identity.function_call_id.clone(),
                tool_name: output_identity.tool_name.clone(),
                output,
                is_error,
            }),
            created_at,
        },
    )?;
    for message_text in user_messages {
        last_node_id = insert_history_node(
            tx,
            NewHistoryNode {
                parent_node_id: Some(last_node_id),
                content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                    message_role: MessageRole::User,
                    message_text,
                }),
                created_at,
            },
        )?;
    }
    Ok(last_node_id)
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
             WHERE task_id = ?3 AND task_status <> 'archived'",
            params![node_id.0, updated_at.0, task_id.0],
        )
        .map_err(map_error)?;
    if changed == 0 {
        let status = task_status_in_tx(tx, task_id)?;
        Err(DbError::InvalidTaskStatus { status })
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
    let task = read_task_in_tx(&tx, task_id)?;
    let next_status = task
        .task_status
        .transition(TaskLifecycleEvent::UserInput)
        .ok_or(DbError::InvalidTaskStatus {
            status: task.task_status,
        })?;
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
    if next_status != task.task_status {
        tx.execute(
            "UPDATE tasks
             SET task_status = ?1, updated_at = ?2, state_version = state_version + 1
             WHERE task_id = ?3 AND task_status = ?4",
            params![
                task_status_to_db(next_status),
                queued_at.0,
                task_id.0,
                task_status_to_db(task.task_status)
            ],
        )
        .map_err(map_error)?;
    }
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
    ensure_history_writable_task_in_tx(&tx, task_id)?;
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
    ensure_history_writable_task_in_tx(&tx, task_id)?;
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
    let current_cursor_node_id = current_cursor_node_id_in_tx(&tx, task_id)?;
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
         WHERE task_id = ?3 AND task_status <> 'archived' AND cursor_node_id = ?4",
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

pub fn read_task_status(db: &DbPool, task_id: &TaskId) -> Result<TaskStatus, DbError> {
    Ok(read_task_row(db, task_id)?.task_status)
}

pub fn transition_task_status(
    db: &DbPool,
    task_id: &TaskId,
    event: TaskLifecycleEvent,
    now: UnixTs,
) -> Result<TaskRow, DbError> {
    if event == TaskLifecycleEvent::UserInput {
        return Err(DbError::Constraint(
            "user input status transition must be committed with the input".to_owned(),
        ));
    }
    let mut connection = db.connection()?;
    let tx = connection.transaction().map_err(map_error)?;
    let task = read_task_in_tx(&tx, task_id)?;
    let next_status = task
        .task_status
        .transition(event)
        .ok_or(DbError::InvalidTaskStatus {
            status: task.task_status,
        })?;
    let changed = tx
        .execute(
            "UPDATE tasks
             SET task_status = ?1, updated_at = ?2, state_version = state_version + 1
             WHERE task_id = ?3 AND task_status = ?4",
            params![
                task_status_to_db(next_status),
                now.0,
                task_id.0,
                task_status_to_db(task.task_status)
            ],
        )
        .map_err(map_error)?;
    if changed == 0 {
        return Err(DbError::Constraint(
            "task status changed before transition commit".to_owned(),
        ));
    }
    let transitioned = read_task_in_tx(&tx, task_id)?;
    tx.commit().map_err(map_error)?;
    Ok(transitioned)
}

pub fn list_runtime_tasks(db: &DbPool) -> Result<Vec<TaskRow>, DbError> {
    let connection = db.connection()?;
    let mut statement = connection
        .prepare(
            "SELECT task_id, task_status, cursor_node_id, model_profile_key, reasoning_effort,
                    max_children_per_fork, max_task_descendants, state_version, created_at, updated_at
             FROM tasks
             WHERE task_status <> 'archived'
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
    Ok(read_task_tool_state(db, task_id)?.manifest)
}

pub fn read_task_tool_state(db: &DbPool, task_id: &TaskId) -> Result<TaskToolState, DbError> {
    let connection = db.connection()?;
    ensure_task_exists(&connection, task_id)?;
    let mut statement = connection
        .prepare(
            "SELECT tools.tool_name, tools.description_text, tools.input_schema_json,
                    unavailable.tool_name IS NOT NULL
             FROM task_tools tools
             LEFT JOIN task_unavailable_tools unavailable
               ON unavailable.task_id = tools.task_id
              AND unavailable.tool_name = tools.tool_name
             WHERE tools.task_id = ?1
             ORDER BY tools.tool_ordinal ASC",
        )
        .map_err(map_error)?;
    let tools = statement
        .query_map(params![task_id.0], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, bool>(3)?,
            ))
        })
        .map_err(map_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(map_error)?;

    let mut manifest_tools = Vec::with_capacity(tools.len());
    let mut unavailable_tools = Vec::new();
    for (name, description, input_schema_json, unavailable) in tools {
        if unavailable {
            unavailable_tools.push(ToolName(name.clone()));
        }
        manifest_tools.push(ToolSpec {
            name,
            description,
            input_schema: decode_json_object(&input_schema_json)?,
        });
    }
    Ok(TaskToolState {
        manifest: ToolManifest {
            tools: manifest_tools,
        },
        unavailable_tools,
    })
}

pub fn read_conversation_for_task(db: &DbPool, task_id: &TaskId) -> Result<Conversation, DbError> {
    let task = read_task_row(db, task_id)?;
    let connection = db.connection()?;
    let mut nodes = Vec::new();
    let mut next_node_id = Some(task.cursor_node_id);
    while let Some(node_id) = next_node_id {
        let node = read_history_node_in_connection(&connection, &node_id)?;
        next_node_id = node.parent_node_id;
        nodes.push(node);
    }
    nodes.reverse();

    let mut messages = Vec::with_capacity(nodes.len());
    for node in nodes {
        let source_node_id = Some(HistoryNodeIdRef(node.node_id.0.to_string()));
        match node.content_kind {
            HistoryContentKindRow::Message => {
                let row = read_message_node(&connection, &node.node_id)?;
                messages.push(ConversationMessage::text(
                    row.message_role,
                    row.message_text,
                    source_node_id,
                ));
            }
            HistoryContentKindRow::FunctionCall => {
                let row = read_function_call_node(&connection, &node.node_id)?;
                messages.push(ConversationMessage::function_call(
                    row.function_call_id,
                    row.tool_name,
                    read_function_call_arguments(&connection, &node.node_id)?,
                    source_node_id,
                ));
            }
            HistoryContentKindRow::FunctionOutput => {
                let row = read_function_output_node(&connection, &node.node_id)?;
                messages.push(ConversationMessage::function_output(
                    row.function_call_id,
                    row.tool_name,
                    row.output,
                    row.is_error,
                    source_node_id,
                ));
            }
            HistoryContentKindRow::Reasoning => {}
        }
    }

    Ok(Conversation { messages })
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

fn read_task_row(db: &DbPool, task_id: &TaskId) -> Result<TaskRow, DbError> {
    let connection = db.connection()?;
    connection
        .query_row(
            "SELECT task_id, task_status, cursor_node_id, model_profile_key, reasoning_effort,
                    max_children_per_fork, max_task_descendants, state_version, created_at, updated_at
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
        "SELECT task_id, task_status, cursor_node_id, model_profile_key, reasoning_effort,
                max_children_per_fork, max_task_descendants, state_version, created_at, updated_at
         FROM tasks
         WHERE task_id = ?1",
        params![task_id.0],
        map_task_row,
    )
    .optional()
    .map_err(map_error)?
    .ok_or(DbError::NotFound)
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
    // Calls and outputs may have sibling branches. A call is open only when the
    // exact call is an ancestor of this cursor and no matching output is an
    // ancestor of the same cursor.
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
                  AND NOT EXISTS (
                      SELECT 1
                      FROM current_path output_path
                      JOIN history_function_output_nodes outputs
                        ON outputs.node_id = output_path.node_id
                      WHERE outputs.function_call_node_id = calls.node_id
                  )
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
        return Err(DbError::StaleFunctionCall);
    }
    Ok(())
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
                output: row.output,
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

fn validate_task_tool_snapshot(tools: &[TaskToolSpec]) -> Result<(), DbError> {
    let mut names = BTreeSet::new();
    for tool in tools {
        validate_task_tool_spec(tool)?;
        if !names.insert(tool.tool.name.as_str()) {
            return Err(DbError::Constraint(
                "task tool names must be unique".to_owned(),
            ));
        }
    }
    Ok(())
}

fn validate_task_tool_spec(tool: &TaskToolSpec) -> Result<(), DbError> {
    if tool.tool.name.trim().is_empty() || tool.tool.description.trim().is_empty() {
        return Err(DbError::Constraint(
            "task tool name and description must be non-empty".to_owned(),
        ));
    }
    if let ToolExecutionSource::Mcp {
        server_id,
        remote_tool_name,
    } = &tool.execution_source
        && (server_id.is_empty() || remote_tool_name.is_empty())
    {
        return Err(DbError::Constraint(
            "MCP server and remote tool names must be non-empty".to_owned(),
        ));
    }
    Ok(())
}

fn insert_task_tool_in_tx(
    tx: &rusqlite::Transaction<'_>,
    task_id: &TaskId,
    ordinal: usize,
    tool: TaskToolSpec,
) -> Result<(), DbError> {
    let (execution_source_kind, mcp_server_id, remote_tool_name) =
        encode_tool_execution_source(tool.execution_source);
    tx.execute(
        "INSERT INTO task_tools
         (task_id, tool_ordinal, tool_name, description_text, input_schema_json,
          execution_source_kind, mcp_server_id, remote_tool_name, recovery_policy)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
        params![
            task_id.0,
            i64::try_from(ordinal).map_err(|_| DbError::Constraint(
                "tool ordinal exceeds database range".to_owned()
            ))?,
            tool.tool.name,
            tool.tool.description,
            encode_json_object(&tool.tool.input_schema)?,
            execution_source_kind,
            mcp_server_id,
            remote_tool_name,
            encode_tool_recovery_policy(tool.recovery_policy)
        ],
    )
    .map_err(map_error)?;
    Ok(())
}

fn read_all_task_tools_in_connection(
    connection: &Connection,
) -> Result<Vec<(TaskId, TaskToolSpec)>, DbError> {
    let mut statement = connection
        .prepare(
            "SELECT task_id, tool_name, description_text, input_schema_json,
                    execution_source_kind, mcp_server_id, remote_tool_name, recovery_policy
             FROM task_tools
             ORDER BY task_id, tool_ordinal",
        )
        .map_err(map_error)?;
    let rows = statement
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                decode_tool_execution_source(&row.get::<_, String>(4)?, row.get(5)?, row.get(6)?)
                    .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?,
                decode_tool_recovery_policy(&row.get::<_, String>(7)?)
                    .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?,
            ))
        })
        .map_err(map_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(map_error)?;
    rows.into_iter()
        .map(
            |(task_id, name, description, input_schema_json, execution_source, recovery_policy)| {
                Ok((
                    TaskId(task_id),
                    TaskToolSpec {
                        tool: ToolSpec {
                            name,
                            description,
                            input_schema: decode_json_object(&input_schema_json)?,
                        },
                        execution_source,
                        recovery_policy,
                    },
                ))
            },
        )
        .collect()
}

fn read_task_tool_recovery_policies_in_connection(
    connection: &Connection,
    task_id: &TaskId,
) -> Result<BTreeMap<String, ToolRecoveryPolicy>, DbError> {
    let mut statement = connection
        .prepare(
            "SELECT tool_name, recovery_policy
             FROM task_tools
             WHERE task_id = ?1",
        )
        .map_err(map_error)?;
    statement
        .query_map(params![task_id.0], |row| {
            Ok((
                row.get::<_, String>(0)?,
                decode_tool_recovery_policy(&row.get::<_, String>(1)?)
                    .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?,
            ))
        })
        .map_err(map_error)?
        .collect::<Result<BTreeMap<_, _>, _>>()
        .map_err(map_error)
}

fn read_all_unavailable_tools_in_connection(
    connection: &Connection,
) -> Result<BTreeSet<(TaskId, ToolName)>, DbError> {
    let mut statement = connection
        .prepare(
            "SELECT task_id, tool_name
             FROM task_unavailable_tools
             ORDER BY task_id, tool_name",
        )
        .map_err(map_error)?;
    statement
        .query_map([], |row| Ok((TaskId(row.get(0)?), ToolName(row.get(1)?))))
        .map_err(map_error)?
        .collect::<Result<BTreeSet<_>, _>>()
        .map_err(map_error)
}

fn insert_history_node(
    tx: &rusqlite::Transaction<'_>,
    node: NewHistoryNode,
) -> Result<HistoryNodeId, DbError> {
    let parent_node_id = node.parent_node_id;
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
            insert_function_output_node(tx, node_id, parent_node_id, content)?
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
    parent_node_id: Option<HistoryNodeId>,
    content: NewFunctionOutputNodeContent,
) -> Result<(), DbError> {
    let Some(parent_node_id) = parent_node_id else {
        return Err(DbError::StaleFunctionCall);
    };
    ensure_current_path_contains_open_function_call(tx, parent_node_id.0, &content)?;
    tx.execute(
        "INSERT INTO history_function_output_nodes
         (node_id, function_call_node_id, function_call_id, tool_name, output_json, is_error)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![
            node_id.0,
            content.function_call_node_id.0,
            content.function_call_id.0,
            content.tool_name.0,
            encode_json_value(&content.output)?,
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

fn task_status_in_tx(
    tx: &rusqlite::Transaction<'_>,
    task_id: &TaskId,
) -> Result<TaskStatus, DbError> {
    let status: Option<String> = tx
        .query_row(
            "SELECT task_status FROM tasks WHERE task_id = ?1",
            params![task_id.0],
            |row| row.get(0),
        )
        .optional()
        .map_err(map_error)?;
    status
        .as_deref()
        .map(task_status_from_db)
        .transpose()?
        .ok_or(DbError::NotFound)
}

fn ensure_history_writable_task_in_tx(
    tx: &rusqlite::Transaction<'_>,
    task_id: &TaskId,
) -> Result<TaskStatus, DbError> {
    let status = task_status_in_tx(tx, task_id)?;
    if status.accepts_history_writes() {
        Ok(status)
    } else {
        Err(DbError::InvalidTaskStatus { status })
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
            "SELECT node_id, function_call_node_id, function_call_id, tool_name, output_json, is_error
             FROM history_function_output_nodes
             WHERE node_id = ?1",
            params![node_id.0],
            |row| {
                Ok(HistoryFunctionOutputNodeRow {
                    node_id: HistoryNodeId(row.get(0)?),
                    function_call_node_id: HistoryNodeId(row.get(1)?),
                    function_call_id: FunctionCallId(row.get(2)?),
                    tool_name: ToolName(row.get(3)?),
                    output: decode_json_value(&row.get::<_, String>(4)?).map_err(|error| {
                        rusqlite::Error::ToSqlConversionFailure(Box::new(error))
                    })?,
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
        max_children_per_fork: row.get(5)?,
        max_task_descendants: row.get(6)?,
        state_version: i64_to_u64(row.get(7)?)
            .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?,
        created_at: UnixTs(row.get(8)?),
        updated_at: UnixTs(row.get(9)?),
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

fn task_status_from_db(value: &str) -> Result<TaskStatus, DbError> {
    match value {
        "active" => Ok(TaskStatus::Active),
        "frozen" => Ok(TaskStatus::Frozen),
        "stopped" => Ok(TaskStatus::Stopped),
        "archived" => Ok(TaskStatus::Archived),
        other => Err(DbError::Storage(format!("unknown task status: {other}"))),
    }
}

fn task_status_to_db(status: TaskStatus) -> &'static str {
    match status {
        TaskStatus::Active => "active",
        TaskStatus::Frozen => "frozen",
        TaskStatus::Stopped => "stopped",
        TaskStatus::Archived => "archived",
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

fn encode_json_object(object: &JsonObject) -> Result<String, DbError> {
    serde_json::to_string(object)
        .map_err(|error| DbError::Storage(format!("could not encode JSON object: {error}")))
}

fn decode_json_object(json: &str) -> Result<JsonObject, DbError> {
    serde_json::from_str(json)
        .map_err(|error| DbError::Storage(format!("stored JSON object is invalid: {error}")))
}

fn encode_json_value(value: &Value) -> Result<String, DbError> {
    serde_json::to_string(value)
        .map_err(|error| DbError::Storage(format!("could not encode JSON value: {error}")))
}

fn decode_json_value(json: &str) -> Result<Value, DbError> {
    serde_json::from_str(json)
        .map_err(|error| DbError::Storage(format!("stored JSON value is invalid: {error}")))
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

fn encode_tool_recovery_policy(policy: ToolRecoveryPolicy) -> &'static str {
    match policy {
        ToolRecoveryPolicy::RetrySafe => "retry_safe",
        ToolRecoveryPolicy::OutcomeUnknown => "outcome_unknown",
    }
}

fn decode_tool_recovery_policy(policy: &str) -> Result<ToolRecoveryPolicy, DbError> {
    match policy {
        "retry_safe" => Ok(ToolRecoveryPolicy::RetrySafe),
        "outcome_unknown" => Ok(ToolRecoveryPolicy::OutcomeUnknown),
        other => Err(DbError::Storage(format!(
            "invalid tool recovery policy: {other}"
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
