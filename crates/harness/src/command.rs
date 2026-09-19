use std::collections::{BTreeMap, BTreeSet};
use std::future::Future;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, Ordering},
};
use std::time::{SystemTime, UNIX_EPOCH};

use selvedge_command_model::{PreparedCommandEnvironment, command_operation_response_channel};
use selvedge_db::*;
use selvedge_domain_model::{CommandOperation, CommandOperationId};
use selvedge_script_runtime::{
    HostRequest, HostResponse, ScriptCheckpoint, ScriptExecutionRequest, ScriptHost,
    ScriptHostError as HostError, ScriptRuntime,
};
use serde_json::{Value, json};
use tokio::sync::{Mutex as AsyncMutex, OwnedMutexGuard};

use crate::kernel::{KernelCommand, kernel_bootstrap};
use crate::*;

pub(crate) struct ExecutedTool {
    pub(crate) branches: Vec<ToolExecutionBranch>,
    pub(crate) prepared_environment: Option<PreparedCommandEnvironment>,
}

impl ExecutedTool {
    pub(crate) fn ordinary(branches: Vec<ToolExecutionBranch>) -> Self {
        Self {
            branches,
            prepared_environment: None,
        }
    }
}

/// Shared by all tool executions in one server. Leases survive execution until the
/// core commits output and checkpoint together, including ordinary fork copies.
#[derive(Clone)]
pub struct CommandEnvironmentManager {
    runtime: Arc<Result<ScriptRuntime, String>>,
    leases: Arc<Mutex<BTreeMap<String, Arc<AsyncMutex<()>>>>>,
}

impl Default for CommandEnvironmentManager {
    fn default() -> Self {
        Self::new()
    }
}

impl CommandEnvironmentManager {
    pub fn new() -> Self {
        Self {
            runtime: Arc::new(
                ScriptRuntime::new(kernel_bootstrap()).map_err(|error| error.to_string()),
            ),
            leases: Arc::new(Mutex::new(BTreeMap::new())),
        }
    }

    async fn acquire(
        &self,
        db: &DbPool,
        request: &ToolExecutionRequest,
        router_tx: &RouterIngressWeakSender,
    ) -> Result<(CommandEnvironmentRow, OwnedMutexGuard<()>), HarnessError> {
        let invocation = CommandInvocationId {
            task_id: request.task_id.clone(),
            function_call_node_id: request.function_call_node_id,
        };
        let mut requested_recovery = None;
        loop {
            let row = read_command_environment(db, &request.task_id).map_err(storage_error)?;
            let lock = self
                .leases
                .lock()
                .map_err(|_| storage_message("command environment lease registry poisoned"))?
                .entry(row.environment_id.0)
                .or_insert_with(|| Arc::new(AsyncMutex::new(())))
                .clone();
            let guard = lock.lock_owned().await;
            match admit_command_invocation(
                db,
                &invocation,
                &request.function_call_id,
                &request.tool_name,
            ) {
                Ok(row) => return Ok((row, guard)),
                Err(DbError::CommandEnvironmentBusy { invocation }) => {
                    drop(guard);
                    if requested_recovery.as_ref() != Some(&invocation) {
                        send_router_command(
                            router_tx,
                            RouterCommand::RecoverCommandInvocation {
                                invocation: invocation.clone(),
                            },
                        )?;
                        requested_recovery = Some(invocation);
                    }
                    tokio::time::sleep(Duration::from_millis(50)).await;
                }
                Err(error) => return Err(storage_error(error)),
            }
        }
    }

    pub(crate) async fn finalize_existing_error(
        &self,
        db: &DbPool,
        request: &ToolExecutionRequest,
        router_tx: &RouterIngressWeakSender,
        error: HarnessError,
    ) -> Result<ExecutedTool, HarnessError> {
        let invocation = CommandInvocationId {
            task_id: request.task_id.clone(),
            function_call_node_id: request.function_call_node_id,
        };
        let row = match read_command_environment(db, &request.task_id) {
            Ok(row) => row,
            Err(DbError::NotFound) => return Err(error),
            Err(error) => return Err(storage_error(error)),
        };
        if row.admitted_invocation.as_ref() != Some(&invocation) {
            return Err(error);
        }
        let (row, guard) = self.acquire(db, request, router_tx).await?;
        // Recovery must not depend on a still-available tool route or an engine that
        // can initialize. Empty base bytes are the database's lazy new-environment marker.
        Ok(ExecutedTool {
            branches: vec![calling_task_branch(error_json(&error), true)],
            prepared_environment: Some(PreparedCommandEnvironment::new(
                CommandEnvironmentCommit {
                    environment_id: row.environment_id,
                    invocation,
                    expected_revision: row.revision,
                    checkpoint: row.checkpoint,
                    base_checkpoint: Vec::new(),
                    new_child_environment_mode: CommandEnvironmentMode::Shared,
                },
                guard,
            )),
        })
    }

