#![doc = include_str!("../README.md")]

use tokio::sync::{mpsc, oneshot};

use selvedge_domain_model::{
    ApiDomainValidationError, ConversationPath, FunctionCallId, HistoryNodeId,
    ModelProviderProfile, ModelReply, ResponsePreference, ToolCallArgument, ToolManifest, ToolName,
    validate_conversation_path, validate_model_provider_profile, validate_model_reply,
    validate_tool_manifest,
};

pub use selvedge_domain_model::TaskId;

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ApiEffectId(pub String);

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ModelRunId(pub String);

pub type ModelCallId = ModelRunId;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiCallCorrelation {
    pub api_effect_id: ApiEffectId,
    pub task_id: TaskId,
    pub model_run_id: ModelRunId,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ModelCallDispatchRequest {
    pub correlation: ApiCallCorrelation,
    pub provider: ModelProviderProfile,
    pub conversation: ConversationPath,
    pub tool_manifest: Option<ToolManifest>,
    pub response_preference: ResponsePreference,
}

#[derive(Clone, Debug, PartialEq)]
pub enum ApiOutputEnvelope {
    Success {
        correlation: ApiCallCorrelation,
        reply: ModelReply,
    },
    Failure {
        correlation: ApiCallCorrelation,
        error: ModelCallError,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ModelCallError {
    pub kind: ModelCallErrorKind,
    pub message: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ModelCallErrorKind {
    Validation,
    ProviderRequest,
    ProviderNetwork,
    ProviderTimeout,
    ProviderResponse,
    Cancelled,
}

#[derive(Debug)]
pub enum RouterIngressMessage {
    ApiOutput(ApiOutputEnvelope),
    Core(CoreOutputEnvelope),
    Tool(ToolExecutionResult),
    RuntimeExit(TaskRuntimeExitNotice),
    QueryRuntimeInventory(RuntimeInventoryQuery),
    PublishToEvents(DomainEventPublishRequest),
}

pub type RouterIngressApiMessage = RouterIngressMessage;
pub type RouterIngressSender = mpsc::Sender<RouterIngressMessage>;
pub type TaskRuntimeSender = mpsc::Sender<TaskRuntimeCommand>;
pub type ModelCallRequest = ModelCallDispatchRequest;

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ToolExecutionRunId(pub String);

#[derive(Debug)]
pub enum TaskRuntimeCommand {
    Start,
    UserInput { message_text: String },
    ApiModelReply(ApiOutputEnvelope),
    ToolResult(ToolExecutionResult),
    Archive,
    Stop,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TaskRuntimeExitNotice {
    pub task_id: TaskId,
    pub reason: TaskRuntimeExitReason,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TaskRuntimeExitReason {
    Stopped,
    Archived,
    DbError(String),
    InternalError(String),
}

#[derive(Debug)]
pub struct CoreOutputEnvelope {
    pub task_id: TaskId,
    pub message: CoreOutputMessage,
}

#[derive(Debug)]
pub enum CoreOutputMessage {
    RequestModelCall(ModelCallRequest),
    RequestToolExecution(ToolExecutionRequest),
    PublishDomainEvent(DomainEventPublishRequest),
    RuntimeReady,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ToolExecutionRequest {
    pub task_id: TaskId,
    pub tool_execution_run_id: ToolExecutionRunId,
    pub function_call_node_id: HistoryNodeId,
    pub function_call_id: FunctionCallId,
    pub tool_name: ToolName,
    pub arguments: Vec<ToolCallArgument>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ToolExecutionResult {
    pub task_id: TaskId,
    pub tool_execution_run_id: ToolExecutionRunId,
    pub function_call_node_id: HistoryNodeId,
    pub function_call_id: FunctionCallId,
    pub tool_name: ToolName,
    pub output_text: String,
    pub is_error: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct DomainEventPublishRequest {
    pub task_id: TaskId,
    pub event: DomainEvent,
}

#[derive(Clone, Debug, PartialEq)]
pub enum DomainEvent {
    TaskRuntimeReady,
    UserMessageCommitted { node_id: HistoryNodeId },
    AssistantMessageCommitted { node_id: HistoryNodeId },
    ReasoningCommitted { node_id: HistoryNodeId },
    FunctionCallCommitted { node_id: HistoryNodeId },
    FunctionOutputCommitted { node_id: HistoryNodeId },
    TaskArchived,
    ErrorNotice { message: String },
}

#[derive(Debug)]
pub struct RuntimeInventoryQuery {
    pub reply_to: oneshot::Sender<RuntimeInventoryResponse>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RuntimeInventoryResponse {
    pub live_task_runtimes: Vec<TaskId>,
    pub pending_task_runtime_effects: Vec<TaskId>,
}

pub fn validate_dispatch_request(request: &ModelCallDispatchRequest) -> Result<(), ModelCallError> {
    validate_correlation(&request.correlation)?;

    validate_model_provider_profile(&request.provider)
        .map_err(|error| validation_error("provider", error))?;

    validate_conversation_path(&request.conversation)
        .map_err(|error| validation_error("conversation", error))?;

    if let Some(tool_manifest) = &request.tool_manifest {
        validate_tool_manifest(tool_manifest)
            .map_err(|error| validation_error("tool_manifest", error))?;
    }

    Ok(())
}

pub fn validate_api_output_envelope(envelope: &ApiOutputEnvelope) -> Result<(), ModelCallError> {
    match envelope {
        ApiOutputEnvelope::Success { correlation, reply } => {
            validate_correlation(correlation)?;
            validate_model_reply(reply).map_err(|error| validation_error("reply", error))?;
        }
        ApiOutputEnvelope::Failure { correlation, error } => {
            if error.kind != ModelCallErrorKind::Validation {
                validate_correlation(correlation)?;
            }
        }
    }

    Ok(())
}

fn validate_correlation(correlation: &ApiCallCorrelation) -> Result<(), ModelCallError> {
    if correlation.api_effect_id.0.trim().is_empty() {
        return Err(validation_message("api_effect_id must not be empty"));
    }

    if correlation.task_id.0.trim().is_empty() {
        return Err(validation_message("task_id must not be empty"));
    }

    if correlation.model_run_id.0.trim().is_empty() {
        return Err(validation_message("model_run_id must not be empty"));
    }

    Ok(())
}

fn validation_error(field: &str, error: ApiDomainValidationError) -> ModelCallError {
    validation_message(format!("{field} is invalid: {error:?}"))
}

fn validation_message(message: impl Into<String>) -> ModelCallError {
    ModelCallError {
        kind: ModelCallErrorKind::Validation,
        message: message.into(),
    }
}
