#![doc = include_str!("../README.md")]

use std::collections::{BTreeSet, HashMap, HashSet, VecDeque};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use selvedge_command_model::{
    ApiCallCorrelation, ApiEffectId, ApiOutputEnvelope, CoreOutputEnvelope, CoreOutputMessage,
    DomainEvent, DomainEventPublishRequest, ModelCallDispatchRequest, ModelRunId,
    RouterIngressMessage, RouterIngressWeakSender, SendUserInputOutcome, SendUserInputResponder,
    TaskCommandError, TaskRuntimeCommand, TaskRuntimeControl, TaskRuntimeExitNotice,
    TaskRuntimeExitReason, TaskRuntimeSender, TaskRuntimeShutdownResult, TaskStatus,
    ToolExecutionBranchTarget, ToolExecutionRequest, ToolExecutionResult, ToolExecutionRunId,
};
use selvedge_db::{
    CommitToolResultBranchesInput, DbError, DbPool, FunctionCallId, HistoryNode, HistoryNodeId,
    MessageRole, NewFunctionCallNodeContent, TaskId, ToolName, ToolRecoveryPolicy,
    ToolResultBranch, ToolResultBranchTarget, UnixTs, append_assistant_message_and_drain_queue,
    append_model_reply_with_tool_calls_and_move_cursor, append_user_message_and_move_cursor,
    commit_tool_result_branches, drain_queued_user_inputs_and_move_cursor, load_runtime_task,
    queue_user_input, read_conversation_for_task, read_open_function_calls_for_task,
    read_task_status, read_task_tool_state,
};
use selvedge_domain_model::{
    CallableTools, Conversation, FUNCTION_CALL_CONTENT_TYPE, FUNCTION_OUTPUT_CONTENT_TYPE,
    JsonObject, ModelProfileKey, ModelProviderProfile, ResponsePreference, ToolCallProposal,
    ToolManifest,
};
use serde_json::Value;
use uuid::Uuid;

#[derive(Clone, Debug, PartialEq)]
pub struct TaskRuntimeConfig {
    pub model_profiles: HashMap<ModelProfileKey, ModelProviderProfile>,
}

#[derive(Clone)]
pub struct TaskRuntimeSpawnDeps {
    pub config: TaskRuntimeConfig,
    pub spawner: Arc<dyn TaskRuntimeSpawner>,
}

impl TaskRuntimeSpawnDeps {
    pub fn new(config: TaskRuntimeConfig) -> Self {
        Self {
            config,
            spawner: Arc::new(DefaultTaskRuntimeSpawner),
        }
    }

    pub fn with_spawner(config: TaskRuntimeConfig, spawner: Arc<dyn TaskRuntimeSpawner>) -> Self {
        Self { config, spawner }
    }
}

pub trait TaskRuntimeSpawner: Send + Sync {
    fn spawn_task_runtime(
        &self,
        args: SpawnTaskRuntimeArgs,
    ) -> Result<SpawnedTaskRuntime, SpawnTaskRuntimeError>;
}

#[derive(Clone, Debug)]
pub struct DefaultTaskRuntimeSpawner;

impl TaskRuntimeSpawner for DefaultTaskRuntimeSpawner {
    fn spawn_task_runtime(
        &self,
        args: SpawnTaskRuntimeArgs,
    ) -> Result<SpawnedTaskRuntime, SpawnTaskRuntimeError> {
        spawn_task_runtime(args)
    }
}

#[derive(Clone)]
pub struct SpawnTaskRuntimeArgs {
    pub task_id: TaskId,
    pub db: DbPool,
    pub router_tx: RouterIngressWeakSender,
    pub config: TaskRuntimeConfig,
}