    pub(crate) async fn execute(
        &self,
        db: DbPool,
        config: HarnessConfig,
        request: ToolExecutionRequest,
        router_tx: RouterIngressWeakSender,
        source: Option<String>,
        fork: Option<ForkTaskInvocation>,
    ) -> Result<ExecutedTool, HarnessError> {
        let runtime = self
            .runtime
            .as_ref()
            .as_ref()
            .map_err(|error| storage_message(error.clone()))?;
        let base = runtime
            .base_checkpoint()
            .map_err(|error| storage_message(error.to_string()))?
            .0;
        let replay_length = command_operation_replay_length(
            &db,
            &CommandInvocationId {
                task_id: request.task_id.clone(),
                function_call_node_id: request.function_call_node_id,
            },
        )
        .map_err(storage_error)?;
        let (row, guard) = self.acquire(&db, &request, &router_tx).await?;
        let checkpoint = if row.checkpoint.is_empty() {
            base.clone()
        } else {
            row.checkpoint
        };
        let invocation = CommandInvocationId {
            task_id: request.task_id.clone(),
            function_call_node_id: request.function_call_node_id,
        };
        let environment_mode = fork
            .as_ref()
            .map_or(CommandEnvironmentMode::Shared, |fork| fork.environment);
        let (branches, checkpoint) = if let Some(source) = source {
            let had_error = Arc::new(AtomicBool::new(false));
            let poisoned = Arc::new(AtomicBool::new(false));
            let visited = Arc::new(Mutex::new(BTreeSet::new()));
            let host = Arc::new(CommandHost {
                db,
                config,
                router_tx,
                invocation: invocation.clone(),
                mode: request.execution_mode,
                had_error: had_error.clone(),
                poisoned: poisoned.clone(),
                visited: visited.clone(),
            });
            let execution = AssertUnwindSafe(runtime.execute(
                ScriptExecutionRequest {
                    checkpoint: ScriptCheckpoint(checkpoint.clone()),
                    source,
                    source_name: format!(
                        "exec_cmd:{}:{}",
                        request.task_id.0, request.function_call_node_id.0
                    ),
                },
                host,
            ))
            .catch_unwind()
            .await
            .unwrap_or_else(|_| {
                Err(selvedge_script_runtime::ScriptRuntimeError::Engine(
                    "script executor panicked".into(),
                ))
            });
            let complete_prefix = visited
                .lock()
                .is_ok_and(|seen| (0..replay_length).all(|ordinal| seen.contains(&ordinal)));
            if poisoned.load(Ordering::Acquire) || !complete_prefix {
                (
                    vec![calling_task_branch(
                        diagnostic(
                            "command_replay_mismatch",
                            "the interrupted invocation changed its recorded host operation sequence; committed script state was retained",
                        ),
                        true,
                    )],
                    checkpoint,
                )
            } else {
                match execution {
                    Ok(result) => (
                        vec![calling_task_branch(
                            result.output,
                            result.is_error || had_error.load(Ordering::Acquire),
                        )],
                        result.checkpoint.0,
                    ),
                    Err(error) => (
                        vec![calling_task_branch(
                            diagnostic("script_runtime_error", error.to_string()),
                            true,
                        )],
                        checkpoint,
                    ),
                }
            }
        } else if let Some(fork) = fork {
            (
                match execute_fork_task(fork) {
                    Ok(branches) => branches,
                    Err(error) => vec![calling_task_branch(error_json(&error), true)],
                },
                checkpoint,
            )
        } else {
            (
                vec![calling_task_branch(
                    diagnostic("invalid_command", "missing command source or fork"),
                    true,
                )],
                checkpoint,
            )
        };
        Ok(ExecutedTool {
            branches,
            prepared_environment: Some(PreparedCommandEnvironment::new(
                CommandEnvironmentCommit {
                    environment_id: row.environment_id,
                    invocation,
                    expected_revision: row.revision,
                    checkpoint,
                    base_checkpoint: base,
                    new_child_environment_mode: environment_mode,
                },
                guard,
            )),
        })
    }
}

