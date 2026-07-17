#![doc = include_str!("../README.md")]

use std::collections::BTreeMap;
use std::future::Future;
use std::{error::Error, fmt};

use selvedge_command_model::{
    ArchiveTaskOutcome, ForkTaskError, ForkTaskOutcome, HistoryNodeProjection,
    HistoryNodeProjectionBody, RouterCommand, RouterCommandEnvelope, RouterIngressMessage,
    RouterIngressWeakSender, SendUserInputOutcome, TaskCommandError, TaskProjectionStatus,
    ToolExecutionRequest, ToolExecutionResult, archive_task_response_channel,
    fork_task_response_channel, send_user_input_response_channel,
};
use selvedge_db::{
    DbError, DbPool, HistoryNode, ReadTaskInput, TaskRead, TaskStatusRow, read_task,
};
use selvedge_domain_model::{
    HistoryNodeId, MessageRole, TaskId, ToolArgumentValue, ToolCallArgument, ToolManifest,
    ToolParameter, ToolParameterType, ToolSpec,
};
use serde_json::{Number, Value};
use tokio::task::JoinHandle;

use selvedge_router::{ToolExecutionSpawnError, ToolExecutionSpawner};

pub const FORK_TASK_TOOL_NAME: &str = "fork_task";
pub const READ_TASK_TOOL_NAME: &str = "read_task";
pub const SEND_MESSAGE_TO_TASK_TOOL_NAME: &str = "send_message_to_task";
pub const ARCHIVE_TASK_TOOL_NAME: &str = "archive_task";

const MAX_READ_LIMIT: i64 = 100;

pub fn tool_manifest() -> ToolManifest {
    ToolManifest {
        tools: vec![
            ToolSpec {
                name: FORK_TASK_TOOL_NAME.to_owned(),
                description: "Create an active child task from the calling task and give it an initial prompt."
                    .to_owned(),
                parameters: vec![string_parameter(
                    "prompt",
                    "Initial prompt for the child task.",
                    true,
                )],
            },
            ToolSpec {
                name: READ_TASK_TOOL_NAME.to_owned(),
                description:
                    "Read task state and a page of history. Omit task_id to read the calling task."
                        .to_owned(),
                parameters: vec![
                    string_parameter(
                        "task_id",
                        "Task to read; omit it to read the calling task.",
                        false,
                    ),
                    integer_parameter(
                        "after_node_id",
                        "Return history nodes after this node ID.",
                        false,
                    ),
                    integer_parameter(
                        "limit",
                        "Maximum history nodes to return, from 1 through 100.",
                        false,
                    ),
                ],
            },
            ToolSpec {
                name: SEND_MESSAGE_TO_TASK_TOOL_NAME.to_owned(),
                description:
                    "Send a message to an active task and report whether it was committed or queued."
                        .to_owned(),
                parameters: vec![
                    string_parameter("task_id", "Task that should receive the message.", true),
                    string_parameter("message", "Message to send to the task.", true),
                ],
            },
            ToolSpec {
                name: ARCHIVE_TASK_TOOL_NAME.to_owned(),
                description: "Archive another active task.".to_owned(),
                parameters: vec![string_parameter("task_id", "Task to archive.", true)],
            },
        ],
    }
}

fn string_parameter(name: &str, description: &str, required: bool) -> ToolParameter {
    ToolParameter {
        name: name.to_owned(),
        parameter_type: ToolParameterType::String,
        description: description.to_owned(),
        required,
    }
}

