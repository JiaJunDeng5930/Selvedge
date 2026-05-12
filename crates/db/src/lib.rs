#![doc = include_str!("../README.md")]
//! @behavior selvedge.state Task history and runtime state needed to resume work remain durable in SQLite across process restarts.
//! @behavior selvedge.state.task Durable task records expose active work, archived work, task relations, queued input, and cursor state.
//! @behavior selvedge.state.history Durable history records expose the conversation graph used to replay model input and tool output.
//! @behavior selvedge.state.transaction Durable database transactions make multi-row task state changes visible atomically.
//! @behavior selvedge.state.conversation Durable conversations can be read back as ordered model conversation items.

use std::collections::HashSet;
use std::sync::{Arc, Mutex, MutexGuard};
use std::{error::Error, fmt};

use rusqlite::{Connection, OptionalExtension, params};
// @behavior selvedge.state.domain_types Database callers exchange persisted task state through shared Selvedge domain identifiers and values.
pub use selvedge_domain_model::{
    Conversation, ConversationItem, FunctionCallId, HistoryNodeId, MessageRole, ModelProfileKey,
    ReasoningEffort, TaskId, ToolArgumentValue, ToolCallArgument, ToolManifest, ToolName,
    ToolParameterName, ToolParameterType, ToolSpec, UnixTs,
};

const SCHEMA_VERSION: &str = "router-mediated-redesign-v4";

/// @behavior selvedge.state.connection The database pool gives callers one synchronized SQLite connection for durable task state operations.
#[derive(Clone)]
pub struct DbPool {
    connection: Arc<Mutex<Connection>>,
}

/// @behavior selvedge.state.connection.handle The database connection marker exposes the public connection concept for persistence callers.
pub struct DbConnection;
/// @behavior selvedge.state.transaction.handle The database transaction marker exposes the public transaction concept for atomic persistence callers.
pub struct DbTransaction;

/// @behavior selvedge.state.error Database operations return caller-visible errors for missing rows, inactive tasks, constraint failures, storage failures, and schema mismatches.
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

/// @behavior selvedge.state.task.status Persisted task rows expose whether a task can still receive runtime writes or has been archived.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TaskStatusRow {
    Active,
    Archived,
}

/// @behavior selvedge.state.history.kind Persisted history rows expose the content kind needed to reconstruct a conversation path.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum HistoryContentKindRow {
    Message,
    Reasoning,
    FunctionCall,
    FunctionOutput,
}

/// @behavior selvedge.state.open Database opening accepts the SQLite path that stores durable Selvedge task state.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OpenDbOptions {
    /// @constraint selvedge.state.open.path The SQLite path is the caller-visible location of persisted task state.
    pub sqlite_path: String,
}

/// @behavior selvedge.state.tool Persisted tool rows expose the tools available to tasks when model calls are built.
/// @constraint selvedge.state.tool.fields Tool rows expose the durable tool name and description used in task manifests.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ToolRow {
    /// @constraint selvedge.state.tool.fields.name Tool rows expose the durable tool name used in task manifests.
    pub tool_name: ToolName,
    /// @constraint selvedge.state.tool.fields.description Tool rows expose the durable tool description used in task manifests.
    pub description_text: String,
}

/// @behavior selvedge.state.tool.parameter Persisted tool parameter rows expose the argument contract a model-visible tool requires.
/// @constraint selvedge.state.tool.parameter.fields Tool parameter rows expose name, type, description, and requiredness for model-visible arguments.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ToolParameterRow {
    /// @constraint selvedge.state.tool.parameter.fields.tool Tool parameter rows expose the owning durable tool name for model-visible arguments.
    pub tool_name: ToolName,
    /// @constraint selvedge.state.tool.parameter.fields.name Tool parameter rows expose the model-visible argument name.
    pub parameter_name: ToolParameterName,
    /// @constraint selvedge.state.tool.parameter.fields.type Tool parameter rows expose the model-visible argument type.
    pub parameter_type: ToolParameterType,
    /// @constraint selvedge.state.tool.parameter.fields.description Tool parameter rows expose the model-visible argument description.
    pub description_text: String,
    /// @constraint selvedge.state.tool.parameter.fields.required Tool parameter rows expose whether the model-visible argument is required.
    pub is_required: bool,
}

/// @behavior selvedge.state.task.row Persisted task rows expose the task cursor, model profile, reasoning effort, status, version, and timestamps.
/// @constraint selvedge.state.task.row.fields Task rows expose identity, status, cursor, profile, reasoning effort, version, and timestamps.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TaskRow {
    /// @constraint selvedge.state.task.row.fields.id Task rows expose the durable task identity.
    pub task_id: TaskId,
    /// @constraint selvedge.state.task.row.fields.status Task rows expose the durable active or archived status.
    pub task_status: TaskStatusRow,
    /// @constraint selvedge.state.task.row.fields.cursor Task rows expose the durable cursor node identity.
    pub cursor_node_id: HistoryNodeId,
    /// @constraint selvedge.state.task.row.fields.profile Task rows expose the model profile selected for task execution.
    pub model_profile_key: ModelProfileKey,
    /// @constraint selvedge.state.task.row.fields.reasoning Task rows expose the reasoning effort selected for task execution.
    pub reasoning_effort: ReasoningEffort,
    /// @constraint selvedge.state.task.row.fields.version Task rows expose the durable state version observed by callers.
    pub state_version: u64,
    /// @constraint selvedge.state.task.row.fields.created Task rows expose the task creation timestamp.
    pub created_at: UnixTs,
    /// @constraint selvedge.state.task.row.fields.updated Task rows expose the most recent task update timestamp.
    pub updated_at: UnixTs,
}

/// @behavior selvedge.state.task.tool Persisted task-tool rows expose which tools are enabled for a task.
/// @constraint selvedge.state.task.tool.fields Task-tool rows expose a task ID and enabled tool name pair.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TaskToolRow {
    /// @constraint selvedge.state.task.tool.fields.task Task-tool rows expose the durable task identity for an enabled tool.
    pub task_id: TaskId,
    /// @constraint selvedge.state.task.tool.fields.tool Task-tool rows expose the enabled durable tool name for a task.
    pub tool_name: ToolName,
}

/// @behavior selvedge.state.task.parent Persisted task parent edges expose parent-child task relationships for snapshots and runtime recovery.
/// @constraint selvedge.state.task.parent.fields Task parent edge rows expose parent ID, child ID, and edge creation time.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TaskParentEdgeRow {
    /// @constraint selvedge.state.task.parent.fields.parent Task parent edge rows expose the durable parent task identity.
    pub parent_task_id: TaskId,
    /// @constraint selvedge.state.task.parent.fields.child Task parent edge rows expose the durable child task identity.
    pub child_task_id: TaskId,
    /// @constraint selvedge.state.task.parent.fields.created Task parent edge rows expose the edge creation timestamp.
    pub created_at: UnixTs,
}