struct CommandHost {
    db: DbPool,
    config: HarnessConfig,
    router_tx: RouterIngressWeakSender,
    invocation: CommandInvocationId,
    mode: ToolExecutionMode,
    had_error: Arc<AtomicBool>,
    poisoned: Arc<AtomicBool>,
    visited: Arc<Mutex<BTreeSet<u64>>>,
}

impl ScriptHost for CommandHost {
    fn call(
        &self,
        request: HostRequest,
    ) -> Pin<Box<dyn Future<Output = Result<HostResponse, HostError>> + Send>> {
        let host = Self {
            db: self.db.clone(),
            config: self.config.clone(),
            router_tx: self.router_tx.clone(),
            invocation: self.invocation.clone(),
            mode: self.mode,
            had_error: self.had_error.clone(),
            poisoned: self.poisoned.clone(),
            visited: self.visited.clone(),
        };
        Box::pin(async move { host.dispatch(request).await })
    }
}

impl CommandHost {
    fn context(&self, ordinal: u64, command: String, arguments: Value) -> CommandOperationContext {
        CommandOperationContext {
            caller_task_id: self.invocation.task_id.clone(),
            mode: self.mode,
            operation: Some(CommandOperation {
                id: CommandOperationId {
                    invocation: self.invocation.clone(),
                    ordinal,
                },
                command,
                arguments,
            }),
        }
    }

    async fn dispatch(&self, request: HostRequest) -> Result<HostResponse, HostError> {
        if self.poisoned.load(Ordering::Acquire) {
            return Err(HostError {
                message: "invocation replay is poisoned".into(),
            });
        }
        let ordinal = match &request {
            HostRequest::Command { ordinal, .. } | HostRequest::LoadModule { ordinal, .. } => {
                *ordinal
            }
        };
        self.visited
            .lock()
            .map_err(|_| HostError {
                message: "operation sequence lock poisoned".into(),
            })?
            .insert(ordinal);
        match request {
            HostRequest::Command {
                ordinal,
                name,
                arguments,
            } => {
                let context = self.context(ordinal, name.clone(), arguments.clone());
                let saved = self.saved(&context)?;
                let outcome = if let Some(value) = saved {
                    Ok(value)
                } else {
                    self.command(&context, &name, arguments).await
                };
                let value = match outcome {
                    Ok(value) => value,
                    Err(error) => {
                        if error.code() == HarnessErrorCode::CommandReplayMismatch {
                            self.poisoned.store(true, Ordering::Release);
                            return Err(HostError {
                                message: error.to_string(),
                            });
                        }
                        let value = diagnostic("command_error", error.to_string());
                        // Failed validation and denied mutations are observations too. Replays
                        // must see the same branch even if task state subsequently changes.
                        save_command_observation(&self.db, &context, value)
                            .map_err(host_db_error)?
                            .result
                    }
                };
                if value.get("error").is_some() {
                    self.had_error.store(true, Ordering::Release);
                }
                Ok(HostResponse::Command(value))
            }
            HostRequest::LoadModule {
                ordinal,
                specifier,
                referrer,
            } => {
                let context = self.context(
                    ordinal,
                    "modules.load".into(),
                    json!({"specifier":specifier,"referrer":referrer}),
                );
                let saved = self.saved(&context)?;
                let value = match saved {
                    Some(value) => value,
                    None => {
                        let value = match load_module(&specifier, &referrer) {
                            Ok((source, resolved)) => {
                                json!({"source":source,"resolved_specifier":resolved})
                            }
                            Err(error) => diagnostic("module_load_error", error),
                        };
                        save_command_observation(&self.db, &context, value)
                            .map_err(host_db_error)?
                            .result
                    }
                };
                if let Some(error) = value.get("error") {
                    self.had_error.store(true, Ordering::Release);
                    return Ok(HostResponse::ModuleError {
                        message: error.to_string(),
                    });
                }
                Ok(HostResponse::Module {
                    source: value["source"]
                        .as_str()
                        .ok_or_else(|| HostError {
                            message: "invalid saved module source".into(),
                        })?
                        .into(),
                    resolved_specifier: value["resolved_specifier"]
                        .as_str()
                        .ok_or_else(|| HostError {
                            message: "invalid saved module specifier".into(),
                        })?
                        .into(),
                })
            }
        }
    }

