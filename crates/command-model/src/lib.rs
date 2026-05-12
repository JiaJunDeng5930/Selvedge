#![doc = include_str!("../README.md")]
//! @behavior selvedge.task An active task advances user input through a single ordered path that may request models, request tools, publish events, and stop with a recorded reason.
//! @behavior selvedge.task.factory A runtime factory call reports runtime creation, scan, skip, and failure outcomes to the router.
//! @behavior selvedge.task.id Task-scoped commands and runtime messages carry a task identifier visible to router and runtime callers.
//! @behavior selvedge.client.events Router-mediated client event delivery uses event ingress, raw events, control messages, and client frames.

use std::collections::BTreeSet;
use std::fmt;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use tokio::sync::{Mutex, Notify, mpsc, oneshot};

use selvedge_domain_model::{
    ApiDomainValidationError, ConversationPath, FunctionCallId, HistoryNodeId, MessageRole,
    ModelProfileKey, ModelProviderProfile, ModelReply, ReasoningEffort, ResponsePreference,
    ToolCallArgument, ToolManifest, ToolName, UnixTs, validate_conversation_path,
    validate_model_provider_profile, validate_model_reply, validate_tool_manifest,
};

/// @behavior selvedge.task.id.export Command model callers use the shared domain task identifier type for task-scoped commands, events, and outputs.
pub use selvedge_domain_model::TaskId;

/// @behavior selvedge.task.api_effect A model API dispatch request carries the caller-visible API effect identifier used to correlate the eventual model output.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ApiEffectId(pub String);

/// @behavior selvedge.task.model_run A model API dispatch request carries the caller-visible model run identifier used to correlate model status and output.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ModelRunId(pub String);

/// @behavior selvedge.task.model_run.event_id Client-visible model call events use the same identifier as model run correlation.
pub type ModelCallId = ModelRunId;

/// @behavior selvedge.task.correlation A model API dispatch request and output envelope share API effect, task, and model run identifiers for routing the provider result back to the originating task.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiCallCorrelation {
    /// @behavior selvedge.task.correlation.api_effect_id The correlation identifies the API effect that produced or will receive the model result.
    pub api_effect_id: ApiEffectId,
    /// @behavior selvedge.task.correlation.task_id The correlation identifies the task that owns the model call.
    pub task_id: TaskId,
    /// @behavior selvedge.task.correlation.model_run_id The correlation identifies the model run reported in status and output messages.
    pub model_run_id: ModelRunId,
}

/// @behavior selvedge.task.dispatch A model dispatch request gives a provider profile, conversation path, optional tool manifest, and response preference to the model execution boundary.
#[derive(Clone, Debug, PartialEq)]
pub struct ModelCallDispatchRequest {
    /// @behavior selvedge.task.dispatch.correlation Model dispatch requests carry correlation for routing the provider result back to the caller.
    pub correlation: ApiCallCorrelation,
    /// @behavior selvedge.task.dispatch.provider Model dispatch requests carry the provider profile selected for the call.
    pub provider: ModelProviderProfile,
    /// @behavior selvedge.task.dispatch.conversation Model dispatch requests carry the conversation path sent to the provider boundary.
    pub conversation: ConversationPath,
    /// @behavior selvedge.task.dispatch.tool_manifest Model dispatch requests may carry the tool manifest made available to the provider boundary.
    pub tool_manifest: Option<ToolManifest>,
    /// @behavior selvedge.task.dispatch.response_preference Model dispatch requests carry the response preference visible to provider execution.
    pub response_preference: ResponsePreference,
}

/// @behavior selvedge.task.api_output A completed model call returns either a successful model reply or a model call failure together with the call correlation.
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

/// @behavior selvedge.task.api_output.failure A model call failure exposes a stable failure kind and caller-visible message text.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ModelCallError {
    /// @behavior selvedge.task.api_output.failure.kind_field Model call failures expose the stable failure class to callers.
    pub kind: ModelCallErrorKind,
    /// @behavior selvedge.task.api_output.failure.message Model call failures expose caller-visible message text.
    pub message: String,
}

/// @behavior selvedge.task.api_output.failure.kind Model call failures classify validation, provider request, provider network, provider timeout, provider response, and cancellation outcomes.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ModelCallErrorKind {
    Validation,
    ProviderRequest,
    ProviderNetwork,
    ProviderTimeout,
    ProviderResponse,
    Cancelled,
}

/// @behavior selvedge.task.router_ingress The router accepts ingress messages for client commands, model outputs, core outputs, tool results, runtime exits, event publication, and router stop.
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

/// @behavior selvedge.task.router_ingress.api_alias API output producers use the router ingress message shape when sending model outputs.
pub type RouterIngressApiMessage = RouterIngressMessage;
/// @behavior selvedge.task.router_ingress.sender Router ingress senders enqueue router messages from runtimes, API workers, tools, and client command handlers.
pub type RouterIngressSender = mpsc::UnboundedSender<RouterIngressMessage>;
/// @behavior selvedge.task.router_ingress.weak_sender Weak router ingress senders let internal producers address the router while an external owner keeps ingress open.
pub type RouterIngressWeakSender = mpsc::WeakUnboundedSender<RouterIngressMessage>;
/// @behavior selvedge.task.runtime_command.sender Runtime command senders deliver task runtime commands to one runtime.
pub type TaskRuntimeSender = mpsc::Sender<TaskRuntimeCommand>;
/// @behavior selvedge.task.dispatch.request_alias Runtime model call requests use the model dispatch request shape.
pub type ModelCallRequest = ModelCallDispatchRequest;
/// @behavior selvedge.client.events.sender Event ingress senders deliver client event control messages and raw events to the event boundary.
pub type EventIngressSender = mpsc::Sender<EventIngress>;
/// @behavior selvedge.client.frame.sender Client frame senders deliver snapshot, event, and notice frames to one attached client.
pub type ClientFrameSender = mpsc::Sender<ClientFrame>;
/// @behavior selvedge.task.router_command.attach_result.sender Attach admission senders return the attach admission result to the requester.
pub type RouterAttachAdmissionSender = oneshot::Sender<RouterAttachAdmissionResult>;
/// @behavior selvedge.client.events.reserve.result_sender Event reservation senders return the client session reservation result to the router.
pub type EventClientReservationSender = oneshot::Sender<EventClientReservationResult>;