/// @behavior selvedge.state.task.queue Persisted queued user input rows expose pending user messages for an active task in sequence order.
/// @constraint selvedge.state.task.queue.fields Queued input rows expose task ID, sequence number, message text, and queue timestamp.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct QueuedUserInputRow {
    /// @constraint selvedge.state.task.queue.fields.task Queued input rows expose the durable task identity for a pending message.
    pub task_id: TaskId,
    /// @constraint selvedge.state.task.queue.fields.sequence Queued input rows expose the durable sequence number for a pending message.
    pub seq_no: u64,
    /// @constraint selvedge.state.task.queue.fields.message Queued input rows expose the pending user message text.
    pub message_text: String,
    /// @constraint selvedge.state.task.queue.fields.queued Queued input rows expose the queue timestamp for a pending message.
    pub queued_at: UnixTs,
}

/// @behavior selvedge.state.history.row Persisted history node rows expose graph linkage, content kind, and creation time for a conversation path.
/// @constraint selvedge.state.history.row.fields History node rows expose node ID, optional parent node, content kind, and creation time.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HistoryNodeRow {
    /// @constraint selvedge.state.history.row.fields.node History node rows expose the durable history node identity.
    pub node_id: HistoryNodeId,
    /// @constraint selvedge.state.history.row.fields.parent History node rows expose the optional durable parent node identity.
    pub parent_node_id: Option<HistoryNodeId>,
    /// @constraint selvedge.state.history.row.fields.kind History node rows expose the durable content kind.
    pub content_kind: HistoryContentKindRow,
    /// @constraint selvedge.state.history.row.fields.created History node rows expose the node creation timestamp.
    pub created_at: UnixTs,
}

/// @behavior selvedge.state.history.message Persisted message nodes expose the role and text that are replayed into model conversation input.
/// @constraint selvedge.state.history.message.fields Message node rows expose node ID, role, and text for conversation replay.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HistoryMessageNodeRow {
    /// @constraint selvedge.state.history.message.fields.node Message node rows expose the durable history node identity.
    pub node_id: HistoryNodeId,
    /// @constraint selvedge.state.history.message.fields.role Message node rows expose the message role for conversation replay.
    pub message_role: MessageRole,
    /// @constraint selvedge.state.history.message.fields.text Message node rows expose the message text for conversation replay.
    pub message_text: String,
}

/// @behavior selvedge.state.history.reasoning Persisted reasoning nodes expose hidden reasoning text retained in task history.
/// @constraint selvedge.state.history.reasoning.fields Reasoning node rows expose node ID and reasoning text retained in history.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HistoryReasoningNodeRow {
    /// @constraint selvedge.state.history.reasoning.fields.node Reasoning node rows expose the durable history node identity.
    pub node_id: HistoryNodeId,
    /// @constraint selvedge.state.history.reasoning.fields.text Reasoning node rows expose reasoning text retained in history.
    pub reasoning_text: String,
}

/// @behavior selvedge.state.history.function_call Persisted function-call nodes expose model-requested tool calls and their target tool names.
/// @constraint selvedge.state.history.function_call.fields Function-call node rows expose node ID, call ID, and tool name.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HistoryFunctionCallNodeRow {
    /// @constraint selvedge.state.history.function_call.fields.node Function-call node rows expose the durable history node identity.
    pub node_id: HistoryNodeId,
    /// @constraint selvedge.state.history.function_call.fields.call Function-call node rows expose the model-visible function call identity.
    pub function_call_id: FunctionCallId,
    /// @constraint selvedge.state.history.function_call.fields.tool Function-call node rows expose the durable target tool name.
    pub tool_name: ToolName,
}

/// @behavior selvedge.state.history.function_argument Persisted function-call argument rows expose typed tool arguments for model-requested calls.
/// @constraint selvedge.state.history.function_argument.fields Function-call argument rows expose call node, tool, argument name, and typed value.
#[derive(Clone, Debug, PartialEq)]
pub struct HistoryFunctionCallArgumentRow {
    /// @constraint selvedge.state.history.function_argument.fields.node Function-call argument rows expose the durable call node identity.
    pub function_call_node_id: HistoryNodeId,
    /// @constraint selvedge.state.history.function_argument.fields.tool Function-call argument rows expose the durable target tool name.
    pub tool_name: ToolName,
    /// @constraint selvedge.state.history.function_argument.fields.name Function-call argument rows expose the durable argument name.
    pub argument_name: ToolParameterName,
    /// @constraint selvedge.state.history.function_argument.fields.value Function-call argument rows expose the typed argument value.
    pub value: ToolArgumentValue,
}

/// @behavior selvedge.state.history.function_output Persisted function-output nodes expose tool results that are replayed into model conversation input.
/// @constraint selvedge.state.history.function_output.fields Function-output node rows expose call identity, output text, and error status.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HistoryFunctionOutputNodeRow {
    /// @constraint selvedge.state.history.function_output.fields.node Function-output node rows expose the durable output node identity.
    pub node_id: HistoryNodeId,
    /// @constraint selvedge.state.history.function_output.fields.call_node Function-output node rows expose the durable function-call node identity.
    pub function_call_node_id: HistoryNodeId,
    /// @constraint selvedge.state.history.function_output.fields.call Function-output node rows expose the model-visible function call identity.
    pub function_call_id: FunctionCallId,
    /// @constraint selvedge.state.history.function_output.fields.tool Function-output node rows expose the durable target tool name.
    pub tool_name: ToolName,
    /// @constraint selvedge.state.history.function_output.fields.text Function-output node rows expose the tool result text.
    pub output_text: String,
    /// @constraint selvedge.state.history.function_output.fields.error Function-output node rows expose whether the tool result is an error.
    pub is_error: bool,
}

/// @behavior selvedge.state.history.open_call Open function-call records expose tool calls on the active path that still need tool output.
/// @constraint selvedge.state.history.open_call.fields Open function-call records expose call node, call ID, tool name, and arguments.
#[derive(Clone, Debug, PartialEq)]
pub struct OpenFunctionCall {
    /// @constraint selvedge.state.history.open_call.fields.node Open function-call records expose the durable call node identity.
    pub function_call_node_id: HistoryNodeId,
    /// @constraint selvedge.state.history.open_call.fields.call Open function-call records expose the model-visible function call identity.
    pub function_call_id: FunctionCallId,
    /// @constraint selvedge.state.history.open_call.fields.tool Open function-call records expose the durable target tool name.
    pub tool_name: ToolName,
    /// @constraint selvedge.state.history.open_call.fields.arguments Open function-call records expose the typed arguments for the call.
    pub arguments: Vec<ToolCallArgument>,
}