#[derive(Debug)]
pub struct SpawnedTaskRuntime {
    pub task_id: TaskId,
    pub task_runtime_tx: TaskRuntimeSender,
    pub task_runtime_control: TaskRuntimeControl,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SpawnTaskRuntimeError {
    TokioSpawnFailed,
}

pub fn spawn_task_runtime(
    args: SpawnTaskRuntimeArgs,
) -> Result<SpawnedTaskRuntime, SpawnTaskRuntimeError> {
    let (task_runtime_tx, task_runtime_rx) = tokio::sync::mpsc::unbounded_channel();
    let task_runtime_control = TaskRuntimeControl::new();
    let spawned = SpawnedTaskRuntime {
        task_id: args.task_id.clone(),
        task_runtime_tx: task_runtime_tx.clone(),
        task_runtime_control: task_runtime_control.clone(),
    };

    let actor = TaskRuntimeActor {
        task_id: args.task_id,
        task_runtime_control,
        db: args.db,
        router_tx: args.router_tx,
        rx: task_runtime_rx,
        started: false,
        cursor_started: false,
        task_status: None,
        deferred_model_call: false,
        model_profiles: args.config.model_profiles,
        wait_state: WaitState::AwaitingUserInput,
        terminal_task_error: None,
    };
    tokio::spawn(actor.run());

    Ok(spawned)
}

struct TaskRuntimeActor {
    task_id: TaskId,
    task_runtime_control: TaskRuntimeControl,
    db: DbPool,
    router_tx: RouterIngressWeakSender,
    rx: tokio::sync::mpsc::UnboundedReceiver<TaskRuntimeCommand>,
    started: bool,
    cursor_started: bool,
    task_status: Option<TaskStatus>,
    deferred_model_call: bool,
    model_profiles: HashMap<ModelProfileKey, ModelProviderProfile>,
    wait_state: WaitState,
    terminal_task_error: Option<TaskCommandError>,
}

#[derive(Clone, Debug, PartialEq)]
enum WaitState {
    AwaitingUserInput,
    WaitingModelReply {
        model_run_id: ModelRunId,
        tool_manifest: ToolManifest,
        callable_tools: CallableTools,
    },
    WaitingToolResult {
        tool_run_id: ToolExecutionRunId,
        active_tool_call: PendingToolCall,
        pending_tool_calls: VecDeque<PendingToolCall>,
    },
}

#[derive(Clone, Debug, PartialEq)]
struct ValidatedToolCall {
    function_call_id: FunctionCallId,
    tool_name: ToolName,
    arguments: JsonObject,
}

#[derive(Clone, Debug, PartialEq)]
struct PendingToolCall {
    function_call_node_id: HistoryNodeId,
    function_call_id: FunctionCallId,
    tool_name: ToolName,
    arguments: JsonObject,
}

impl TaskRuntimeActor {
    async fn run(mut self) {
        let mut shutdown_exit = false;
        loop {
            if self.task_runtime_control.is_shutdown_requested() {
                shutdown_exit = true;
                break;
            }
            let command = if self.started && self.task_status == Some(TaskStatus::Frozen) {
                self.task_runtime_control.wait_for_control_change().await;
                if self.task_runtime_control.is_shutdown_requested() {
                    shutdown_exit = true;
                    break;
                }
                if self.handle_status_changed().await {
                    break;
                }
                continue;
            } else {
                tokio::select! {
                    biased;
                    _ = self.task_runtime_control.wait_for_control_change() => {
                        if self.task_runtime_control.is_shutdown_requested() {
                            shutdown_exit = true;
                            break;
                        }
                        if self.handle_status_changed().await {
                            break;
                        }
                        continue;
                    },
                    command = self.rx.recv() => {
                        let Some(command) = command else {
                            shutdown_exit = true;
                            break;
                        };
                        command
                    }
                }
            };
            if self.task_runtime_control.is_shutdown_requested() {
                shutdown_exit = true;
                break;
            }
            let should_stop = match command {
                TaskRuntimeCommand::Start => self.handle_start().await,
                TaskRuntimeCommand::UserInput {
                    message_text,
                    responder,
                } => self.handle_user_input(message_text, responder).await,
                TaskRuntimeCommand::ModelCallNotStarted { correlation } => {
                    self.handle_model_call_not_started(correlation).await
                }
                TaskRuntimeCommand::ApiModelReply(envelope) => {
                    self.handle_model_reply(envelope).await
                }
                TaskRuntimeCommand::ToolResult(result) => self.handle_tool_result(result).await,
            };

            if should_stop {
                break;
            }
        }
        if shutdown_exit {
            self.send_exit(TaskRuntimeExitReason::Shutdown).await;
        }
        self.rx.close();
        let terminal_error = self
            .terminal_task_error
            .unwrap_or(TaskCommandError::RuntimeUnavailable);
        while let Some(command) = self.rx.recv().await {
            settle_task_runtime_command(command, terminal_error);
        }
        self.task_runtime_control
            .finish_shutdown(TaskRuntimeShutdownResult)
            .await;
    }

    async fn handle_start(&mut self) -> bool {
        if self.started {
            return false;
        }
        match load_runtime_task(&self.db, &self.task_id) {
            Ok(loaded) => {
                self.started = true;
                self.task_status = Some(loaded.task.task_status);
                if self
                    .send_core(CoreOutputMessage::RuntimeReady)
                    .await
                    .is_err()
                {
                    return true;
                }
                if loaded.task.task_status == TaskStatus::Frozen {
                    false
                } else {
                    self.cursor_started = true;
                    self.start_from_cursor_tail(loaded).await
                }
            }
            Err(error) => self.stop_with_db_error(error).await,
        }
    }

