#![doc = include_str!("../README.md")]

mod arguments;
mod command;
use arguments::*;
mod kernel;
mod mcp;
pub use command::CommandEnvironmentManager;

use std::collections::BTreeMap;
use std::future::Future;
use std::io;
use std::panic::AssertUnwindSafe;
use std::process::Stdio;
use std::time::Duration;
use std::{error::Error, fmt};

use futures_util::FutureExt;
use rustix::io::Errno;
use rustix::process::{Pid, Signal, kill_process_group};
use selvedge_command_model::{
    HistoryNodeProjection, HistoryNodeProjectionBody, RouterCommand, RouterIngressMessage,
    RouterIngressWeakSender, TaskCommandError, ToolExecutionBranch, ToolExecutionBranchTarget,
    ToolExecutionCompletion, ToolExecutionRequest, ToolExecutionResult,
};
use selvedge_config_model::HarnessConfig;
use selvedge_db::{
    DbError, DbPool, HistoryNode, ReadTaskInput, TaskRead, TaskToolSpec, ToolExecutionSource,
    ToolRecoveryPolicy, read_task, read_tool_execution_source,
};
use selvedge_domain_model::{HistoryNodeId, MessageRole, TaskId, TaskStatus, ToolSpec};
use serde_json::Value;
use tokio::io::{AsyncRead, AsyncReadExt};
use tokio::process::Command;
use tokio::task::JoinHandle;
use uuid::Uuid;

use selvedge_router::{ToolExecutionSpawnError, ToolExecutionSpawner};

pub use mcp::{McpConnectionSet, McpStartupError, McpStartupOperation};

// Keep the finite identifier set, exported wire names and enumeration in one declaration.
macro_rules! builtin_tools {
    ($($variant:ident => $constant:ident = $name:literal),+ $(,)?) => {
        $(pub const $constant: &str = $name;)+
        #[derive(Clone, Copy)]
        enum BuiltinTool { $($variant),+ }
        impl BuiltinTool {
            const ALL: &[Self] = &[$(Self::$variant),+];
            const fn name(self) -> &'static str {
                match self { $(Self::$variant => $constant),+ }
            }
        }
    };
}

builtin_tools! {
    ForkTask => FORK_TASK_TOOL_NAME = "fork_task",
    ReadTask => READ_TASK_TOOL_NAME = "read_task",
    SendMessageToTask => SEND_MESSAGE_TO_TASK_TOOL_NAME = "send_message_to_task",
    ArchiveTask => ARCHIVE_TASK_TOOL_NAME = "archive_task",
    Bash => BASH_TOOL_NAME = "bash",
    ExecCmd => EXEC_CMD_TOOL_NAME = "exec_cmd",
}

pub const DEFAULT_BASH_TIMEOUT_MS: i64 = 30_000;
pub const MIN_BASH_TIMEOUT_MS: i64 = 100;
pub const MAX_BASH_TIMEOUT_MS: i64 = 120_000;
pub const BASH_OUTPUT_LIMIT_BYTES: usize = 64 * 1024;

const BASH_REAP_TIMEOUT: Duration = Duration::from_secs(5);

pub fn harness_tool_catalog(config: &HarnessConfig) -> Vec<TaskToolSpec> {
    BuiltinTool::ALL
        .iter()
        .map(|tool| tool.registration(config))
        .collect()
}