/// @behavior selvedge.state.history.node Loaded history nodes expose concrete message, reasoning, function-call, or function-output content.
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
    /// @behavior selvedge.state.history.node.id Loaded history nodes expose their durable node ID independent of content kind.
    pub fn node_id(&self) -> HistoryNodeId {
        match self {
            HistoryNode::Message { node_id, .. }
            | HistoryNode::Reasoning { node_id, .. }
            | HistoryNode::FunctionCall { node_id, .. }
            | HistoryNode::FunctionOutput { node_id, .. } => *node_id,
        }
    }
}

/// @behavior selvedge.state.task.create_root Root task creation persists a caller-provided task ID, existing cursor node, model profile, enabled tools, and timestamp.
/// @constraint selvedge.state.task.create_root.fields Root task creation input exposes identity, cursor, profile, tools, and creation time.
#[derive(Clone, Debug, PartialEq)]
pub struct CreateRootTaskInput {
    /// @constraint selvedge.state.task.create_root.fields.id Root task creation input exposes the durable task identity.
    pub task_id: TaskId,
    /// @constraint selvedge.state.task.create_root.fields.cursor Root task creation input exposes the existing cursor node that the task records.
    pub cursor_node_id: HistoryNodeId,
    /// @constraint selvedge.state.task.create_root.fields.profile Root task creation input exposes the model profile recorded for the task.
    pub model_profile_key: ModelProfileKey,
    /// @constraint selvedge.state.task.create_root.fields.reasoning Root task creation input exposes the reasoning effort recorded for the task.
    pub reasoning_effort: ReasoningEffort,
    /// @constraint selvedge.state.task.create_root.fields.tools Root task creation input exposes the enabled tool names recorded for the task.
    pub enabled_tools: Vec<ToolName>,
    /// @constraint selvedge.state.task.create_root.fields.created Root task creation input exposes the timestamp recorded as creation and update time.
    pub now: UnixTs,
}

/// @behavior selvedge.state.task.create_child Child task creation persists a child task with a task-layer parent edge and caller-provided cursor node.
/// @constraint selvedge.state.task.create_child.fields Child task creation input exposes parent ID, child ID, cursor node, and creation time.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CreateChildTaskInput {
    /// @constraint selvedge.state.task.create_child.fields.parent Child task creation input exposes the durable parent task identity.
    pub parent_task_id: TaskId,
    /// @constraint selvedge.state.task.create_child.fields.child Child task creation input exposes the durable child task identity.
    pub child_task_id: TaskId,
    /// @constraint selvedge.state.task.create_child.fields.cursor Child task creation input exposes the cursor node recorded for the child task.
    pub cursor_node_id: HistoryNodeId,
    /// @constraint selvedge.state.task.create_child.fields.created Child task creation input exposes the timestamp recorded as child creation and update time.
    pub now: UnixTs,
}

/// @behavior selvedge.state.task.loaded Active task loading exposes the task row, current cursor node, enabled tool manifest, and queued inputs.
/// @constraint selvedge.state.task.loaded.fields Loaded active tasks expose the task row, cursor node, tool manifest, and queued inputs.
#[derive(Clone, Debug, PartialEq)]
pub struct LoadedActiveTask {
    /// @constraint selvedge.state.task.loaded.fields.task Loaded active tasks expose the durable task row.
    pub task: TaskRow,
    /// @constraint selvedge.state.task.loaded.fields.cursor Loaded active tasks expose the concrete cursor history node.
    pub cursor_node: HistoryNode,
    /// @constraint selvedge.state.task.loaded.fields.tools Loaded active tasks expose the enabled tool manifest.
    pub tool_manifest: ToolManifest,
    /// @constraint selvedge.state.task.loaded.fields.queue Loaded active tasks expose pending queued user inputs.
    pub queued_inputs: Vec<QueuedUserInputRow>,
}

/// @behavior selvedge.state.history.new_content New history content exposes the concrete kind that will be persisted into the task history graph.
#[derive(Clone, Debug, PartialEq)]
pub enum NewHistoryNodeContent {
    Message(NewMessageNodeContent),
    Reasoning(NewReasoningNodeContent),
    FunctionCall(NewFunctionCallNodeContent),
    FunctionOutput(NewFunctionOutputNodeContent),
}

/// @behavior selvedge.state.history.new_node New history nodes expose the optional parent pointer, content, and creation timestamp to be persisted.
/// @constraint selvedge.state.history.new_node.fields New history nodes expose parent linkage, content, and creation time.
#[derive(Clone, Debug, PartialEq)]
pub struct NewHistoryNode {
    /// @constraint selvedge.state.history.new_node.fields.parent New history nodes expose the optional parent linkage to persist.
    pub parent_node_id: Option<HistoryNodeId>,
    /// @constraint selvedge.state.history.new_node.fields.content New history nodes expose the content to persist.
    pub content: NewHistoryNodeContent,
    /// @constraint selvedge.state.history.new_node.fields.created New history nodes expose the creation timestamp to persist.
    pub created_at: UnixTs,
}

/// @behavior selvedge.state.history.new_message New message content exposes the role and text that will be persisted for conversation replay.
/// @constraint selvedge.state.history.new_message.fields New message content exposes role and text.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NewMessageNodeContent {
    /// @constraint selvedge.state.history.new_message.fields.role New message content exposes the role to persist.
    pub message_role: MessageRole,
    /// @constraint selvedge.state.history.new_message.fields.text New message content exposes the text to persist.
    pub message_text: String,
}

/// @behavior selvedge.state.history.new_reasoning New reasoning content exposes reasoning text that will be retained in task history.
/// @constraint selvedge.state.history.new_reasoning.fields New reasoning content exposes reasoning text.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NewReasoningNodeContent {
    /// @constraint selvedge.state.history.new_reasoning.fields.text New reasoning content exposes the reasoning text to persist.
    pub reasoning_text: String,
}

/// @behavior selvedge.state.history.new_function_call New function-call content exposes a model-requested tool call and arguments to persist.
/// @constraint selvedge.state.history.new_function_call.fields New function-call content exposes call ID, tool name, and arguments.
#[derive(Clone, Debug, PartialEq)]
pub struct NewFunctionCallNodeContent {
    /// @constraint selvedge.state.history.new_function_call.fields.call New function-call content exposes the model-visible function call identity to persist.
    pub function_call_id: FunctionCallId,
    /// @constraint selvedge.state.history.new_function_call.fields.tool New function-call content exposes the target tool name to persist.
    pub tool_name: ToolName,
    /// @constraint selvedge.state.history.new_function_call.fields.arguments New function-call content exposes the typed arguments to persist.
    pub arguments: Vec<ToolCallArgument>,
}