/// @behavior selvedge.task.factory.effect A factory output carries the caller-visible factory effect identifier that originated the runtime creation request.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct FactoryEffectId(pub String);

/// @behavior selvedge.task.router_command A router command envelope carries optional client correlation fields and a router command payload.
#[derive(Debug)]
pub struct RouterCommandEnvelope {
    /// @behavior selvedge.task.router_command.client_id The router command envelope exposes the client identifier for client-scoped commands.
    pub client_id: Option<ClientId>,
    /// @behavior selvedge.task.router_command.client_command_id The router command envelope exposes the client command identifier for client-scoped commands.
    pub client_command_id: Option<ClientCommandId>,
    /// @behavior selvedge.task.router_command.command The router command envelope carries the requested router action.
    pub command: RouterCommand,
}

/// @behavior selvedge.task.router_command.payload Router commands express client attachment, client detachment, subscription changes, user input, archive requests, runtime stop requests, runtime creation requests, missing runtime scans, and child task creation.
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
    },
    ArchiveTask {
        task_id: TaskId,
    },
    StopTaskRuntime {
        task_id: TaskId,
    },
    EnsureTaskRuntime {
        task_id: TaskId,
    },
    EnsureMissingTaskRuntimes,
    CreateChildTaskAndRuntime {
        parent_task_id: TaskId,
        child_cursor_node_id: HistoryNodeId,
    },
}

/// @behavior selvedge.task.router_command.attach_result Client attachment admission returns accepted, duplicate attach, full registry, or closed event mailbox to the requester.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RouterAttachAdmissionResult {
    Accepted,
    DuplicateAttach,
    ClientRegistryFull,
    EventsMailboxClosed,
}

/// @behavior selvedge.task.router_command.validation Router command validation reports missing client correlation, mismatched client correlation, empty task identifiers, empty user messages, and empty parent task identifiers.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RouterCommandValidationError {
    MissingClientId,
    MissingClientCommandId,
    MismatchedClientId,
    MismatchedClientCommandId,
    EmptyTaskId,
    EmptyMessageText,
    EmptyParentTaskId,
}

/// @behavior selvedge.task.factory.output A factory output envelope returns the effect identifier and either a created runtime, a scan report, or a factory failure.
#[derive(Debug)]
pub struct FactoryOutputEnvelope {
    /// @behavior selvedge.task.factory.output.effect_id Factory output envelopes carry the factory effect identifier being answered.
    pub effect_id: FactoryEffectId,
    /// @behavior selvedge.task.factory.output.result Factory output envelopes carry the runtime creation, scan, or failure result.
    pub output: FactoryOutput,
}

/// @behavior selvedge.task.factory.output.payload Factory output distinguishes a single runtime creation, a scan completion report, and a failed factory call.
#[derive(Debug)]
pub enum FactoryOutput {
    RuntimeCreated(TaskRuntimeCreated),
    ScanFinished(FactoryScanOutput),
    Failed(FactoryFailure),
}

/// @behavior selvedge.task.factory.runtime_created A created runtime result exposes the task identifier, runtime command sender, runtime control handle, and created runtime kind.
#[derive(Debug)]
pub struct TaskRuntimeCreated {
    /// @behavior selvedge.task.factory.runtime_created.task_id Created runtime results expose the task identifier for the runtime.
    pub task_id: TaskId,
    /// @behavior selvedge.task.factory.runtime_created.sender Created runtime results expose the command sender for the runtime.
    pub task_runtime_tx: TaskRuntimeSender,
    /// @behavior selvedge.task.factory.runtime_created.control Created runtime results expose the runtime control handle.
    pub task_runtime_control: TaskRuntimeControl,
    /// @behavior selvedge.task.factory.runtime_created.kind_field Created runtime results expose whether the runtime belongs to an existing task or child task.
    pub created_runtime_kind: CreatedRuntimeKind,
}

/// @behavior selvedge.task.factory.runtime_created.kind A created runtime reports whether it belongs to an existing task or a newly created child task.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CreatedRuntimeKind {
    ExistingTaskRuntime,
    ChildTaskRuntime,
}

/// @behavior selvedge.task.factory.scan A runtime scan result lists tasks with created runtimes, skipped tasks, and failed task runtime creation attempts.
#[derive(Debug)]
pub struct FactoryScanOutput {
    /// @behavior selvedge.task.factory.scan.created Runtime scan output lists runtimes created during the scan.
    pub created: Vec<TaskRuntimeCreated>,
    /// @behavior selvedge.task.factory.scan.skipped_list Runtime scan output lists tasks skipped during the scan.
    pub skipped: Vec<FactorySkippedTask>,
    /// @behavior selvedge.task.factory.scan.failed_list Runtime scan output lists task runtime creation failures observed during the scan.
    pub failed: Vec<FactoryTaskFailure>,
}

/// @behavior selvedge.task.factory.scan.skipped A skipped factory task reports the task identifier and the skip reason visible to the caller.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FactorySkippedTask {
    /// @behavior selvedge.task.factory.scan.skipped.task_id A skipped factory task exposes the skipped task identifier.
    pub task_id: TaskId,
    /// @behavior selvedge.task.factory.scan.skipped.reason A skipped factory task exposes the reason for skipping runtime creation.
    pub reason: FactorySkipReason,
}

/// @behavior selvedge.task.factory.scan.skip_reason A factory scan skip reason reports live runtime or pending runtime creation for the task.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum FactorySkipReason {
    RuntimeAlreadyLive,
    RuntimeCreationPending,
}