    async fn handle_status_changed(&mut self) -> bool {
        let status = match read_task_status(&self.db, &self.task_id) {
            Ok(status) => status,
            Err(error) => return self.stop_with_db_error(error).await,
        };
        self.task_status = Some(status);
        if status == TaskStatus::Archived {
            self.terminal_task_error = Some(TaskCommandError::TaskArchived);
            self.send_exit(TaskRuntimeExitReason::Archived).await;
            return true;
        }
        if self.started && !self.cursor_started && status != TaskStatus::Frozen {
            let loaded = match load_runtime_task(&self.db, &self.task_id) {
                Ok(loaded) => loaded,
                Err(error) => return self.stop_with_db_error(error).await,
            };
            self.cursor_started = true;
            return self.start_from_cursor_tail(loaded).await;
        }
        if status == TaskStatus::Active && self.deferred_model_call {
            return self.request_model_call().await;
        }
        false
    }

    async fn start_from_cursor_tail(&mut self, loaded: selvedge_db::LoadedRuntimeTask) -> bool {
        match read_open_function_calls_for_task(&self.db, &self.task_id) {
            Ok(open_calls) if !open_calls.is_empty() => {
                return self.recover_open_tool_calls(open_calls).await;
            }
            Ok(_) => {}
            Err(error) => return self.stop_with_db_error(error).await,
        }

        match loaded.cursor_node {
            HistoryNode::Message { message_role, .. } => match message_role {
                MessageRole::System | MessageRole::User => self.request_model_call().await,
                MessageRole::Assistant | MessageRole::Developer => {
                    self.enter_awaiting_user_input_or_promote_queue().await
                }
                MessageRole::Tool => {
                    self.stop_with_internal_error("tool message cannot be a task cursor tail")
                        .await
                }
            },
            HistoryNode::FunctionOutput { .. } => self.request_model_call().await,
            HistoryNode::FunctionCall {
                node_id,
                function_call_id,
                tool_name,
                arguments,
                ..
            } => {
                self.dispatch_tool_call(
                    PendingToolCall {
                        function_call_node_id: node_id,
                        function_call_id,
                        tool_name,
                        arguments,
                    },
                    VecDeque::new(),
                )
                .await
            }
            HistoryNode::Reasoning { .. } => {
                self.stop_with_internal_error("reasoning cannot be a task cursor tail")
                    .await
            }
        }
    }

    async fn recover_open_tool_calls(
        &mut self,
        open_calls: Vec<selvedge_db::OpenFunctionCall>,
    ) -> bool {
        let mut pending_tool_calls = VecDeque::new();
        for call in open_calls {
            let tool_call = PendingToolCall {
                function_call_node_id: call.function_call_node_id,
                function_call_id: call.function_call_id,
                tool_name: call.tool_name,
                arguments: call.arguments,
            };
            match call.recovery_policy {
                ToolRecoveryPolicy::RetrySafe => pending_tool_calls.push_back(tool_call),
                ToolRecoveryPolicy::OutcomeUnknown => {
                    if let Err(error) = commit_tool_result_branches(
                        &self.db,
                        CommitToolResultBranchesInput {
                            calling_task_id: self.task_id.clone(),
                            function_call_node_id: tool_call.function_call_node_id,
                            function_call_id: tool_call.function_call_id,
                            tool_name: tool_call.tool_name,
                            branches: vec![ToolResultBranch {
                                target: ToolResultBranchTarget::CallingTask,
                                output: interrupted_tool_call_output(),
                                is_error: true,
                                user_messages: Vec::new(),
                            }],
                            now: now(),
                        },
                    ) {
                        return self.stop_with_db_error(error).await;
                    }
                }
            }
        }
        let Some(tool_call) = pending_tool_calls.pop_front() else {
            return self.request_model_call().await;
        };
        self.dispatch_tool_call(tool_call, pending_tool_calls).await
    }

    async fn enter_awaiting_user_input_or_promote_queue(&mut self) -> bool {
        match drain_queued_user_inputs_and_move_cursor(&self.db, &self.task_id, now()) {
            Ok(Some(_)) => self.request_model_call().await,
            Ok(None) => {
                self.wait_state = WaitState::AwaitingUserInput;
                false
            }
            Err(error) => self.stop_with_db_error(error).await,
        }
    }