/// @behavior selvedge.state.history.new_function_output New function-output content exposes a tool result to persist against a prior function call.
/// @constraint selvedge.state.history.new_function_output.fields New function-output content exposes the referenced call, tool, output text, and error status.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NewFunctionOutputNodeContent {
    /// @constraint selvedge.state.history.new_function_output.fields.call_node New function-output content exposes the referenced call node to persist.
    pub function_call_node_id: HistoryNodeId,
    /// @constraint selvedge.state.history.new_function_output.fields.call New function-output content exposes the model-visible function call identity to persist.
    pub function_call_id: FunctionCallId,
    /// @constraint selvedge.state.history.new_function_output.fields.tool New function-output content exposes the target tool name to persist.
    pub tool_name: ToolName,
    /// @constraint selvedge.state.history.new_function_output.fields.text New function-output content exposes the output text to persist.
    pub output_text: String,
    /// @constraint selvedge.state.history.new_function_output.fields.error New function-output content exposes the tool error status to persist.
    pub is_error: bool,
}

/// @behavior selvedge.state.open.call Opening a database creates the schema when needed, verifies the schema version, and returns a usable pool.
pub fn open_db(options: OpenDbOptions) -> Result<DbPool, DbError> {
    let connection = Connection::open(&options.sqlite_path).map_err(map_error)?;
    connection
        .pragma_update(None, "foreign_keys", "ON")
        .map_err(map_error)?;

    if database_is_empty(&connection)? {
        connection
            .execute_batch(include_str!("schema.sql"))
            // @constraint selvedge.state.open.call.schema_error Opening a database reports schema initialization failures as caller-visible database errors.
            .map_err(map_error)?;
    }

    let db = DbPool {
        connection: Arc::new(Mutex::new(connection)),
    };
    verify_schema(&db)?;
    Ok(db)
}

/// @constraint selvedge.state.schema Database callers receive a schema mismatch error when stored schema metadata differs from the expected version.
pub fn verify_schema(db: &DbPool) -> Result<(), DbError> {
    let connection = db.connection()?;
    let actual: Option<String> = connection
        .query_row(
            "SELECT schema_value FROM schema_metadata WHERE schema_key = 'selvedge_schema_version'",
            [],
            |row| row.get(0),
        )
        .optional()
        // @constraint selvedge.state.schema.read_error Schema verification reports schema metadata read failures as caller-visible database errors.
        .map_err(map_error)?;

    if actual.as_deref() == Some(SCHEMA_VERSION) {
        Ok(())
    } else {
        // @constraint selvedge.state.schema.mismatch Schema verification reports unexpected schema metadata as a caller-visible schema mismatch.
        Err(DbError::SchemaMismatch {
            expected: SCHEMA_VERSION.to_owned(),
            actual,
        })
    }
}

/// @behavior selvedge.state.tool.register Registering a tool persists its description and parameter contract for task tool manifests.
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
// @constraint selvedge.state.error.anchor493 Database persistence operations surface this storage branch as caller-visible database data or errors.
// @constraint selvedge.state.error.p2l494 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;
    }
    // @constraint selvedge.state.error.anchor495 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l497 Database persistence operations surface this storage branch as caller-visible database data or errors.
    tx.commit().map_err(map_error)
}

/// @behavior selvedge.state.history.create Creating a history node persists one graph node and leaves task rows unchanged.
pub fn create_history_node(db: &DbPool, node: NewHistoryNode) -> Result<HistoryNodeId, DbError> {
    let mut connection = db.connection()?;
    let tx = connection.transaction().map_err(map_error)?;
    let node_id = insert_history_node(&tx, node)?;
    tx.commit().map_err(map_error)?;
    Ok(node_id)
}

/// @behavior selvedge.state.task.create_root.call Creating a root task persists an active task whose cursor points at an existing history node.
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
// @constraint selvedge.state.error.anchor525 Database persistence operations surface this storage branch as caller-visible database data or errors.
// @constraint selvedge.state.error.p2l528 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;
        for tool_name in input.enabled_tools {
            tx.execute(
                "INSERT INTO task_tools (task_id, tool_name) VALUES (?1, ?2)",
                params![task_id.0, tool_name.0],
            )
            // @constraint selvedge.state.error.anchor531 Database persistence operations surface this storage branch as caller-visible database data or errors.
            // @constraint selvedge.state.error.p2l535 Database persistence operations surface this storage branch as caller-visible database data or errors.
            .map_err(map_error)?;
        }
        // @constraint selvedge.state.error.anchor533 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l538 Database persistence operations surface this storage branch as caller-visible database data or errors.
        tx.commit().map_err(map_error)?;
    }
    read_task(db, &task_id)
}

/// @behavior selvedge.state.task.create_child.call Creating a child task copies the parent task profile and tools while recording a task parent edge.
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
// @constraint selvedge.state.error.anchor560 Database persistence operations surface this storage branch as caller-visible database data or errors.
// @constraint selvedge.state.error.p2l566 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;
        tx.execute(
            "INSERT INTO task_tools (task_id, tool_name)
             SELECT ?1, tool_name FROM task_tools WHERE task_id = ?2",
            params![input.child_task_id.0, input.parent_task_id.0],
        )
        // @constraint selvedge.state.error.anchor566 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l573 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;
        tx.execute(
            "INSERT INTO task_parent_edges (parent_task_id, child_task_id, created_at)
             VALUES (?1, ?2, ?3)",
            params![input.parent_task_id.0, input.child_task_id.0, input.now.0],
        )
        // @constraint selvedge.state.error.anchor572 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l580 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;
        // @constraint selvedge.state.error.anchor573 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l582 Database persistence operations surface this storage branch as caller-visible database data or errors.
        tx.commit().map_err(map_error)?;
    }
    read_task(db, &child_task_id)
}

/// @behavior selvedge.state.task.load_active Loading an active task returns its cursor history node, enabled tools, and queued user inputs.
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

/// @behavior selvedge.state.history.append_user Appending a user message persists it under the current task cursor and moves the active task cursor.
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

/// @behavior selvedge.state.history.append_model_tool_calls Appending a model tool-call reply persists optional assistant text and one or more function calls on the active path.
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
    // @constraint selvedge.state.error.anchor630 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l640 Database persistence operations surface this storage branch as caller-visible database data or errors.
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
    // @constraint selvedge.state.error.anchor653 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l664 Database persistence operations surface this storage branch as caller-visible database data or errors.
    tx.commit().map_err(map_error)?;
    Ok(function_call_node_ids)
}

/// @behavior selvedge.state.history.append_assistant Appending an assistant message persists it and then drains queued user inputs onto the same active path.
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
    // @constraint selvedge.state.error.anchor679 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l691 Database persistence operations surface this storage branch as caller-visible database data or errors.
    tx.commit().map_err(map_error)?;
    Ok(last_node_id)
}

