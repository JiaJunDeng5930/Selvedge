#![doc = include_str!("../README.md")]

mod mcp;

use std::collections::BTreeMap;
use std::future::Future;
use std::io;
use std::process::Stdio;
use std::time::Duration;
use std::{error::Error, fmt};

use rustix::io::Errno;
use rustix::process::{Pid, Signal, kill_process_group};
use selvedge_command_model::{
    ArchiveTaskOutcome, HistoryNodeProjection, HistoryNodeProjectionBody, RouterCommand,
    RouterCommandEnvelope, RouterIngressMessage, RouterIngressWeakSender, SendUserInputOutcome,
    TaskCommandError, TaskProjectionStatus, ToolExecutionBranch, ToolExecutionBranchTarget,
    ToolExecutionRequest, ToolExecutionResult, archive_task_response_channel,
    send_user_input_response_channel,
};
use selvedge_db::{
    DbError, DbPool, HistoryNode, ReadTaskInput, TaskRead, TaskStatusRow, ToolExecutionSource,
    read_task, read_tool_execution_source,
};
use selvedge_domain_model::{
    HistoryNodeId, JsonObject, MessageRole, TaskId, ToolManifest, ToolSpec,
};
use serde_json::{Number, Value};
use tokio::io::{AsyncRead, AsyncReadExt};
use tokio::process::Command;
use tokio::task::JoinHandle;
use uuid::Uuid;

use selvedge_router::{ToolExecutionSpawnError, ToolExecutionSpawner};

pub use mcp::{McpConnectionSet, McpStartupError, McpStartupOperation};

pub const FORK_TASK_TOOL_NAME: &str = "fork_task";
pub const READ_TASK_TOOL_NAME: &str = "read_task";
pub const SEND_MESSAGE_TO_TASK_TOOL_NAME: &str = "send_message_to_task";
pub const ARCHIVE_TASK_TOOL_NAME: &str = "archive_task";
pub const BASH_TOOL_NAME: &str = "bash";
pub const DEFAULT_BASH_TIMEOUT_MS: i64 = 30_000;
pub const MIN_BASH_TIMEOUT_MS: i64 = 100;
pub const MAX_BASH_TIMEOUT_MS: i64 = 120_000;
pub const BASH_OUTPUT_LIMIT_BYTES: usize = 64 * 1024;

const MAX_READ_LIMIT: i64 = 100;
const BASH_REAP_TIMEOUT: Duration = Duration::from_secs(5);

pub fn tool_manifest() -> ToolManifest {
    ToolManifest {
        tools: vec![
            ToolSpec {
                name: FORK_TASK_TOOL_NAME.to_owned(),
                description:
                    "Create parallel child task branches with optional aligned initial messages."
                        .to_owned(),
                input_schema: input_schema(
                    [
                        (
                            "child_count",
                            integer_property("Number of child task branches to create."),
                        ),
                        (
                            "messages",
                            string_array_property(
                                "Optional initial messages aligned by child branch number.",
                            ),
                        ),
                    ],
                    &["child_count"],
                ),
            },
            ToolSpec {
                name: READ_TASK_TOOL_NAME.to_owned(),
                description:
                    "Read task state and a page of history. Omit task_id to read the calling task."
                        .to_owned(),
                input_schema: input_schema(
                    [
                        (
                            "task_id",
                            string_property("Task to read; omit it to read the calling task."),
                        ),
                        (
                            "after_node_id",
                            integer_property(
                                "Return history nodes after this node ID.",
                            ),
                        ),
                        (
                            "limit",
                            integer_property(
                                "Maximum history nodes to return, from 1 through 100.",
                            ),
                        ),
                    ],
                    &[],
                ),
            },
            ToolSpec {
                name: SEND_MESSAGE_TO_TASK_TOOL_NAME.to_owned(),
                description:
                    "Send a message to an active task and report whether it was committed or queued."
                        .to_owned(),
                input_schema: input_schema(
                    [
                        (
                            "task_id",
                            string_property("Task that should receive the message."),
                        ),
                        ("message", string_property("Message to send to the task.")),
                    ],
                    &["message", "task_id"],
                ),
            },
            ToolSpec {
                name: ARCHIVE_TASK_TOOL_NAME.to_owned(),
                description: "Archive another active task.".to_owned(),
                input_schema: input_schema(
                    [("task_id", string_property("Task to archive."))],
                    &["task_id"],
                ),
            },
            ToolSpec {
                name: BASH_TOOL_NAME.to_owned(),
                description:
                    "Run a non-interactive Bash login command in the server process environment and working directory. Stdout and stderr are each capped at 65536 bytes."
                        .to_owned(),
                input_schema: input_schema(
                    [
                        ("command", string_property("Bash command to run.")),
                        (
                            "timeout_ms",
                            integer_property(
                                "Timeout in milliseconds; defaults to 30000, from 100 through 120000.",
                            ),
                        ),
                    ],
                    &["command"],
                ),
            },
        ],
    }
}

