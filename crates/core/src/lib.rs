#![doc = include_str!("../README.md")]

use std::collections::{BTreeMap, HashMap, VecDeque};
use std::time::{SystemTime, UNIX_EPOCH};

use selvedge_command_model::{
    ApiEffectId, ApiOutputEnvelope, CoreOutputEnvelope, CoreOutputMessage,
    ModelCallDispatchRequest, ModelRunId, RouterIngressMessage, RouterIngressSender,
    TaskRuntimeCommand, TaskRuntimeExitNotice, TaskRuntimeExitReason, TaskRuntimeSender,
    ToolExecutionRequest, ToolExecutionResult, ToolExecutionRunId,
};
use selvedge_db::{
    DbError, DbPool, HistoryNodeId, MessageRole, NewFunctionCallNodeContent,
    NewFunctionOutputNodeContent, NewHistoryNode, NewHistoryNodeContent, NewMessageNodeContent,
    TaskId, ToolArgumentValue, ToolCallArgument, ToolName, ToolParameterName, UnixTs,
    append_history_node_and_move_cursor, append_next_queued_user_input_and_move_cursor,
    archive_task, load_active_task, queue_user_input, read_conversation_for_task,
    read_tool_manifest_for_task,
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
pub struct SpawnTaskRuntimeArgs {
    pub task_id: TaskId,
    pub db: DbPool,
    pub router_tx: RouterIngressSender,
    pub config: TaskRuntimeConfig,
}

#[derive(Debug)]
pub struct SpawnedTaskRuntime {
    pub task_id: TaskId,
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
        task_runtime_tx: task_runtime_tx.clone(),
    };

    let actor = TaskRuntimeActor {
        task_id: args.task_id,
        db: args.db,
        router_tx: args.router_tx,
        self_tx: task_runtime_tx,
        rx: task_runtime_rx,
        cursor_node_id: None,
        started: false,
        model_profiles: args.config.model_profiles,
        wait_state: WaitState::Idle,
    };
    tokio::spawn(actor.run());

    Ok(spawned)
}

struct TaskRuntimeActor {
    task_id: TaskId,
    db: DbPool,
    router_tx: RouterIngressSender,
    self_tx: TaskRuntimeSender,
    rx: tokio::sync::mpsc::Receiver<TaskRuntimeCommand>,
    cursor_node_id: Option<HistoryNodeId>,
    started: bool,
    model_profiles: HashMap<ModelProfileKey, ModelProviderProfile>,
    wait_state: WaitState,
}