/// @behavior selvedge.state.history.append_function_output Appending a function output persists a tool result for an open call and then drains queued user inputs.
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
    // @constraint selvedge.state.error.anchor704 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l717 Database persistence operations surface this storage branch as caller-visible database data or errors.
    tx.commit().map_err(map_error)?;
    Ok(last_node_id)
}

/// @behavior selvedge.state.task.queue.drain Draining queued user inputs appends them in sequence and returns the final appended history node.
pub fn drain_queued_user_inputs_and_move_cursor(
    db: &DbPool,
    task_id: &TaskId,
    created_at: UnixTs,
) -> Result<Option<HistoryNodeId>, DbError> {
    let mut connection = db.connection()?;
    let tx = connection.transaction().map_err(map_error)?;
    ensure_active_task_in_tx(&tx, task_id)?;
    let last_node_id = append_all_queued_user_inputs_in_tx(&tx, task_id, created_at)?;
    // @constraint selvedge.state.error.anchor718 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l732 Database persistence operations surface this storage branch as caller-visible database data or errors.
    tx.commit().map_err(map_error)?;
    Ok(last_node_id)
}

/// @behavior selvedge.state.history.open_call.read Reading open function calls returns calls on the active path without matching function outputs.
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
                    // @constraint selvedge.state.error.anchor773 Database persistence operations surface this storage branch as caller-visible database data or errors.
                    // @constraint selvedge.state.error.p2l788 Database persistence operations surface this storage branch as caller-visible database data or errors.
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

// @constraint selvedge.state.error.append_history Transactional history appends surface cursor update and storage failures as caller-visible database errors.
fn append_history_node_and_move_cursor(
    db: &DbPool,
    task_id: &TaskId,
    mut node: NewHistoryNode,
) -> Result<HistoryNodeId, DbError> {
    let mut connection = db.connection()?;
    // @constraint selvedge.state.error.anchor790 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l807 Database persistence operations surface this storage branch as caller-visible database data or errors.
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
        // @constraint selvedge.state.error.anchor813 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l831 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;
    if changed == 0 {
        // @constraint selvedge.state.error.anchor815 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l834 Database persistence operations surface this storage branch as caller-visible database data or errors.
        return Err(DbError::TaskNotActive);
    }
    // @constraint selvedge.state.error.anchor817 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l837 Database persistence operations surface this storage branch as caller-visible database data or errors.
    tx.commit().map_err(map_error)?;
    Ok(node_id)
}

// @constraint selvedge.state.error.current_cursor Active cursor reads surface missing active tasks and storage failures as caller-visible database errors.
fn current_cursor_node_id_in_tx(
    tx: &rusqlite::Transaction<'_>,
    task_id: &TaskId,
) -> Result<i64, DbError> {
    tx.query_row(
        "SELECT cursor_node_id FROM tasks WHERE task_id = ?1 AND task_status = 'active'",
        params![task_id.0],
        |row| row.get(0),
    )
    // @constraint selvedge.state.error.anchor830 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l852 Database persistence operations surface this storage branch as caller-visible database data or errors.
    .map_err(map_error)
}

// @constraint selvedge.state.error.append_cursor Transactional cursor appends surface history insert and cursor update failures as caller-visible database errors.
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

// @constraint selvedge.state.error.queue_drain Transactional queue draining surfaces queue read, history append, delete, and conversion failures as caller-visible database errors.
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
            // @constraint selvedge.state.error.anchor865 Database persistence operations surface this storage branch as caller-visible database data or errors.
            // @constraint selvedge.state.error.p2l890 Database persistence operations surface this storage branch as caller-visible database data or errors.
            .map_err(map_error)?;
        statement
            .query_map(params![task_id.0], map_queued_user_input_row)
            // @constraint selvedge.state.error.anchor868 Database persistence operations surface this storage branch as caller-visible database data or errors.
            // @constraint selvedge.state.error.p2l894 Database persistence operations surface this storage branch as caller-visible database data or errors.
            .map_err(map_error)?
            .collect::<Result<Vec<_>, _>>()
            // @constraint selvedge.state.error.anchor870 Database persistence operations surface this storage branch as caller-visible database data or errors.
            // @constraint selvedge.state.error.p2l897 Database persistence operations surface this storage branch as caller-visible database data or errors.
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
        // @constraint selvedge.state.error.anchor888 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l916 Database persistence operations surface this storage branch as caller-visible database data or errors.
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
    // @constraint selvedge.state.error.anchor899 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l928 Database persistence operations surface this storage branch as caller-visible database data or errors.
) -> Result<(), DbError> {
    let changed = tx
        .execute(
            "UPDATE tasks
             SET cursor_node_id = ?1, updated_at = ?2, state_version = state_version + 1
             WHERE task_id = ?3 AND task_status = 'active'",
            params![node_id.0, updated_at.0, task_id.0],
        )
        // @constraint selvedge.state.error.anchor907 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l937 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;
    if changed == 0 {
        // @constraint selvedge.state.error.anchor909 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l940 Database persistence operations surface this storage branch as caller-visible database data or errors.
        Err(DbError::TaskNotActive)
    } else {
        Ok(())
    }
}

/// @behavior selvedge.state.task.queue.add Queueing user input persists the next sequenced pending message for an active task.
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
        // @constraint selvedge.state.error.anchor931 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l963 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;
    tx.execute(
        "INSERT INTO queued_user_inputs (task_id, seq_no, message_text, queued_at)
         VALUES (?1, ?2, ?3, ?4)",
        params![task_id.0, next_seq_no, message_text, queued_at.0],
    )
    // @constraint selvedge.state.error.anchor937 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l970 Database persistence operations surface this storage branch as caller-visible database data or errors.
    .map_err(map_error)?;
    // @constraint selvedge.state.error.anchor938 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l972 Database persistence operations surface this storage branch as caller-visible database data or errors.
    tx.commit().map_err(map_error)?;
    Ok(QueuedUserInputRow {
        task_id: task_id.clone(),
        seq_no: i64_to_u64(next_seq_no)?,
        message_text,
        queued_at,
    })
}

/// @behavior selvedge.state.task.queue.consume Consuming queued user input returns and deletes the oldest pending message for an active task.
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
        // @constraint selvedge.state.error.anchor966 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1001 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;
    if let Some(queued) = &queued {
        tx.execute(
            "DELETE FROM queued_user_inputs WHERE task_id = ?1 AND seq_no = ?2",
            params![queued.task_id.0, u64_to_i64(queued.seq_no)?],
        )
        // @constraint selvedge.state.error.anchor972 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1008 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;
    }
    // @constraint selvedge.state.error.anchor974 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l1011 Database persistence operations surface this storage branch as caller-visible database data or errors.
    tx.commit().map_err(map_error)?;
    Ok(queued)
}