/// @behavior selvedge.task.factory.scan.failure A failed factory scan task reports the task identifier, failure kind, and caller-visible message text.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FactoryTaskFailure {
    /// @behavior selvedge.task.factory.scan.failure.task_id A factory scan failure exposes the task identifier that failed.
    pub task_id: TaskId,
    /// @behavior selvedge.task.factory.scan.failure.kind A factory scan failure exposes the failure kind.
    pub kind: FactoryFailureKind,
    /// @behavior selvedge.task.factory.scan.failure.message A factory scan failure exposes caller-visible message text.
    pub message: String,
}

/// @behavior selvedge.task.factory.failure A failed factory call reports an optional task identifier, failure kind, and caller-visible message text.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FactoryFailure {
    /// @behavior selvedge.task.factory.failure.task_id Factory call failures expose task identity when the failure is task-specific.
    pub task_id: Option<TaskId>,
    /// @behavior selvedge.task.factory.failure.kind_field Factory call failures expose the failure kind.
    pub kind: FactoryFailureKind,
    /// @behavior selvedge.task.factory.failure.message Factory call failures expose caller-visible message text.
    pub message: String,
}

/// @behavior selvedge.task.factory.failure.kind Factory failures classify database, parent task, task state, cursor, runtime inventory, duplicate runtime, pending runtime, and core spawn failures.
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

/// @behavior selvedge.client.id Router-facing client messages carry a caller-visible client identifier.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ClientId(pub String);

/// @behavior selvedge.client.command_id Router-facing client messages carry a caller-visible client command identifier.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ClientCommandId(pub String);

/// @constraint selvedge.client.delivery_seq Client frames carry a delivery sequence chosen by the event delivery boundary.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct DeliverySeq(pub u64);

/// @behavior selvedge.client.events.ingress The event ingress accepts event control messages and raw task events from router-owned producers.
#[derive(Debug)]
pub enum EventIngress {
    Control(EventControlMessage),
    Raw(RawEvent),
}

/// @behavior selvedge.client.events.control Event control messages reserve client sessions, begin hydration, deliver snapshots, deliver notices, update subscriptions, and detach clients.
#[derive(Debug)]
pub enum EventControlMessage {
    ReserveClientSession(ReserveClientSession),
    BeginClientHydration(BeginClientHydration),
    DeliverSnapshot(DeliverSnapshot),
    DeliverNotice(DeliverNotice),
    UpdateSubscription(UpdateSubscription),
    DetachClient(DetachClient),
}

/// @behavior selvedge.client.events.reserve A client session reservation request carries client correlation and returns the reservation result through its responder.
#[derive(Debug)]
pub struct ReserveClientSession {
    /// @behavior selvedge.client.events.reserve.client_id Client session reservation carries the client identifier to reserve.
    pub client_id: ClientId,
    /// @behavior selvedge.client.events.reserve.command_id Client session reservation carries the attach command identifier being reserved.
    pub client_command_id: ClientCommandId,
    /// @behavior selvedge.client.events.reserve.responder Client session reservation carries the responder for the reservation result.
    pub result_tx: EventClientReservationSender,
}

/// @behavior selvedge.client.events.reserve.result Client session reservation reports reserved, duplicate attach, or full registry to the router.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum EventClientReservationResult {
    Reserved,
    DuplicateAttach,
    ClientRegistryFull,
}

/// @behavior selvedge.client.events.hydration Beginning client hydration carries client correlation, outbound frame sender, and the requested subscription.
#[derive(Debug)]
pub struct BeginClientHydration {
    /// @behavior selvedge.client.events.hydration.client_id Client hydration carries the client identifier being hydrated.
    pub client_id: ClientId,
    /// @behavior selvedge.client.events.hydration.command_id Client hydration carries the attach command identifier.
    pub client_command_id: ClientCommandId,
    /// @behavior selvedge.client.events.hydration.outbound Client hydration carries the outbound client frame sender.
    pub outbound: ClientFrameSender,
    /// @behavior selvedge.client.events.hydration.subscription Client hydration carries the requested subscription.
    pub subscription: ClientSubscription,
}

/// @behavior selvedge.client.events.snapshot_delivery Snapshot delivery carries client correlation and a client snapshot.
#[derive(Clone, Debug, PartialEq)]
pub struct DeliverSnapshot {
    /// @behavior selvedge.client.events.snapshot_delivery.client_id Snapshot delivery carries the client identifier receiving the snapshot.
    pub client_id: ClientId,
    /// @behavior selvedge.client.events.snapshot_delivery.command_id Snapshot delivery carries the attach command identifier for the snapshot.
    pub client_command_id: ClientCommandId,
    /// @behavior selvedge.client.events.snapshot_delivery.snapshot Snapshot delivery carries the snapshot visible to the client.
    pub snapshot: ClientSnapshot,
}

/// @behavior selvedge.client.events.notice_delivery Notice delivery carries client correlation and a client notice.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DeliverNotice {
    /// @behavior selvedge.client.events.notice_delivery.client_id Notice delivery carries the client identifier receiving the notice.
    pub client_id: ClientId,
    /// @behavior selvedge.client.events.notice_delivery.command_id Notice delivery carries the client command identifier associated with the notice.
    pub client_command_id: ClientCommandId,
    /// @behavior selvedge.client.events.notice_delivery.notice Notice delivery carries the notice visible to the client.
    pub notice: ClientNotice,
}

/// @behavior selvedge.client.events.subscription_update Subscription updates carry client correlation and the replacement subscription.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct UpdateSubscription {
    /// @behavior selvedge.client.events.subscription_update.client_id Subscription update carries the client identifier being updated.
    pub client_id: ClientId,
    /// @behavior selvedge.client.events.subscription_update.command_id Subscription update carries the client command identifier.
    pub client_command_id: ClientCommandId,
    /// @behavior selvedge.client.events.subscription_update.subscription Subscription update carries the replacement subscription.
    pub subscription: ClientSubscription,
}

/// @behavior selvedge.client.events.detach Client detachment carries client correlation and a visible detach reason.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DetachClient {
    /// @behavior selvedge.client.events.detach.client_id Client detachment carries the client identifier being detached.
    pub client_id: ClientId,
    /// @behavior selvedge.client.events.detach.command_id Client detachment carries the client command identifier.
    pub client_command_id: ClientCommandId,
    /// @behavior selvedge.client.events.detach.reason Client detachment carries the visible detach reason.
    pub reason: DetachReason,
}

