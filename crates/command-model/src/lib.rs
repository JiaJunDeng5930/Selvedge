#![doc = include_str!("../README.md")]

use std::collections::BTreeSet;
use std::fmt;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use tokio::sync::{Mutex, Notify, mpsc, oneshot};

use selvedge_domain_model::{
    ApiDomainValidationError, Conversation, FunctionCallId, HistoryNodeId, JsonObject, MessageRole,
    ModelProfileKey, ModelProviderProfile, ModelReply, ReasoningEffort, ResponsePreference,
    ToolManifest, ToolName, UnixTs, validate_conversation, validate_model_provider_profile,
    validate_model_reply, validate_tool_manifest,
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
    pub conversation: Conversation,
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
    Command(RouterCommandEnvelope),
    ApiOutput(ApiOutputEnvelope),
    Core(CoreOutputEnvelope),
    Tool(ToolExecutionResult),
    RuntimeExit(TaskRuntimeExitNotice),
    PublishToEvents(DomainEventPublishRequest),
    StopRouter,
}

pub type RouterIngressApiMessage = RouterIngressMessage;
pub type RouterIngressSender = mpsc::UnboundedSender<RouterIngressMessage>;
pub type RouterIngressWeakSender = mpsc::WeakUnboundedSender<RouterIngressMessage>;
pub type TaskRuntimeSender = mpsc::Sender<TaskRuntimeCommand>;
pub type ModelCallRequest = ModelCallDispatchRequest;
pub type EventIngressSender = mpsc::Sender<EventIngress>;
pub type ClientFrameSender = mpsc::Sender<ClientFrame>;
pub type RouterAttachAdmissionSender = oneshot::Sender<RouterAttachAdmissionResult>;
pub type EventClientReservationSender = oneshot::Sender<EventClientReservationResult>;
pub type SendUserInputResult = Result<SendUserInputOutcome, TaskCommandError>;
pub type ArchiveTaskResult = Result<ArchiveTaskOutcome, TaskCommandError>;
pub type SendUserInputResponseReceiver = oneshot::Receiver<SendUserInputResult>;
pub type ArchiveTaskResponseReceiver = oneshot::Receiver<ArchiveTaskResult>;
pub type SendUserInputResponder = TaskCommandResponder<SendUserInputOutcome>;
pub type ArchiveTaskResponder = TaskCommandResponder<ArchiveTaskOutcome>;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SendUserInputOutcome {
    Committed { node_id: HistoryNodeId },
    Queued,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ArchiveTaskOutcome {
    Archived,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TaskCommandError {
    InvalidCommand,
    TaskMissing,
    TaskArchived,
    RuntimeUnavailable,
    PersistenceFailed,
}

pub struct TaskCommandResponder<T> {
    result_tx: Option<oneshot::Sender<Result<T, TaskCommandError>>>,
}

impl<T> TaskCommandResponder<T> {
    pub fn settle(mut self, result: Result<T, TaskCommandError>) {
        if let Some(result_tx) = self.result_tx.take() {
            let _ = result_tx.send(result);
        }
    }
}

impl<T> Drop for TaskCommandResponder<T> {
    fn drop(&mut self) {
        if let Some(result_tx) = self.result_tx.take() {
            let _ = result_tx.send(Err(TaskCommandError::RuntimeUnavailable));
        }
    }
}

impl<T> fmt::Debug for TaskCommandResponder<T> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("TaskCommandResponder")
            .field("pending", &self.result_tx.is_some())
            .finish()
    }
}

pub fn send_user_input_response_channel() -> (SendUserInputResponder, SendUserInputResponseReceiver)
{
    let (result_tx, result_rx) = oneshot::channel();
    (
        TaskCommandResponder {
            result_tx: Some(result_tx),
        },
        result_rx,
    )
}