    fn saved(&self, context: &CommandOperationContext) -> Result<Option<Value>, HostError> {
        read_command_operation(&self.db, context).map_err(|error| {
            self.poisoned.store(true, Ordering::Release);
            host_db_error(error)
        })
    }

    async fn command(
        &self,
        context: &CommandOperationContext,
        name: &str,
        arguments: Value,
    ) -> Result<Value, HarnessError> {
        let command = KernelCommand::parse(name).ok_or_else(|| {
            HarnessError::invalid_arguments(format!("unknown kernel command '{name}'"))
        })?;
        let arguments: JsonObject = arguments
            .as_object()
            .ok_or_else(|| HarnessError::invalid_arguments("command arguments must be an object"))?
            .iter()
            .map(|(key, value)| (key.clone(), value.clone()))
            .collect();
        match command {
            KernelCommand::Read | KernelCommand::Logs => {
                let HarnessInvocation::ReadTask(invocation) = parse_read_task(&arguments)? else {
                    unreachable!()
                };
                let success =
                    execute_read_task(self.db.clone(), self.invocation.task_id.clone(), invocation)
                        .await?;
                let value = if command == KernelCommand::Logs {
                    let HarnessSuccess::ReadTask(read) = success else {
                        unreachable!()
                    };
                    history_page_json(&read.history)
                } else {
                    success_json(&success)
                };
                Ok(save_command_observation(&self.db, context, value)
                    .map_err(storage_error)?
                    .result)
            }
            KernelCommand::Send => {
                let HarnessInvocation::SendMessageToTask(invocation) =
                    parse_send_message_to_task(&arguments)?
                else {
                    unreachable!()
                };
                send_task_input(invocation, self.router_tx.clone(), context.clone()).await
            }
            KernelCommand::Archive
            | KernelCommand::Freeze
            | KernelCommand::Unfreeze
            | KernelCommand::Stop => {
                let args = Arguments::new(&arguments, &["task_id"])?;
                let task_id = args
                    .optional_nonempty_string("task_id")?
                    .map(TaskId)
                    .unwrap_or_else(|| self.invocation.task_id.clone());
                let event = match command {
                    KernelCommand::Archive => TaskLifecycleEvent::Archive,
                    KernelCommand::Freeze => TaskLifecycleEvent::Freeze,
                    KernelCommand::Unfreeze => TaskLifecycleEvent::Unfreeze,
                    KernelCommand::Stop => TaskLifecycleEvent::Stop,
                    _ => unreachable!(),
                };
                change_task_status(task_id, event, self.router_tx.clone(), context.clone()).await
            }
            KernelCommand::Fork => {
                let HarnessInvocation::ForkTask(fork) = parse_fork_task(&arguments, &self.config)?
                else {
                    unreachable!()
                };
                let children = (0..fork.child_count)
                    .map(|index| {
                        (
                            TaskId(format!("child-{}", Uuid::new_v4())),
                            fork.messages
                                .as_ref()
                                .map_or_else(Vec::new, |messages| vec![messages[index].clone()]),
                        )
                    })
                    .collect();
                Ok(create_pending_command_children(
                    &self.db,
                    context,
                    children,
                    fork.environment,
                    now(),
                )
                .map_err(storage_error)?
                .result)
            }
            KernelCommand::Bash | KernelCommand::WriteFile => {
                self.external(context, command, &arguments).await
            }
        }
    }