/// @behavior selvedge.client.subscription A client subscription selects task scope, detail level, and inclusion of model, tool, and debug events.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ClientSubscription {
    /// @behavior selvedge.client.subscription.task_scope_field Client subscriptions expose the requested task scope.
    pub task_scope: TaskScope,
    /// @behavior selvedge.client.subscription.detail_field Client subscriptions expose the requested detail level.
    pub detail_level: DetailLevel,
    /// @behavior selvedge.client.subscription.include_model_call_status Client subscriptions expose whether model call status events are included.
    pub include_model_call_status: bool,
    /// @behavior selvedge.client.subscription.include_tool_execution_status Client subscriptions expose whether tool execution status events are included.
    pub include_tool_execution_status: bool,
    /// @behavior selvedge.client.subscription.include_debug_notices Client subscriptions expose whether debug notices are included.
    pub include_debug_notices: bool,
}

/// @behavior selvedge.client.subscription.task_scope A client subscription can request every task or an explicit set of task identifiers.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TaskScope {
    AllTasks,
    TaskIds(BTreeSet<TaskId>),
}

/// @behavior selvedge.client.subscription.detail A client subscription can request summary or verbose task detail.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DetailLevel {
    Summary,
    Verbose,
}

/// @behavior selvedge.client.events.raw Raw task events expose task changes, appended history, model call status, tool execution status, and debug notices.
#[derive(Clone, Debug, PartialEq)]
pub enum RawEvent {
    TaskChanged(TaskChangedRawEvent),
    HistoryAppended(HistoryAppendedRawEvent),
    ModelCallStatus(ModelCallStatusRawEvent),
    ToolExecutionStatus(ToolExecutionStatusRawEvent),
    Debug(DebugRawEvent),
}

/// @behavior selvedge.client.events.raw.task_changed A task changed raw event exposes the latest task projection to subscribers.
#[derive(Clone, Debug, PartialEq)]
pub struct TaskChangedRawEvent {
    /// @behavior selvedge.client.events.raw.task_changed.task A task changed raw event carries the updated task projection.
    pub task: TaskProjection,
}

/// @behavior selvedge.client.events.raw.history_appended A history appended raw event exposes the task identifier, task state version, and appended history nodes.
#[derive(Clone, Debug, PartialEq)]
pub struct HistoryAppendedRawEvent {
    /// @behavior selvedge.client.events.raw.history_appended.task_id A history appended raw event carries the task identifier whose history changed.
    pub task_id: TaskId,
    /// @behavior selvedge.client.events.raw.history_appended.version A history appended raw event carries the resulting task state version.
    pub task_state_version: u64,
    /// @behavior selvedge.client.events.raw.history_appended.nodes A history appended raw event carries the appended history nodes.
    pub appended_nodes: Vec<HistoryNodeProjection>,
}

/// @behavior selvedge.client.events.raw.model_call_status A model call status raw event exposes the task identifier, model call identifier, and model call phase.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ModelCallStatusRawEvent {
    /// @behavior selvedge.client.events.raw.model_call_status.task_id A model call status raw event carries the task identifier.
    pub task_id: TaskId,
    /// @behavior selvedge.client.events.raw.model_call_status.model_call_id A model call status raw event carries the model call identifier.
    pub model_call_id: ModelCallId,
    /// @behavior selvedge.client.events.raw.model_call_status.phase A model call status raw event carries the reported model call phase.
    pub phase: ModelCallStatusPhase,
}

/// @behavior selvedge.client.events.raw.tool_status A tool execution status raw event exposes the task identifier, tool run identifier, function call node, tool name, and tool phase.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ToolExecutionStatusRawEvent {
    /// @behavior selvedge.client.events.raw.tool_status.task_id A tool execution status raw event carries the task identifier.
    pub task_id: TaskId,
    /// @behavior selvedge.client.events.raw.tool_status.run_id A tool execution status raw event carries the tool execution run identifier.
    pub tool_execution_run_id: ToolExecutionRunId,
    /// @behavior selvedge.client.events.raw.tool_status.node_id A tool execution status raw event carries the function call history node identifier.
    pub function_call_node_id: HistoryNodeId,
    /// @behavior selvedge.client.events.raw.tool_status.tool_name A tool execution status raw event carries the tool name.
    pub tool_name: ToolName,
    /// @behavior selvedge.client.events.raw.tool_status.phase A tool execution status raw event carries the reported tool execution phase.
    pub phase: ToolExecutionStatusPhase,
}

/// @behavior selvedge.client.events.raw.debug A debug raw event exposes optional task correlation and debug message text.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DebugRawEvent {
    /// @behavior selvedge.client.events.raw.debug.task_id A debug raw event may carry task identity for task-scoped debug notices.
    pub task_id: Option<TaskId>,
    /// @behavior selvedge.client.events.raw.debug.message A debug raw event carries debug message text.
    pub message_text: String,
}

/// @behavior selvedge.client.snapshot A client snapshot exposes generation time, tasks, task parent edges, history nodes, and task versions.
#[derive(Clone, Debug, PartialEq)]
pub struct ClientSnapshot {
    /// @behavior selvedge.client.snapshot.generated_at Client snapshots expose their generation timestamp.
    pub generated_at: UnixTs,
    /// @behavior selvedge.client.snapshot.tasks Client snapshots expose task projections.
    pub tasks: Vec<TaskProjection>,
    /// @behavior selvedge.client.snapshot.parent_edges Client snapshots expose task parent edges.
    pub task_parent_edges: Vec<TaskParentProjection>,
    /// @behavior selvedge.client.snapshot.history_nodes Client snapshots expose history node projections.
    pub history_nodes: Vec<HistoryNodeProjection>,
    /// @behavior selvedge.client.snapshot.task_versions Client snapshots expose task state versions included in the snapshot.
    pub task_versions: Vec<SnapshotTaskVersion>,
}