    async fn handle_user_input(
        &mut self,
        message_text: String,
        responder: SendUserInputResponder,
    ) -> bool {
        if message_text.is_empty() {
            responder.settle(Err(TaskCommandError::InvalidCommand));
            return self
                .stop_with_internal_error("user input must not be empty")
                .await;
        }

        match self.wait_state {
            WaitState::AwaitingUserInput => match self.append_user_message(message_text) {
                Ok(node_id) => {
                    responder.settle(Ok(SendUserInputOutcome::Committed { node_id }));
                    self.request_model_call().await
                }
                Err(error) => {
                    responder.settle(Err(task_command_db_error(&error)));
                    self.stop_with_db_error(error).await
                }
            },
            WaitState::WaitingModelReply { .. } | WaitState::WaitingToolResult { .. } => {
                match queue_user_input(&self.db, &self.task_id, message_text, now()) {
                    Ok(_) => {
                        responder.settle(Ok(SendUserInputOutcome::Queued));
                        false
                    }
                    Err(error) => {
                        responder.settle(Err(task_command_db_error(&error)));
                        self.stop_with_db_error(error).await
                    }
                }
            }
        }
    }

    async fn handle_model_reply(&mut self, envelope: ApiOutputEnvelope) -> bool {
        let (expected_model_run_id, tool_manifest, callable_tools) = match &self.wait_state {
            WaitState::WaitingModelReply {
                model_run_id,
                tool_manifest,
                callable_tools,
            } => (
                model_run_id.clone(),
                tool_manifest.clone(),
                callable_tools.clone(),
            ),
            WaitState::AwaitingUserInput | WaitState::WaitingToolResult { .. } => return false,
        };

        match envelope {
            ApiOutputEnvelope::Success { correlation, reply } => {
                if correlation.task_id != self.task_id
                    || correlation.model_run_id != expected_model_run_id
                {
                    return false;
                }
                let validated_tool_calls = if reply.tool_calls.is_empty() {
                    VecDeque::new()
                } else {
                    match validate_tool_calls(reply.tool_calls, &tool_manifest, &callable_tools) {
                        Ok(tool_calls) => tool_calls,
                        Err(message) => return self.stop_with_internal_error(&message).await,
                    }
                };

                if validated_tool_calls.is_empty() {
                    let Some(content) = reply.content.filter(|content| !content.trim().is_empty())
                    else {
                        return self
                            .stop_with_internal_error("model reply has no terminal history node")
                            .await;
                    };
                    let had_queued_inputs = match load_runtime_task(&self.db, &self.task_id) {
                        Ok(loaded) => !loaded.queued_inputs.is_empty(),
                        Err(error) => return self.stop_with_db_error(error).await,
                    };
                    match append_assistant_message_and_drain_queue(
                        &self.db,
                        &self.task_id,
                        content,
                        now(),
                    ) {
                        Ok(_) if had_queued_inputs => self.request_model_call().await,
                        Ok(_) => self.enter_awaiting_user_input_or_promote_queue().await,
                        Err(error) => self.stop_with_db_error(error).await,
                    }
                } else {
                    let assistant_message_text =
                        reply.content.filter(|content| !content.trim().is_empty());
                    match self.append_tool_calls(assistant_message_text, validated_tool_calls) {
                        Ok(mut pending_tool_calls) => {
                            let tool_call = pending_tool_calls
                                .pop_front()
                                .expect("validated tool calls cannot be empty here");
                            self.dispatch_tool_call(tool_call, pending_tool_calls).await
                        }
                        Err(error) => self.stop_with_db_error(error).await,
                    }
                }
            }
            ApiOutputEnvelope::Failure { correlation, error } => {
                if correlation.task_id != self.task_id
                    || correlation.model_run_id != expected_model_run_id
                {
                    return false;
                }
                self.wait_state = WaitState::AwaitingUserInput;
                let promoted_queued_input = match drain_queued_user_inputs_and_move_cursor(
                    &self.db,
                    &self.task_id,
                    now(),
                ) {
                    Ok(node_id) => node_id.is_some(),
                    Err(error) => return self.stop_with_db_error(error).await,
                };
                if self
                    .send_core(CoreOutputMessage::PublishDomainEvent(
                        DomainEventPublishRequest {
                            task_id: self.task_id.clone(),
                            event: DomainEvent::ErrorNotice {
                                message: format!(
                                    "model call failed: {:?}: {}",
                                    error.kind, error.message
                                ),
                            },
                        },
                    ))
                    .await
                    .is_err()
                {
                    return true;
                }
                if promoted_queued_input {
                    self.request_model_call().await
                } else {
                    self.enter_awaiting_user_input_or_promote_queue().await
                }
            }
        }
    }