    async fn external(
        &self,
        context: &CommandOperationContext,
        command: KernelCommand,
        arguments: &JsonObject,
    ) -> Result<Value, HarnessError> {
        // Validate before durable admission; once admitted, any crash leaves an unknown
        // external outcome, never a license to execute shell or filesystem effects twice.
        let bash = if command == KernelCommand::Bash {
            let HarnessInvocation::Bash(bash) = parse_bash(arguments)? else {
                unreachable!()
            };
            Some(bash)
        } else {
            None
        };
        let write = if command == KernelCommand::WriteFile {
            let args = Arguments::new(arguments, &["path", "content"])?;
            let path = args.required_nonempty_string("path")?;
            let content = arguments
                .get("content")
                .and_then(Value::as_str)
                .ok_or_else(|| HarnessError::invalid_arguments("content must be a string"))?
                .to_owned();
            Some((path, content))
        } else {
            None
        };
        match admit_external_command_operation(&self.db, context).map_err(storage_error)? {
            CommandOperationAdmission::Completed(value) => return Ok(value),
            CommandOperationAdmission::OutcomeUnknown => {
                return Ok(diagnostic(
                    "outcome_unknown",
                    "external operation was admitted before interruption; it was not repeated",
                ));
            }
            CommandOperationAdmission::Execute => {}
        }
        let value = if let Some(bash) = bash {
            match execute_bash(bash).await {
                Ok(success) => success_json(&success),
                Err(error) => error_json(&error),
            }
        } else if let Some((path, content)) = write {
            match std::fs::write(&path, content.as_bytes()) {
                Ok(()) => json!({"path":path,"bytes_written":content.len()}),
                Err(error) => diagnostic("file_write_error", error.to_string()),
            }
        } else {
            unreachable!()
        };
        Ok(
            complete_external_command_operation(&self.db, context, value)
                .map_err(storage_error)?
                .result,
        )
    }
}

pub(crate) fn caller_context(request: &ToolExecutionRequest) -> CommandOperationContext {
    CommandOperationContext {
        caller_task_id: request.task_id.clone(),
        mode: request.execution_mode,
        operation: None,
    }
}

pub(crate) async fn send_task_input(
    invocation: SendMessageToTaskInvocation,
    router_tx: RouterIngressWeakSender,
    context: CommandOperationContext,
) -> Result<Value, HarnessError> {
    let (responder, response) = command_operation_response_channel();
    send_router_command(
        &router_tx,
        RouterCommand::SendTaskInput {
            task_id: invocation.task_id,
            message_text: invocation.message,
            context,
            responder,
        },
    )?;
    response
        .await
        .map_err(|_| storage_message("task input response cancelled"))?
        .map_err(map_task_command_error)
}

pub(crate) async fn change_task_status(
    task_id: TaskId,
    event: TaskLifecycleEvent,
    router_tx: RouterIngressWeakSender,
    context: CommandOperationContext,
) -> Result<Value, HarnessError> {
    let (responder, response) = command_operation_response_channel();
    send_router_command(
        &router_tx,
        RouterCommand::ChangeTaskStatus {
            task_id,
            event,
            context,
            responder,
        },
    )?;
    response
        .await
        .map_err(|_| storage_message("task status response cancelled"))?
        .map_err(map_task_command_error)
}

pub(crate) fn parse_environment_mode(
    value: Option<&Value>,
) -> Result<CommandEnvironmentMode, HarnessError> {
    match value {
        None => Ok(CommandEnvironmentMode::Shared),
        Some(Value::String(value)) if value == "shared" => Ok(CommandEnvironmentMode::Shared),
        Some(Value::String(value)) if value == "copy" => Ok(CommandEnvironmentMode::Copy),
        Some(Value::String(value)) if value == "new" => Ok(CommandEnvironmentMode::New),
        _ => Err(HarnessError::invalid_arguments(
            "environment must be shared, copy, or new",
        )),
    }
}

fn load_module(specifier: &str, referrer: &str) -> Result<(String, String), String> {
    if specifier.contains("://") || specifier.contains('\0') {
        return Err("module specifier must be a local path".into());
    }
    let path = Path::new(specifier);
    let path = if path.is_absolute() {
        path.to_owned()
    } else {
        let base = if Path::new(referrer).is_absolute() {
            Path::new(referrer).parent().map(Path::to_owned)
        } else {
            None
        };
        base.unwrap_or(std::env::current_dir().map_err(|error| error.to_string())?)
            .join(path)
    };
    let resolved: PathBuf = path.canonicalize().map_err(|error| error.to_string())?;
    let file = std::fs::File::open(&resolved).map_err(|error| error.to_string())?;
    let metadata = file.metadata().map_err(|error| error.to_string())?;
    if !metadata.is_file() || metadata.len() > 4 * 1024 * 1024 {
        return Err("module must be a regular file no larger than 4 MiB".into());
    }
    let mut source = String::new();
    use std::io::Read;
    file.take(4 * 1024 * 1024 + 1)
        .read_to_string(&mut source)
        .map_err(|error| error.to_string())?;
    if source.len() > 4 * 1024 * 1024 {
        return Err("module exceeds 4 MiB".into());
    }
    Ok((source, resolved.to_string_lossy().into_owned()))
}

