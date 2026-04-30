#![doc = include_str!("../README.md")]

use std::collections::{BTreeMap, HashMap, HashSet, VecDeque};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use selvedge_command_model::{
    ApiEffectId, ApiOutputEnvelope, CoreOutputEnvelope, CoreOutputMessage, DomainEvent,
    DomainEventPublishRequest, ModelCallDispatchRequest, ModelRunId, RouterIngressMessage,
    RouterIngressSender, TaskRuntimeCommand, TaskRuntimeExitNotice, TaskRuntimeExitReason,
    TaskRuntimeSender, TaskRuntimeToken, ToolExecutionRequest, ToolExecutionResult,
    ToolExecutionRunId,
};
use selvedge_db::{
    DbError, DbPool, FunctionCallId, HistoryNode, HistoryNodeId, MessageRole,
    NewFunctionCallNodeContent, NewFunctionOutputNodeContent, TaskId, ToolArgumentValue,
    ToolCallArgument, ToolName, ToolParameterName, UnixTs,
    append_assistant_message_and_drain_queue, append_function_output_and_drain_queue,
    append_model_reply_with_tool_calls_and_move_cursor, append_user_message_and_move_cursor,
    archive_task, drain_queued_user_inputs_and_move_cursor, load_active_task, queue_user_input,
    read_conversation_for_task, read_open_function_calls_for_task, read_tool_manifest_for_task,
};
use selvedge_domain_model::{
    ConversationItem, ConversationMessage, ConversationPath, MessageContent, ModelProfileKey,
    ModelProviderProfile, ResponsePreference, StructuredPayload, ToolCallProposal, ToolManifest,
    ToolParameterType,
};
use uuid::Uuid;

#[derive(Clone, Debug, PartialEq)]
pub struct TaskRuntimeConfig {
    pub mailbox_capacity: usize,
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
    pub runtime_token: TaskRuntimeToken,
    pub db: DbPool,
    pub router_tx: RouterIngressSender,
    pub config: TaskRuntimeConfig,
}

#[derive(Debug)]
pub struct SpawnedTaskRuntime {
    pub task_id: TaskId,
    pub runtime_token: TaskRuntimeToken,
    pub task_runtime_tx: TaskRuntimeSender,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SpawnTaskRuntimeError {
    MailboxCreateFailed,
    TokioSpawnFailed,
}

pub fn spawn_task_runtime(
    args: SpawnTaskRuntimeArgs,
) -> Result<SpawnedTaskRuntime, SpawnTaskRuntimeError> {
    let capacity = args.config.mailbox_capacity.max(1);
    let (task_runtime_tx, task_runtime_rx) = tokio::sync::mpsc::channel(capacity);
    let spawned = SpawnedTaskRuntime {
        task_id: args.task_id.clone(),
        runtime_token: args.runtime_token.clone(),
        task_runtime_tx: task_runtime_tx.clone(),
    };

    let actor = TaskRuntimeActor {
        task_id: args.task_id,
        runtime_token: args.runtime_token,
        db: args.db,
        router_tx: args.router_tx,
        rx: task_runtime_rx,
        started: false,
        model_profiles: args.config.model_profiles,
        wait_state: WaitState::AwaitingUserInput,
    };
    tokio::spawn(actor.run());

    Ok(spawned)
}

struct TaskRuntimeActor {
    task_id: TaskId,
    runtime_token: TaskRuntimeToken,
    db: DbPool,
    router_tx: RouterIngressSender,
    rx: tokio::sync::mpsc::Receiver<TaskRuntimeCommand>,
    started: bool,
    model_profiles: HashMap<ModelProfileKey, ModelProviderProfile>,
    wait_state: WaitState,
}

#[derive(Clone, Debug, PartialEq)]
enum WaitState {
    AwaitingUserInput,
    WaitingModelReply {
        model_run_id: ModelRunId,
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
    arguments: Vec<ToolCallArgument>,
}

#[derive(Clone, Debug, PartialEq)]
struct PendingToolCall {
    function_call_node_id: HistoryNodeId,
    function_call_id: FunctionCallId,
    tool_name: ToolName,
    arguments: Vec<ToolCallArgument>,
}

impl TaskRuntimeActor {
    async fn run(mut self) {
        while let Some(command) = self.rx.recv().await {
            let should_stop = match command {
                TaskRuntimeCommand::Start => self.handle_start().await,
                TaskRuntimeCommand::UserInput { message_text } => {
                    self.handle_user_input(message_text).await
                }
                TaskRuntimeCommand::ApiModelReply(envelope) => {
                    self.handle_model_reply(envelope).await
                }
                TaskRuntimeCommand::ToolResult(result) => self.handle_tool_result(result).await,
                TaskRuntimeCommand::Archive => self.handle_archive().await,
                TaskRuntimeCommand::Stop => {
                    self.send_exit(TaskRuntimeExitReason::Stopped).await;
                    true
                }
            };

            if should_stop {
                break;
            }
        }
    }