/// @behavior selvedge.state.task.queue.append_next Appending the next queued user input persists the oldest pending message and moves the active task cursor.
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
        // @constraint selvedge.state.error.anchor998 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1036 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;
    let Some(queued) = queued else {
        // @constraint selvedge.state.error.anchor1000 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1039 Database persistence operations surface this storage branch as caller-visible database data or errors.
        tx.commit().map_err(map_error)?;
        return Ok(None);
    };
    let current_cursor_node_id: i64 = tx
        .query_row(
            "SELECT cursor_node_id FROM tasks WHERE task_id = ?1 AND task_status = 'active'",
            params![task_id.0],
            |row| row.get(0),
        )
        // @constraint selvedge.state.error.anchor1009 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1049 Database persistence operations surface this storage branch as caller-visible database data or errors.
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
        // @constraint selvedge.state.error.anchor1028 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1069 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;
    if changed == 0 {
        // @constraint selvedge.state.error.anchor1030 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1072 Database persistence operations surface this storage branch as caller-visible database data or errors.
        return Err(DbError::Constraint(
            "queued input append cursor changed before update".to_owned(),
        ));
    }
    tx.execute(
        "DELETE FROM queued_user_inputs WHERE task_id = ?1 AND seq_no = ?2",
        params![queued.task_id.0, u64_to_i64(queued.seq_no)?],
    )
    // @constraint selvedge.state.error.anchor1038 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l1081 Database persistence operations surface this storage branch as caller-visible database data or errors.
    .map_err(map_error)?;
    // @constraint selvedge.state.error.anchor1039 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l1083 Database persistence operations surface this storage branch as caller-visible database data or errors.
    tx.commit().map_err(map_error)?;
    Ok(Some(node_id))
}

/// @behavior selvedge.state.task.archive Archiving a task clears queued input, marks the task archived, and advances its durable state version.
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
        // @constraint selvedge.state.error.anchor1060 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1105 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;
    if changed == 0 {
        // @constraint selvedge.state.error.anchor1062 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1108 Database persistence operations surface this storage branch as caller-visible database data or errors.
        Err(DbError::TaskNotActive)
    } else {
        // @constraint selvedge.state.error.anchor1064 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1111 Database persistence operations surface this storage branch as caller-visible database data or errors.
        tx.commit().map_err(map_error)?;
        Ok(())
    }
}

/// @behavior selvedge.state.task.list_active Listing active tasks returns non-archived task rows ordered by most recent update.
pub fn list_active_tasks(db: &DbPool) -> Result<Vec<TaskRow>, DbError> {
    let connection = db.connection()?;
    let mut statement = connection
        .prepare(
            "SELECT task_id, task_status, cursor_node_id, model_profile_key, reasoning_effort, state_version, created_at, updated_at
             FROM tasks
             WHERE task_status = 'active'
             ORDER BY updated_at DESC, task_id ASC",
        )
// @constraint selvedge.state.error.anchor1079 Database persistence operations surface this storage branch as caller-visible database data or errors.
// @constraint selvedge.state.error.p2l1127 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;
    let rows = statement
        .query_map([], map_task_row)
        // @constraint selvedge.state.error.anchor1082 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1131 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?
        .collect::<Result<Vec<_>, _>>()
        // @constraint selvedge.state.error.anchor1084 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1134 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;
    Ok(rows)
}

/// @behavior selvedge.state.task.parent.read Reading task parent edges returns durable parent-child task links in deterministic order.
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
        // @constraint selvedge.state.error.anchor1106 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1157 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?
        .collect::<Result<Vec<_>, _>>()
        // @constraint selvedge.state.error.anchor1108 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1160 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)
}

/// @behavior selvedge.state.tool.manifest Reading a task tool manifest returns the enabled tools and parameters for an active task.
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
        // @constraint selvedge.state.error.anchor1123 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1176 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;
    let tools = statement
        .query_map(params![task_id.0], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })
        // @constraint selvedge.state.error.anchor1128 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1182 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?
        .collect::<Result<Vec<_>, _>>()
        // @constraint selvedge.state.error.anchor1130 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1185 Database persistence operations surface this storage branch as caller-visible database data or errors.
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
            // @constraint selvedge.state.error.anchor1141 Database persistence operations surface this storage branch as caller-visible database data or errors.
            // @constraint selvedge.state.error.p2l1197 Database persistence operations surface this storage branch as caller-visible database data or errors.
            .map_err(map_error)?;
        let parameters = parameter_statement
            .query_map(params![name], |row| {
                Ok(selvedge_domain_model::ToolParameter {
                    name: row.get(0)?,
                    parameter_type: tool_parameter_type_from_db(&row.get::<_, String>(1)?)
                        // @constraint selvedge.state.error.anchor1147 Database persistence operations surface this storage branch as caller-visible database data or errors.
                        // @constraint selvedge.state.error.p2l1204 Database persistence operations surface this storage branch as caller-visible database data or errors.
                        .map_err(|error| {
                            rusqlite::Error::ToSqlConversionFailure(Box::new(error))
                        })?,
                    description: row.get(2)?,
                    required: row.get::<_, i64>(3)? == 1,
                })
            })
            // @constraint selvedge.state.error.anchor1154 Database persistence operations surface this storage branch as caller-visible database data or errors.
            // @constraint selvedge.state.error.p2l1212 Database persistence operations surface this storage branch as caller-visible database data or errors.
            .map_err(map_error)?
            .collect::<Result<Vec<_>, _>>()
            // @constraint selvedge.state.error.anchor1156 Database persistence operations surface this storage branch as caller-visible database data or errors.
            // @constraint selvedge.state.error.p2l1215 Database persistence operations surface this storage branch as caller-visible database data or errors.
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

/// @behavior selvedge.state.conversation.read Reading a task conversation replays the active cursor path into model conversation items.
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
            // @constraint selvedge.state.error.anchor1219 Database persistence operations surface this storage branch as caller-visible database data or errors.
            // @constraint selvedge.state.error.p2l1279 Database persistence operations surface this storage branch as caller-visible database data or errors.
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
        // @constraint selvedge.state.error.anchor1230 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1291 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;
    Ok(count == 0)
}

fn read_task(db: &DbPool, task_id: &TaskId) -> Result<TaskRow, DbError> {
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
// @constraint selvedge.state.error.anchor1245 Database persistence operations surface this storage branch as caller-visible database data or errors.
// @constraint selvedge.state.error.p2l1307 Database persistence operations surface this storage branch as caller-visible database data or errors.
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
// @constraint selvedge.state.error.anchor1258 Database persistence operations surface this storage branch as caller-visible database data or errors.
// @constraint selvedge.state.error.p2l1321 Database persistence operations surface this storage branch as caller-visible database data or errors.
    .map_err(map_error)?
    .ok_or(DbError::NotFound)
}