fn now() -> UnixTs {
    UnixTs(
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64,
    )
}
fn diagnostic(code: &str, message: impl Into<String>) -> Value {
    json!({"error":{"code":code,"message":message.into()}})
}
fn storage_message(message: impl Into<String>) -> HarnessError {
    HarnessError::new(HarnessErrorCode::StorageError, message)
}
fn storage_error(error: DbError) -> HarnessError {
    storage_message(error.to_string())
}
fn host_db_error(error: DbError) -> HostError {
    HostError {
        message: error.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use selvedge_command_model::ToolExecutionRunId;
    use selvedge_test_support::db::{create_root_task_with_user_message_and_tools, open_memory_db};

    #[tokio::test]
    async fn failed_engine_initialization_still_finalizes_an_admitted_invocation() {
        let db = open_memory_db();
        let task_id = TaskId("root".into());
        create_root_task_with_user_message_and_tools(
            &db,
            "root",
            "test",
            harness_tool_catalog(&Default::default()),
            now(),
        );
        let function_call_id = FunctionCallId("call".into());
        let tool_name = ToolName(EXEC_CMD_TOOL_NAME.into());
        let arguments = JsonObject::from_iter([("code".into(), json!("42"))]);
        let function_call_node_id = append_model_reply_with_tool_calls_and_move_cursor(
            &db,
            &task_id,
            None,
            vec![NewFunctionCallNodeContent {
                function_call_id: function_call_id.clone(),
                tool_name: tool_name.clone(),
                arguments: arguments.clone(),
            }],
            now(),
        )
        .expect("open command call")[0];
        let invocation = CommandInvocationId {
            task_id: task_id.clone(),
            function_call_node_id,
        };
        admit_command_invocation(&db, &invocation, &function_call_id, &tool_name)
            .expect("admit interrupted invocation");
        let child = TaskId("child".into());
        let context = CommandOperationContext {
            caller_task_id: task_id.clone(),
            mode: ToolExecutionMode::Normal,
            operation: Some(CommandOperation {
                id: CommandOperationId {
                    invocation,
                    ordinal: 0,
                },
                command: "tasks.fork".into(),
                arguments: json!({"child_count":1,"environment":"new"}),
            }),
        };
        create_pending_command_children(
            &db,
            &context,
            vec![(child.clone(), vec![])],
            CommandEnvironmentMode::New,
            now(),
        )
        .expect("stage child before engine becomes unavailable");
        let manager = CommandEnvironmentManager {
            runtime: Arc::new(Err("injected engine initialization failure".into())),
            leases: Arc::new(Mutex::new(BTreeMap::new())),
        };
        let request = ToolExecutionRequest {
            task_id: task_id.clone(),
            function_call_node_id,
            function_call_id: function_call_id.clone(),
            tool_name: tool_name.clone(),
            arguments,
            execution_mode: ToolExecutionMode::Startup,
            tool_execution_run_id: ToolExecutionRunId("retry".into()),
        };
        let (tx, _rx) = tokio::sync::mpsc::unbounded_channel();
        let result = execute_routed_request(
            db.clone(),
            McpConnectionSet::default(),
            manager,
            request,
            tx.downgrade(),
        )
        .await
        .expect("prepare recovery error without engine");
        assert!(result.branches[0].is_error);
        let prepared = result
            .prepared_environment
            .expect("retain environment lease for finalization");
        commit_tool_result_branches_with_environment(
            &db,
            CommitToolResultBranchesInput {
                calling_task_id: task_id.clone(),
                function_call_node_id,
                function_call_id,
                tool_name,
                now: now(),
                branches: vec![ToolResultBranch {
                    target: ToolResultBranchTarget::CallingTask,
                    output: result.branches[0].output.clone(),
                    is_error: true,
                    user_messages: vec![],
                }],
            },
            &prepared.commit,
        )
        .expect("finalize interrupted invocation without an engine");
        assert!(
            read_command_environment(&db, &task_id)
                .expect("root environment")
                .admitted_invocation
                .is_none()
        );
        assert!(!task_is_pending(&db, &child).expect("published child"));
        assert!(
            read_command_environment(&db, &child)
                .expect("new child lazy environment")
                .checkpoint
                .is_empty()
        );
    }
}