/// @constraint selvedge.client.snapshot.version A snapshot task version pairs one task identifier with the task state version included in the snapshot.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SnapshotTaskVersion {
    /// @constraint selvedge.client.snapshot.version.task_id Snapshot task versions identify the task whose state version is reported.
    pub task_id: TaskId,
    /// @constraint selvedge.client.snapshot.version.state_version Snapshot task versions report the task state version visible in the snapshot.
    pub state_version: u64,
}

/// @behavior selvedge.client.task_projection A task projection exposes task identity, status, cursor, model profile, reasoning effort, state version, and timestamps.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TaskProjection {
    /// @behavior selvedge.client.task_projection.task_id Task projections expose the projected task identifier.
    pub task_id: TaskId,
    /// @behavior selvedge.client.task_projection.status_field Task projections expose active or archived status.
    pub status: TaskProjectionStatus,
    /// @behavior selvedge.client.task_projection.cursor Task projections expose the current cursor history node identifier.
    pub cursor_node_id: HistoryNodeId,
    /// @behavior selvedge.client.task_projection.model_profile Task projections expose the selected model profile key.
    pub model_profile_key: ModelProfileKey,
    /// @behavior selvedge.client.task_projection.reasoning_effort Task projections expose the selected reasoning effort.
    pub reasoning_effort: ReasoningEffort,
    /// @behavior selvedge.client.task_projection.state_version Task projections expose the task state version.
    pub state_version: u64,
    /// @behavior selvedge.client.task_projection.created_at Task projections expose the task creation timestamp.
    pub created_at: UnixTs,
    /// @behavior selvedge.client.task_projection.updated_at Task projections expose the latest task update timestamp.
    pub updated_at: UnixTs,
}

/// @behavior selvedge.client.task_projection.status A task projection reports active or archived status.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TaskProjectionStatus {
    Active,
    Archived,
}

/// @behavior selvedge.client.task_projection.parent A task parent projection exposes a parent task identifier and child task identifier.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TaskParentProjection {
    /// @behavior selvedge.client.task_projection.parent.parent_task_id Task parent projections expose the parent task identifier.
    pub parent_task_id: TaskId,
    /// @behavior selvedge.client.task_projection.parent.child_task_id Task parent projections expose the child task identifier.
    pub child_task_id: TaskId,
}

/// @behavior selvedge.client.history_projection A history node projection exposes node identity, optional parent identity, creation time, and node body.
#[derive(Clone, Debug, PartialEq)]
pub struct HistoryNodeProjection {
    /// @behavior selvedge.client.history_projection.node_id History node projections expose the node identifier.
    pub node_id: HistoryNodeId,
    /// @behavior selvedge.client.history_projection.parent_node_id History node projections expose the optional parent node identifier.
    pub parent_node_id: Option<HistoryNodeId>,
    /// @behavior selvedge.client.history_projection.created_at History node projections expose the node creation timestamp.
    pub created_at: UnixTs,
    /// @behavior selvedge.client.history_projection.body_field History node projections expose the visible node body.
    pub body: HistoryNodeProjectionBody,
}

/// @behavior selvedge.client.history_projection.body A history node body exposes messages, reasoning text, function calls, and function outputs to clients.
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

/// @behavior selvedge.client.frame A client frame is a snapshot, event, or notice delivered to an attached client.
#[derive(Clone, Debug, PartialEq)]
pub enum ClientFrame {
    Snapshot(ClientSnapshotFrame),
    Event(ClientEventFrame),
    Notice(ClientNoticeFrame),
}

/// @behavior selvedge.client.frame.snapshot A snapshot frame carries delivery sequence, attach command identifier, and the snapshot payload.
#[derive(Clone, Debug, PartialEq)]
pub struct ClientSnapshotFrame {
    /// @behavior selvedge.client.frame.snapshot.delivery_seq Snapshot frames expose the delivery sequence assigned to the frame.
    pub delivery_seq: DeliverySeq,
    /// @behavior selvedge.client.frame.snapshot.command_id Snapshot frames expose the attach command identifier.
    pub client_command_id: ClientCommandId,
    /// @behavior selvedge.client.frame.snapshot.payload Snapshot frames expose the snapshot payload.
    pub snapshot: ClientSnapshot,
}

/// @behavior selvedge.client.frame.event An event frame carries delivery sequence and a client event payload.
#[derive(Clone, Debug, PartialEq)]
pub struct ClientEventFrame {
    /// @behavior selvedge.client.frame.event.delivery_seq Event frames expose the delivery sequence assigned to the frame.
    pub delivery_seq: DeliverySeq,
    /// @behavior selvedge.client.frame.event.payload Event frames expose the client event payload.
    pub event: ClientEvent,
}

/// @behavior selvedge.client.frame.notice A notice frame carries delivery sequence, client command identifier, and notice payload.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ClientNoticeFrame {
    /// @behavior selvedge.client.frame.notice.delivery_seq Notice frames expose the delivery sequence assigned to the frame.
    pub delivery_seq: DeliverySeq,
    /// @behavior selvedge.client.frame.notice.command_id Notice frames expose the client command identifier.
    pub client_command_id: ClientCommandId,
    /// @behavior selvedge.client.frame.notice.payload Notice frames expose the notice payload.
    pub notice: ClientNotice,
}

/// @behavior selvedge.client.event A client event exposes task changes, appended history, model call status, tool execution status, and debug notices.
#[derive(Clone, Debug, PartialEq)]
pub enum ClientEvent {
    TaskChanged(TaskChangedEvent),
    HistoryAppended(HistoryAppendedEvent),
    ModelCallStatus(ModelCallStatusEvent),
    ToolExecutionStatus(ToolExecutionStatusEvent),
    DebugNotice(DebugNoticeEvent),
}

/// @behavior selvedge.client.event.task_changed A task changed event exposes the latest task projection to the client.
#[derive(Clone, Debug, PartialEq)]
pub struct TaskChangedEvent {
    /// @behavior selvedge.client.event.task_changed.task Task changed events expose the updated task projection.
    pub task: TaskProjection,
}