fn ensure_current_path_contains_open_function_call(
    tx: &rusqlite::Transaction<'_>,
    current_cursor_node_id: i64,
    output: &NewFunctionOutputNodeContent,
    // @constraint selvedge.state.error.anchor1266 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l1330 Database persistence operations surface this storage branch as caller-visible database data or errors.
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
        // @constraint selvedge.state.error.anchor1299 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1364 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;

    if !exists {
        // @constraint selvedge.state.error.anchor1302 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1368 Database persistence operations surface this storage branch as caller-visible database data or errors.
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
// @constraint selvedge.state.error.anchor1325 Database persistence operations surface this storage branch as caller-visible database data or errors.
// @constraint selvedge.state.error.p2l1392 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;

    if output_exists {
        // @constraint selvedge.state.error.anchor1328 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1396 Database persistence operations surface this storage branch as caller-visible database data or errors.
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

// @constraint selvedge.state.error.history_concrete Concrete history node loading surfaces missing content rows and decode failures as caller-visible database errors.
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

// @constraint selvedge.state.error.history_base Base history node loading surfaces missing node rows and storage failures as caller-visible database errors.
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
        // @constraint selvedge.state.error.anchor1406 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1477 Database persistence operations surface this storage branch as caller-visible database data or errors.
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
        // @constraint selvedge.state.error.anchor1419 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1491 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;
    statement
        .query_map(params![task_id.0], map_queued_user_input_row)
        // @constraint selvedge.state.error.anchor1422 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1495 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?
        .collect::<Result<Vec<_>, _>>()
        // @constraint selvedge.state.error.anchor1424 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1498 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)
}

// @constraint selvedge.state.error.history_insert History insertion surfaces graph row and content row failures as caller-visible database errors.
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
    // @constraint selvedge.state.error.anchor1441 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l1517 Database persistence operations surface this storage branch as caller-visible database data or errors.
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

// @constraint selvedge.state.error.message_insert Message insertion surfaces unsupported roles and storage failures as caller-visible database errors.
fn insert_message_node(
    tx: &rusqlite::Transaction<'_>,
    node_id: HistoryNodeId,
    content: NewMessageNodeContent,
) -> Result<(), DbError> {
    let Some(message_role) = message_role_to_db(&content.message_role) else {
        // @constraint selvedge.state.error.anchor1462 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1540 Database persistence operations surface this storage branch as caller-visible database data or errors.
        return Err(DbError::Constraint(
            "message role cannot be persisted as a history message".to_owned(),
        ));
    };
    tx.execute(
        "INSERT INTO history_message_nodes (node_id, message_role, message_text)
         VALUES (?1, ?2, ?3)",
        params![node_id.0, message_role, content.message_text],
    )
    // @constraint selvedge.state.error.anchor1471 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l1550 Database persistence operations surface this storage branch as caller-visible database data or errors.
    .map_err(map_error)?;
    Ok(())
}

// @constraint selvedge.state.error.reasoning_insert Reasoning insertion surfaces durable reasoning row failures as caller-visible database errors.
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
    // @constraint selvedge.state.error.anchor1485 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l1566 Database persistence operations surface this storage branch as caller-visible database data or errors.
    .map_err(map_error)?;
    Ok(())
}

// @constraint selvedge.state.error.call_insert Function-call insertion surfaces required argument and storage failures as caller-visible database errors.
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
            // @constraint selvedge.state.error.anchor1507 Database persistence operations surface this storage branch as caller-visible database data or errors.
            // @constraint selvedge.state.error.p2l1590 Database persistence operations surface this storage branch as caller-visible database data or errors.
            .map_err(map_error)?;
        statement
            .query_map(params![content.tool_name.0], |row| row.get::<_, String>(0))
            // @constraint selvedge.state.error.anchor1510 Database persistence operations surface this storage branch as caller-visible database data or errors.
            // @constraint selvedge.state.error.p2l1594 Database persistence operations surface this storage branch as caller-visible database data or errors.
            .map_err(map_error)?
            .collect::<Result<Vec<_>, _>>()
            // @constraint selvedge.state.error.anchor1512 Database persistence operations surface this storage branch as caller-visible database data or errors.
            // @constraint selvedge.state.error.p2l1597 Database persistence operations surface this storage branch as caller-visible database data or errors.
            .map_err(map_error)?
    };
    for parameter_name in required_parameters {
        if !argument_names.contains(parameter_name.as_str()) {
            // @constraint selvedge.state.error.anchor1516 Database persistence operations surface this storage branch as caller-visible database data or errors.
            // @constraint selvedge.state.error.p2l1602 Database persistence operations surface this storage branch as caller-visible database data or errors.
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
    // @constraint selvedge.state.error.anchor1528 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l1615 Database persistence operations surface this storage branch as caller-visible database data or errors.
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
// @constraint selvedge.state.error.anchor1547 Database persistence operations surface this storage branch as caller-visible database data or errors.
// @constraint selvedge.state.error.p2l1635 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;
    }
    Ok(())
}

// @constraint selvedge.state.error.output_insert Function-output insertion surfaces durable tool result row failures as caller-visible database errors.
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
    // @constraint selvedge.state.error.anchor1570 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l1660 Database persistence operations surface this storage branch as caller-visible database data or errors.
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
        // @constraint selvedge.state.error.anchor1582 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1673 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;
    match status.as_deref() {
        Some("active") => Ok(()),
        // @constraint selvedge.state.error.anchor1585 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1677 Database persistence operations surface this storage branch as caller-visible database data or errors.
        Some(_) => Err(DbError::TaskNotActive),
        // @constraint selvedge.state.error.anchor1586 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1679 Database persistence operations surface this storage branch as caller-visible database data or errors.
        None => Err(DbError::NotFound),
    }
}

// @constraint selvedge.state.error.active_tx Transactional active task checks surface missing and archived tasks as caller-visible database errors.
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
        // @constraint selvedge.state.error.anchor1601 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1696 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?;
    match status.as_deref() {
        Some("active") => Ok(()),
        // @constraint selvedge.state.error.anchor1604 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1700 Database persistence operations surface this storage branch as caller-visible database data or errors.
        Some(_) => Err(DbError::TaskNotActive),
        // @constraint selvedge.state.error.anchor1605 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1702 Database persistence operations surface this storage branch as caller-visible database data or errors.
        None => Err(DbError::NotFound),
    }
}