fn input_schema<const N: usize>(properties: [(&str, Value); N], required: &[&str]) -> JsonObject {
    JsonObject::from_iter([
        ("type".to_owned(), Value::String("object".to_owned())),
        (
            "properties".to_owned(),
            Value::Object(
                properties
                    .into_iter()
                    .map(|(name, schema)| (name.to_owned(), schema))
                    .collect(),
            ),
        ),
        (
            "required".to_owned(),
            Value::Array(
                required
                    .iter()
                    .map(|name| Value::String((*name).to_owned()))
                    .collect(),
            ),
        ),
        ("additionalProperties".to_owned(), Value::Bool(false)),
    ])
}

fn string_property(description: &str) -> Value {
    Value::Object(JsonObject::from_iter([
        ("type".to_owned(), Value::String("string".to_owned())),
        (
            "description".to_owned(),
            Value::String(description.to_owned()),
        ),
    ]))
}

fn integer_property(description: &str) -> Value {
    Value::Object(JsonObject::from_iter([
        ("type".to_owned(), Value::String("integer".to_owned())),
        (
            "description".to_owned(),
            Value::String(description.to_owned()),
        ),
    ]))
}

fn string_array_property(description: &str) -> Value {
    Value::Object(JsonObject::from_iter([
        ("type".to_owned(), Value::String("array".to_owned())),
        (
            "items".to_owned(),
            Value::Object(JsonObject::from_iter([(
                "type".to_owned(),
                Value::String("string".to_owned()),
            )])),
        ),
        (
            "description".to_owned(),
            Value::String(description.to_owned()),
        ),
    ]))
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum HarnessInvocation {
    ForkTask(ForkTaskInvocation),
    ReadTask(ReadTaskInvocation),
    SendMessageToTask(SendMessageToTaskInvocation),
    ArchiveTask(ArchiveTaskInvocation),
    Bash(BashInvocation),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ForkTaskInvocation {
    pub child_count: usize,
    pub messages: Option<Vec<String>>,
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

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BashInvocation {
    pub command: String,
    pub timeout_ms: u64,
}

pub fn parse_invocation(request: &ToolExecutionRequest) -> Result<HarnessInvocation, HarnessError> {
    match request.tool_name.0.as_str() {
        FORK_TASK_TOOL_NAME => parse_fork_task(&request.arguments),
        READ_TASK_TOOL_NAME => parse_read_task(&request.arguments),
        SEND_MESSAGE_TO_TASK_TOOL_NAME => parse_send_message_to_task(&request.arguments),
        ARCHIVE_TASK_TOOL_NAME => parse_archive_task(&request.task_id, &request.arguments),
        BASH_TOOL_NAME => parse_bash(&request.arguments),
        unknown => Err(HarnessError::new(
            HarnessErrorCode::UnknownTool,
            format!("unknown tool '{unknown}'"),
        )),
    }
}

fn parse_bash(arguments: &JsonObject) -> Result<HarnessInvocation, HarnessError> {
    let arguments = Arguments::new(arguments, &["command", "timeout_ms"])?;
    let command = arguments.required_nonempty_string("command")?;
    let timeout_ms = arguments
        .optional_integer("timeout_ms")?
        .unwrap_or(DEFAULT_BASH_TIMEOUT_MS);
    if !(MIN_BASH_TIMEOUT_MS..=MAX_BASH_TIMEOUT_MS).contains(&timeout_ms) {
        return Err(HarnessError::invalid_arguments(format!(
            "argument 'timeout_ms' must be between {MIN_BASH_TIMEOUT_MS} and {MAX_BASH_TIMEOUT_MS}"
        )));
    }
    Ok(HarnessInvocation::Bash(BashInvocation {
        command,
        timeout_ms: timeout_ms as u64,
    }))
}

fn parse_fork_task(arguments: &JsonObject) -> Result<HarnessInvocation, HarnessError> {
    let arguments = Arguments::new(arguments, &["child_count", "messages"])?;
    let child_count = arguments.required_integer("child_count")?;
    let child_count = usize::try_from(child_count)
        .ok()
        .filter(|child_count| *child_count > 0)
        .ok_or_else(|| {
            HarnessError::invalid_arguments("argument 'child_count' must be a positive integer")
        })?;
    let messages = arguments.optional_nonempty_string_array("messages")?;
    if messages
        .as_ref()
        .is_some_and(|messages| messages.len() != child_count)
    {
        return Err(HarnessError::invalid_arguments(
            "argument 'messages' length must equal 'child_count'",
        ));
    }
    Ok(HarnessInvocation::ForkTask(ForkTaskInvocation {
        child_count,
        messages,
    }))
}

fn parse_read_task(arguments: &JsonObject) -> Result<HarnessInvocation, HarnessError> {
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

fn parse_send_message_to_task(arguments: &JsonObject) -> Result<HarnessInvocation, HarnessError> {
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
    arguments: &JsonObject,
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
    values: &'a JsonObject,
}

impl<'a> Arguments<'a> {
    fn new(arguments: &'a JsonObject, allowed: &[&str]) -> Result<Arguments<'a>, HarnessError> {
        for name in arguments.keys() {
            if !allowed.contains(&name.as_str()) {
                return Err(HarnessError::invalid_arguments(format!(
                    "unexpected argument '{name}'"
                )));
            }
        }
        Ok(Arguments { values: arguments })
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
        let Value::String(value) = value else {
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
        let Value::Number(value) = value else {
            return Err(HarnessError::invalid_arguments(format!(
                "argument '{name}' must be an integer"
            )));
        };
        exact_json_integer(value).map(Some).ok_or_else(|| {
            HarnessError::invalid_arguments(format!("argument '{name}' must be an integer"))
        })
    }

    fn required_integer(&self, name: &str) -> Result<i64, HarnessError> {
        self.optional_integer(name)?.ok_or_else(|| {
            HarnessError::invalid_arguments(format!("missing required argument '{name}'"))
        })
    }

    fn optional_nonempty_string_array(
        &self,
        name: &str,
    ) -> Result<Option<Vec<String>>, HarnessError> {
        let Some(value) = self.values.get(name) else {
            return Ok(None);
        };
        let Value::Array(values) = value else {
            return Err(HarnessError::invalid_arguments(format!(
                "argument '{name}' must be an array of strings"
            )));
        };
        let mut strings = Vec::with_capacity(values.len());
        for value in values {
            let Value::String(value) = value else {
                return Err(HarnessError::invalid_arguments(format!(
                    "argument '{name}' must be an array of strings"
                )));
            };
            if value.trim().is_empty() {
                return Err(HarnessError::invalid_arguments(format!(
                    "argument '{name}' entries must not be empty"
                )));
            }
            strings.push(value.clone());
        }
        Ok(Some(strings))
    }
}

// JSON Schema integer semantics are mathematical, so decimal and exponent
// spellings must be evaluated from the exact token instead of through f64.
fn exact_json_integer(number: &Number) -> Option<i64> {
    let source = number.to_string();
    let (negative, unsigned) = match source.strip_prefix('-') {
        Some(unsigned) => (true, unsigned),
        None => (false, source.as_str()),
    };
    let exponent_start = unsigned.find(['e', 'E']);
    let (mantissa, exponent) = exponent_start.map_or((unsigned, None), |index| {
        (&unsigned[..index], Some(&unsigned[index + 1..]))
    });
    let (whole, fraction) = mantissa.split_once('.').unwrap_or((mantissa, ""));
    let mut digits = String::with_capacity(whole.len() + fraction.len());
    digits.push_str(whole);
    digits.push_str(fraction);

    if digits.bytes().all(|digit| digit == b'0') {
        return Some(0);
    }

    let exponent = match exponent {
        Some(exponent) => exponent.parse::<i64>().ok()?,
        None => 0,
    };
    let fraction_len = i64::try_from(fraction.len()).ok()?;
    let scale = exponent.checked_sub(fraction_len)?;
    let coefficient_end = if scale < 0 {
        let discarded_len = scale.checked_neg()?;
        if discarded_len > i64::try_from(digits.len()).ok()? {
            return None;
        }
        let coefficient_end = digits.len() - usize::try_from(discarded_len).ok()?;
        if digits.as_bytes()[coefficient_end..]
            .iter()
            .any(|digit| *digit != b'0')
        {
            return None;
        }
        coefficient_end
    } else {
        digits.len()
    };

    // A nonzero i64 cannot contain more than 19 decimal places. This bound
    // also keeps enormous JSON exponents from turning into long loops.
    if scale > 18 {
        return None;
    }
    let limit = if negative {
        (i64::MAX as u64) + 1
    } else {
        i64::MAX as u64
    };
    let mut magnitude = 0_u64;
    for digit in digits.as_bytes()[..coefficient_end].iter().copied() {
        let digit = u64::from(digit.checked_sub(b'0')?);
        if digit > 9 {
            return None;
        }
        magnitude = magnitude.checked_mul(10)?.checked_add(digit)?;
        if magnitude > limit {
            return None;
        }
    }
    for _ in 0..usize::try_from(scale).unwrap_or(0) {
        magnitude = magnitude.checked_mul(10)?;
        if magnitude > limit {
            return None;
        }
    }

    if negative && magnitude == (i64::MAX as u64) + 1 {
        Some(i64::MIN)
    } else {
        let magnitude = i64::try_from(magnitude).ok()?;
        Some(if negative { -magnitude } else { magnitude })
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum HarnessSuccess {
    ReadTask(ReadTaskSuccess),
    SendMessageToTask(SendMessageToTaskSuccess),
    ArchiveTask(ArchiveTaskSuccess),
    Bash(BashSuccess),
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

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BashSuccess {
    pub exit_code: Option<i32>,
    pub stdout: String,
    pub stderr: String,
    pub stdout_truncated: bool,
    pub stderr_truncated: bool,
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
    HistoryCursorNotOnTask,
    CannotArchiveCurrentTask,
    OperationCancelled,
    RouterUnavailable,
    StorageError,
    ExecutorPanicked,
    CommandSpawnFailed,
    CommandIoFailed,
    CommandWaitFailed,
    CommandTimedOut,
    McpRouteUnavailable,
    McpCallFailed,
    McpCallTimedOut,
    McpResultEncodingFailed,
}

impl HarnessErrorCode {
    pub const fn as_str(self) -> &'static str {
        match self {
            HarnessErrorCode::InvalidArguments => "invalid_arguments",
            HarnessErrorCode::UnknownTool => "unknown_tool",
            HarnessErrorCode::TaskNotFound => "task_not_found",
            HarnessErrorCode::TaskArchived => "task_archived",
            HarnessErrorCode::HistoryCursorNotOnTask => "history_cursor_not_on_task",
            HarnessErrorCode::CannotArchiveCurrentTask => "cannot_archive_current_task",
            HarnessErrorCode::OperationCancelled => "operation_cancelled",
            HarnessErrorCode::RouterUnavailable => "router_unavailable",
            HarnessErrorCode::StorageError => "storage_error",
            HarnessErrorCode::ExecutorPanicked => "executor_panicked",
            HarnessErrorCode::CommandSpawnFailed => "command_spawn_failed",
            HarnessErrorCode::CommandIoFailed => "command_io_failed",
            HarnessErrorCode::CommandWaitFailed => "command_wait_failed",
            HarnessErrorCode::CommandTimedOut => "command_timed_out",
            HarnessErrorCode::McpRouteUnavailable => "mcp_route_unavailable",
            HarnessErrorCode::McpCallFailed => "mcp_call_failed",
            HarnessErrorCode::McpCallTimedOut => "mcp_call_timed_out",
            HarnessErrorCode::McpResultEncodingFailed => "mcp_result_encoding_failed",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HarnessError {
    code: HarnessErrorCode,
    message: String,
}

impl HarnessError {
    pub fn new(code: HarnessErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }

    pub fn invalid_arguments(message: impl Into<String>) -> Self {
        Self::new(HarnessErrorCode::InvalidArguments, message)
    }

    pub const fn code(&self) -> HarnessErrorCode {
        self.code
    }

    pub fn message(&self) -> &str {
        &self.message
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
    let branch = match outcome {
        Ok(success) => calling_task_branch(success_json(&success), false),
        Err(error) => calling_task_branch(error_json(&error), true),
    };
    correlated_tool_execution_result(request, vec![branch])
}

fn correlated_tool_execution_result(
    request: &ToolExecutionRequest,
    branches: Vec<ToolExecutionBranch>,
) -> ToolExecutionResult {
    ToolExecutionResult {
        task_id: request.task_id.clone(),
        tool_execution_run_id: request.tool_execution_run_id.clone(),
        function_call_node_id: request.function_call_node_id,
        function_call_id: request.function_call_id.clone(),
        tool_name: request.tool_name.clone(),
        branches,
    }
}

fn calling_task_branch(output: Value, is_error: bool) -> ToolExecutionBranch {
    ToolExecutionBranch {
        target: ToolExecutionBranchTarget::CallingTask,
        output,
        is_error,
        messages: Vec::new(),
    }
}

#[derive(Clone)]
pub struct ToolExecutor {
    db: DbPool,
    mcp: McpConnectionSet,
}

impl ToolExecutor {
    pub fn new(db: DbPool, mcp: McpConnectionSet) -> Self {
        Self { db, mcp }
    }
}

impl ToolExecutionSpawner for ToolExecutor {
    fn spawn_tool_execution(
        &self,
        request: ToolExecutionRequest,
        router_tx: RouterIngressWeakSender,
    ) -> Result<JoinHandle<()>, ToolExecutionSpawnError> {
        let db = self.db.clone();
        let mcp = self.mcp.clone();
        let execution_request = request.clone();
        let execution_router_tx = router_tx.clone();
        spawn_supervised_execution(request, router_tx, async move {
            execute_routed_request(db, mcp, execution_request, execution_router_tx).await
        })
    }
}

fn spawn_supervised_execution<F>(
    request: ToolExecutionRequest,
    router_tx: RouterIngressWeakSender,
    execution: F,
) -> Result<JoinHandle<()>, ToolExecutionSpawnError>
where
    F: Future<Output = Result<Vec<ToolExecutionBranch>, HarnessError>> + Send + 'static,
{
    let runtime = tokio::runtime::Handle::try_current()
        .map_err(|_| ToolExecutionSpawnError::TokioSpawnFailed)?;
    Ok(runtime.spawn(async move {
        let branches = match tokio::spawn(execution).await {
            Ok(Ok(branches)) => branches,
            Ok(Err(error)) => vec![calling_task_branch(error_json(&error), true)],
            Err(error) if error.is_panic() => vec![calling_task_branch(
                error_json(&HarnessError::new(
                    HarnessErrorCode::ExecutorPanicked,
                    "tool executor panicked",
                )),
                true,
            )],
            Err(_) => vec![calling_task_branch(
                error_json(&HarnessError::new(
                    HarnessErrorCode::OperationCancelled,
                    "tool execution was cancelled",
                )),
                true,
            )],
        };
        let result = correlated_tool_execution_result(&request, branches);
        if let Some(router_tx) = router_tx.upgrade() {
            let _ = router_tx.send(RouterIngressMessage::Tool(result));
        }
    }))
}

async fn execute_routed_request(
    db: DbPool,
    mcp: McpConnectionSet,
    request: ToolExecutionRequest,
    router_tx: RouterIngressWeakSender,
) -> Result<Vec<ToolExecutionBranch>, HarnessError> {
    let route_db = db.clone();
    let tool_name = request.tool_name.clone();
    let source =
        tokio::task::spawn_blocking(move || read_tool_execution_source(&route_db, &tool_name))
            .await
            .map_err(map_join_error)?
            .map_err(map_tool_route_error)?;
    match source {
        ToolExecutionSource::Harness => execute_harness_request(db, request, router_tx).await,
        ToolExecutionSource::Mcp {
            server_id,
            remote_tool_name,
        } => {
            let (output, is_error) = mcp
                .call_tool(&server_id, remote_tool_name, request.arguments)
                .await?;
            Ok(vec![calling_task_branch(output, is_error)])
        }
    }
}

async fn execute_harness_request(
    db: DbPool,
    request: ToolExecutionRequest,
    router_tx: RouterIngressWeakSender,
) -> Result<Vec<ToolExecutionBranch>, HarnessError> {
    match parse_invocation(&request)? {
        HarnessInvocation::ForkTask(invocation) => Ok(execute_fork_task(invocation)),
        HarnessInvocation::ReadTask(invocation) => {
            execute_read_task(db, request.task_id, invocation)
                .await
                .map(single_success_branch)
        }
        HarnessInvocation::SendMessageToTask(invocation) => {
            execute_send_message_to_task(invocation, router_tx)
                .await
                .map(single_success_branch)
        }
        HarnessInvocation::ArchiveTask(invocation) => execute_archive_task(invocation, router_tx)
            .await
            .map(single_success_branch),
        HarnessInvocation::Bash(invocation) => {
            execute_bash(invocation).await.map(single_success_branch)
        }
    }
}

fn map_tool_route_error(error: DbError) -> HarnessError {
    match error {
        DbError::NotFound => HarnessError::new(
            HarnessErrorCode::UnknownTool,
            "tool does not have a durable execution route",
        ),
        error => HarnessError::new(
            HarnessErrorCode::StorageError,
            format!("failed to read tool execution route: {error}"),
        ),
    }
}

fn single_success_branch(success: HarnessSuccess) -> Vec<ToolExecutionBranch> {
    vec![calling_task_branch(success_json(&success), false)]
}

fn execute_fork_task(invocation: ForkTaskInvocation) -> Vec<ToolExecutionBranch> {
    let mut branches = Vec::with_capacity(invocation.child_count + 1);
    branches.push(calling_task_branch(Value::from(0), false));
    for index in 1..=invocation.child_count {
        let messages = invocation
            .messages
            .as_ref()
            .map_or_else(Vec::new, |messages| vec![messages[index - 1].clone()]);
        branches.push(ToolExecutionBranch {
            target: ToolExecutionBranchTarget::NewChildTask {
                task_id: TaskId(format!("child-{}", Uuid::new_v4())),
            },
            output: Value::from(index),
            is_error: false,
            messages,
        });
    }
    branches
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

async fn execute_bash(invocation: BashInvocation) -> Result<HarnessSuccess, HarnessError> {
    let mut command = Command::new("/bin/bash");
    command
        .arg("-lc")
        .arg(&invocation.command)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .process_group(0);
    let mut child = command.spawn().map_err(|error| {
        HarnessError::new(
            HarnessErrorCode::CommandSpawnFailed,
            format!("failed to spawn bash command: {error}"),
        )
    })?;
    let process_group_id = child
        .id()
        .and_then(|id| i32::try_from(id).ok())
        .and_then(Pid::from_raw)
        .ok_or_else(|| {
            HarnessError::new(
                HarnessErrorCode::CommandSpawnFailed,
                "spawned bash command did not have a process ID",
            )
        })?;
    let mut process_group = ProcessGroupGuard::new(process_group_id);
    let stdout = child.stdout.take().ok_or_else(|| {
        HarnessError::new(
            HarnessErrorCode::CommandIoFailed,
            "failed to capture bash stdout",
        )
    })?;
    let stderr = child.stderr.take().ok_or_else(|| {
        HarnessError::new(
            HarnessErrorCode::CommandIoFailed,
            "failed to capture bash stderr",
        )
    })?;

    // The readers keep draining after their prefixes fill so neither child pipe can block.
    let mut stdout_reader = tokio::spawn(capture_output(stdout));
    let mut stderr_reader = tokio::spawn(capture_output(stderr));
    let completed = tokio::time::timeout(Duration::from_millis(invocation.timeout_ms), async {
        let status = child.wait().await;
        let stdout = (&mut stdout_reader).await;
        let stderr = (&mut stderr_reader).await;
        (status, stdout, stderr)
    })
    .await;

    let (status, stdout, stderr) = match completed {
        Ok(completed) => {
            // A non-interactive command cannot leave a background session behind.
            process_group.terminate()?;
            process_group.disarm();
            completed
        }
        Err(_) => {
            let termination = process_group.terminate();
            let cleanup = tokio::time::timeout(BASH_REAP_TIMEOUT, async {
                let status = child.wait().await;
                let stdout = (&mut stdout_reader).await;
                let stderr = (&mut stderr_reader).await;
                (status, stdout, stderr)
            })
            .await;
            let (status, _, _) = match cleanup {
                Ok(cleanup) => cleanup,
                Err(_) => {
                    stdout_reader.abort();
                    stderr_reader.abort();
                    return Err(HarnessError::new(
                        HarnessErrorCode::CommandWaitFailed,
                        "timed-out bash command could not be reaped",
                    ));
                }
            };
            termination?;
            status.map_err(|error| {
                HarnessError::new(
                    HarnessErrorCode::CommandWaitFailed,
                    format!("failed to reap timed-out bash command: {error}"),
                )
            })?;
            process_group.disarm();
            return Err(HarnessError::new(
                HarnessErrorCode::CommandTimedOut,
                format!("bash command timed out after {} ms", invocation.timeout_ms),
            ));
        }
    };

    let status = status.map_err(|error| {
        HarnessError::new(
            HarnessErrorCode::CommandWaitFailed,
            format!("failed to wait for bash command: {error}"),
        )
    })?;
    let stdout = capture_result("stdout", stdout)?;
    let stderr = capture_result("stderr", stderr)?;
    Ok(HarnessSuccess::Bash(BashSuccess {
        exit_code: status.code(),
        stdout: stdout.text,
        stderr: stderr.text,
        stdout_truncated: stdout.truncated,
        stderr_truncated: stderr.truncated,
    }))
}

struct CapturedOutput {
    text: String,
    truncated: bool,
}

async fn capture_output(mut reader: impl AsyncRead + Unpin) -> Result<CapturedOutput, io::Error> {
    let mut bytes = Vec::with_capacity(BASH_OUTPUT_LIMIT_BYTES);
    let mut buffer = [0_u8; 8192];
    let mut truncated = false;
    loop {
        let read = reader.read(&mut buffer).await?;
        if read == 0 {
            break;
        }
        let remaining = BASH_OUTPUT_LIMIT_BYTES.saturating_sub(bytes.len());
        let retained = read.min(remaining);
        bytes.extend_from_slice(&buffer[..retained]);
        truncated |= retained < read;
    }
    Ok(CapturedOutput {
        text: String::from_utf8_lossy(&bytes).into_owned(),
        truncated,
    })
}

fn capture_result(
    stream: &str,
    result: Result<Result<CapturedOutput, io::Error>, tokio::task::JoinError>,
) -> Result<CapturedOutput, HarnessError> {
    result.map_err(map_join_error)?.map_err(|error| {
        HarnessError::new(
            HarnessErrorCode::CommandIoFailed,
            format!("failed to read bash {stream}: {error}"),
        )
    })
}

struct ProcessGroupGuard {
    process_group_id: Pid,
    armed: bool,
}

impl ProcessGroupGuard {
    fn new(process_group_id: Pid) -> Self {
        Self {
            process_group_id,
            armed: true,
        }
    }

    fn terminate(&self) -> Result<(), HarnessError> {
        match kill_process_group(self.process_group_id, Signal::KILL) {
            Ok(()) | Err(Errno::SRCH) => Ok(()),
            Err(error) => Err(HarnessError::new(
                HarnessErrorCode::CommandWaitFailed,
                format!("failed to terminate bash process group: {error}"),
            )),
        }
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for ProcessGroupGuard {
    fn drop(&mut self) {
        if self.armed {
            let _ = kill_process_group(self.process_group_id, Signal::KILL);
        }
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
            output,
            is_error,
        } => HistoryNodeProjection {
            node_id,
            parent_node_id,
            created_at,
            body: HistoryNodeProjectionBody::FunctionOutput {
                function_call_node_id,
                function_call_id,
                tool_name,
                output,
                is_error,
            },
        },
    }
}

fn success_json(success: &HarnessSuccess) -> Value {
    match success {
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
        HarnessSuccess::Bash(success) => object([
            (
                "exit_code",
                success.exit_code.map_or(Value::Null, Value::from),
            ),
            ("stdout", Value::String(success.stdout.clone())),
            ("stderr", Value::String(success.stderr.clone())),
            ("stdout_truncated", Value::Bool(success.stdout_truncated)),
            ("stderr_truncated", Value::Bool(success.stderr_truncated)),
        ]),
    }
}

fn error_json(error: &HarnessError) -> Value {
    let fields = BTreeMap::from([
        (
            "code".to_owned(),
            Value::String(error.code().as_str().to_owned()),
        ),
        (
            "message".to_owned(),
            Value::String(error.message().to_owned()),
        ),
    ]);
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
            fields.insert("arguments".to_owned(), Value::Object(arguments.clone()));
        }
        HistoryNodeProjectionBody::FunctionOutput {
            function_call_node_id,
            function_call_id,
            tool_name,
            output,
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
            fields.insert("output".to_owned(), output.clone());
            fields.insert("is_error".to_owned(), Value::Bool(*is_error));
        }
    }

    Value::Object(fields.into_iter().collect())
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
    use selvedge_command_model::{
        RouterIngressMessage, ToolExecutionBranch, ToolExecutionBranchTarget, ToolExecutionRunId,
    };
    use selvedge_domain_model::{FunctionCallId, HistoryNodeId, JsonObject, TaskId, ToolName};

    use super::spawn_supervised_execution;
    use crate::ToolExecutionRequest;

    #[tokio::test]
    async fn panicking_execution_still_emits_one_correlated_terminal_result() {
        let request = ToolExecutionRequest {
            task_id: TaskId("task-1".to_owned()),
            tool_execution_run_id: ToolExecutionRunId("run-1".to_owned()),
            function_call_node_id: HistoryNodeId(7),
            function_call_id: FunctionCallId("call-1".to_owned()),
            tool_name: ToolName("read_task".to_owned()),
            arguments: JsonObject::new(),
        };
        let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
        let supervisor =
            spawn_supervised_execution(request.clone(), router_tx.downgrade(), async move {
                panic!("executor panic");
                #[allow(unreachable_code)]
                Ok::<Vec<ToolExecutionBranch>, super::HarnessError>(unreachable!())
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
        assert_eq!(result.branches.len(), 1);
        let branch = &result.branches[0];
        assert_eq!(branch.target, ToolExecutionBranchTarget::CallingTask);
        assert!(branch.is_error);
        assert!(branch.messages.is_empty());
        assert_eq!(
            branch.output,
            serde_json::json!({
                "error": {
                    "code": "executor_panicked",
                    "message": "tool executor panicked"
                }
            })
        );
        assert!(matches!(
            router_rx.try_recv(),
            Err(tokio::sync::mpsc::error::TryRecvError::Empty)
        ));
    }
}