    async fn handle_model_call_not_started(&mut self, correlation: ApiCallCorrelation) -> bool {
        let WaitState::WaitingModelReply { model_run_id, .. } = &self.wait_state else {
            return false;
        };
        if correlation.task_id != self.task_id || correlation.model_run_id != *model_run_id {
            return false;
        }

        self.wait_state = WaitState::AwaitingUserInput;
        match read_task_status(&self.db, &self.task_id) {
            Ok(TaskStatus::Active) => self.request_model_call().await,
            Ok(TaskStatus::Frozen) => {
                self.task_status = Some(TaskStatus::Frozen);
                self.deferred_model_call = true;
                false
            }
            Ok(TaskStatus::Stopped) => self.enter_stopped_without_model_call().await,
            Ok(TaskStatus::Archived) => {
                self.task_status = Some(TaskStatus::Archived);
                self.terminal_task_error = Some(TaskCommandError::TaskArchived);
                self.send_exit(TaskRuntimeExitReason::Archived).await;
                true
            }
            Err(error) => self.stop_with_db_error(error).await,
        }
    }

    async fn handle_tool_result(&mut self, result: ToolExecutionResult) -> bool {
        let pending_tool_calls =
            match std::mem::replace(&mut self.wait_state, WaitState::AwaitingUserInput) {
                WaitState::WaitingToolResult {
                    tool_run_id,
                    active_tool_call,
                    pending_tool_calls,
                } if result.task_id == self.task_id
                    && result.tool_execution_run_id == tool_run_id
                    && result.function_call_node_id == active_tool_call.function_call_node_id
                    && result.function_call_id == active_tool_call.function_call_id
                    && result.tool_name == active_tool_call.tool_name =>
                {
                    pending_tool_calls
                }
                wait_state @ WaitState::WaitingToolResult { .. } => {
                    self.wait_state = wait_state;
                    return false;
                }
                wait_state @ (WaitState::AwaitingUserInput
                | WaitState::WaitingModelReply { .. }) => {
                    self.wait_state = wait_state;
                    return false;
                }
            };

        let function_call_node_id = result.function_call_node_id;
        let function_call_id = result.function_call_id;
        let tool_name = result.tool_name;
        let commit_result = commit_tool_result_branches(
            &self.db,
            CommitToolResultBranchesInput {
                calling_task_id: self.task_id.clone(),
                function_call_node_id,
                function_call_id: function_call_id.clone(),
                tool_name: tool_name.clone(),
                branches: result
                    .branches
                    .into_iter()
                    .map(|branch| ToolResultBranch {
                        target: match branch.target {
                            ToolExecutionBranchTarget::CallingTask => {
                                ToolResultBranchTarget::CallingTask
                            }
                            ToolExecutionBranchTarget::NewChildTask { task_id } => {
                                ToolResultBranchTarget::NewChildTask(task_id)
                            }
                        },
                        output: branch.output,
                        is_error: branch.is_error,
                        user_messages: branch.messages,
                    })
                    .collect(),
                now: now(),
            },
        );
        let commit_result = match commit_result {
            Err(DbError::TaskDescendantLimitExceeded { task_id, limit }) => {
                commit_tool_result_branches(
                    &self.db,
                    CommitToolResultBranchesInput {
                        calling_task_id: self.task_id.clone(),
                        function_call_node_id,
                        function_call_id,
                        tool_name,
                        branches: vec![ToolResultBranch {
                            target: ToolResultBranchTarget::CallingTask,
                            output: task_descendant_limit_output(&task_id, limit),
                            is_error: true,
                            user_messages: Vec::new(),
                        }],
                        now: now(),
                    },
                )
            }
            result => result,
        };
        match commit_result {
            Ok(committed) => {
                if !committed.created_child_task_ids.is_empty()
                    && self
                        .send_core(CoreOutputMessage::EnsureTaskRuntimes {
                            task_ids: committed.created_child_task_ids,
                        })
                        .await
                        .is_err()
                {
                    return true;
                }
                self.dispatch_next_tool_or_request_model(pending_tool_calls)
                    .await
            }
            Err(error) => self.stop_with_db_error(error).await,
        }
    }

    fn append_user_message(&mut self, message_text: String) -> Result<HistoryNodeId, DbError> {
        append_user_message_and_move_cursor(&self.db, &self.task_id, message_text, now())
    }