#[derive(Clone, Debug, PartialEq)]
enum WaitState {
    Idle,
    WaitingModelReply {
        model_run_id: ModelRunId,
    },
    WaitingToolResult {
        tool_run_id: ToolExecutionRunId,
        pending_tool_calls: VecDeque<ToolCallProposal>,
    },
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
            Ok(task) => {
                self.started = true;
                self.cursor_node_id = Some(task.task.cursor_node_id);
                if self
                    .send_core(CoreOutputMessage::RuntimeReady {
                        sender: self.self_tx.clone(),
                    })
                    .await
                    .is_err()
                {
                    return true;
                }
                self.drain_queue_or_idle().await
            }
            Err(error) => {
                self.send_exit(TaskRuntimeExitReason::DbError(error.to_string()))
                    .await;
                true
            }
        }
    }

    async fn handle_user_input(&mut self, message_text: String) -> bool {
        match self.wait_state {
            WaitState::Idle => {
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
            WaitState::Idle | WaitState::WaitingToolResult { .. } => return false,
        };

        match envelope {
            ApiOutputEnvelope::Success { correlation, reply } => {
                if correlation.task_id != self.task_id
                    || correlation.model_run_id != expected_model_run_id
                {
                    return false;
                }
                if let Some(content) = reply.content.filter(|content| !content.trim().is_empty()) {
                    let Some(parent_node_id) = self.cursor_node_id else {
                        return self
                            .stop_with_internal_error("task cursor is missing")
                            .await;
                    };
                    match append_history_node_and_move_cursor(
                        &self.db,
                        &self.task_id,
                        NewHistoryNode {
                            parent_node_id: Some(parent_node_id),
                            content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                                message_role: MessageRole::Assistant,
                                message_text: content,
                            }),
                            created_at: now(),
                        },
                    ) {
                        Ok(node_id) => self.cursor_node_id = Some(node_id),
                        Err(error) => return self.stop_with_db_error(error).await,
                    }
                }

                let mut pending_tool_calls = VecDeque::from(reply.tool_calls);
                if let Some(tool_call) = pending_tool_calls.pop_front() {
                    self.dispatch_tool_call(tool_call, pending_tool_calls).await
                } else {
                    self.wait_state = WaitState::Idle;
                    self.drain_queue_or_idle().await
                }
            }
            ApiOutputEnvelope::Failure { correlation, error } => {
                if correlation.task_id != self.task_id
                    || correlation.model_run_id != expected_model_run_id
                {
                    return false;
                }
                self.wait_state = WaitState::Idle;
                let _ = error;
                self.drain_queue_or_idle().await
            }
        }
    }

    async fn handle_tool_result(&mut self, result: ToolExecutionResult) -> bool {
        let pending_tool_calls = match std::mem::replace(&mut self.wait_state, WaitState::Idle) {
            WaitState::WaitingToolResult {
                tool_run_id,
                pending_tool_calls,
            } if result.task_id == self.task_id && result.tool_execution_run_id == tool_run_id => {
                pending_tool_calls
            }
            wait_state @ WaitState::WaitingToolResult { .. } => {
                self.wait_state = wait_state;
                return false;
            }
            wait_state @ (WaitState::Idle | WaitState::WaitingModelReply { .. }) => {
                self.wait_state = wait_state;
                return false;
            }
        };

        let node = NewHistoryNode {
            parent_node_id: Some(result.function_call_node_id),
            content: NewHistoryNodeContent::FunctionOutput(NewFunctionOutputNodeContent {
                function_call_node_id: result.function_call_node_id,
                function_call_id: result.function_call_id,
                tool_name: result.tool_name,
                output_text: result.output_text,
                is_error: result.is_error,
            }),
            created_at: now(),
        };
        match append_history_node_and_move_cursor(&self.db, &self.task_id, node) {
            Ok(node_id) => {
                self.cursor_node_id = Some(node_id);
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
        let Some(parent_node_id) = self.cursor_node_id else {
            return Err(DbError::Storage("task cursor is missing".to_owned()));
        };
        match append_history_node_and_move_cursor(
            &self.db,
            &self.task_id,
            NewHistoryNode {
                parent_node_id: Some(parent_node_id),
                content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                    message_role: MessageRole::User,
                    message_text,
                }),
                created_at: now(),
            },
        ) {
            Ok(node_id) => {
                self.cursor_node_id = Some(node_id);
                Ok(())
            }
            Err(error) => Err(error),
        }
    }

    async fn request_model_call(&mut self) -> bool {
        let conversation = match read_conversation_for_task(&self.db, &self.task_id) {
            Ok(conversation) => conversation,
            Err(error) => return self.stop_with_db_error(error).await,
        };
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

    async fn dispatch_tool_call(
        &mut self,
        tool_call: ToolCallProposal,
        pending_tool_calls: VecDeque<ToolCallProposal>,
    ) -> bool {
        let Some(parent_node_id) = self.cursor_node_id else {
            return self
                .stop_with_internal_error("task cursor is missing")
                .await;
        };
        let tool_name = ToolName(tool_call.tool_name);
        let function_call_id = selvedge_db::FunctionCallId(tool_call.call_id);
        let tool_manifest = match read_tool_manifest_for_task(&self.db, &self.task_id) {
            Ok(tool_manifest) => tool_manifest,
            Err(error) => return self.stop_with_db_error(error).await,
        };
        let arguments =
            match tool_call_arguments_from_payload(tool_call.arguments, &tool_name, &tool_manifest)
            {
                Ok(arguments) => arguments,
                Err(message) => return self.stop_with_internal_error(&message).await,
            };
        let node = NewHistoryNode {
            parent_node_id: Some(parent_node_id),
            content: NewHistoryNodeContent::FunctionCall(NewFunctionCallNodeContent {
                function_call_id: function_call_id.clone(),
                tool_name: tool_name.clone(),
                arguments: arguments.clone(),
            }),
            created_at: now(),
        };
        let function_call_node_id =
            match append_history_node_and_move_cursor(&self.db, &self.task_id, node) {
                Ok(node_id) => {
                    self.cursor_node_id = Some(node_id);
                    node_id
                }
                Err(error) => return self.stop_with_db_error(error).await,
            };

        let tool_run_id = ToolExecutionRunId(format!("{}-tool-{}", self.task_id.0, Uuid::new_v4()));
        let request = ToolExecutionRequest {
            task_id: self.task_id.clone(),
            tool_execution_run_id: tool_run_id.clone(),
            function_call_node_id,
            function_call_id,
            tool_name,
            arguments,
        };
        self.wait_state = WaitState::WaitingToolResult {
            tool_run_id,
            pending_tool_calls,
        };
        self.send_core(CoreOutputMessage::RequestToolExecution(request))
            .await
            .is_err()
    }

    async fn dispatch_next_tool_or_request_model(
        &mut self,
        mut pending_tool_calls: VecDeque<ToolCallProposal>,
    ) -> bool {
        if let Some(tool_call) = pending_tool_calls.pop_front() {
            self.dispatch_tool_call(tool_call, pending_tool_calls).await
        } else {
            self.request_model_call().await
        }
    }

    async fn drain_queue_or_idle(&mut self) -> bool {
        match append_next_queued_user_input_and_move_cursor(&self.db, &self.task_id, now()) {
            Ok(Some(node_id)) => {
                self.cursor_node_id = Some(node_id);
                self.wait_state = WaitState::Idle;
                self.request_model_call().await
            }
            Ok(None) => {
                self.wait_state = WaitState::Idle;
                false
            }
            Err(error) => self.stop_with_db_error(error).await,
        }
    }

    async fn send_core(&self, message: CoreOutputMessage) -> Result<(), ()> {
        self.router_tx
            .send(RouterIngressMessage::Core(CoreOutputEnvelope {
                task_id: self.task_id.clone(),
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