fn integer_parameter(name: &str, description: &str, required: bool) -> ToolParameter {
    ToolParameter {
        name: name.to_owned(),
        parameter_type: ToolParameterType::Integer,
        description: description.to_owned(),
        required,
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum HarnessInvocation {
    ForkTask(ForkTaskInvocation),
    ReadTask(ReadTaskInvocation),
    SendMessageToTask(SendMessageToTaskInvocation),
    ArchiveTask(ArchiveTaskInvocation),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ForkTaskInvocation {
    pub prompt: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ReadTaskInvocation {
    pub task_id: Option<TaskId>,
    pub after_node_id: Option<HistoryNodeId>,
    pub limit: Option<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SendMessageToTaskInvocation {
    pub task_id: TaskId,
    pub message: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ArchiveTaskInvocation {
    pub task_id: TaskId,
}

pub fn parse_invocation(request: &ToolExecutionRequest) -> Result<HarnessInvocation, HarnessError> {
    match request.tool_name.0.as_str() {
        FORK_TASK_TOOL_NAME => parse_fork_task(&request.arguments),
        READ_TASK_TOOL_NAME => parse_read_task(&request.arguments),
        SEND_MESSAGE_TO_TASK_TOOL_NAME => parse_send_message_to_task(&request.arguments),
        ARCHIVE_TASK_TOOL_NAME => parse_archive_task(&request.task_id, &request.arguments),
        unknown => Err(HarnessError::new(
            HarnessErrorCode::UnknownTool,
            format!("unknown tool '{unknown}'"),
        )),
    }
}

fn parse_fork_task(arguments: &[ToolCallArgument]) -> Result<HarnessInvocation, HarnessError> {
    let arguments = Arguments::new(arguments, &["prompt"])?;
    let prompt = arguments.required_nonempty_string("prompt")?;
    Ok(HarnessInvocation::ForkTask(ForkTaskInvocation { prompt }))
}

fn parse_read_task(arguments: &[ToolCallArgument]) -> Result<HarnessInvocation, HarnessError> {
    let arguments = Arguments::new(arguments, &["task_id", "after_node_id", "limit"])?;
    let task_id = arguments.optional_nonempty_string("task_id")?.map(TaskId);
    let after_node_id = arguments
        .optional_integer("after_node_id")?
        .map(HistoryNodeId);
    let limit = match arguments.optional_integer("limit")? {
        Some(limit) if (1..=MAX_READ_LIMIT).contains(&limit) => Some(limit as u8),
        Some(_) => {
            return Err(HarnessError::invalid_arguments(
                "argument 'limit' must be between 1 and 100",
            ));
        }
        None => None,
    };

    Ok(HarnessInvocation::ReadTask(ReadTaskInvocation {
        task_id,
        after_node_id,
        limit,
    }))
}

fn parse_send_message_to_task(
    arguments: &[ToolCallArgument],
) -> Result<HarnessInvocation, HarnessError> {
    let arguments = Arguments::new(arguments, &["task_id", "message"])?;
    Ok(HarnessInvocation::SendMessageToTask(
        SendMessageToTaskInvocation {
            task_id: TaskId(arguments.required_nonempty_string("task_id")?),
            message: arguments.required_nonempty_string("message")?,
        },
    ))
}

fn parse_archive_task(
    calling_task_id: &TaskId,
    arguments: &[ToolCallArgument],
) -> Result<HarnessInvocation, HarnessError> {
    let arguments = Arguments::new(arguments, &["task_id"])?;
    let task_id = TaskId(arguments.required_nonempty_string("task_id")?);
    if task_id == *calling_task_id {
        return Err(HarnessError::new(
            HarnessErrorCode::CannotArchiveCurrentTask,
            "cannot archive the calling task",
        ));
    }
    Ok(HarnessInvocation::ArchiveTask(ArchiveTaskInvocation {
        task_id,
    }))
}

struct Arguments<'a> {
    values: BTreeMap<&'a str, &'a ToolArgumentValue>,
}

impl<'a> Arguments<'a> {
    fn new(
        arguments: &'a [ToolCallArgument],
        allowed: &[&str],
    ) -> Result<Arguments<'a>, HarnessError> {
        let mut values = BTreeMap::new();
        for argument in arguments {
            let name = argument.name.0.as_str();
            if !allowed.contains(&name) {
                return Err(HarnessError::invalid_arguments(format!(
                    "unexpected argument '{name}'"
                )));
            }
            if values.insert(name, &argument.value).is_some() {
                return Err(HarnessError::invalid_arguments(format!(
                    "duplicate argument '{name}'"
                )));
            }
        }
        Ok(Arguments { values })
    }

    fn required_nonempty_string(&self, name: &str) -> Result<String, HarnessError> {
        self.optional_nonempty_string(name)?.ok_or_else(|| {
            HarnessError::invalid_arguments(format!("missing required argument '{name}'"))
        })
    }

    fn optional_nonempty_string(&self, name: &str) -> Result<Option<String>, HarnessError> {
        let Some(value) = self.values.get(name) else {
            return Ok(None);
        };
        let ToolArgumentValue::String(value) = value else {
            return Err(HarnessError::invalid_arguments(format!(
                "argument '{name}' must be a string"
            )));
        };
        if value.trim().is_empty() {
            return Err(HarnessError::invalid_arguments(format!(
                "argument '{name}' must not be empty"
            )));
        }
        Ok(Some(value.clone()))
    }

    fn optional_integer(&self, name: &str) -> Result<Option<i64>, HarnessError> {
        let Some(value) = self.values.get(name) else {
            return Ok(None);
        };
        let ToolArgumentValue::Integer(value) = value else {
            return Err(HarnessError::invalid_arguments(format!(
                "argument '{name}' must be an integer"
            )));
        };
        Ok(Some(*value))
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum HarnessSuccess {
    ForkTask(ForkTaskSuccess),
    ReadTask(ReadTaskSuccess),
    SendMessageToTask(SendMessageToTaskSuccess),
    ArchiveTask(ArchiveTaskSuccess),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ForkTaskSuccess {
    pub task_id: TaskId,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ReadTaskSuccess {
    pub task_id: TaskId,
    pub status: TaskProjectionStatus,
    pub state_version: u64,
    pub cursor_node_id: HistoryNodeId,
    pub parent_task_id: Option<TaskId>,
    pub queued_message_count: u64,
    pub history: HistoryPage,
}

#[derive(Clone, Debug, PartialEq)]
pub struct HistoryPage {
    pub nodes: Vec<HistoryNodeProjection>,
    pub next_after_node_id: Option<HistoryNodeId>,
    pub has_more: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MessageDisposition {
    Committed { node_id: HistoryNodeId },
    Queued,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SendMessageToTaskSuccess {
    pub task_id: TaskId,
    pub disposition: MessageDisposition,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ArchiveTaskSuccess {
    pub task_id: TaskId,
}

impl HarnessSuccess {
    pub fn to_stable_json(&self) -> String {
        success_json(self).to_string()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HarnessErrorCode {
    InvalidArguments,
    UnknownTool,
    TaskNotFound,
    TaskArchived,
    StaleToolCall,
    HistoryCursorNotOnTask,
    CannotArchiveCurrentTask,
    OperationCancelled,
    RouterUnavailable,
    RuntimeStartFailed,
    StorageError,
    ExecutorPanicked,
}

impl HarnessErrorCode {
    pub const fn as_str(self) -> &'static str {
        match self {
            HarnessErrorCode::InvalidArguments => "invalid_arguments",
            HarnessErrorCode::UnknownTool => "unknown_tool",
            HarnessErrorCode::TaskNotFound => "task_not_found",
            HarnessErrorCode::TaskArchived => "task_archived",
            HarnessErrorCode::StaleToolCall => "stale_tool_call",
            HarnessErrorCode::HistoryCursorNotOnTask => "history_cursor_not_on_task",
            HarnessErrorCode::CannotArchiveCurrentTask => "cannot_archive_current_task",
            HarnessErrorCode::OperationCancelled => "operation_cancelled",
            HarnessErrorCode::RouterUnavailable => "router_unavailable",
            HarnessErrorCode::RuntimeStartFailed => "runtime_start_failed",
            HarnessErrorCode::StorageError => "storage_error",
            HarnessErrorCode::ExecutorPanicked => "executor_panicked",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum HarnessError {
    General {
        code: HarnessErrorCode,
        message: String,
    },
    RuntimeStartFailedAfterChildCreated {
        task_id: TaskId,
        message: String,
    },
}

impl HarnessError {
    pub fn new(code: HarnessErrorCode, message: impl Into<String>) -> Self {
        Self::General {
            code,
            message: message.into(),
        }
    }

    pub fn runtime_start_failed_after_child_created(
        task_id: TaskId,
        message: impl Into<String>,
    ) -> Self {
        Self::RuntimeStartFailedAfterChildCreated {
            task_id,
            message: message.into(),
        }
    }

    pub fn invalid_arguments(message: impl Into<String>) -> Self {
        Self::new(HarnessErrorCode::InvalidArguments, message)
    }

    pub const fn code(&self) -> HarnessErrorCode {
        match self {
            HarnessError::General { code, .. } => *code,
            HarnessError::RuntimeStartFailedAfterChildCreated { .. } => {
                HarnessErrorCode::RuntimeStartFailed
            }
        }
    }

    pub fn message(&self) -> &str {
        match self {
            HarnessError::General { message, .. }
            | HarnessError::RuntimeStartFailedAfterChildCreated { message, .. } => message,
        }
    }

    pub fn created_child_task_id(&self) -> Option<&TaskId> {
        match self {
            HarnessError::General { .. } => None,
            HarnessError::RuntimeStartFailedAfterChildCreated { task_id, .. } => Some(task_id),
        }
    }

    pub fn to_stable_json(&self) -> String {
        error_json(self).to_string()
    }
}

impl fmt::Display for HarnessError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}: {}", self.code().as_str(), self.message())
    }
}

impl Error for HarnessError {}

pub fn encode_tool_execution_result(
    request: &ToolExecutionRequest,
    outcome: Result<HarnessSuccess, HarnessError>,
) -> ToolExecutionResult {
    let (output_text, is_error) = match outcome {
        Ok(success) => (success.to_stable_json(), false),
        Err(error) => (error.to_stable_json(), true),
    };
    ToolExecutionResult {
        task_id: request.task_id.clone(),
        tool_execution_run_id: request.tool_execution_run_id.clone(),
        function_call_node_id: request.function_call_node_id,
        function_call_id: request.function_call_id.clone(),
        tool_name: request.tool_name.clone(),
        output_text,
        is_error,
    }
}

#[derive(Clone)]
pub struct HarnessToolExecutor {
    db: DbPool,
}

impl HarnessToolExecutor {
    pub fn new(db: DbPool) -> Self {
        Self { db }
    }
}

impl ToolExecutionSpawner for HarnessToolExecutor {
    fn spawn_tool_execution(
        &self,
        request: ToolExecutionRequest,
        router_tx: RouterIngressWeakSender,
    ) -> Result<JoinHandle<()>, ToolExecutionSpawnError> {
        let db = self.db.clone();
        let execution_request = request.clone();
        let execution_router_tx = router_tx.clone();
        spawn_supervised_execution(request, router_tx, async move {
            execute_request(db, execution_request, execution_router_tx).await
        })
    }
}

fn spawn_supervised_execution<F>(
    request: ToolExecutionRequest,
    router_tx: RouterIngressWeakSender,
    execution: F,
) -> Result<JoinHandle<()>, ToolExecutionSpawnError>
where
    F: Future<Output = Result<HarnessSuccess, HarnessError>> + Send + 'static,
{
    let runtime = tokio::runtime::Handle::try_current()
        .map_err(|_| ToolExecutionSpawnError::TokioSpawnFailed)?;
    Ok(runtime.spawn(async move {
        let outcome = match tokio::spawn(execution).await {
            Ok(outcome) => outcome,
            Err(error) if error.is_panic() => Err(HarnessError::new(
                HarnessErrorCode::ExecutorPanicked,
                "tool executor panicked",
            )),
            Err(_) => Err(HarnessError::new(
                HarnessErrorCode::OperationCancelled,
                "tool execution was cancelled",
            )),
        };
        let result = encode_tool_execution_result(&request, outcome);
        if let Some(router_tx) = router_tx.upgrade() {
            let _ = router_tx.send(RouterIngressMessage::Tool(result));
        }
    }))
}

async fn execute_request(
    db: DbPool,
    request: ToolExecutionRequest,
    router_tx: RouterIngressWeakSender,
) -> Result<HarnessSuccess, HarnessError> {
    match parse_invocation(&request)? {
        HarnessInvocation::ForkTask(invocation) => {
            execute_fork_task(request, invocation, router_tx).await
        }
        HarnessInvocation::ReadTask(invocation) => {
            execute_read_task(db, request.task_id, invocation).await
        }
        HarnessInvocation::SendMessageToTask(invocation) => {
            execute_send_message_to_task(invocation, router_tx).await
        }
        HarnessInvocation::ArchiveTask(invocation) => {
            execute_archive_task(invocation, router_tx).await
        }
    }
}

async fn execute_fork_task(
    request: ToolExecutionRequest,
    invocation: ForkTaskInvocation,
    router_tx: RouterIngressWeakSender,
) -> Result<HarnessSuccess, HarnessError> {
    let (responder, response) = fork_task_response_channel();
    send_router_command(
        &router_tx,
        RouterCommand::CreateChildTaskAndRuntime {
            parent_task_id: request.task_id,
            function_call_node_id: request.function_call_node_id,
            function_call_id: request.function_call_id,
            tool_name: request.tool_name,
            child_prompt: invocation.prompt,
            responder,
        },
    )?;
    match response.await {
        Ok(Ok(ForkTaskOutcome::RuntimeStarted { task_id })) => {
            Ok(HarnessSuccess::ForkTask(ForkTaskSuccess { task_id }))
        }
        Ok(Err(error)) => Err(map_fork_task_error(error)),
        Err(_) => Err(HarnessError::new(
            HarnessErrorCode::OperationCancelled,
            "fork task response was cancelled",
        )),
    }
}

async fn execute_read_task(
    db: DbPool,
    calling_task_id: TaskId,
    invocation: ReadTaskInvocation,
) -> Result<HarnessSuccess, HarnessError> {
    let task_id = invocation.task_id.unwrap_or(calling_task_id);
    let limit = u32::from(invocation.limit.unwrap_or(MAX_READ_LIMIT as u8));
    let read = tokio::task::spawn_blocking(move || {
        read_task(
            &db,
            ReadTaskInput {
                task_id,
                after_node_id: invocation.after_node_id,
                limit,
            },
        )
    })
    .await
    .map_err(map_join_error)?
    .map_err(map_read_error)?;
    Ok(HarnessSuccess::ReadTask(task_read_success(read)))
}

async fn execute_send_message_to_task(
    invocation: SendMessageToTaskInvocation,
    router_tx: RouterIngressWeakSender,
) -> Result<HarnessSuccess, HarnessError> {
    let task_id = invocation.task_id;
    let (responder, response) = send_user_input_response_channel();
    send_router_command(
        &router_tx,
        RouterCommand::SendUserInput {
            task_id: task_id.clone(),
            message_text: invocation.message,
            responder,
        },
    )?;
    match response.await {
        Ok(Ok(SendUserInputOutcome::Committed { node_id })) => Ok(
            HarnessSuccess::SendMessageToTask(SendMessageToTaskSuccess {
                task_id,
                disposition: MessageDisposition::Committed { node_id },
            }),
        ),
        Ok(Ok(SendUserInputOutcome::Queued)) => Ok(HarnessSuccess::SendMessageToTask(
            SendMessageToTaskSuccess {
                task_id,
                disposition: MessageDisposition::Queued,
            },
        )),
        Ok(Err(error)) => Err(map_task_command_error(error)),
        Err(_) => Err(HarnessError::new(
            HarnessErrorCode::OperationCancelled,
            "send message response was cancelled",
        )),
    }
}

async fn execute_archive_task(
    invocation: ArchiveTaskInvocation,
    router_tx: RouterIngressWeakSender,
) -> Result<HarnessSuccess, HarnessError> {
    let task_id = invocation.task_id;
    let (responder, response) = archive_task_response_channel();
    send_router_command(
        &router_tx,
        RouterCommand::ArchiveTask {
            task_id: task_id.clone(),
            responder,
        },
    )?;
    match response.await {
        Ok(Ok(ArchiveTaskOutcome::Archived)) => {
            Ok(HarnessSuccess::ArchiveTask(ArchiveTaskSuccess { task_id }))
        }
        Ok(Err(error)) => Err(map_task_command_error(error)),
        Err(_) => Err(HarnessError::new(
            HarnessErrorCode::OperationCancelled,
            "archive task response was cancelled",
        )),
    }
}

fn send_router_command(
    router_tx: &RouterIngressWeakSender,
    command: RouterCommand,
) -> Result<(), HarnessError> {
    let router_tx = router_tx.upgrade().ok_or_else(|| {
        HarnessError::new(HarnessErrorCode::RouterUnavailable, "router is unavailable")
    })?;
    router_tx
        .send(RouterIngressMessage::Command(RouterCommandEnvelope {
            client_id: None,
            client_command_id: None,
            command,
        }))
        .map_err(|_| {
            HarnessError::new(HarnessErrorCode::RouterUnavailable, "router is unavailable")
        })
}

fn map_fork_task_error(error: ForkTaskError) -> HarnessError {
    match error {
        ForkTaskError::InvalidCommand => HarnessError::new(
            HarnessErrorCode::InvalidArguments,
            "fork task command was invalid",
        ),
        ForkTaskError::ParentTaskMissing => {
            HarnessError::new(HarnessErrorCode::TaskNotFound, "parent task was not found")
        }
        ForkTaskError::ParentTaskArchived => {
            HarnessError::new(HarnessErrorCode::TaskArchived, "parent task is archived")
        }
        ForkTaskError::StaleToolCall => {
            HarnessError::new(HarnessErrorCode::StaleToolCall, "fork tool call is stale")
        }
        ForkTaskError::PersistenceFailed => HarnessError::new(
            HarnessErrorCode::StorageError,
            "fork task persistence failed",
        ),
        ForkTaskError::RuntimeUnavailable => HarnessError::new(
            HarnessErrorCode::RouterUnavailable,
            "child task runtime is unavailable",
        ),
        ForkTaskError::RuntimeStartFailedAfterChildCreated { task_id } => {
            HarnessError::runtime_start_failed_after_child_created(
                task_id,
                "child task was created but its runtime did not start",
            )
        }
    }
}

fn map_task_command_error(error: TaskCommandError) -> HarnessError {
    match error {
        TaskCommandError::TaskMissing => {
            HarnessError::new(HarnessErrorCode::TaskNotFound, "task was not found")
        }
        TaskCommandError::TaskArchived => {
            HarnessError::new(HarnessErrorCode::TaskArchived, "task is archived")
        }
        TaskCommandError::PersistenceFailed => {
            HarnessError::new(HarnessErrorCode::StorageError, "task persistence failed")
        }
        TaskCommandError::InvalidCommand => HarnessError::new(
            HarnessErrorCode::InvalidArguments,
            "task command was invalid",
        ),
        TaskCommandError::RuntimeUnavailable => HarnessError::new(
            HarnessErrorCode::RouterUnavailable,
            "task runtime is unavailable",
        ),
    }
}

fn map_read_error(error: DbError) -> HarnessError {
    match error {
        DbError::NotFound => {
            HarnessError::new(HarnessErrorCode::TaskNotFound, "task was not found")
        }
        DbError::HistoryCursorNotOnTask => HarnessError::new(
            HarnessErrorCode::HistoryCursorNotOnTask,
            "history cursor is not on the task path",
        ),
        DbError::TaskNotActive => {
            HarnessError::new(HarnessErrorCode::TaskArchived, "task is archived")
        }
        DbError::StaleFunctionCall
        | DbError::Constraint(_)
        | DbError::Storage(_)
        | DbError::SchemaMismatch { .. } => {
            HarnessError::new(HarnessErrorCode::StorageError, error.to_string())
        }
    }
}

fn map_join_error(error: tokio::task::JoinError) -> HarnessError {
    if error.is_panic() {
        HarnessError::new(HarnessErrorCode::ExecutorPanicked, "tool executor panicked")
    } else {
        HarnessError::new(
            HarnessErrorCode::OperationCancelled,
            "tool execution was cancelled",
        )
    }
}

fn task_read_success(read: TaskRead) -> ReadTaskSuccess {
    let history_nodes = read
        .history_nodes
        .into_iter()
        .map(history_node_projection)
        .collect::<Vec<_>>();
    let next_after_node_id = read
        .has_more
        .then(|| history_nodes.last().map(|node| node.node_id))
        .flatten();
    ReadTaskSuccess {
        task_id: read.task_id,
        status: match read.task_status {
            TaskStatusRow::Active => TaskProjectionStatus::Active,
            TaskStatusRow::Archived => TaskProjectionStatus::Archived,
        },
        state_version: read.state_version,
        cursor_node_id: read.cursor_node_id,
        parent_task_id: read.parent_task_id,
        queued_message_count: read.queued_input_count,
        history: HistoryPage {
            nodes: history_nodes,
            next_after_node_id,
            has_more: read.has_more,
        },
    }
}

fn history_node_projection(node: HistoryNode) -> HistoryNodeProjection {
    match node {
        HistoryNode::Message {
            node_id,
            parent_node_id,
            created_at,
            message_role,
            message_text,
        } => HistoryNodeProjection {
            node_id,
            parent_node_id,
            created_at,
            body: HistoryNodeProjectionBody::Message {
                role: message_role,
                text: message_text,
            },
        },
        HistoryNode::Reasoning {
            node_id,
            parent_node_id,
            created_at,
            reasoning_text,
        } => HistoryNodeProjection {
            node_id,
            parent_node_id,
            created_at,
            body: HistoryNodeProjectionBody::Reasoning {
                text: reasoning_text,
            },
        },
        HistoryNode::FunctionCall {
            node_id,
            parent_node_id,
            created_at,
            function_call_id,
            tool_name,
            arguments,
        } => HistoryNodeProjection {
            node_id,
            parent_node_id,
            created_at,
            body: HistoryNodeProjectionBody::FunctionCall {
                function_call_id,
                tool_name,
                arguments,
            },
        },
        HistoryNode::FunctionOutput {
            node_id,
            parent_node_id,
            created_at,
            function_call_node_id,
            function_call_id,
            tool_name,
            output_text,
            is_error,
        } => HistoryNodeProjection {
            node_id,
            parent_node_id,
            created_at,
            body: HistoryNodeProjectionBody::FunctionOutput {
                function_call_node_id,
                function_call_id,
                tool_name,
                output_text,
                is_error,
            },
        },
    }
}

fn success_json(success: &HarnessSuccess) -> Value {
    match success {
        HarnessSuccess::ForkTask(success) => object([
            ("task_id", task_id_json(&success.task_id)),
            ("status", Value::String("active".to_owned())),
        ]),
        HarnessSuccess::ReadTask(success) => object([
            ("task_id", task_id_json(&success.task_id)),
            ("status", task_status_json(&success.status)),
            ("state_version", Value::from(success.state_version)),
            ("cursor_node_id", Value::from(success.cursor_node_id.0)),
            (
                "parent_task_id",
                optional_task_id_json(success.parent_task_id.as_ref()),
            ),
            (
                "queued_message_count",
                Value::from(success.queued_message_count),
            ),
            ("history", history_page_json(&success.history)),
        ]),
        HarnessSuccess::SendMessageToTask(success) => {
            let mut fields = BTreeMap::new();
            fields.insert("task_id".to_owned(), task_id_json(&success.task_id));
            match success.disposition {
                MessageDisposition::Committed { node_id } => {
                    fields.insert(
                        "disposition".to_owned(),
                        Value::String("committed".to_owned()),
                    );
                    fields.insert("node_id".to_owned(), Value::from(node_id.0));
                }
                MessageDisposition::Queued => {
                    fields.insert("disposition".to_owned(), Value::String("queued".to_owned()));
                }
            }
            Value::Object(fields.into_iter().collect())
        }
        HarnessSuccess::ArchiveTask(success) => object([
            ("task_id", task_id_json(&success.task_id)),
            ("status", Value::String("archived".to_owned())),
        ]),
    }
}

fn error_json(error: &HarnessError) -> Value {
    let mut fields = BTreeMap::from([
        (
            "code".to_owned(),
            Value::String(error.code().as_str().to_owned()),
        ),
        (
            "message".to_owned(),
            Value::String(error.message().to_owned()),
        ),
    ]);
    if let Some(task_id) = error.created_child_task_id() {
        fields.insert("task_created".to_owned(), Value::Bool(true));
        fields.insert("task_id".to_owned(), task_id_json(task_id));
    }
    object([("error", Value::Object(fields.into_iter().collect()))])
}

fn history_page_json(page: &HistoryPage) -> Value {
    object([
        (
            "nodes",
            Value::Array(page.nodes.iter().map(history_node_json).collect()),
        ),
        (
            "next_after_node_id",
            page.next_after_node_id
                .map_or(Value::Null, |node_id| Value::from(node_id.0)),
        ),
        ("has_more", Value::Bool(page.has_more)),
    ])
}

fn history_node_json(node: &HistoryNodeProjection) -> Value {
    let mut fields = BTreeMap::new();
    fields.insert("node_id".to_owned(), Value::from(node.node_id.0));
    fields.insert(
        "parent_node_id".to_owned(),
        node.parent_node_id
            .map_or(Value::Null, |node_id| Value::from(node_id.0)),
    );
    fields.insert("created_at".to_owned(), Value::from(node.created_at.0));

    match &node.body {
        HistoryNodeProjectionBody::Message { role, text } => {
            fields.insert("kind".to_owned(), Value::String("message".to_owned()));
            fields.insert("role".to_owned(), message_role_json(role));
            fields.insert("text".to_owned(), Value::String(text.clone()));
        }
        HistoryNodeProjectionBody::Reasoning { text } => {
            fields.insert("kind".to_owned(), Value::String("reasoning".to_owned()));
            fields.insert("text".to_owned(), Value::String(text.clone()));
        }
        HistoryNodeProjectionBody::FunctionCall {
            function_call_id,
            tool_name,
            arguments,
        } => {
            fields.insert("kind".to_owned(), Value::String("function_call".to_owned()));
            fields.insert(
                "function_call_id".to_owned(),
                Value::String(function_call_id.0.clone()),
            );
            fields.insert("tool_name".to_owned(), Value::String(tool_name.0.clone()));
            fields.insert(
                "arguments".to_owned(),
                Value::Array(arguments.iter().map(tool_argument_json).collect()),
            );
        }
        HistoryNodeProjectionBody::FunctionOutput {
            function_call_node_id,
            function_call_id,
            tool_name,
            output_text,
            is_error,
        } => {
            fields.insert(
                "kind".to_owned(),
                Value::String("function_output".to_owned()),
            );
            fields.insert(
                "function_call_node_id".to_owned(),
                Value::from(function_call_node_id.0),
            );
            fields.insert(
                "function_call_id".to_owned(),
                Value::String(function_call_id.0.clone()),
            );
            fields.insert("tool_name".to_owned(), Value::String(tool_name.0.clone()));
            fields.insert("output_text".to_owned(), Value::String(output_text.clone()));
            fields.insert("is_error".to_owned(), Value::Bool(*is_error));
        }
    }

    Value::Object(fields.into_iter().collect())
}

fn tool_argument_json(argument: &ToolCallArgument) -> Value {
    object([
        ("name", Value::String(argument.name.0.clone())),
        ("value", tool_argument_value_json(&argument.value)),
    ])
}

fn tool_argument_value_json(value: &ToolArgumentValue) -> Value {
    match value {
        ToolArgumentValue::String(value) => Value::String(value.clone()),
        ToolArgumentValue::Integer(value) => Value::from(*value),
        ToolArgumentValue::Number(value) => {
            Number::from_f64(*value).map_or(Value::Null, Value::Number)
        }
        ToolArgumentValue::Boolean(value) => Value::Bool(*value),
    }
}

fn task_id_json(task_id: &TaskId) -> Value {
    Value::String(task_id.0.clone())
}

fn optional_task_id_json(task_id: Option<&TaskId>) -> Value {
    task_id.map_or(Value::Null, task_id_json)
}

fn task_status_json(status: &TaskProjectionStatus) -> Value {
    Value::String(
        match status {
            TaskProjectionStatus::Active => "active",
            TaskProjectionStatus::Archived => "archived",
        }
        .to_owned(),
    )
}

fn message_role_json(role: &MessageRole) -> Value {
    Value::String(
        match role {
            MessageRole::System => "system",
            MessageRole::Developer => "developer",
            MessageRole::User => "user",
            MessageRole::Assistant => "assistant",
            MessageRole::Tool => "tool",
        }
        .to_owned(),
    )
}

fn object<const N: usize>(entries: [(&str, Value); N]) -> Value {
    let fields = entries
        .into_iter()
        .map(|(key, value)| (key.to_owned(), value))
        .collect::<BTreeMap<_, _>>();
    Value::Object(fields.into_iter().collect())
}

#[cfg(test)]
mod tests {
    use selvedge_command_model::{RouterIngressMessage, ToolExecutionRunId};
    use selvedge_domain_model::{FunctionCallId, HistoryNodeId, TaskId, ToolName};

    use super::{HarnessSuccess, spawn_supervised_execution};
    use crate::ToolExecutionRequest;

    #[tokio::test]
    async fn panicking_execution_still_emits_one_correlated_terminal_result() {
        let request = ToolExecutionRequest {
            task_id: TaskId("task-1".to_owned()),
            tool_execution_run_id: ToolExecutionRunId("run-1".to_owned()),
            function_call_node_id: HistoryNodeId(7),
            function_call_id: FunctionCallId("call-1".to_owned()),
            tool_name: ToolName("read_task".to_owned()),
            arguments: Vec::new(),
        };
        let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
        let supervisor =
            spawn_supervised_execution(request.clone(), router_tx.downgrade(), async move {
                panic!("executor panic");
                #[allow(unreachable_code)]
                Ok::<HarnessSuccess, super::HarnessError>(unreachable!())
            })
            .expect("spawn supervisor");

        supervisor.await.expect("supervisor completes");
        let RouterIngressMessage::Tool(result) =
            router_rx.recv().await.expect("terminal tool result")
        else {
            panic!("unexpected router message");
        };
        assert_eq!(result.task_id, request.task_id);
        assert_eq!(result.tool_execution_run_id, request.tool_execution_run_id);
        assert_eq!(result.function_call_node_id, request.function_call_node_id);
        assert_eq!(result.function_call_id, request.function_call_id);
        assert_eq!(result.tool_name, request.tool_name);
        assert!(result.is_error);
        assert_eq!(
            result.output_text,
            r#"{"error":{"code":"executor_panicked","message":"tool executor panicked"}}"#
        );
        assert!(matches!(
            router_rx.try_recv(),
            Err(tokio::sync::mpsc::error::TryRecvError::Empty)
        ));
    }
}