pub fn archive_task_response_channel() -> (ArchiveTaskResponder, ArchiveTaskResponseReceiver) {
    let (result_tx, result_rx) = oneshot::channel();
    (
        TaskCommandResponder {
            result_tx: Some(result_tx),
        },
        result_rx,
    )
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct FactoryEffectId(pub String);

#[derive(Debug)]
pub struct RouterCommandEnvelope {
    pub client_id: Option<ClientId>,
    pub client_command_id: Option<ClientCommandId>,
    pub command: RouterCommand,
}

#[derive(Debug)]
pub enum RouterCommand {
    AttachClient {
        client_id: ClientId,
        client_command_id: ClientCommandId,
        outbound: ClientFrameSender,
        subscription: ClientSubscription,
        admission_tx: RouterAttachAdmissionSender,
    },
    DetachClient {
        client_id: ClientId,
        client_command_id: ClientCommandId,
    },
    UpdateSubscription {
        client_id: ClientId,
        client_command_id: ClientCommandId,
        subscription: ClientSubscription,
    },
    SendUserInput {
        task_id: TaskId,
        message_text: String,
        responder: SendUserInputResponder,
    },
    ArchiveTask {
        task_id: TaskId,
        responder: ArchiveTaskResponder,
    },
    StopTaskRuntime {
        task_id: TaskId,
    },
    EnsureTaskRuntime {
        task_id: TaskId,
    },
    EnsureMissingTaskRuntimes,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RouterAttachAdmissionResult {
    Accepted,
    DuplicateAttach,
    ClientRegistryFull,
    EventsMailboxClosed,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RouterCommandValidationError {
    MissingClientId,
    MissingClientCommandId,
    MismatchedClientId,
    MismatchedClientCommandId,
    EmptyTaskId,
    EmptyMessageText,
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
    pub task_runtime_control: TaskRuntimeControl,
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
    TaskMissing,
    TaskArchived,
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
    ReserveClientSession(ReserveClientSession),
    BeginClientHydration(BeginClientHydration),
    DeliverSnapshot(DeliverSnapshot),
    DeliverNotice(DeliverNotice),
    UpdateSubscription(UpdateSubscription),
    DetachClient(DetachClient),
}

#[derive(Debug)]
pub struct ReserveClientSession {
    pub client_id: ClientId,
    pub client_command_id: ClientCommandId,
    pub result_tx: EventClientReservationSender,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum EventClientReservationResult {
    Reserved,
    DuplicateAttach,
    ClientRegistryFull,
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
    pub snapshot_mode: SnapshotMode,
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

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SnapshotMode {
    CurrentState,
    Empty,
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
        arguments: JsonObject,
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
    pub kind: ClientNoticeKind,
    pub message_text: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ClientNoticeKind {
    Text,
    LoginUserCode {
        client_command_id: ClientCommandId,
        verification_url: String,
        user_code: String,
    },
    CommandCompleted {
        client_command_id: ClientCommandId,
        command_name: String,
    },
    CommandFailed {
        client_command_id: ClientCommandId,
        command_name: String,
    },
    Diagnostic {
        client_command_id: Option<ClientCommandId>,
    },
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
    ClientDisconnected,
    ReplacedByNewHydration,
    DeliveryFailed,
    HydrationBufferOverflow,
    EventsShutdown,
}

#[derive(Clone)]
pub struct TaskRuntimeControl {
    inner: Arc<TaskRuntimeControlInner>,
}

struct TaskRuntimeControlInner {
    frozen: AtomicBool,
    stopping: AtomicBool,
    stop_result: Mutex<Option<TaskRuntimeStopResult>>,
    actor_notify: Notify,
    stop_notify: Notify,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TaskRuntimeStopResult;

impl TaskRuntimeControl {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(TaskRuntimeControlInner {
                frozen: AtomicBool::new(false),
                stopping: AtomicBool::new(false),
                stop_result: Mutex::new(None),
                actor_notify: Notify::new(),
                stop_notify: Notify::new(),
            }),
        }
    }

    pub fn freeze(&self) {
        self.inner.frozen.store(true, Ordering::SeqCst);
        self.inner.actor_notify.notify_one();
    }

    pub fn unfreeze(&self) {
        self.inner.frozen.store(false, Ordering::SeqCst);
        self.inner.actor_notify.notify_one();
    }

    pub fn is_frozen(&self) -> bool {
        self.inner.frozen.load(Ordering::SeqCst)
    }

    pub fn is_stopping(&self) -> bool {
        self.inner.stopping.load(Ordering::SeqCst)
    }

    pub async fn stop(&self) -> TaskRuntimeStopResult {
        self.inner.stopping.store(true, Ordering::SeqCst);
        self.inner.actor_notify.notify_one();
        loop {
            let notified = self.inner.stop_notify.notified();
            if let Some(result) = self.inner.stop_result.lock().await.clone() {
                return result;
            }
            notified.await;
        }
    }

    pub async fn wait_for_control_change(&self) {
        self.inner.actor_notify.notified().await;
    }

    pub async fn finish_stop(&self, result: TaskRuntimeStopResult) {
        let mut stop_result = self.inner.stop_result.lock().await;
        if stop_result.is_none() {
            *stop_result = Some(result);
            self.inner.stop_notify.notify_waiters();
        }
    }

    pub fn same_control(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.inner, &other.inner)
    }
}

impl Default for TaskRuntimeControl {
    fn default() -> Self {
        Self::new()
    }
}

impl fmt::Debug for TaskRuntimeControl {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("TaskRuntimeControl")
            .field("frozen", &self.is_frozen())
            .field("stopping", &self.is_stopping())
            .finish_non_exhaustive()
    }
}

impl PartialEq for TaskRuntimeControl {
    fn eq(&self, other: &Self) -> bool {
        self.same_control(other)
    }
}

impl Eq for TaskRuntimeControl {}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ToolExecutionRunId(pub String);

#[derive(Debug)]
pub enum TaskRuntimeCommand {
    Start,
    UserInput {
        message_text: String,
        responder: SendUserInputResponder,
    },
    ApiModelReply(ApiOutputEnvelope),
    ToolResult(ToolExecutionResult),
    Archive {
        responder: ArchiveTaskResponder,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TaskRuntimeExitNotice {
    pub task_id: TaskId,
    pub task_runtime_control: TaskRuntimeControl,
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
    EnsureTaskRuntimes { task_ids: Vec<TaskId> },
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
    pub arguments: JsonObject,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ToolExecutionResult {
    pub task_id: TaskId,
    pub tool_execution_run_id: ToolExecutionRunId,
    pub function_call_node_id: HistoryNodeId,
    pub function_call_id: FunctionCallId,
    pub tool_name: ToolName,
    pub branches: Vec<ToolExecutionBranch>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ToolExecutionBranch {
    pub target: ToolExecutionBranchTarget,
    pub output: serde_json::Value,
    pub is_error: bool,
    pub messages: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ToolExecutionBranchTarget {
    CallingTask,
    NewChildTask { task_id: TaskId },
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

pub fn validate_dispatch_request(request: &ModelCallDispatchRequest) -> Result<(), ModelCallError> {
    validate_correlation(&request.correlation)?;

    validate_model_provider_profile(&request.provider)
        .map_err(|error| validation_error("provider", error))?;

    validate_conversation(&request.conversation)
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

pub fn validate_router_command(
    command: &RouterCommandEnvelope,
) -> Result<(), RouterCommandValidationError> {
    match &command.command {
        RouterCommand::AttachClient {
            client_id,
            client_command_id,
            ..
        }
        | RouterCommand::DetachClient {
            client_id,
            client_command_id,
        }
        | RouterCommand::UpdateSubscription {
            client_id,
            client_command_id,
            ..
        } => {
            validate_client_id(command.client_id.as_ref())?;
            validate_client_command_id(command.client_command_id.as_ref())?;
            validate_client_id(Some(client_id))?;
            validate_client_command_id(Some(client_command_id))?;
            if command.client_id.as_ref() != Some(client_id) {
                return Err(RouterCommandValidationError::MismatchedClientId);
            }
            if command.client_command_id.as_ref() != Some(client_command_id) {
                return Err(RouterCommandValidationError::MismatchedClientCommandId);
            }
        }
        RouterCommand::SendUserInput {
            task_id,
            message_text,
            ..
        } => {
            validate_task_id(task_id)?;
            if message_text.trim().is_empty() {
                return Err(RouterCommandValidationError::EmptyMessageText);
            }
        }
        RouterCommand::ArchiveTask { task_id, .. }
        | RouterCommand::StopTaskRuntime { task_id }
        | RouterCommand::EnsureTaskRuntime { task_id } => validate_task_id(task_id)?,
        RouterCommand::EnsureMissingTaskRuntimes => {}
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

fn validate_client_id(client_id: Option<&ClientId>) -> Result<(), RouterCommandValidationError> {
    match client_id {
        Some(client_id) if !client_id.0.trim().is_empty() => Ok(()),
        Some(_) | None => Err(RouterCommandValidationError::MissingClientId),
    }
}

fn validate_client_command_id(
    client_command_id: Option<&ClientCommandId>,
) -> Result<(), RouterCommandValidationError> {
    match client_command_id {
        Some(client_command_id) if !client_command_id.0.trim().is_empty() => Ok(()),
        Some(_) | None => Err(RouterCommandValidationError::MissingClientCommandId),
    }
}

fn validate_task_id(task_id: &TaskId) -> Result<(), RouterCommandValidationError> {
    if task_id.0.trim().is_empty() {
        return Err(RouterCommandValidationError::EmptyTaskId);
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
