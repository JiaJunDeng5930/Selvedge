#![doc = include_str!("../README.md")]

use std::collections::BTreeSet;

use tokio::sync::{mpsc, oneshot};

use selvedge_domain_model::{
    ApiDomainValidationError, ConversationPath, FunctionCallId, HistoryNodeId, MessageRole,
    ModelProfileKey, ModelProviderProfile, ModelReply, ReasoningEffort, ResponsePreference,
    ToolCallArgument, ToolManifest, ToolName, UnixTs, validate_conversation_path,
    validate_model_provider_profile, validate_model_reply, validate_tool_manifest,
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
    Factory(RouterIngressFactoryMessage),
    QueryRuntimeInventory(RuntimeInventoryQuery),
    PublishToEvents(DomainEventPublishRequest),
}

pub type RouterIngressApiMessage = RouterIngressMessage;
pub type RouterIngressSender = mpsc::Sender<RouterIngressMessage>;
pub type TaskRuntimeSender = mpsc::Sender<TaskRuntimeCommand>;
pub type ModelCallRequest = ModelCallDispatchRequest;
pub type EventIngressSender = mpsc::Sender<EventIngress>;
pub type ClientFrameSender = mpsc::Sender<ClientFrame>;

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct FactoryEffectId(pub String);

#[derive(Debug)]
pub enum RouterIngressFactoryMessage {
    Output(FactoryOutputEnvelope),
}

#[derive(Debug)]
pub struct FactoryOutputEnvelope {
    pub effect_id: FactoryEffectId,
    pub output: FactoryOutput,
}

#[derive(Debug)]
pub enum FactoryOutput {
    RuntimeCreated(TaskRuntimeCreated),
    ScanFinished(FactoryScanOutput),
    Failed(FactoryFailure),
}