    async fn request_model_call(&mut self) -> bool {
        if let Some(should_stop) = self.stop_or_defer_model_call_if_inactive().await {
            return should_stop;
        }

        let db = self.db.clone();
        let task_id = self.task_id.clone();
        let context = tokio::task::spawn_blocking(move || {
            let conversation = read_conversation_for_task(&db, &task_id)?;
            let tool_state = read_task_tool_state(&db, &task_id)?;
            let loaded = load_runtime_task(&db, &task_id)?;
            Ok::<_, DbError>((conversation, tool_state, loaded.task.model_profile_key))
        })
        .await;
        let (conversation, tool_state, model_profile_key) = match context {
            Ok(Ok(context)) => context,
            Ok(Err(error)) => return self.stop_with_db_error(error).await,
            Err(error) => {
                return self
                    .stop_with_internal_error(&format!("database worker failed: {error}"))
                    .await;
            }
        };
        if let Some(should_stop) = self.stop_or_defer_model_call_if_inactive().await {
            return should_stop;
        }
        if let Err(message) = validate_conversation_tool_pairs(&conversation) {
            return self.stop_with_internal_error(&message).await;
        }
        let model_run_id = ModelRunId(format!("{}-model-{}", self.task_id.0, Uuid::new_v4()));
        let Some(provider) = self.model_profiles.get(&model_profile_key).cloned() else {
            return self
                .stop_with_internal_error("model profile key is not configured")
                .await;
        };
        let tool_manifest = tool_state.manifest;
        let callable_tools =
            callable_tools_for_manifest(&tool_manifest, tool_state.unavailable_tools);
        let request = ModelCallDispatchRequest {
            correlation: selvedge_command_model::ApiCallCorrelation {
                api_effect_id: ApiEffectId(format!("{}-api-{}", self.task_id.0, Uuid::new_v4())),
                task_id: self.task_id.clone(),
                model_run_id: model_run_id.clone(),
            },
            provider,
            conversation,
            tool_manifest: Some(tool_manifest.clone()),
            callable_tools: callable_tools.clone(),
            response_preference: ResponsePreference::PlainTextOrToolCalls,
        };
        self.wait_state = WaitState::WaitingModelReply {
            model_run_id,
            tool_manifest,
            callable_tools,
        };
        self.send_core(CoreOutputMessage::RequestModelCall(request))
            .await
            .is_err()
    }

    async fn stop_or_defer_model_call_if_inactive(&mut self) -> Option<bool> {
        let status = match read_task_status(&self.db, &self.task_id) {
            Ok(status) => status,
            Err(error) => return Some(self.stop_with_db_error(error).await),
        };
        self.task_status = Some(status);
        match status {
            TaskStatus::Active => {
                self.deferred_model_call = false;
                None
            }
            TaskStatus::Frozen => {
                self.deferred_model_call = true;
                self.wait_state = WaitState::AwaitingUserInput;
                Some(false)
            }
            TaskStatus::Stopped => Some(self.enter_stopped_without_model_call().await),
            TaskStatus::Archived => {
                self.terminal_task_error = Some(TaskCommandError::TaskArchived);
                self.send_exit(TaskRuntimeExitReason::Archived).await;
                Some(true)
            }
        }
    }

    async fn enter_stopped_without_model_call(&mut self) -> bool {
        self.task_status = Some(TaskStatus::Stopped);
        self.deferred_model_call = false;
        self.wait_state = WaitState::AwaitingUserInput;
        match drain_queued_user_inputs_and_move_cursor(&self.db, &self.task_id, now()) {
            Ok(_) => false,
            Err(error) => self.stop_with_db_error(error).await,
        }
    }

    fn append_tool_calls(
        &mut self,
        assistant_message_text: Option<String>,
        tool_calls: VecDeque<ValidatedToolCall>,
    ) -> Result<VecDeque<PendingToolCall>, DbError> {
        // A model turn can emit several tool calls at once. Persist every call
        // from that turn in one DB transaction before any tool output so the
        // provider path keeps the reply batch as durable history.
        let tool_calls = tool_calls.into_iter().collect::<Vec<_>>();
        let function_call_node_ids = append_model_reply_with_tool_calls_and_move_cursor(
            &self.db,
            &self.task_id,
            assistant_message_text,
            tool_calls
                .iter()
                .map(|tool_call| NewFunctionCallNodeContent {
                    function_call_id: tool_call.function_call_id.clone(),
                    tool_name: tool_call.tool_name.clone(),
                    arguments: tool_call.arguments.clone(),
                })
                .collect(),
            now(),
        )?;
        let pending_tool_calls = function_call_node_ids
            .into_iter()
            .zip(tool_calls)
            .map(|(node_id, tool_call)| PendingToolCall {
                function_call_node_id: node_id,
                function_call_id: tool_call.function_call_id,
                tool_name: tool_call.tool_name,
                arguments: tool_call.arguments,
            })
            .collect();
        Ok(pending_tool_calls)
    }