    async fn handle_start(&mut self) -> bool {
        if self.started {
            return false;
        }
        match load_active_task(&self.db, &self.task_id) {
            Ok(loaded) => {
                self.started = true;
                if self
                    .send_core(CoreOutputMessage::RuntimeReady)
                    .await
                    .is_err()
                {
                    return true;
                }
                self.start_from_cursor_tail(loaded).await
            }
            Err(error) => {
                self.send_exit(TaskRuntimeExitReason::DbError(error.to_string()))
                    .await;
                true
            }
        }
    }

    async fn start_from_cursor_tail(&mut self, loaded: selvedge_db::LoadedActiveTask) -> bool {
        match read_open_function_calls_for_task(&self.db, &self.task_id) {
            Ok(open_calls) if !open_calls.is_empty() => {
                return self.dispatch_open_tool_calls(open_calls).await;
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

    async fn dispatch_open_tool_calls(
        &mut self,
        open_calls: Vec<selvedge_db::OpenFunctionCall>,
    ) -> bool {
        let mut pending_tool_calls = open_calls
            .into_iter()
            .map(|call| PendingToolCall {
                function_call_node_id: call.function_call_node_id,
                function_call_id: call.function_call_id,
                tool_name: call.tool_name,
                arguments: call.arguments,
            })
            .collect::<VecDeque<_>>();
        let Some(tool_call) = pending_tool_calls.pop_front() else {
            return false;
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

    async fn handle_user_input(&mut self, message_text: String) -> bool {
        if message_text.is_empty() {
            return self
                .stop_with_internal_error("user input must not be empty")
                .await;
        }

        match self.wait_state {
            WaitState::AwaitingUserInput => {
                self.commit_user_message_and_request_model(message_text)
                    .await
            }
            WaitState::WaitingModelReply { .. } | WaitState::WaitingToolResult { .. } => {
                match queue_user_input(&self.db, &self.task_id, message_text, now()) {
                    Ok(_) => false,
                    Err(error) => self.stop_with_db_error(error).await,
                }
            }
        }
    }

    async fn handle_model_reply(&mut self, envelope: ApiOutputEnvelope) -> bool {
        let expected_model_run_id = match &self.wait_state {
            WaitState::WaitingModelReply { model_run_id } => model_run_id.clone(),
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
                    let tool_manifest = match read_tool_manifest_for_task(&self.db, &self.task_id) {
                        Ok(tool_manifest) => tool_manifest,
                        Err(error) => return self.stop_with_db_error(error).await,
                    };
                    match validate_tool_calls(reply.tool_calls, &tool_manifest) {
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
                    let had_queued_inputs = match load_active_task(&self.db, &self.task_id) {
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

        match append_function_output_and_drain_queue(
            &self.db,
            &self.task_id,
            NewFunctionOutputNodeContent {
                function_call_node_id: result.function_call_node_id,
                function_call_id: result.function_call_id,
                tool_name: result.tool_name,
                output_text: result.output_text,
                is_error: result.is_error,
            },
            now(),
        ) {
            Ok(_) => {
                self.dispatch_next_tool_or_request_model(pending_tool_calls)
                    .await
            }
            Err(error) => self.stop_with_db_error(error).await,
        }
    }

    async fn handle_archive(&mut self) -> bool {
        match archive_task(&self.db, &self.task_id, now()) {
            Ok(()) => {
                self.send_exit(TaskRuntimeExitReason::Archived).await;
                true
            }
            Err(error) => self.stop_with_db_error(error).await,
        }
    }

    async fn commit_user_message_and_request_model(&mut self, message_text: String) -> bool {
        match self.append_user_message(message_text) {
            Ok(()) => self.request_model_call().await,
            Err(error) => self.stop_with_db_error(error).await,
        }
    }

    fn append_user_message(&mut self, message_text: String) -> Result<(), DbError> {
        append_user_message_and_move_cursor(&self.db, &self.task_id, message_text, now())
            .map(|_| ())
    }

    async fn request_model_call(&mut self) -> bool {
        let conversation = match read_conversation_for_task(&self.db, &self.task_id) {
            Ok(conversation) => conversation,
            Err(error) => return self.stop_with_db_error(error).await,
        };
        if let Err(message) = validate_conversation_tool_pairs(&conversation) {
            return self.stop_with_internal_error(&message).await;
        }
        let tool_manifest = match read_tool_manifest_for_task(&self.db, &self.task_id) {
            Ok(tool_manifest) => tool_manifest,
            Err(error) => return self.stop_with_db_error(error).await,
        };
        let loaded = match load_active_task(&self.db, &self.task_id) {
            Ok(loaded) => loaded,
            Err(error) => return self.stop_with_db_error(error).await,
        };
        let model_run_id = ModelRunId(format!("{}-model-{}", self.task_id.0, Uuid::new_v4()));
        let Some(provider) = self
            .model_profiles
            .get(&loaded.task.model_profile_key)
            .cloned()
        else {
            return self
                .stop_with_internal_error("model profile key is not configured")
                .await;
        };
        let request = ModelCallDispatchRequest {
            correlation: selvedge_command_model::ApiCallCorrelation {
                api_effect_id: ApiEffectId(format!("{}-api-{}", self.task_id.0, Uuid::new_v4())),
                task_id: self.task_id.clone(),
                model_run_id: model_run_id.clone(),
            },
            provider,
            conversation: conversation_to_path(conversation),
            tool_manifest: Some(tool_manifest),
            response_preference: ResponsePreference::PlainTextOrToolCalls,
        };
        self.wait_state = WaitState::WaitingModelReply { model_run_id };
        self.send_core(CoreOutputMessage::RequestModelCall(request))
            .await
            .is_err()
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
        self.router_tx
            .send(RouterIngressMessage::Core(CoreOutputEnvelope {
                task_id: self.task_id.clone(),
                runtime_token: self.runtime_token.clone(),
                message,
            }))
            .await
            .map_err(|_| ())
    }

    async fn send_exit(&self, reason: TaskRuntimeExitReason) {
        let _ = self
            .router_tx
            .send(RouterIngressMessage::RuntimeExit(TaskRuntimeExitNotice {
                task_id: self.task_id.clone(),
                runtime_token: self.runtime_token.clone(),
                reason,
            }))
            .await;
    }

    async fn stop_with_db_error(&self, error: DbError) -> bool {
        self.send_exit(TaskRuntimeExitReason::DbError(error.to_string()))
            .await;
        true
    }

    async fn stop_with_internal_error(&self, message: &str) -> bool {
        self.send_exit(TaskRuntimeExitReason::InternalError(message.to_owned()))
            .await;
        true
    }
}

fn conversation_to_path(conversation: selvedge_db::Conversation) -> ConversationPath {
    let messages = conversation
        .items
        .into_iter()
        .map(conversation_item_to_message)
        .collect();
    ConversationPath { messages }
}

fn validate_conversation_tool_pairs(
    conversation: &selvedge_db::Conversation,
) -> Result<(), String> {
    let mut pending_tool_calls = HashMap::new();

    for item in &conversation.items {
        match item {
            ConversationItem::FunctionCall {
                function_call_id,
                tool_name,
                ..
            } => {
                if pending_tool_calls
                    .insert(function_call_id.0.clone(), tool_name.0.clone())
                    .is_some()
                {
                    return Err("conversation contains duplicate open tool call id".to_owned());
                }
            }
            ConversationItem::FunctionOutput {
                function_call_id,
                tool_name,
                ..
            } => {
                let Some(expected_tool_name) = pending_tool_calls.remove(&function_call_id.0)
                else {
                    return Err(
                        "conversation contains tool output without matching call".to_owned()
                    );
                };
                if expected_tool_name != tool_name.0 {
                    return Err("conversation contains tool output with mismatched tool".to_owned());
                }
            }
            ConversationItem::Message { .. } => {}
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

fn conversation_item_to_message(item: ConversationItem) -> ConversationMessage {
    match item {
        ConversationItem::Message { role, text } => ConversationMessage {
            role,
            content: MessageContent::Text(text),
            source_node_id: None,
        },
        ConversationItem::FunctionCall {
            function_call_id,
            tool_name,
            arguments,
        } => ConversationMessage {
            role: MessageRole::Assistant,
            content: MessageContent::Structured(StructuredPayload::Object(BTreeMap::from([
                (
                    "function_call_id".to_owned(),
                    StructuredPayload::String(function_call_id.0),
                ),
                (
                    "tool_name".to_owned(),
                    StructuredPayload::String(tool_name.0),
                ),
                (
                    "arguments".to_owned(),
                    StructuredPayload::Array(
                        arguments
                            .into_iter()
                            .map(argument_to_structured_payload)
                            .collect(),
                    ),
                ),
            ]))),
            source_node_id: None,
        },
        ConversationItem::FunctionOutput {
            function_call_id,
            tool_name,
            output_text,
            is_error,
        } => ConversationMessage {
            role: MessageRole::Tool,
            content: MessageContent::Structured(StructuredPayload::Object(BTreeMap::from([
                (
                    "function_call_id".to_owned(),
                    StructuredPayload::String(function_call_id.0),
                ),
                (
                    "tool_name".to_owned(),
                    StructuredPayload::String(tool_name.0),
                ),
                (
                    "output_text".to_owned(),
                    StructuredPayload::String(output_text),
                ),
                ("is_error".to_owned(), StructuredPayload::Boolean(is_error)),
            ]))),
            source_node_id: None,
        },
    }
}

fn argument_to_structured_payload(argument: ToolCallArgument) -> StructuredPayload {
    StructuredPayload::Object(BTreeMap::from([
        (
            "name".to_owned(),
            StructuredPayload::String(argument.name.0),
        ),
        (
            "value".to_owned(),
            tool_argument_value_to_payload(argument.value),
        ),
    ]))
}

fn validate_tool_calls(
    tool_calls: Vec<ToolCallProposal>,
    tool_manifest: &ToolManifest,
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
        let arguments =
            tool_call_arguments_from_payload(tool_call.arguments, &tool_name, tool_manifest)?;
        validated.push_back(ValidatedToolCall {
            function_call_id: FunctionCallId(tool_call.call_id),
            tool_name,
            arguments,
        });
    }
    Ok(validated)
}

fn tool_call_arguments_from_payload(
    payload: StructuredPayload,
    tool_name: &ToolName,
    tool_manifest: &ToolManifest,
) -> Result<Vec<ToolCallArgument>, String> {
    let Some(tool_spec) = tool_manifest
        .tools
        .iter()
        .find(|tool| tool.name == tool_name.0)
    else {
        return Err(format!("tool is not enabled for task: {}", tool_name.0));
    };
    let StructuredPayload::Object(arguments) = payload else {
        return Err(format!("tool arguments must be an object: {}", tool_name.0));
    };
    for parameter in tool_spec
        .parameters
        .iter()
        .filter(|parameter| parameter.required)
    {
        if !arguments.contains_key(&parameter.name) {
            return Err(format!(
                "required tool argument is missing: {}.{}",
                tool_name.0, parameter.name
            ));
        }
    }

    let mut converted = Vec::with_capacity(arguments.len());
    for (name, value) in arguments {
        let Some(parameter_type) = tool_spec
            .parameters
            .iter()
            .find(|parameter| parameter.name == name)
            .map(|parameter| &parameter.parameter_type)
        else {
            return Err(format!(
                "tool argument is not declared: {}.{}",
                tool_name.0, name
            ));
        };
        let Some(value) = tool_argument_value_from_payload(value, parameter_type) else {
            return Err(format!(
                "tool argument value cannot be converted: {}.{}",
                tool_name.0, name
            ));
        };
        converted.push(ToolCallArgument {
            name: ToolParameterName(name),
            value,
        });
    }
    Ok(converted)
}

fn tool_argument_value_from_payload(
    payload: StructuredPayload,
    parameter_type: &ToolParameterType,
) -> Option<ToolArgumentValue> {
    match (parameter_type, payload) {
        (ToolParameterType::String, StructuredPayload::String(value)) => {
            Some(ToolArgumentValue::String(value))
        }
        (ToolParameterType::Integer, StructuredPayload::Number(value))
            if value.is_finite()
                && value.fract() == 0.0
                && value >= i64::MIN as f64
                && value < 9_223_372_036_854_775_808.0 =>
        {
            let converted = value as i64;
            if converted as f64 == value {
                Some(ToolArgumentValue::Integer(converted))
            } else {
                None
            }
        }
        (ToolParameterType::Number, StructuredPayload::Number(value)) if value.is_finite() => {
            Some(ToolArgumentValue::Number(value))
        }
        (ToolParameterType::Boolean, StructuredPayload::Boolean(value)) => {
            Some(ToolArgumentValue::Boolean(value))
        }
        _ => None,
    }
}

fn tool_argument_value_to_payload(value: ToolArgumentValue) -> StructuredPayload {
    match value {
        ToolArgumentValue::String(value) => StructuredPayload::String(value),
        ToolArgumentValue::Integer(value) => StructuredPayload::Number(value as f64),
        ToolArgumentValue::Number(value) => StructuredPayload::Number(value),
        ToolArgumentValue::Boolean(value) => StructuredPayload::Boolean(value),
    }
}

fn now() -> UnixTs {
    UnixTs(
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_secs() as i64)
            .unwrap_or(0),
    )
}