/// @behavior selvedge.client.event.history_appended A history appended event exposes task identity, task state version, and appended history nodes to the client.
#[derive(Clone, Debug, PartialEq)]
pub struct HistoryAppendedEvent {
    /// @behavior selvedge.client.event.history_appended.task_id History appended events expose the task identifier whose history changed.
    pub task_id: TaskId,
    /// @behavior selvedge.client.event.history_appended.version History appended events expose the resulting task state version.
    pub task_state_version: u64,
    /// @behavior selvedge.client.event.history_appended.nodes History appended events expose the appended history nodes.
    pub appended_nodes: Vec<HistoryNodeProjection>,
}

/// @behavior selvedge.client.event.model_call_status A model call status event exposes task identity, model call identity, and model call phase to the client.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ModelCallStatusEvent {
    /// @behavior selvedge.client.event.model_call_status.task_id Model call status events expose the task identifier.
    pub task_id: TaskId,
    /// @behavior selvedge.client.event.model_call_status.model_call_id Model call status events expose the model call identifier.
    pub model_call_id: ModelCallId,
    /// @behavior selvedge.client.event.model_call_status.phase Model call status events expose the reported model call phase.
    pub phase: ModelCallStatusPhase,
}

/// @behavior selvedge.client.event.tool_status A tool execution status event exposes task identity, tool execution identity, function call node, tool name, and phase to the client.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ToolExecutionStatusEvent {
    /// @behavior selvedge.client.event.tool_status.task_id Tool execution status events expose the task identifier.
    pub task_id: TaskId,
    /// @behavior selvedge.client.event.tool_status.run_id Tool execution status events expose the tool execution run identifier.
    pub tool_execution_run_id: ToolExecutionRunId,
    /// @behavior selvedge.client.event.tool_status.node_id Tool execution status events expose the function call node identifier.
    pub function_call_node_id: HistoryNodeId,
    /// @behavior selvedge.client.event.tool_status.tool_name Tool execution status events expose the tool name.
    pub tool_name: ToolName,
    /// @behavior selvedge.client.event.tool_status.phase Tool execution status events expose the reported tool execution phase.
    pub phase: ToolExecutionStatusPhase,
}

/// @behavior selvedge.client.event.debug_notice A debug notice event exposes optional task correlation and debug message text to the client.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DebugNoticeEvent {
    /// @behavior selvedge.client.event.debug_notice.task_id Debug notice events may expose task identity.
    pub task_id: Option<TaskId>,
    /// @behavior selvedge.client.event.debug_notice.message Debug notice events expose debug message text.
    pub message_text: String,
}

/// @behavior selvedge.client.notice A client notice exposes severity level and message text.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ClientNotice {
    /// @behavior selvedge.client.notice.level_field Client notices expose the notice severity level.
    pub level: ClientNoticeLevel,
    /// @behavior selvedge.client.notice.message Client notices expose message text.
    pub message_text: String,
}

/// @behavior selvedge.client.notice.level A client notice reports info, warning, or error severity.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ClientNoticeLevel {
    Info,
    Warning,
    Error,
}

/// @behavior selvedge.task.model_status_phase A model call status reports requested, completed, failed, or discarded phases.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ModelCallStatusPhase {
    Requested,
    Completed,
    Failed,
    Discarded,
}

/// @behavior selvedge.task.tool_status_phase A tool execution status reports requested, completed, failed, or discarded phases.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ToolExecutionStatusPhase {
    Requested,
    Completed,
    Failed,
    Discarded,
}

/// @behavior selvedge.client.detach_reason Client detach reasons distinguish requested detach, disconnected clients, replacement hydration, delivery failure, hydration overflow, and event shutdown.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DetachReason {
    ClientRequested,
    ClientDisconnected,
    ReplacedByNewHydration,
    DeliveryFailed,
    HydrationBufferOverflow,
    EventsShutdown,
}

/// @behavior selvedge.task.runtime_control A task runtime control handle exposes freeze, unfreeze, stop, control-change, stop-finish, and handle-identity operations for one runtime.
#[derive(Clone)]
pub struct TaskRuntimeControl {
    inner: Arc<TaskRuntimeControlInner>,
}

/// @intent selvedge.task.runtime_control.state The runtime control state coordinates caller-visible freeze and stop outcomes shared by every clone of the same control handle.
struct TaskRuntimeControlInner {
    frozen: AtomicBool,
    stopping: AtomicBool,
    stop_result: Mutex<Option<TaskRuntimeStopResult>>,
    actor_notify: Notify,
    stop_notify: Notify,
}

/// @behavior selvedge.task.runtime_control.stop_result A task runtime stop result marks completion of the runtime stop barrier.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TaskRuntimeStopResult;

impl TaskRuntimeControl {
    /// @behavior selvedge.task.runtime_control.new A new runtime control starts unfrozen and without a stop request.
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

    /// @behavior selvedge.task.runtime_control.freeze Freezing a runtime control makes `is_frozen` return true and wakes runtime control waiters.
    pub fn freeze(&self) {
        self.inner.frozen.store(true, Ordering::SeqCst);
        self.inner.actor_notify.notify_one();
    }

    /// @behavior selvedge.task.runtime_control.unfreeze Unfreezing a runtime control makes `is_frozen` return false and wakes runtime control waiters.
    pub fn unfreeze(&self) {
        self.inner.frozen.store(false, Ordering::SeqCst);
        self.inner.actor_notify.notify_one();
    }

    /// @behavior selvedge.task.runtime_control.is_frozen Runtime callers can observe the current frozen flag on a runtime control handle.
    pub fn is_frozen(&self) -> bool {
        self.inner.frozen.load(Ordering::SeqCst)
    }

    /// @behavior selvedge.task.runtime_control.is_stopping Runtime callers can observe whether stop has been requested on a runtime control handle.
    pub fn is_stopping(&self) -> bool {
        self.inner.stopping.load(Ordering::SeqCst)
    }

    /// @behavior selvedge.task.runtime_control.stop Stopping a runtime control sets the stopping flag, wakes the runtime, and resolves after the runtime publishes a stop result.
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