#[derive(Debug)]
pub struct TaskRuntimeCreated {
    pub task_id: TaskId,
    pub task_runtime_tx: TaskRuntimeSender,
    pub created_runtime_kind: CreatedRuntimeKind,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CreatedRuntimeKind {
    ExistingTaskRuntime,
    ChildTaskRuntime,
}

#[derive(Debug)]
pub struct FactoryScanOutput {
    pub created: Vec<TaskRuntimeCreated>,
    pub skipped: Vec<FactorySkippedTask>,
    pub failed: Vec<FactoryTaskFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FactorySkippedTask {
    pub task_id: TaskId,
    pub reason: FactorySkipReason,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum FactorySkipReason {
    RuntimeAlreadyLive,
    RuntimeCreationPending,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FactoryTaskFailure {
    pub task_id: TaskId,
    pub kind: FactoryFailureKind,
    pub message: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FactoryFailure {
    pub task_id: Option<TaskId>,
    pub kind: FactoryFailureKind,
    pub message: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum FactoryFailureKind {
    DbReadFailed,
    DbWriteFailed,
    ParentTaskMissing,
    ParentTaskArchived,
    TaskMissing,
    TaskArchived,
    CursorNodeMissing,
    RuntimeInventoryUnavailable,
    RuntimeAlreadyLive,
    RuntimeCreationPending,
    CoreSpawnFailed,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ClientId(pub String);

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ClientCommandId(pub String);

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct DeliverySeq(pub u64);

#[derive(Debug)]
pub enum EventIngress {
    Control(EventControlMessage),
    Raw(RawEvent),
}

#[derive(Debug)]
pub enum EventControlMessage {
    BeginClientHydration(BeginClientHydration),
    DeliverSnapshot(DeliverSnapshot),
    DeliverNotice(DeliverNotice),
    UpdateSubscription(UpdateSubscription),
    DetachClient(DetachClient),
}

#[derive(Debug)]
pub struct BeginClientHydration {
    pub client_id: ClientId,
    pub client_command_id: ClientCommandId,
    pub outbound: ClientFrameSender,
    pub subscription: ClientSubscription,
}

#[derive(Clone, Debug, PartialEq)]
pub struct DeliverSnapshot {
    pub client_id: ClientId,
    pub client_command_id: ClientCommandId,
    pub snapshot: ClientSnapshot,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DeliverNotice {
    pub client_id: ClientId,
    pub client_command_id: ClientCommandId,
    pub notice: ClientNotice,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct UpdateSubscription {
    pub client_id: ClientId,
    pub client_command_id: ClientCommandId,
    pub subscription: ClientSubscription,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DetachClient {
    pub client_id: ClientId,
    pub client_command_id: ClientCommandId,
    pub reason: DetachReason,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ClientSubscription {
    pub task_scope: TaskScope,
    pub detail_level: DetailLevel,
    pub include_model_call_status: bool,
    pub include_tool_execution_status: bool,
    pub include_debug_notices: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TaskScope {
    AllTasks,
    TaskIds(BTreeSet<TaskId>),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DetailLevel {
    Summary,
    Verbose,
}

#[derive(Clone, Debug, PartialEq)]
pub enum RawEvent {
    TaskChanged(TaskChangedRawEvent),
    HistoryAppended(HistoryAppendedRawEvent),
    ModelCallStatus(ModelCallStatusRawEvent),
    ToolExecutionStatus(ToolExecutionStatusRawEvent),
    Debug(DebugRawEvent),
}

#[derive(Clone, Debug, PartialEq)]
pub struct TaskChangedRawEvent {
    pub task: TaskProjection,
}

#[derive(Clone, Debug, PartialEq)]
pub struct HistoryAppendedRawEvent {
    pub task_id: TaskId,
    pub task_state_version: u64,
    pub appended_nodes: Vec<HistoryNodeProjection>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ModelCallStatusRawEvent {
    pub task_id: TaskId,
    pub model_call_id: ModelCallId,
    pub phase: ModelCallStatusPhase,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ToolExecutionStatusRawEvent {
    pub task_id: TaskId,
    pub tool_execution_run_id: ToolExecutionRunId,
    pub function_call_node_id: HistoryNodeId,
    pub tool_name: ToolName,
    pub phase: ToolExecutionStatusPhase,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DebugRawEvent {
    pub task_id: Option<TaskId>,
    pub message_text: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ClientSnapshot {
    pub generated_at: UnixTs,
    pub tasks: Vec<TaskProjection>,
    pub task_parent_edges: Vec<TaskParentProjection>,
    pub history_nodes: Vec<HistoryNodeProjection>,
    pub task_versions: Vec<SnapshotTaskVersion>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SnapshotTaskVersion {
    pub task_id: TaskId,
    pub state_version: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TaskProjection {
    pub task_id: TaskId,
    pub status: TaskProjectionStatus,
    pub cursor_node_id: HistoryNodeId,
    pub model_profile_key: ModelProfileKey,
    pub reasoning_effort: ReasoningEffort,
    pub state_version: u64,
    pub created_at: UnixTs,
    pub updated_at: UnixTs,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TaskProjectionStatus {
    Active,
    Archived,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TaskParentProjection {
    pub parent_task_id: TaskId,
    pub child_task_id: TaskId,
}

#[derive(Clone, Debug, PartialEq)]
pub struct HistoryNodeProjection {
    pub node_id: HistoryNodeId,
    pub parent_node_id: Option<HistoryNodeId>,
    pub created_at: UnixTs,
    pub body: HistoryNodeProjectionBody,
}

#[derive(Clone, Debug, PartialEq)]
pub enum HistoryNodeProjectionBody {
    Message {
        role: MessageRole,
        text: String,
    },
    Reasoning {
        text: String,
    },
    FunctionCall {
        function_call_id: FunctionCallId,
        tool_name: ToolName,
        arguments: Vec<ToolCallArgument>,
    },
    FunctionOutput {
        function_call_node_id: HistoryNodeId,
        function_call_id: FunctionCallId,
        tool_name: ToolName,
        output_text: String,
        is_error: bool,
    },
}

#[derive(Clone, Debug, PartialEq)]
pub enum ClientFrame {
    Snapshot(ClientSnapshotFrame),
    Event(ClientEventFrame),
    Notice(ClientNoticeFrame),
}

#[derive(Clone, Debug, PartialEq)]
pub struct ClientSnapshotFrame {
    pub delivery_seq: DeliverySeq,
    pub client_command_id: ClientCommandId,
    pub snapshot: ClientSnapshot,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ClientEventFrame {
    pub delivery_seq: DeliverySeq,
    pub event: ClientEvent,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ClientNoticeFrame {
    pub delivery_seq: DeliverySeq,
    pub client_command_id: ClientCommandId,
    pub notice: ClientNotice,
}

#[derive(Clone, Debug, PartialEq)]
pub enum ClientEvent {
    TaskChanged(TaskChangedEvent),
    HistoryAppended(HistoryAppendedEvent),
    ModelCallStatus(ModelCallStatusEvent),
    ToolExecutionStatus(ToolExecutionStatusEvent),
    DebugNotice(DebugNoticeEvent),
}

#[derive(Clone, Debug, PartialEq)]
pub struct TaskChangedEvent {
    pub task: TaskProjection,
}

#[derive(Clone, Debug, PartialEq)]
pub struct HistoryAppendedEvent {
    pub task_id: TaskId,
    pub task_state_version: u64,
    pub appended_nodes: Vec<HistoryNodeProjection>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ModelCallStatusEvent {
    pub task_id: TaskId,
    pub model_call_id: ModelCallId,
    pub phase: ModelCallStatusPhase,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ToolExecutionStatusEvent {
    pub task_id: TaskId,
    pub tool_execution_run_id: ToolExecutionRunId,
    pub function_call_node_id: HistoryNodeId,
    pub tool_name: ToolName,
    pub phase: ToolExecutionStatusPhase,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DebugNoticeEvent {
    pub task_id: Option<TaskId>,
    pub message_text: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ClientNotice {
    pub level: ClientNoticeLevel,
    pub message_text: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ClientNoticeLevel {
    Info,
    Warning,
    Error,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ModelCallStatusPhase {
    Requested,
    Completed,
    Failed,
    Discarded,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ToolExecutionStatusPhase {
    Requested,
    Completed,
    Failed,
    Discarded,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DetachReason {
    ClientRequested,
    ReplacedByNewHydration,
    DeliveryFailed,
    HydrationBufferOverflow,
    EventsShutdown,
}

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