// @constraint selvedge.state.error.message_read Message node reads surface missing rows and role decode failures as caller-visible database errors.
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
// @constraint selvedge.state.error.anchor1621 Database persistence operations surface this storage branch as caller-visible database data or errors.
// @constraint selvedge.state.error.p2l1720 Database persistence operations surface this storage branch as caller-visible database data or errors.
                        .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?,
                    message_text: row.get(2)?,
                })
            },
        )
// @constraint selvedge.state.error.anchor1626 Database persistence operations surface this storage branch as caller-visible database data or errors.
// @constraint selvedge.state.error.p2l1726 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)
}

// @constraint selvedge.state.error.reasoning_read Reasoning node reads surface missing rows and storage failures as caller-visible database errors.
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
        // @constraint selvedge.state.error.anchor1644 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1746 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)
}

// @constraint selvedge.state.error.call_read Function-call node reads surface missing rows and storage failures as caller-visible database errors.
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
// @constraint selvedge.state.error.anchor1663 Database persistence operations surface this storage branch as caller-visible database data or errors.
// @constraint selvedge.state.error.p2l1767 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)
}

// @constraint selvedge.state.error.call_argument_read Function-call argument reads surface missing typed values and decode failures as caller-visible database errors.
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
// @constraint selvedge.state.error.anchor1677 Database persistence operations surface this storage branch as caller-visible database data or errors.
// @constraint selvedge.state.error.p2l1783 Database persistence operations surface this storage branch as caller-visible database data or errors.
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
                // @constraint selvedge.state.error.anchor1690 Database persistence operations surface this storage branch as caller-visible database data or errors.
                // @constraint selvedge.state.error.p2l1797 Database persistence operations surface this storage branch as caller-visible database data or errors.
                .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?,
            })
        })
        // @constraint selvedge.state.error.anchor1693 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1801 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)?
        .collect::<Result<Vec<_>, _>>()
        // @constraint selvedge.state.error.anchor1695 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1804 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)
}

// @constraint selvedge.state.error.output_read Function-output node reads surface missing rows and storage failures as caller-visible database errors.
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
// @constraint selvedge.state.error.anchor1719 Database persistence operations surface this storage branch as caller-visible database data or errors.
// @constraint selvedge.state.error.p2l1830 Database persistence operations surface this storage branch as caller-visible database data or errors.
        .map_err(map_error)
}

fn map_task_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<TaskRow> {
    Ok(TaskRow {
        task_id: TaskId(row.get(0)?),
        task_status: task_status_from_db(&row.get::<_, String>(1)?)
            // @constraint selvedge.state.error.anchor1726 Database persistence operations surface this storage branch as caller-visible database data or errors.
            // @constraint selvedge.state.error.p2l1838 Database persistence operations surface this storage branch as caller-visible database data or errors.
            .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?,
        cursor_node_id: HistoryNodeId(row.get(2)?),
        model_profile_key: ModelProfileKey(row.get(3)?),
        reasoning_effort: reasoning_effort_from_db(&row.get::<_, String>(4)?)
            // @constraint selvedge.state.error.anchor1730 Database persistence operations surface this storage branch as caller-visible database data or errors.
            // @constraint selvedge.state.error.p2l1843 Database persistence operations surface this storage branch as caller-visible database data or errors.
            .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?,
        state_version: i64_to_u64(row.get(5)?)
            // @constraint selvedge.state.error.anchor1732 Database persistence operations surface this storage branch as caller-visible database data or errors.
            // @constraint selvedge.state.error.p2l1846 Database persistence operations surface this storage branch as caller-visible database data or errors.
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
            // @constraint selvedge.state.error.anchor1744 Database persistence operations surface this storage branch as caller-visible database data or errors.
            // @constraint selvedge.state.error.p2l1859 Database persistence operations surface this storage branch as caller-visible database data or errors.
            .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?,
        created_at: UnixTs(row.get(3)?),
    })
}

fn map_queued_user_input_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<QueuedUserInputRow> {
    Ok(QueuedUserInputRow {
        task_id: TaskId(row.get(0)?),
        seq_no: i64_to_u64(row.get(1)?)
            // @constraint selvedge.state.error.anchor1753 Database persistence operations surface this storage branch as caller-visible database data or errors.
            // @constraint selvedge.state.error.p2l1869 Database persistence operations surface this storage branch as caller-visible database data or errors.
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
        // @constraint selvedge.state.error.anchor1774 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1891 Database persistence operations surface this storage branch as caller-visible database data or errors.
        other => Err(DbError::Storage(format!(
            "unknown history content kind: {other}"
        ))),
    }
}

fn task_status_from_db(value: &str) -> Result<TaskStatusRow, DbError> {
    match value {
        "active" => Ok(TaskStatusRow::Active),
        "archived" => Ok(TaskStatusRow::Archived),
        // @constraint selvedge.state.error.anchor1784 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1902 Database persistence operations surface this storage branch as caller-visible database data or errors.
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
        // @constraint selvedge.state.error.anchor1804 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1923 Database persistence operations surface this storage branch as caller-visible database data or errors.
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
        // @constraint selvedge.state.error.anchor1823 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1943 Database persistence operations surface this storage branch as caller-visible database data or errors.
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
        // @constraint selvedge.state.error.anchor1844 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l1965 Database persistence operations surface this storage branch as caller-visible database data or errors.
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

// @constraint selvedge.state.error.argument_value_decode Tool argument value decoding surfaces missing typed value columns as caller-visible storage errors.
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
        // @constraint selvedge.state.error.anchor1889 Database persistence operations surface this storage branch as caller-visible database data or errors.
        // @constraint selvedge.state.error.p2l2012 Database persistence operations surface this storage branch as caller-visible database data or errors.
        other => Err(DbError::Storage(format!(
            "unknown argument value type: {other}"
        ))),
    }
}

fn bool_to_i64(value: bool) -> i64 {
    if value { 1 } else { 0 }
}

fn i64_to_u64(value: i64) -> Result<u64, DbError> {
    // @constraint selvedge.state.error.anchor1900 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l2024 Database persistence operations surface this storage branch as caller-visible database data or errors.
    u64::try_from(value).map_err(|_| DbError::Storage(format!("negative integer: {value}")))
}

fn u64_to_i64(value: u64) -> Result<i64, DbError> {
    // @constraint selvedge.state.error.anchor1904 Database persistence operations surface this storage branch as caller-visible database data or errors.
    // @constraint selvedge.state.error.p2l2029 Database persistence operations surface this storage branch as caller-visible database data or errors.
    i64::try_from(value).map_err(|_| DbError::Storage(format!("integer is too large: {value}")))
}

// @constraint selvedge.state.error.anchor1907 Database persistence operations surface this storage branch as caller-visible database data or errors.
// @constraint selvedge.state.error.p2l2033 Database persistence operations surface this storage branch as caller-visible database data or errors.
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