    /// @behavior selvedge.task.runtime_control.wait Runtime callers can wait for freeze, unfreeze, or stop control changes.
    pub async fn wait_for_control_change(&self) {
        self.inner.actor_notify.notified().await;
    }

    /// @behavior selvedge.task.runtime_control.finish_stop Finishing a runtime stop publishes the first stop result and wakes all stop waiters.
    pub async fn finish_stop(&self, result: TaskRuntimeStopResult) {
        let mut stop_result = self.inner.stop_result.lock().await;
        if stop_result.is_none() {
            *stop_result = Some(result);
            self.inner.stop_notify.notify_waiters();
        }
    }

    /// @behavior selvedge.task.runtime_control.same_control Runtime callers can compare whether two control handles address the same runtime control state.
    pub fn same_control(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.inner, &other.inner)
    }
}

impl Default for TaskRuntimeControl {
    /// @behavior selvedge.task.runtime_control.default The default runtime control has the same initial caller-visible state as `TaskRuntimeControl::new`.
    fn default() -> Self {
        Self::new()
    }
}

impl fmt::Debug for TaskRuntimeControl {
    /// @behavior selvedge.task.runtime_control.debug Debug output for a runtime control exposes frozen and stopping state without exposing synchronization internals.
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("TaskRuntimeControl")
            .field("frozen", &self.is_frozen())
            .field("stopping", &self.is_stopping())
            .finish_non_exhaustive()
    }
}

impl PartialEq for TaskRuntimeControl {
    /// @behavior selvedge.task.runtime_control.eq Runtime control equality reports whether two handles address the same runtime control state.
    fn eq(&self, other: &Self) -> bool {
        self.same_control(other)
    }
}

impl Eq for TaskRuntimeControl {}

/// @behavior selvedge.task.tool_run A tool execution request and result carry the caller-visible tool execution run identifier.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ToolExecutionRunId(pub String);

/// @behavior selvedge.task.runtime_command A task runtime command carries start, user input, model reply, tool result, or archive instructions to one runtime.
#[derive(Debug)]
pub enum TaskRuntimeCommand {
    Start,
    UserInput { message_text: String },
    ApiModelReply(ApiOutputEnvelope),
    ToolResult(ToolExecutionResult),
    Archive,
}

/// @behavior selvedge.task.runtime_exit A task runtime exit notice exposes task identity, runtime control identity, and exit reason to the router.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TaskRuntimeExitNotice {
    /// @behavior selvedge.task.runtime_exit.task_id Runtime exit notices expose the exited task identifier.
    pub task_id: TaskId,
    /// @behavior selvedge.task.runtime_exit.control Runtime exit notices expose the runtime control handle for the exited runtime.
    pub task_runtime_control: TaskRuntimeControl,
    /// @behavior selvedge.task.runtime_exit.reason_field Runtime exit notices expose the runtime exit reason.
    pub reason: TaskRuntimeExitReason,
}

/// @behavior selvedge.task.runtime_exit.reason A task runtime exit reason reports stopped, archived, database error, or internal error outcomes.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TaskRuntimeExitReason {
    Stopped,
    Archived,
    DbError(String),
    InternalError(String),
}

/// @behavior selvedge.task.core_output A core output envelope carries the task identifier used by the router and a core output message.
#[derive(Debug)]
pub struct CoreOutputEnvelope {
    /// @behavior selvedge.task.core_output.task_id Core output envelopes expose the task identifier used for router routing.
    pub task_id: TaskId,
    /// @behavior selvedge.task.core_output.payload Core output envelopes expose the core output message.
    pub message: CoreOutputMessage,
}

/// @behavior selvedge.task.core_output.message Core output messages request model calls, request tool execution, publish domain events, or signal runtime readiness.
#[derive(Debug)]
pub enum CoreOutputMessage {
    RequestModelCall(ModelCallRequest),
    RequestToolExecution(ToolExecutionRequest),
    PublishDomainEvent(DomainEventPublishRequest),
    RuntimeReady,
}

/// @behavior selvedge.task.tool_request A tool execution request exposes task identity, tool run identity, function call identity, tool name, and arguments to the tool boundary.
#[derive(Clone, Debug, PartialEq)]
pub struct ToolExecutionRequest {
    /// @behavior selvedge.task.tool_request.task_id Tool execution requests expose the task identifier requesting tool execution.
    pub task_id: TaskId,
    /// @behavior selvedge.task.tool_request.run_id Tool execution requests expose the tool execution run identifier.
    pub tool_execution_run_id: ToolExecutionRunId,
    /// @behavior selvedge.task.tool_request.node_id Tool execution requests expose the function call history node identifier.
    pub function_call_node_id: HistoryNodeId,
    /// @behavior selvedge.task.tool_request.call_id Tool execution requests expose the function call identifier.
    pub function_call_id: FunctionCallId,
    /// @behavior selvedge.task.tool_request.tool_name Tool execution requests expose the tool name.
    pub tool_name: ToolName,
    /// @behavior selvedge.task.tool_request.arguments Tool execution requests expose tool call arguments.
    pub arguments: Vec<ToolCallArgument>,
}

/// @behavior selvedge.task.tool_result A tool execution result exposes task identity, tool run identity, function call identity, tool name, output text, and error flag to the runtime.
#[derive(Clone, Debug, PartialEq)]
pub struct ToolExecutionResult {
    /// @behavior selvedge.task.tool_result.task_id Tool execution results expose the task identifier receiving the result.
    pub task_id: TaskId,
    /// @behavior selvedge.task.tool_result.run_id Tool execution results expose the tool execution run identifier.
    pub tool_execution_run_id: ToolExecutionRunId,
    /// @behavior selvedge.task.tool_result.node_id Tool execution results expose the function call history node identifier.
    pub function_call_node_id: HistoryNodeId,
    /// @behavior selvedge.task.tool_result.call_id Tool execution results expose the function call identifier.
    pub function_call_id: FunctionCallId,
    /// @behavior selvedge.task.tool_result.tool_name Tool execution results expose the tool name.
    pub tool_name: ToolName,
    /// @behavior selvedge.task.tool_result.output_text Tool execution results expose output text.
    pub output_text: String,
    /// @behavior selvedge.task.tool_result.is_error Tool execution results expose whether the output text is an error.
    pub is_error: bool,
}