    async fn dispatch_tool_call(
        &mut self,
        tool_call: PendingToolCall,
        pending_tool_calls: VecDeque<PendingToolCall>,
    ) -> bool {
        let tool_run_id = ToolExecutionRunId(format!("{}-tool-{}", self.task_id.0, Uuid::new_v4()));
        let request = ToolExecutionRequest {
            task_id: self.task_id.clone(),
            tool_execution_run_id: tool_run_id.clone(),
            function_call_node_id: tool_call.function_call_node_id,
            function_call_id: tool_call.function_call_id.clone(),
            tool_name: tool_call.tool_name.clone(),
            arguments: tool_call.arguments.clone(),
        };
        self.wait_state = WaitState::WaitingToolResult {
            tool_run_id,
            active_tool_call: tool_call,
            pending_tool_calls,
        };
        self.send_core(CoreOutputMessage::RequestToolExecution(request))
            .await
            .is_err()
    }

    async fn dispatch_next_tool_or_request_model(
        &mut self,
        mut pending_tool_calls: VecDeque<PendingToolCall>,
    ) -> bool {
        if let Some(tool_call) = pending_tool_calls.pop_front() {
            self.dispatch_tool_call(tool_call, pending_tool_calls).await
        } else {
            self.request_model_call().await
        }
    }

    async fn send_core(&self, message: CoreOutputMessage) -> Result<(), ()> {
        let Some(router_tx) = self.router_tx.upgrade() else {
            return Err(());
        };
        router_tx
            .send(RouterIngressMessage::Core(CoreOutputEnvelope {
                task_id: self.task_id.clone(),
                message,
            }))
            .map_err(|_| ())
    }

    async fn send_exit(&self, reason: TaskRuntimeExitReason) {
        let Some(router_tx) = self.router_tx.upgrade() else {
            return;
        };
        let _ = router_tx.send(RouterIngressMessage::RuntimeExit(TaskRuntimeExitNotice {
            task_id: self.task_id.clone(),
            task_runtime_control: self.task_runtime_control.clone(),
            reason,
        }));
    }

    async fn stop_with_db_error(&mut self, error: DbError) -> bool {
        self.terminal_task_error = Some(task_command_db_error(&error));
        self.send_exit(TaskRuntimeExitReason::DbError(error.to_string()))
            .await;
        true
    }