impl BuiltinTool {
    fn registration(self, config: &HarnessConfig) -> TaskToolSpec {
        let (description, input_schema) = match self {
            Self::ForkTask => (format!("Create up to {} parallel child task branches with optional aligned initial messages.", config.max_children_per_fork), ForkTaskInvocation::schema(config)),
            Self::ReadTask => ("Read task state and a page of history. Omit task_id to read the calling task.".to_owned(), ReadTaskInvocation::schema(config)),
            Self::SendMessageToTask => ("Send a message to an active task and report whether it was committed or queued.".to_owned(), SendMessageToTaskInvocation::schema(config)),
            Self::ArchiveTask => ("Archive another active task.".to_owned(), ArchiveTaskInvocation::schema(config)),
            Self::ExecCmd => ("Execute JavaScript in the task's persistent command environment. Use kernel.describe() to discover task operations and host tools; modules.load() and modules.source() inspect extensions.".to_owned(), ExecCmdArguments::schema(config)),
            Self::Bash => ("Run a non-interactive Bash login command in the server process environment and working directory. Stdout and stderr are each capped at 65536 bytes.".to_owned(), BashInvocation::schema(config)),
        };
        let tool = ToolSpec {
            name: self.name().to_owned(),
            description,
            input_schema,
        };
        let recovery_policy = match self {
            Self::ForkTask | Self::ReadTask | Self::ExecCmd => ToolRecoveryPolicy::RetrySafe,
            Self::SendMessageToTask | Self::ArchiveTask | Self::Bash => {
                ToolRecoveryPolicy::OutcomeUnknown
            }
        };
        TaskToolSpec {
            tool,
            recovery_policy,
            execution_source: ToolExecutionSource::Harness,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum HarnessInvocation {
    ForkTask(ForkTaskInvocation),
    ReadTask(ReadTaskInvocation),
    SendMessageToTask(SendMessageToTaskInvocation),
    ArchiveTask(ArchiveTaskInvocation),
    Bash(BashInvocation),
    ExecCmd(String),
}

fn parse_invocation(
    request: &ToolExecutionRequest,
    config: &HarnessConfig,
) -> Result<HarnessInvocation, HarnessError> {
    let tool = BuiltinTool::ALL
        .iter()
        .copied()
        .find(|tool| tool.name() == request.tool_name.0)
        .ok_or_else(|| {
            HarnessError::new(
                HarnessErrorCode::UnknownTool,
                format!("unknown tool '{}'", request.tool_name.0),
            )
        })?;
    let arguments = &request.arguments;
    Ok(match tool {
        BuiltinTool::ForkTask => {
            HarnessInvocation::ForkTask(ForkTaskInvocation::parse(arguments, config)?)
        }
        BuiltinTool::ReadTask => {
            HarnessInvocation::ReadTask(ReadTaskInvocation::parse(arguments, config)?)
        }
        BuiltinTool::SendMessageToTask => HarnessInvocation::SendMessageToTask(
            SendMessageToTaskInvocation::parse(arguments, config)?,
        ),
        BuiltinTool::ArchiveTask => {
            let invocation = ArchiveTaskInvocation::parse(arguments, config)?;
            if invocation.task_id == request.task_id {
                return Err(HarnessError::new(
                    HarnessErrorCode::CannotArchiveCurrentTask,
                    "cannot archive the calling task",
                ));
            }
            HarnessInvocation::ArchiveTask(invocation)
        }
        BuiltinTool::Bash => HarnessInvocation::Bash(BashInvocation::parse(arguments, config)?),
        BuiltinTool::ExecCmd => {
            HarnessInvocation::ExecCmd(ExecCmdArguments::parse(arguments, config)?.code)
        }
    })
}

#[derive(Clone, Debug, PartialEq)]
enum HarnessSuccess {
    ReadTask(ReadTaskSuccess),
    SendMessageToTask(SendMessageToTaskSuccess),
    ArchiveTask(ArchiveTaskSuccess),
    Bash(BashSuccess),
}

#[derive(Clone, Debug, PartialEq)]
struct ReadTaskSuccess {
    task_id: TaskId,
    status: TaskStatus,
    state_version: u64,
    cursor_node_id: HistoryNodeId,
    parent_task_id: Option<TaskId>,
    queued_message_count: u64,
    history: HistoryPage,
}

#[derive(Clone, Debug, PartialEq)]
struct HistoryPage {
    nodes: Vec<HistoryNodeProjection>,
    next_after_node_id: Option<HistoryNodeId>,
    has_more: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum MessageDisposition {
    Committed { node_id: HistoryNodeId },
    Queued,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct SendMessageToTaskSuccess {
    task_id: TaskId,
    disposition: MessageDisposition,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct ArchiveTaskSuccess {
    task_id: TaskId,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct BashSuccess {
    exit_code: Option<i32>,
    stdout: String,
    stderr: String,
    stdout_truncated: bool,
    stderr_truncated: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum HarnessErrorCode {
    InvalidArguments,
    CommandReplayMismatch,
    UnknownTool,
    TaskNotFound,
    TaskArchived,
    HistoryCursorNotOnTask,
    CannotArchiveCurrentTask,
    OperationCancelled,
    RouterUnavailable,
    StorageError,
    ResourceExhausted,
    ExecutorPanicked,
    CommandSpawnFailed,
    CommandIoFailed,
    CommandWaitFailed,
    CommandTimedOut,
    McpRouteUnavailable,
    ToolUnavailable,
    McpCallFailed,
    McpCallTimedOut,
    McpResultEncodingFailed,
}

impl HarnessErrorCode {
    const fn as_str(self) -> &'static str {
        match self {
            HarnessErrorCode::InvalidArguments => "invalid_arguments",
            HarnessErrorCode::CommandReplayMismatch => "command_replay_mismatch",
            HarnessErrorCode::UnknownTool => "unknown_tool",
            HarnessErrorCode::TaskNotFound => "task_not_found",
            HarnessErrorCode::TaskArchived => "task_archived",
            HarnessErrorCode::HistoryCursorNotOnTask => "history_cursor_not_on_task",
            HarnessErrorCode::CannotArchiveCurrentTask => "cannot_archive_current_task",
            HarnessErrorCode::OperationCancelled => "operation_cancelled",
            HarnessErrorCode::RouterUnavailable => "router_unavailable",
            HarnessErrorCode::StorageError => "storage_error",
            HarnessErrorCode::ResourceExhausted => "resource_exhausted",
            HarnessErrorCode::ExecutorPanicked => "executor_panicked",
            HarnessErrorCode::CommandSpawnFailed => "command_spawn_failed",
            HarnessErrorCode::CommandIoFailed => "command_io_failed",
            HarnessErrorCode::CommandWaitFailed => "command_wait_failed",
            HarnessErrorCode::CommandTimedOut => "command_timed_out",
            HarnessErrorCode::McpRouteUnavailable => "mcp_route_unavailable",
            HarnessErrorCode::ToolUnavailable => "tool_unavailable",
            HarnessErrorCode::McpCallFailed => "mcp_call_failed",
            HarnessErrorCode::McpCallTimedOut => "mcp_call_timed_out",
            HarnessErrorCode::McpResultEncodingFailed => "mcp_result_encoding_failed",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct HarnessError {
    code: HarnessErrorCode,
    message: String,
}

impl HarnessError {
    fn new(code: HarnessErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }

    fn invalid_arguments(message: impl Into<String>) -> Self {
        Self::new(HarnessErrorCode::InvalidArguments, message)
    }

    const fn code(&self) -> HarnessErrorCode {
        self.code
    }

    fn message(&self) -> &str {
        &self.message
    }
}

impl fmt::Display for HarnessError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}: {}", self.code().as_str(), self.message())
    }
}

impl Error for HarnessError {}

fn correlated_tool_execution_result(
    request: &ToolExecutionRequest,
    branches: Vec<ToolExecutionBranch>,
) -> ToolExecutionResult {
    ToolExecutionResult {
        completion: ToolExecutionCompletion::ordinary(),
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
    commands: CommandEnvironmentManager,
}

impl ToolExecutor {
    pub fn with_command_environments(
        db: DbPool,
        mcp: McpConnectionSet,
        commands: CommandEnvironmentManager,
    ) -> Self {
        Self { db, mcp, commands }
    }
    pub fn new(db: DbPool, mcp: McpConnectionSet) -> Self {
        Self {
            db,
            mcp,
            commands: CommandEnvironmentManager::new(),
        }
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
        let commands = self.commands.clone();
        let execution_request = request.clone();
        let execution_router_tx = router_tx.clone();
        spawn_supervised_execution(request, router_tx, async move {
            execute_routed_request(db, mcp, commands, execution_request, execution_router_tx).await
        })
    }
}

fn spawn_supervised_execution<F>(
    request: ToolExecutionRequest,
    router_tx: RouterIngressWeakSender,
    execution: F,
) -> Result<JoinHandle<()>, ToolExecutionSpawnError>
where
    F: Future<Output = Result<command::ExecutedTool, HarnessError>> + Send + 'static,
{
    let runtime = tokio::runtime::Handle::try_current()
        .map_err(|_| ToolExecutionSpawnError::TokioSpawnFailed)?;
    Ok(runtime.spawn(async move {
        let branches = match AssertUnwindSafe(execution).catch_unwind().await {
            Ok(Ok(result)) => result,
            Ok(Err(error)) => {
                command::ExecutedTool::ordinary(vec![calling_task_branch(error_json(&error), true)])
            }
            Err(_) => command::ExecutedTool::ordinary(vec![calling_task_branch(
                error_json(&HarnessError::new(
                    HarnessErrorCode::ExecutorPanicked,
                    "tool executor panicked",
                )),
                true,
            )]),
        };
        let mut result = correlated_tool_execution_result(&request, branches.branches);
        result.completion = branches.completion;
        if let Some(router_tx) = router_tx.upgrade() {
            let _ = router_tx.send(RouterIngressMessage::Tool(result));
        }
    }))
}

async fn execute_routed_request(
    db: DbPool,
    mcp: McpConnectionSet,
    commands: CommandEnvironmentManager,
    request: ToolExecutionRequest,
    router_tx: RouterIngressWeakSender,
) -> Result<command::ExecutedTool, HarnessError> {
    let execution = AssertUnwindSafe(execute_routed_request_inner(
        db.clone(),
        mcp,
        commands.clone(),
        request.clone(),
        router_tx.clone(),
    ))
    .catch_unwind()
    .await;
    let error = match execution {
        Ok(Ok(result)) => return Ok(result),
        Ok(Err(error)) => error,
        Err(_) => HarnessError::new(HarnessErrorCode::ExecutorPanicked, "tool executor panicked"),
    };
    commands
        .finalize_existing_error(&db, &request, &router_tx, error)
        .await
}

async fn execute_routed_request_inner(
    db: DbPool,
    mcp: McpConnectionSet,
    commands: CommandEnvironmentManager,
    request: ToolExecutionRequest,
    router_tx: RouterIngressWeakSender,
) -> Result<command::ExecutedTool, HarnessError> {
    let route_db = db.clone();
    let task_id = request.task_id.clone();
    let tool_name = request.tool_name.clone();
    let execution = tokio::task::spawn_blocking(move || {
        read_tool_execution_source(&route_db, &task_id, &tool_name)
    })
    .await
    .map_err(map_join_error)?
    .map_err(map_tool_route_error)?;
    match execution.source {
        ToolExecutionSource::Harness => {
            let config = HarnessConfig {
                max_children_per_fork: execution.max_children_per_fork,
                max_descendants_per_task: execution.max_task_descendants,
            };
            execute_harness_request(db, commands, config, request, router_tx).await
        }
        ToolExecutionSource::Mcp {
            server_id,
            remote_tool_name,
        } => {
            let (output, is_error) = mcp
                .call_tool(&server_id, remote_tool_name, request.arguments)
                .await?;
            Ok(command::ExecutedTool::ordinary(vec![calling_task_branch(
                output, is_error,
            )]))
        }
    }
}

async fn execute_harness_request(
    db: DbPool,
    commands: CommandEnvironmentManager,
    config: HarnessConfig,
    request: ToolExecutionRequest,
    router_tx: RouterIngressWeakSender,
) -> Result<command::ExecutedTool, HarnessError> {
    let branches = match parse_invocation(&request, &config)? {
        HarnessInvocation::ExecCmd(code) => {
            return commands
                .execute(db, config, request, router_tx, Some(code), None)
                .await;
        }
        HarnessInvocation::ForkTask(invocation) => {
            return commands
                .execute(db, config, request, router_tx, None, Some(invocation))
                .await;
        }
        HarnessInvocation::ReadTask(invocation) => {
            execute_read_task(db, request.task_id, invocation)
                .await
                .map(single_success_branch)
        }
        HarnessInvocation::SendMessageToTask(invocation) => {
            execute_send_message_to_task(invocation, router_tx, command::caller_context(&request))
                .await
                .map(single_success_branch)
        }
        HarnessInvocation::ArchiveTask(invocation) => {
            execute_archive_task(invocation, router_tx, command::caller_context(&request))
                .await
                .map(single_success_branch)
        }
        HarnessInvocation::Bash(invocation) => {
            execute_bash(invocation).await.map(single_success_branch)
        }
    }?;
    Ok(command::ExecutedTool::ordinary(branches))
}

fn map_tool_route_error(error: DbError) -> HarnessError {
    match error {
        DbError::NotFound => HarnessError::new(
            HarnessErrorCode::UnknownTool,
            "tool does not have a durable execution route",
        ),
        DbError::ToolUnavailable => HarnessError::new(
            HarnessErrorCode::ToolUnavailable,
            "tool is unavailable for this task",
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

fn execute_fork_task(
    invocation: ForkTaskInvocation,
) -> Result<Vec<ToolExecutionBranch>, HarnessError> {
    let branch_count = invocation.child_count.checked_add(1).ok_or_else(|| {
        HarnessError::new(
            HarnessErrorCode::ResourceExhausted,
            "fork result branch count exceeds this platform's capacity",
        )
    })?;
    let mut branches = Vec::new();
    branches.try_reserve_exact(branch_count).map_err(|_| {
        HarnessError::new(
            HarnessErrorCode::ResourceExhausted,
            "fork result branches could not be allocated",
        )
    })?;
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
    Ok(branches)
}

async fn execute_read_task(
    db: DbPool,
    calling_task_id: TaskId,
    invocation: ReadTaskInvocation,
) -> Result<HarnessSuccess, HarnessError> {
    let task_id = invocation.task_id.unwrap_or(calling_task_id);
    let limit = u32::from(invocation.limit.unwrap_or(MAX_READ_LIMIT));
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
    context: selvedge_domain_model::CommandOperationContext,
) -> Result<HarnessSuccess, HarnessError> {
    let task_id = invocation.task_id.clone();
    let value = command::send_task_input(invocation, router_tx, context).await?;
    let disposition = if value["disposition"] == "queued" {
        MessageDisposition::Queued
    } else {
        MessageDisposition::Committed {
            node_id: HistoryNodeId(value["node_id"].as_i64().ok_or_else(|| {
                HarnessError::new(
                    HarnessErrorCode::StorageError,
                    "committed input response lacks node_id",
                )
            })?),
        }
    };
    Ok(HarnessSuccess::SendMessageToTask(
        SendMessageToTaskSuccess {
            task_id,
            disposition,
        },
    ))
}

async fn execute_archive_task(
    invocation: ArchiveTaskInvocation,
    router_tx: RouterIngressWeakSender,
    context: selvedge_domain_model::CommandOperationContext,
) -> Result<HarnessSuccess, HarnessError> {
    let task_id = invocation.task_id;
    command::change_task_status(
        task_id.clone(),
        selvedge_domain_model::TaskLifecycleEvent::Archive,
        router_tx,
        context,
    )
    .await?;
    Ok(HarnessSuccess::ArchiveTask(ArchiveTaskSuccess { task_id }))
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

    // Keep completed outputs inside the same join future when the deadline expires.
    // Cancelling execution drops both pipe readers along with the child owner.
    let completion =
        async { tokio::join!(child.wait(), capture_output(stdout), capture_output(stderr)) };
    tokio::pin!(completion);
    let completed = tokio::time::timeout(
        Duration::from_millis(invocation.timeout_ms),
        completion.as_mut(),
    )
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
            let cleanup = tokio::time::timeout(BASH_REAP_TIMEOUT, completion.as_mut()).await;
            let (status, _, _) = match cleanup {
                Ok(cleanup) => cleanup,
                Err(_) => {
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
    result: Result<CapturedOutput, io::Error>,
) -> Result<CapturedOutput, HarnessError> {
    result.map_err(|error| {
        HarnessError::new(
            HarnessErrorCode::CommandIoFailed,
            format!("failed to read bash {stream}: {error}"),
        )
    })
}

pub(crate) struct ProcessGroupGuard {
    process_group_id: Pid,
    armed: bool,
}

impl ProcessGroupGuard {
    pub(crate) fn new(process_group_id: Pid) -> Self {
        Self {
            process_group_id,
            armed: true,
        }
    }

    fn terminate(&self) -> Result<(), HarnessError> {
        self.terminate_raw().map_err(|error| {
            HarnessError::new(
                HarnessErrorCode::CommandWaitFailed,
                format!("failed to terminate bash process group: {error}"),
            )
        })
    }

    pub(crate) fn terminate_raw(&self) -> Result<(), Errno> {
        match kill_process_group(self.process_group_id, Signal::KILL) {
            Ok(()) | Err(Errno::SRCH) => Ok(()),
            Err(error) => Err(error),
        }
    }

    pub(crate) fn disarm(&mut self) {
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
        .send(RouterIngressMessage::Command(command))
        .map_err(|_| {
            HarnessError::new(HarnessErrorCode::RouterUnavailable, "router is unavailable")
        })
}

fn map_task_command_error(error: TaskCommandError) -> HarnessError {
    match error {
        TaskCommandError::CommandOperationMismatch => HarnessError::new(
            HarnessErrorCode::CommandReplayMismatch,
            "command operation replay mismatch",
        ),
        TaskCommandError::TaskMissing => {
            HarnessError::new(HarnessErrorCode::TaskNotFound, "task was not found")
        }
        TaskCommandError::TaskArchived => {
            HarnessError::new(HarnessErrorCode::TaskArchived, "task is archived")
        }
        TaskCommandError::PersistenceFailed => {
            HarnessError::new(HarnessErrorCode::StorageError, "task persistence failed")
        }
        TaskCommandError::InvalidTaskStatus {
            status: TaskStatus::Archived,
        } => HarnessError::new(HarnessErrorCode::TaskArchived, "task is archived"),
        TaskCommandError::InvalidTaskStatus { status } => HarnessError::new(
            HarnessErrorCode::StorageError,
            format!("task status does not allow the command: {status:?}"),
        ),
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
        DbError::InvalidTaskStatus {
            status: TaskStatus::Archived,
        } => HarnessError::new(HarnessErrorCode::TaskArchived, "task is archived"),
        DbError::InvalidTaskStatus { .. }
        | DbError::StaleFunctionCall
        | DbError::CommandEnvironmentBusy { .. }
        | DbError::CommandOperationMismatch
        | DbError::ToolUnavailable
        | DbError::TaskDescendantLimitExceeded { .. }
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
        status: read.task_status,
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

fn task_status_json(status: &TaskStatus) -> Value {
    Value::String(
        match status {
            TaskStatus::Active => "active",
            TaskStatus::Frozen => "frozen",
            TaskStatus::Stopped => "stopped",
            TaskStatus::Archived => "archived",
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
        RouterIngressMessage, ToolExecutionBranchTarget, ToolExecutionRunId,
    };
    use selvedge_domain_model::{FunctionCallId, HistoryNodeId, JsonObject, TaskId, ToolName};

    use super::{execute_fork_task, spawn_supervised_execution};
    use crate::{ForkTaskInvocation, HarnessErrorCode, ToolExecutionRequest};

    #[test]
    fn fork_branch_allocation_failure_is_a_typed_error() {
        for child_count in [usize::MAX, usize::MAX - 1] {
            let error = execute_fork_task(ForkTaskInvocation {
                child_count,
                environment: selvedge_domain_model::CommandEnvironmentMode::Shared,
                messages: None,
            })
            .expect_err("capacity must be rejected");

            assert_eq!(error.code(), HarnessErrorCode::ResourceExhausted);
        }
    }

    #[tokio::test]
    async fn panicking_execution_still_emits_one_correlated_terminal_result() {
        let request = ToolExecutionRequest {
            execution_mode: selvedge_domain_model::ToolExecutionMode::Normal,
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
                Ok::<super::command::ExecutedTool, super::HarnessError>(unreachable!())
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

#[cfg(test)]
mod projection_tests;

#[cfg(test)]
mod protocol_tests;