/// @behavior selvedge.task.domain_event_publish A domain event publish request exposes task identity and domain event payload to the event boundary.
#[derive(Clone, Debug, PartialEq)]
pub struct DomainEventPublishRequest {
    /// @behavior selvedge.task.domain_event_publish.task_id Domain event publish requests expose the task identifier for the event.
    pub task_id: TaskId,
    /// @behavior selvedge.task.domain_event_publish.event Domain event publish requests expose the domain event payload.
    pub event: DomainEvent,
}

/// @behavior selvedge.task.domain_event Domain events expose runtime readiness, committed history nodes, task archival, and error notices for a task.
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

/// @behavior selvedge.task.dispatch.validation Dispatch request validation accepts complete request fields and returns validation failures with stable validation kind and field-specific message text.
pub fn validate_dispatch_request(request: &ModelCallDispatchRequest) -> Result<(), ModelCallError> {
    validate_correlation(&request.correlation)?;

    validate_model_provider_profile(&request.provider)
        .map_err(|error| validation_error("provider", error))?;

    validate_conversation_path(&request.conversation)
        .map_err(|error| validation_error("conversation", error))?;

    if let Some(tool_manifest) = &request.tool_manifest {
        // @constraint selvedge.task.dispatch.validation.tool_manifest Dispatch request validation reports a field-specific validation error for invalid tool manifests.
        validate_tool_manifest(tool_manifest)
            .map_err(|error| validation_error("tool_manifest", error))?;
    }

    Ok(())
}

/// @behavior selvedge.task.api_output.validation API output validation accepts valid success replies and validates failure correlation unless the failure itself reports validation.
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

/// @behavior selvedge.task.router_command.validation_result Router command validation accepts valid command envelopes and reports stable validation errors for invalid caller-visible fields.
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
            // @constraint selvedge.task.router_command.validation_result.client_correlation Client-scoped router commands require present, non-empty, and matching client correlation fields.
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
        } => {
            // @constraint selvedge.task.router_command.validation_result.user_input User-input router commands require a non-empty task identifier and non-empty message text.
            validate_task_id(task_id)?;
            if message_text.trim().is_empty() {
                return Err(RouterCommandValidationError::EmptyMessageText);
            }
        }
        RouterCommand::ArchiveTask { task_id }
        | RouterCommand::StopTaskRuntime { task_id }
        | RouterCommand::EnsureTaskRuntime { task_id } => {
            // @constraint selvedge.task.router_command.validation_result.task_scoped Task-scoped router commands require a non-empty task identifier.
            validate_task_id(task_id)?
        }
        RouterCommand::EnsureMissingTaskRuntimes => {}
        RouterCommand::CreateChildTaskAndRuntime { parent_task_id, .. } => {
            // @constraint selvedge.task.router_command.validation_result.child_task Child-task runtime creation requires a non-empty parent task identifier.
            if parent_task_id.0.trim().is_empty() {
                return Err(RouterCommandValidationError::EmptyParentTaskId);
            }
        }
    }

    Ok(())
}

/// @constraint selvedge.task.correlation.validation API call correlation rejects empty API effect, task, and model run identifiers with validation error messages naming the invalid field.
fn validate_correlation(correlation: &ApiCallCorrelation) -> Result<(), ModelCallError> {
    if correlation.api_effect_id.0.trim().is_empty() {
        // @constraint selvedge.task.correlation.validation.api_effect Validation rejects empty API effect identifiers with a field-named validation message.
        return Err(validation_message("api_effect_id must not be empty"));
    }

    if correlation.task_id.0.trim().is_empty() {
        // @constraint selvedge.task.correlation.validation.task Validation rejects empty task identifiers with a field-named validation message.
        return Err(validation_message("task_id must not be empty"));
    }

    if correlation.model_run_id.0.trim().is_empty() {
        // @constraint selvedge.task.correlation.validation.model_run Validation rejects empty model run identifiers with a field-named validation message.
        return Err(validation_message("model_run_id must not be empty"));
    }

    Ok(())
}

/// @constraint selvedge.client.id.validation Router command validation requires client identifiers to be present and non-empty when a command is client-scoped.
fn validate_client_id(client_id: Option<&ClientId>) -> Result<(), RouterCommandValidationError> {
    match client_id {
        Some(client_id) if !client_id.0.trim().is_empty() => Ok(()),
        Some(_) | None => Err(RouterCommandValidationError::MissingClientId),
    }
}

/// @constraint selvedge.client.command_id.validation Router command validation requires client command identifiers to be present and non-empty when a command is client-scoped.
fn validate_client_command_id(
    client_command_id: Option<&ClientCommandId>,
) -> Result<(), RouterCommandValidationError> {
    match client_command_id {
        Some(client_command_id) if !client_command_id.0.trim().is_empty() => Ok(()),
        Some(_) | None => Err(RouterCommandValidationError::MissingClientCommandId),
    }
}

/// @constraint selvedge.task.id.validation Router command validation rejects empty task identifiers for task-scoped commands.
fn validate_task_id(task_id: &TaskId) -> Result<(), RouterCommandValidationError> {
    if task_id.0.trim().is_empty() {
        return Err(RouterCommandValidationError::EmptyTaskId);
    }

    Ok(())
}

/// @behavior selvedge.task.validation_error Domain validation failures become model validation errors with field-specific message text.
fn validation_error(field: &str, error: ApiDomainValidationError) -> ModelCallError {
    validation_message(format!("{field} is invalid: {error:?}"))
}

/// @behavior selvedge.task.validation_message Model validation messages carry validation kind and caller-visible message text.
fn validation_message(message: impl Into<String>) -> ModelCallError {
    ModelCallError {
        kind: ModelCallErrorKind::Validation,
        message: message.into(),
    }
}