    async fn stop_with_internal_error(&mut self, message: &str) -> bool {
        self.terminal_task_error = Some(TaskCommandError::RuntimeUnavailable);
        self.send_exit(TaskRuntimeExitReason::InternalError(message.to_owned()))
            .await;
        true
    }
}

fn task_command_db_error(error: &DbError) -> TaskCommandError {
    match error {
        DbError::NotFound => TaskCommandError::TaskMissing,
        DbError::InvalidTaskStatus {
            status: TaskStatus::Archived,
        } => TaskCommandError::TaskArchived,
        DbError::InvalidTaskStatus { status } => {
            TaskCommandError::InvalidTaskStatus { status: *status }
        }
        DbError::StaleFunctionCall
        | DbError::HistoryCursorNotOnTask
        | DbError::ToolUnavailable
        | DbError::TaskDescendantLimitExceeded { .. }
        | DbError::Constraint(_)
        | DbError::Storage(_)
        | DbError::SchemaMismatch { .. } => TaskCommandError::PersistenceFailed,
    }
}

fn task_descendant_limit_output(task_id: &TaskId, limit: u32) -> Value {
    serde_json::json!({
        "error": {
            "code": "task_descendant_limit_exceeded",
            "message": format!("task '{}' cannot exceed {limit} descendants", task_id.0),
        }
    })
}

fn interrupted_tool_call_output() -> Value {
    serde_json::json!({
        "error": {
            "code": "tool_outcome_unknown_after_interruption",
            "message": "The tool call was interrupted before a result was committed for this task branch. Whether it took effect is unknown. Inspect the relevant state and invoke the tool again only if needed. Do not report this internal recovery notice unless unresolved uncertainty prevents completing the task; continue the task."
        }
    })
}

fn settle_task_runtime_command(command: TaskRuntimeCommand, error: TaskCommandError) {
    match command {
        TaskRuntimeCommand::UserInput { responder, .. } => responder.settle(Err(error)),
        TaskRuntimeCommand::Start
        | TaskRuntimeCommand::ModelCallNotStarted { .. }
        | TaskRuntimeCommand::ApiModelReply(_)
        | TaskRuntimeCommand::ToolResult(_) => {}
    }
}

fn validate_conversation_tool_pairs(conversation: &Conversation) -> Result<(), String> {
    let mut pending_tool_calls = HashMap::new();

    for message in &conversation.messages {
        match message.content_type() {
            Some(FUNCTION_CALL_CONTENT_TYPE) => {
                let function_call_id = message.function_call_id().ok_or_else(|| {
                    "conversation tool call is missing function_call_id".to_owned()
                })?;
                let tool_name = message
                    .tool_name()
                    .ok_or_else(|| "conversation tool call is missing tool_name".to_owned())?;
                if message.function_call_arguments().is_none() {
                    return Err("conversation tool call is missing arguments".to_owned());
                }
                if pending_tool_calls
                    .insert(function_call_id.to_owned(), tool_name.to_owned())
                    .is_some()
                {
                    return Err("conversation contains duplicate open tool call id".to_owned());
                }
            }
            Some(FUNCTION_OUTPUT_CONTENT_TYPE) => {
                let function_call_id = message.function_call_id().ok_or_else(|| {
                    "conversation tool output is missing function_call_id".to_owned()
                })?;
                let tool_name = message
                    .tool_name()
                    .ok_or_else(|| "conversation tool output is missing tool_name".to_owned())?;
                if message.function_output_value().is_none()
                    || message.function_output_is_error().is_none()
                {
                    return Err("conversation tool output is incomplete".to_owned());
                }
                let Some(expected_tool_name) = pending_tool_calls.remove(function_call_id) else {
                    return Err(
                        "conversation contains tool output without matching call".to_owned()
                    );
                };
                if expected_tool_name != tool_name {
                    return Err("conversation contains tool output with mismatched tool".to_owned());
                }
            }
            _ => {}
        }
    }

    // Provider APIs correlate tool outputs by call id. Core only checks that
    // every output in the selected conversation path has a matching prior
    // call, and that every call has one matching output before dispatch. The
    // meaning of messages between those two nodes belongs to the persisted
    // history path and provider adapter policy, not to task runtime state.
    if pending_tool_calls.is_empty() {
        Ok(())
    } else {
        Err("conversation contains tool call without matching output".to_owned())
    }
}

fn validate_tool_calls(
    tool_calls: Vec<ToolCallProposal>,
    tool_manifest: &ToolManifest,
    callable_tools: &CallableTools,
) -> Result<VecDeque<ValidatedToolCall>, String> {
    // A provider reply is accepted as one unit. Validate and normalize every
    // requested tool call before persisting the first function_call node or
    // dispatching the first tool, so a malformed later call cannot leave
    // earlier side effects behind.
    let mut seen_call_ids = HashSet::new();
    let mut validated = VecDeque::new();
    for tool_call in tool_calls {
        if !seen_call_ids.insert(tool_call.call_id.clone()) {
            return Err("model reply contains duplicate tool call id".to_owned());
        }
        let tool_name = ToolName(tool_call.tool_name);
        if !tool_manifest
            .tools
            .iter()
            .any(|tool| tool.name == tool_name.0)
        {
            return Err(format!("tool is not enabled for task: {}", tool_name.0));
        }
        if let CallableTools::Only(callable_tools) = callable_tools
            && !callable_tools.contains(&tool_name)
        {
            return Err(format!(
                "tool was unavailable for model run: {}",
                tool_name.0
            ));
        }
        validated.push_back(ValidatedToolCall {
            function_call_id: FunctionCallId(tool_call.call_id),
            tool_name,
            arguments: tool_call.arguments,
        });
    }
    Ok(validated)
}

fn callable_tools_for_manifest(
    tool_manifest: &ToolManifest,
    unavailable_tools: Vec<ToolName>,
) -> CallableTools {
    if unavailable_tools.is_empty() {
        return CallableTools::All;
    }
    let unavailable_tools = unavailable_tools.into_iter().collect::<BTreeSet<_>>();
    CallableTools::Only(
        tool_manifest
            .tools
            .iter()
            .filter(|tool| !unavailable_tools.contains(&ToolName(tool.name.clone())))
            .map(|tool| ToolName(tool.name.clone()))
            .collect(),
    )
}

fn now() -> UnixTs {
    UnixTs(
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_secs() as i64)
            .unwrap_or(0),
    )
}
