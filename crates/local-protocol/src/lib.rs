#![doc = include_str!("../README.md")]
//! @behavior selvedge.client.protocol The local protocol serializes ready probes, command submissions, attach requests, attach responses, stream frames, snapshots, events, and validation problems for localhost clients.
//! @behavior selvedge.client.protocol.ready Ready protocol messages let localhost clients observe server readiness for a protocol version.
//! @behavior selvedge.client.protocol.command Command protocol messages let localhost clients submit command names with JSON payloads and receive accepted or rejected outcomes.
//! @behavior selvedge.client.protocol.attach Attach protocol messages let localhost clients request a subscribed task stream and receive accepted or rejected attach results.
//! @behavior selvedge.client.protocol.attach_stream The attach stream protocol delivers one accepted response followed by frames and a terminal stream error when needed.
//! @behavior selvedge.client.protocol.task_id Task-scoped local protocol payloads carry non-empty task identifiers.
//! @constraint selvedge.client.protocol.delivery_seq Delivered local client frames use positive delivery sequence numbers.
//! @constraint selvedge.client.protocol.tool_name Tool-related local protocol payloads carry non-empty tool names.

use std::collections::BTreeSet;

use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;

/// @constraint selvedge.client.protocol.version.constant Local protocol messages produced by this crate advertise protocol version 2.
pub const LOCAL_PROTOCOL_VERSION: u32 = 2;

/// @constraint selvedge.client.protocol.version The local protocol version advertised by this crate is version 2.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProtocolVersion(pub u32);

/// @behavior selvedge.client.protocol.client_id Local protocol requests carry a non-empty client identifier.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct LocalClientId(pub String);

/// @behavior selvedge.client.protocol.command_id Local protocol requests carry a non-empty client command identifier.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct LocalClientCommandId(pub String);

/// @behavior selvedge.client.protocol.ready.request A ready request carries the protocol version the client wants to use.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReadyRequest {
    /// @behavior selvedge.client.protocol.ready.request.version Ready requests expose the client protocol version.
    pub protocol_version: ProtocolVersion,
}

/// @behavior selvedge.client.protocol.ready.response A ready response carries the server protocol version and current ready state.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReadyResponse {
    /// @behavior selvedge.client.protocol.ready.response.version Ready responses expose the server protocol version.
    pub protocol_version: ProtocolVersion,
    /// @behavior selvedge.client.protocol.ready.response.state Ready responses expose the server ready state.
    pub state: ReadyState,
}

/// @behavior selvedge.client.protocol.ready.state A ready response reports ready or not-ready state.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum ReadyState {
    Ready,
    NotReady,
}

/// @behavior selvedge.client.protocol.command.request A command request carries protocol version, client correlation, command name, and JSON payload.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct CommandRequest {
    /// @behavior selvedge.client.protocol.command.request.version Command requests expose the client protocol version.
    pub protocol_version: ProtocolVersion,
    /// @behavior selvedge.client.protocol.command.request.client_id Command requests expose the client identifier.
    pub client_id: LocalClientId,
    /// @behavior selvedge.client.protocol.command.request.command_id Command requests expose the client command identifier.
    pub client_command_id: LocalClientCommandId,
    /// @behavior selvedge.client.protocol.command.request.name Command requests expose the command name.
    pub command_name: String,
    /// @behavior selvedge.client.protocol.command.request.payload Command requests expose the JSON command payload.
    pub payload: JsonValue,
}

/// @behavior selvedge.client.protocol.command.response A command response carries protocol version, client command identifier, and command outcome.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CommandResponse {
    /// @behavior selvedge.client.protocol.command.response.version Command responses expose the server protocol version.
    pub protocol_version: ProtocolVersion,
    /// @behavior selvedge.client.protocol.command.response.command_id Command responses expose the client command identifier being answered.
    pub client_command_id: LocalClientCommandId,
    /// @behavior selvedge.client.protocol.command.response.outcome Command responses expose the command outcome.
    pub outcome: CommandOutcome,
}

/// @behavior selvedge.client.protocol.command.outcome A command outcome reports accepted or rejected with a rejection reason.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum CommandOutcome {
    Accepted,
    Rejected(CommandRejectReason),
}

/// @behavior selvedge.client.protocol.command.reject_reason A command rejection reports protocol mismatch, malformed request, readiness, unsupported command, closed router mailbox, or internal failure.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum CommandRejectReason {
    ProtocolVersionMismatch,
    MalformedRequest,
    ServerNotReady,
    UnsupportedCommand,
    RouterMailboxClosed,
    InternalFailure,
}

/// @behavior selvedge.client.protocol.attach.reject_reason Attach rejection reports protocol mismatch, malformed request, readiness, duplicate attach, registry capacity, closed router mailbox, unavailable client sync, channel creation failure, or internal failure.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum AttachRejectReason {
    ProtocolVersionMismatch,
    MalformedRequest,
    ServerNotReady,
    DuplicateAttach,
    ClientRegistryFull,
    RouterMailboxClosed,
    ClientSyncUnavailable,
    AttachChannelFailed,
    InternalFailure,
}

/// @behavior selvedge.client.protocol.attach.request An attach request carries protocol version, client correlation, and requested subscription.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AttachRequest {
    /// @behavior selvedge.client.protocol.attach.request.version Attach requests expose the client protocol version.
    pub protocol_version: ProtocolVersion,
    /// @behavior selvedge.client.protocol.attach.request.client_id Attach requests expose the client identifier.
    pub client_id: LocalClientId,
    /// @behavior selvedge.client.protocol.attach.request.command_id Attach requests expose the attach command identifier.
    pub client_command_id: LocalClientCommandId,
    /// @behavior selvedge.client.protocol.attach.request.subscription Attach requests expose the requested subscription.
    pub subscription: LocalClientSubscription,
}

/// @behavior selvedge.client.protocol.attach.accepted An accepted attach response carries protocol version, client identifier, and attach command identifier.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AttachAccepted {
    /// @behavior selvedge.client.protocol.attach.accepted.version Accepted attach responses expose the server protocol version.
    pub protocol_version: ProtocolVersion,
    /// @behavior selvedge.client.protocol.attach.accepted.client_id Accepted attach responses expose the accepted client identifier.
    pub client_id: LocalClientId,
    /// @behavior selvedge.client.protocol.attach.accepted.command_id Accepted attach responses expose the accepted attach command identifier.
    pub client_command_id: LocalClientCommandId,
}

/// @behavior selvedge.client.protocol.attach.rejected A rejected attach response carries protocol version, attach command identifier, and attach rejection reason.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AttachRejected {
    /// @behavior selvedge.client.protocol.attach.rejected.version Rejected attach responses expose the server protocol version.
    pub protocol_version: ProtocolVersion,
    /// @behavior selvedge.client.protocol.attach.rejected.command_id Rejected attach responses expose the rejected attach command identifier.
    pub client_command_id: LocalClientCommandId,
    /// @behavior selvedge.client.protocol.attach.rejected.reason Rejected attach responses expose the attach rejection reason.
    pub reason: AttachRejectReason,
}

/// @behavior selvedge.client.protocol.subscription A local client subscription selects task scope, detail level, and inclusion of model, tool, and debug events.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalClientSubscription {
    /// @behavior selvedge.client.protocol.subscription.task_scope_field Local subscriptions expose the requested task scope.
    pub task_scope: LocalTaskScope,
    /// @behavior selvedge.client.protocol.subscription.detail_field Local subscriptions expose the requested detail level.
    pub detail_level: LocalDetailLevel,
    /// @behavior selvedge.client.protocol.subscription.include_model_call_status Local subscriptions expose whether model call status events are included.
    pub include_model_call_status: bool,
    /// @behavior selvedge.client.protocol.subscription.include_tool_execution_status Local subscriptions expose whether tool execution status events are included.
    pub include_tool_execution_status: bool,
    /// @behavior selvedge.client.protocol.subscription.include_debug_notices Local subscriptions expose whether debug notices are included.
    pub include_debug_notices: bool,
}

/// @behavior selvedge.client.protocol.subscription.task_scope A local subscription can request every task or an explicit task identifier list.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalTaskScope {
    AllTasks,
    TaskIds(Vec<String>),
}

/// @behavior selvedge.client.protocol.subscription.detail A local subscription can request summary or verbose detail.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalDetailLevel {
    Summary,
    Verbose,
}

/// @behavior selvedge.client.protocol.frame A local client frame is a snapshot, event, or notice in the attach stream.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub enum LocalClientFrame {
    Snapshot(LocalClientSnapshotFrame),
    Event(LocalClientEventFrame),
    Notice(LocalClientNoticeFrame),
}

/// @behavior selvedge.client.protocol.frame.snapshot A local snapshot frame carries delivery sequence, attach command identifier, and snapshot payload.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct LocalClientSnapshotFrame {
    /// @behavior selvedge.client.protocol.frame.snapshot.delivery_seq Local snapshot frames expose their delivery sequence.
    pub delivery_seq: u64,
    /// @behavior selvedge.client.protocol.frame.snapshot.command_id Local snapshot frames expose the attach command identifier.
    pub client_command_id: LocalClientCommandId,
    /// @behavior selvedge.client.protocol.frame.snapshot.payload Local snapshot frames expose the snapshot payload.
    pub snapshot: LocalClientSnapshot,
}

/// @behavior selvedge.client.protocol.frame.event A local event frame carries delivery sequence and event payload.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct LocalClientEventFrame {
    /// @behavior selvedge.client.protocol.frame.event.delivery_seq Local event frames expose their delivery sequence.
    pub delivery_seq: u64,
    /// @behavior selvedge.client.protocol.frame.event.payload Local event frames expose the event payload.
    pub event: LocalClientEvent,
}

/// @behavior selvedge.client.protocol.frame.notice A local notice frame carries delivery sequence, client command identifier, and notice payload.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalClientNoticeFrame {
    /// @behavior selvedge.client.protocol.frame.notice.delivery_seq Local notice frames expose their delivery sequence.
    pub delivery_seq: u64,
    /// @behavior selvedge.client.protocol.frame.notice.command_id Local notice frames expose the client command identifier.
    pub client_command_id: LocalClientCommandId,
    /// @behavior selvedge.client.protocol.frame.notice.payload Local notice frames expose the notice payload.
    pub notice: LocalNotice,
}

/// @behavior selvedge.client.protocol.snapshot A local client snapshot carries generation time, tasks, task parent edges, history nodes, and task versions.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct LocalClientSnapshot {
    /// @behavior selvedge.client.protocol.snapshot.generated_at Local snapshots expose their generation timestamp.
    pub generated_at: i64,
    /// @behavior selvedge.client.protocol.snapshot.tasks Local snapshots expose task projections.
    pub tasks: Vec<LocalTaskProjection>,
    /// @behavior selvedge.client.protocol.snapshot.parent_edges Local snapshots expose task parent edges.
    pub task_parent_edges: Vec<LocalTaskParentProjection>,
    /// @behavior selvedge.client.protocol.snapshot.history_nodes Local snapshots expose history node projections.
    pub history_nodes: Vec<LocalHistoryNodeProjection>,
    /// @behavior selvedge.client.protocol.snapshot.task_versions Local snapshots expose task state versions included in the snapshot.
    pub task_versions: Vec<LocalSnapshotTaskVersion>,
}

/// @constraint selvedge.client.protocol.snapshot.version A local snapshot task version pairs one task identifier with the state version included in the snapshot.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalSnapshotTaskVersion {
    /// @constraint selvedge.client.protocol.snapshot.version.task_id Local snapshot task versions expose the task identifier.
    pub task_id: String,
    /// @constraint selvedge.client.protocol.snapshot.version.state_version Local snapshot task versions expose the task state version.
    pub state_version: u64,
}

/// @behavior selvedge.client.protocol.task_projection A local task projection carries task identity, status, cursor node, model profile, reasoning effort, state version, and timestamps.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalTaskProjection {
    /// @behavior selvedge.client.protocol.task_projection.task_id Local task projections expose the task identifier.
    pub task_id: String,
    /// @behavior selvedge.client.protocol.task_projection.status_field Local task projections expose active or archived status.
    pub status: LocalTaskProjectionStatus,
    /// @behavior selvedge.client.protocol.task_projection.cursor Local task projections expose the cursor history node identifier.
    pub cursor_node_id: i64,
    /// @behavior selvedge.client.protocol.task_projection.model_profile Local task projections expose the model profile key.
    pub model_profile_key: String,
    /// @behavior selvedge.client.protocol.task_projection.reasoning_effort Local task projections expose the reasoning effort.
    pub reasoning_effort: LocalReasoningEffort,
    /// @behavior selvedge.client.protocol.task_projection.state_version Local task projections expose the task state version.
    pub state_version: u64,
    /// @behavior selvedge.client.protocol.task_projection.created_at Local task projections expose the task creation timestamp.
    pub created_at: i64,
    /// @behavior selvedge.client.protocol.task_projection.updated_at Local task projections expose the latest task update timestamp.
    pub updated_at: i64,
}

/// @behavior selvedge.client.protocol.task_projection.status A local task projection reports active or archived status.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalTaskProjectionStatus {
    Active,
    Archived,
}

/// @behavior selvedge.client.protocol.task_projection.parent A local task parent projection carries parent and child task identifiers.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalTaskParentProjection {
    /// @behavior selvedge.client.protocol.task_projection.parent.parent_task_id Local task parent projections expose the parent task identifier.
    pub parent_task_id: String,
    /// @behavior selvedge.client.protocol.task_projection.parent.child_task_id Local task parent projections expose the child task identifier.
    pub child_task_id: String,
}

/// @behavior selvedge.client.protocol.history_projection A local history node projection carries node identity, optional parent identity, creation time, and body.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct LocalHistoryNodeProjection {
    /// @behavior selvedge.client.protocol.history_projection.node_id Local history node projections expose the node identifier.
    pub node_id: i64,
    /// @behavior selvedge.client.protocol.history_projection.parent_node_id Local history node projections expose the optional parent node identifier.
    pub parent_node_id: Option<i64>,
    /// @behavior selvedge.client.protocol.history_projection.created_at Local history node projections expose the node creation timestamp.
    pub created_at: i64,
    /// @behavior selvedge.client.protocol.history_projection.body_field Local history node projections expose the node body.
    pub body: LocalHistoryNodeProjectionBody,
}

/// @behavior selvedge.client.protocol.history_projection.body A local history node body serializes messages, reasoning, function calls, and function outputs.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub enum LocalHistoryNodeProjectionBody {
    Message {
        role: LocalMessageRole,
        text: String,
    },
    Reasoning {
        text: String,
    },
    FunctionCall {
        function_call_id: String,
        tool_name: String,
        arguments: Vec<LocalToolCallArgument>,
    },
    FunctionOutput {
        function_call_node_id: i64,
        function_call_id: String,
        tool_name: String,
        output_text: String,
        is_error: bool,
    },
}

/// @behavior selvedge.client.protocol.event A local client event serializes task changes, appended history, model call status, tool execution status, and debug notices.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub enum LocalClientEvent {
    TaskChanged(LocalTaskChangedEvent),
    HistoryAppended(LocalHistoryAppendedEvent),
    ModelCallStatus(LocalModelCallStatusEvent),
    ToolExecutionStatus(LocalToolExecutionStatusEvent),
    DebugNotice(LocalDebugNoticeEvent),
}

/// @behavior selvedge.client.protocol.event.task_changed A local task changed event carries the latest task projection.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct LocalTaskChangedEvent {
    /// @behavior selvedge.client.protocol.event.task_changed.task Local task changed events expose the updated task projection.
    pub task: LocalTaskProjection,
}

/// @behavior selvedge.client.protocol.event.history_appended A local history appended event carries task identity, task state version, and appended history nodes.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct LocalHistoryAppendedEvent {
    /// @behavior selvedge.client.protocol.event.history_appended.task_id Local history appended events expose the task identifier.
    pub task_id: String,
    /// @behavior selvedge.client.protocol.event.history_appended.version Local history appended events expose the resulting task state version.
    pub task_state_version: u64,
    /// @behavior selvedge.client.protocol.event.history_appended.nodes Local history appended events expose the appended history nodes.
    pub appended_nodes: Vec<LocalHistoryNodeProjection>,
}

/// @behavior selvedge.client.protocol.event.model_call_status A local model call status event carries task identity, model call identity, and phase.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalModelCallStatusEvent {
    /// @behavior selvedge.client.protocol.event.model_call_status.task_id Local model call status events expose the task identifier.
    pub task_id: String,
    /// @behavior selvedge.client.protocol.event.model_call_status.model_call_id Local model call status events expose the model call identifier.
    pub model_call_id: String,
    /// @behavior selvedge.client.protocol.event.model_call_status.phase Local model call status events expose the reported model call phase.
    pub phase: LocalModelCallStatusPhase,
}

/// @behavior selvedge.client.protocol.event.tool_status A local tool execution status event carries task identity, tool run identity, function call node, tool name, and phase.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalToolExecutionStatusEvent {
    /// @behavior selvedge.client.protocol.event.tool_status.task_id Local tool execution status events expose the task identifier.
    pub task_id: String,
    /// @behavior selvedge.client.protocol.event.tool_status.run_id Local tool execution status events expose the tool execution run identifier.
    pub tool_execution_run_id: String,
    /// @behavior selvedge.client.protocol.event.tool_status.node_id Local tool execution status events expose the function call node identifier.
    pub function_call_node_id: i64,
    /// @behavior selvedge.client.protocol.event.tool_status.tool_name Local tool execution status events expose the tool name.
    pub tool_name: String,
    /// @behavior selvedge.client.protocol.event.tool_status.phase Local tool execution status events expose the reported tool execution phase.
    pub phase: LocalToolExecutionStatusPhase,
}

/// @behavior selvedge.client.protocol.event.debug_notice A local debug notice event carries optional task identity and message text.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalDebugNoticeEvent {
    /// @behavior selvedge.client.protocol.event.debug_notice.task_id Local debug notice events may expose task identity.
    pub task_id: Option<String>,
    /// @behavior selvedge.client.protocol.event.debug_notice.message Local debug notice events expose debug message text.
    pub message_text: String,
}

/// @behavior selvedge.client.protocol.notice A local notice carries severity level and message text.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalNotice {
    /// @behavior selvedge.client.protocol.notice.level_field Local notices expose the notice severity level.
    pub level: LocalNoticeLevel,
    /// @behavior selvedge.client.protocol.notice.message Local notices expose message text.
    pub message_text: String,
}

/// @behavior selvedge.client.protocol.notice.level A local notice reports info, warning, or error severity.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalNoticeLevel {
    Info,
    Warning,
    Error,
}

/// @behavior selvedge.client.protocol.model_status_phase A local model call status reports requested, completed, failed, or discarded phases.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalModelCallStatusPhase {
    Requested,
    Completed,
    Failed,
    Discarded,
}

/// @behavior selvedge.client.protocol.tool_status_phase A local tool execution status reports requested, completed, failed, or discarded phases.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalToolExecutionStatusPhase {
    Requested,
    Completed,
    Failed,
    Discarded,
}

/// @behavior selvedge.client.protocol.message_role A local message role serializes system, developer, user, assistant, and tool roles.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalMessageRole {
    System,
    Developer,
    User,
    Assistant,
    Tool,
}

/// @behavior selvedge.client.protocol.reasoning_effort A local reasoning effort serializes minimal, low, medium, and high effort levels.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalReasoningEffort {
    Minimal,
    Low,
    Medium,
    High,
}

/// @behavior selvedge.client.protocol.tool_argument A local tool call argument carries a non-empty argument name and typed argument value.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct LocalToolCallArgument {
    /// @behavior selvedge.client.protocol.tool_argument.name Local tool call arguments expose the argument name.
    pub name: String,
    /// @behavior selvedge.client.protocol.tool_argument.value_field Local tool call arguments expose the typed argument value.
    pub value: LocalToolArgumentValue,
}

/// @behavior selvedge.client.protocol.tool_argument.value A local tool argument value serializes string, integer, number, and boolean values.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub enum LocalToolArgumentValue {
    String(String),
    Integer(i64),
    Number(f64),
    Boolean(bool),
}

/// @behavior selvedge.client.protocol.validation_error Local protocol validation reports protocol, identity, command, task, delivery, snapshot, history, tool, and notice validation failures.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalProtocolValidationError {
    ProtocolVersionMismatch,
    EmptyClientId,
    EmptyClientCommandId,
    EmptyCommandName,
    EmptyTaskId,
    DuplicateTaskId,
    InvalidDeliverySeq,
    DuplicateSnapshotTaskVersion,
    InvalidHistoryNodeId,
    InvalidParentHistoryNodeId,
    EmptyModelProfileKey,
    EmptyToolName,
    EmptyToolArgumentName,
    EmptyNoticeText,
}

/// @behavior selvedge.client.protocol.http_problem A local HTTP problem carries protocol version, problem code, and caller-visible message text.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalHttpProblem {
    /// @behavior selvedge.client.protocol.http_problem.version Local HTTP problems expose the protocol version.
    pub protocol_version: ProtocolVersion,
    /// @behavior selvedge.client.protocol.http_problem.code_field Local HTTP problems expose the problem code.
    pub code: LocalHttpProblemCode,
    /// @behavior selvedge.client.protocol.http_problem.message Local HTTP problems expose caller-visible message text.
    pub message_text: String,
}

/// @behavior selvedge.client.protocol.http_problem.code A local HTTP problem code reports method, content type, JSON, body size, route, shutdown, and internal failures.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalHttpProblemCode {
    MethodNotAllowed,
    UnsupportedContentType,
    MalformedJson,
    BodyTooLarge,
    RouteNotFound,
    ServerClosing,
    InternalFailure,
}

/// @behavior selvedge.client.protocol.attach_stream.item A local attach stream item is an accepted response, a client frame, or a terminal stream error.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub enum LocalAttachStreamItem {
    Accepted(AttachAccepted),
    Frame(LocalClientFrame),
    StreamError(LocalStreamError),
}

/// @behavior selvedge.client.protocol.attach_stream.error A local stream error carries protocol version, attach command identifier, reason, and message text.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalStreamError {
    /// @behavior selvedge.client.protocol.attach_stream.error.version Local stream errors expose the protocol version.
    pub protocol_version: ProtocolVersion,
    /// @behavior selvedge.client.protocol.attach_stream.error.command_id Local stream errors expose the attach command identifier.
    pub client_command_id: LocalClientCommandId,
    /// @behavior selvedge.client.protocol.attach_stream.error.reason Local stream errors expose the stream error reason.
    pub reason: LocalStreamErrorReason,
    /// @behavior selvedge.client.protocol.attach_stream.error.message Local stream errors expose caller-visible message text.
    pub message_text: String,
}

/// @behavior selvedge.client.protocol.attach_stream.error_reason A local stream error reason reports closed stream, server shutdown, encode failure, or internal failure.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalStreamErrorReason {
    StreamClosed,
    ServerShuttingDown,
    EncodeFailed,
    InternalFailure,
}

/// @behavior selvedge.client.protocol.attach_stream.state The local attach stream validator reports waiting-accepted, streaming, or ended state.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LocalAttachStreamValidationState {
    WaitingAccepted,
    Streaming,
    Ended,
}

/// @behavior selvedge.client.protocol.attach_stream.order_error Attach stream order validation reports accepted-first, duplicate accepted, rejected-inside-stream, frame-before-accepted, and item-after-ended errors.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LocalAttachStreamOrderError {
    ExpectedAcceptedFirst,
    DuplicateAccepted,
    RejectedInsideStream,
    FrameBeforeAccepted,
    ItemAfterEnded,
}

/// @intent selvedge.client.protocol.attach_stream.validator The attach stream validator gives clients a local state model for checking accepted-first attach stream ordering.
/// @behavior selvedge.client.protocol.attach_stream.validator.state_storage The attach stream validator stores the current caller-visible stream validation state.
#[derive(Clone, Debug)]
pub struct LocalAttachStreamValidator {
    state: LocalAttachStreamValidationState,
}

impl LocalClientId {
    /// @constraint selvedge.client.protocol.client_id.validation Local client identifier construction rejects empty identifiers and returns the empty-client-id validation error.
    pub fn new(value: impl Into<String>) -> Result<Self, LocalProtocolValidationError> {
        let value = value.into();
        if value.trim().is_empty() {
            return Err(LocalProtocolValidationError::EmptyClientId);
        }

        Ok(Self(value))
    }
}

impl LocalClientCommandId {
    /// @constraint selvedge.client.protocol.command_id.validation Local client command identifier construction rejects empty identifiers and returns the empty-client-command-id validation error.
    pub fn new(value: impl Into<String>) -> Result<Self, LocalProtocolValidationError> {
        let value = value.into();
        if value.trim().is_empty() {
            return Err(LocalProtocolValidationError::EmptyClientCommandId);
        }

        Ok(Self(value))
    }
}

/// @behavior selvedge.client.protocol.version.current The current protocol version function returns the protocol version advertised by this crate.
pub fn current_protocol_version() -> ProtocolVersion {
    ProtocolVersion(LOCAL_PROTOCOL_VERSION)
}

/// @behavior selvedge.client.protocol.ready.validation Ready request validation accepts current protocol version and rejects mismatched protocol version.
pub fn validate_ready_request(request: &ReadyRequest) -> Result<(), LocalProtocolValidationError> {
    validate_protocol_version(request.protocol_version)?;

    Ok(())
}

/// @behavior selvedge.client.protocol.command.validation Command request validation accepts current protocol version, non-empty client correlation, and non-empty command name.
pub fn validate_command_request(
    request: &CommandRequest,
) -> Result<(), LocalProtocolValidationError> {
    validate_protocol_version(request.protocol_version)?;
    validate_client_id(&request.client_id)?;
    validate_client_command_id(&request.client_command_id)?;
    if request.command_name.trim().is_empty() {
        // @constraint selvedge.client.protocol.command.validation.name Command request validation rejects blank command names before router mapping.
        return Err(LocalProtocolValidationError::EmptyCommandName);
    }

    Ok(())
}

/// @behavior selvedge.client.protocol.attach.validation Attach request validation accepts current protocol version, non-empty client correlation, and valid subscription filters.
pub fn validate_attach_request(
    request: &AttachRequest,
) -> Result<(), LocalProtocolValidationError> {
    validate_protocol_version(request.protocol_version)?;
    validate_client_id(&request.client_id)?;
    validate_client_command_id(&request.client_command_id)?;
    validate_subscription(&request.subscription)?;

    Ok(())
}

/// @behavior selvedge.client.protocol.subscription.validation Subscription validation accepts all-task subscriptions and rejects empty or duplicate task identifiers in explicit task filters.
pub fn validate_subscription(
    subscription: &LocalClientSubscription,
) -> Result<(), LocalProtocolValidationError> {
    if let LocalTaskScope::TaskIds(task_ids) = &subscription.task_scope {
        let mut seen = BTreeSet::new();
        for task_id in task_ids {
            let task_id = task_id.trim();
            if task_id.is_empty() {
                // @constraint selvedge.client.protocol.subscription.validation.empty_task Explicit subscription task filters reject empty task identifiers.
                return Err(LocalProtocolValidationError::EmptyTaskId);
            }
            if !seen.insert(task_id) {
                // @constraint selvedge.client.protocol.subscription.validation.duplicate_task Explicit subscription task filters reject duplicate task identifiers.
                return Err(LocalProtocolValidationError::DuplicateTaskId);
            }
        }
    }

    Ok(())
}

/// @behavior selvedge.client.protocol.frame.validation Client frame validation accepts valid snapshot, event, and notice frames and returns stable validation errors for invalid frame payloads.
pub fn validate_client_frame(frame: &LocalClientFrame) -> Result<(), LocalProtocolValidationError> {
    match frame {
        LocalClientFrame::Snapshot(frame) => {
            validate_delivery_seq(frame.delivery_seq)?;
            validate_client_command_id(&frame.client_command_id)?;
            validate_snapshot(&frame.snapshot)?;
        }
        LocalClientFrame::Event(frame) => {
            validate_delivery_seq(frame.delivery_seq)?;
            validate_client_event(&frame.event)?;
        }
        LocalClientFrame::Notice(frame) => {
            validate_delivery_seq(frame.delivery_seq)?;
            validate_client_command_id(&frame.client_command_id)?;
            validate_notice(&frame.notice)?;
        }
    }

    Ok(())
}

/// @behavior selvedge.client.protocol.snapshot.validation Snapshot validation accepts valid task projections, parent edges, history nodes, and task versions while rejecting duplicate snapshot task versions.
pub fn validate_snapshot(
    snapshot: &LocalClientSnapshot,
) -> Result<(), LocalProtocolValidationError> {
    for task in &snapshot.tasks {
        validate_task_projection(task)?;
    }

    for parent_edge in &snapshot.task_parent_edges {
        validate_task_id(&parent_edge.parent_task_id)?;
        validate_task_id(&parent_edge.child_task_id)?;
    }

    for history_node in &snapshot.history_nodes {
        validate_history_node(history_node)?;
    }

    let mut seen = BTreeSet::new();
    for task_version in &snapshot.task_versions {
        validate_task_id(&task_version.task_id)?;
        if !seen.insert(task_version.task_id.trim()) {
            // @constraint selvedge.client.protocol.snapshot.validation.duplicate_version Snapshot validation reports duplicate-snapshot-task-version for repeated task version identifiers.
            return Err(LocalProtocolValidationError::DuplicateSnapshotTaskVersion);
        }
    }

    Ok(())
}

/// @behavior selvedge.client.protocol.attach_stream.item_validation Attach stream item validation accepts valid accepted responses, frames, and stream errors and validates only each item's payload shape.
pub fn validate_attach_stream_item(
    item: &LocalAttachStreamItem,
) -> Result<(), LocalProtocolValidationError> {
    match item {
        LocalAttachStreamItem::Accepted(accepted) => {
            validate_protocol_version(accepted.protocol_version)?;
            validate_client_id(&accepted.client_id)?;
            validate_client_command_id(&accepted.client_command_id)
        }
        LocalAttachStreamItem::Frame(frame) => validate_client_frame(frame),
        LocalAttachStreamItem::StreamError(error) => {
            validate_protocol_version(error.protocol_version)?;
            validate_client_command_id(&error.client_command_id)?;
            if error.message_text.trim().is_empty() {
                // @constraint selvedge.client.protocol.attach_stream.item_validation.error_text Stream error items reject empty message text.
                return Err(LocalProtocolValidationError::EmptyNoticeText);
            }
            Ok(())
        }
    }
}

/// @behavior selvedge.client.protocol.http_problem.build Building a local HTTP problem uses the current protocol version and preserves the supplied code and message text.
pub fn http_problem(
    code: LocalHttpProblemCode,
    message_text: impl Into<String>,
) -> LocalHttpProblem {
    LocalHttpProblem {
        protocol_version: current_protocol_version(),
        code,
        message_text: message_text.into(),
    }
}

impl LocalAttachStreamValidator {
    /// @behavior selvedge.client.protocol.attach_stream.validator.new A new attach stream validator starts in waiting-accepted state.
    pub fn new() -> Self {
        Self {
            state: LocalAttachStreamValidationState::WaitingAccepted,
        }
    }

    /// @behavior selvedge.client.protocol.attach_stream.validator.state The attach stream validator exposes its current order-validation state.
    pub fn state(&self) -> LocalAttachStreamValidationState {
        self.state.clone()
    }

    /// @behavior selvedge.client.protocol.attach_stream.validator.next Attach stream order validation accepts one accepted item first, accepts frames while streaming, treats stream error as terminal, and reports stable order errors for invalid transitions.
    pub fn validate_next(
        &mut self,
        item: &LocalAttachStreamItem,
    ) -> Result<(), LocalAttachStreamOrderError> {
        if self.state == LocalAttachStreamValidationState::Ended {
            // @constraint selvedge.client.protocol.attach_stream.validator.next.ended Attach stream order validation rejects every item after terminal stream error.
            return Err(LocalAttachStreamOrderError::ItemAfterEnded);
        }

        // @constraint selvedge.client.protocol.attach_stream.validator.next.transition_table Attach stream order validation applies the accepted-first, streaming-frame, terminal-error, and invalid-transition rules to each stream item.
        match self.state {
            LocalAttachStreamValidationState::WaitingAccepted => match item {
                LocalAttachStreamItem::Accepted(_) => {
                    self.state = LocalAttachStreamValidationState::Streaming;
                    Ok(())
                }
                LocalAttachStreamItem::Frame(_) => {
                    // @constraint selvedge.client.protocol.attach_stream.validator.next.frame_first Attach stream order validation rejects frames before accepted attach.
                    Err(LocalAttachStreamOrderError::FrameBeforeAccepted)
                }
                LocalAttachStreamItem::StreamError(_) => {
                    // @constraint selvedge.client.protocol.attach_stream.validator.next.error_first Attach stream order validation rejects stream errors before accepted attach.
                    Err(LocalAttachStreamOrderError::ExpectedAcceptedFirst)
                }
            },
            LocalAttachStreamValidationState::Streaming => match item {
                LocalAttachStreamItem::Accepted(_) => {
                    // @constraint selvedge.client.protocol.attach_stream.validator.next.duplicate_accepted Attach stream order validation rejects a second accepted attach item.
                    Err(LocalAttachStreamOrderError::DuplicateAccepted)
                }
                LocalAttachStreamItem::Frame(_) => Ok(()),
                LocalAttachStreamItem::StreamError(_) => {
                    self.state = LocalAttachStreamValidationState::Ended;
                    Ok(())
                }
            },
            LocalAttachStreamValidationState::Ended => {
                // @constraint selvedge.client.protocol.attach_stream.validator.next.item_after_end Attach stream order validation rejects any item after the stream has ended.
                Err(LocalAttachStreamOrderError::ItemAfterEnded)
            }
        }
    }
}

impl Default for LocalAttachStreamValidator {
    /// @behavior selvedge.client.protocol.attach_stream.validator.default The default attach stream validator starts in the same waiting-accepted state as `LocalAttachStreamValidator::new`.
    fn default() -> Self {
        Self::new()
    }
}

/// @constraint selvedge.client.protocol.version.validation Protocol version validation rejects versions different from the current protocol version.
fn validate_protocol_version(
    protocol_version: ProtocolVersion,
) -> Result<(), LocalProtocolValidationError> {
    if protocol_version != current_protocol_version() {
        // @constraint selvedge.client.protocol.version.validation.mismatch Protocol version validation reports protocol-version-mismatch for every non-current version.
        return Err(LocalProtocolValidationError::ProtocolVersionMismatch);
    }

    Ok(())
}

/// @constraint selvedge.client.protocol.client_id.payload_validation Request validation rejects empty local client identifiers.
fn validate_client_id(client_id: &LocalClientId) -> Result<(), LocalProtocolValidationError> {
    if client_id.0.trim().is_empty() {
        // @constraint selvedge.client.protocol.client_id.payload_validation.empty Request validation reports empty-client-id for blank local client identifiers.
        return Err(LocalProtocolValidationError::EmptyClientId);
    }

    Ok(())
}

/// @constraint selvedge.client.protocol.command_id.payload_validation Request validation rejects empty local client command identifiers.
fn validate_client_command_id(
    client_command_id: &LocalClientCommandId,
) -> Result<(), LocalProtocolValidationError> {
    if client_command_id.0.trim().is_empty() {
        // @constraint selvedge.client.protocol.command_id.payload_validation.empty Request validation reports empty-client-command-id for blank local client command identifiers.
        return Err(LocalProtocolValidationError::EmptyClientCommandId);
    }

    Ok(())
}

/// @constraint selvedge.client.protocol.task_id.validation Local protocol validation rejects empty task identifiers.
fn validate_task_id(task_id: &str) -> Result<(), LocalProtocolValidationError> {
    if task_id.trim().is_empty() {
        // @constraint selvedge.client.protocol.task_id.validation.empty Local protocol validation reports empty-task-id for blank task identifiers.
        return Err(LocalProtocolValidationError::EmptyTaskId);
    }

    Ok(())
}

/// @constraint selvedge.client.protocol.delivery_seq.validation Client frame validation rejects delivery sequence zero.
fn validate_delivery_seq(delivery_seq: u64) -> Result<(), LocalProtocolValidationError> {
    if delivery_seq == 0 {
        // @constraint selvedge.client.protocol.delivery_seq.validation.zero Local protocol validation reports invalid-delivery-seq for delivery sequence zero.
        return Err(LocalProtocolValidationError::InvalidDeliverySeq);
    }

    Ok(())
}

/// @constraint selvedge.client.protocol.task_projection.validation Task projection validation rejects empty task identifiers, invalid cursor node identifiers, and empty model profile keys.
fn validate_task_projection(
    task: &LocalTaskProjection,
) -> Result<(), LocalProtocolValidationError> {
    validate_task_id(&task.task_id)?;
    if task.cursor_node_id <= 0 {
        // @constraint selvedge.client.protocol.task_projection.validation.cursor Task projection validation reports invalid-history-node-id for non-positive cursor node identifiers.
        return Err(LocalProtocolValidationError::InvalidHistoryNodeId);
    }
    if task.model_profile_key.trim().is_empty() {
        // @constraint selvedge.client.protocol.task_projection.validation.model_profile Task projection validation reports empty-model-profile-key for blank model profile keys.
        return Err(LocalProtocolValidationError::EmptyModelProfileKey);
    }

    Ok(())
}

/// @constraint selvedge.client.protocol.history_projection.validation History node validation rejects invalid node identifiers, invalid parent identifiers, and invalid body payloads.
fn validate_history_node(
    history_node: &LocalHistoryNodeProjection,
) -> Result<(), LocalProtocolValidationError> {
    if history_node.node_id <= 0 {
        // @constraint selvedge.client.protocol.history_projection.validation.node History node validation reports invalid-history-node-id for non-positive node identifiers.
        return Err(LocalProtocolValidationError::InvalidHistoryNodeId);
    }
    if history_node
        .parent_node_id
        .is_some_and(|node_id| node_id <= 0)
    {
        // @constraint selvedge.client.protocol.history_projection.validation.parent History node validation reports invalid-parent-history-node-id for non-positive parent node identifiers.
        return Err(LocalProtocolValidationError::InvalidParentHistoryNodeId);
    }
    validate_history_node_body(&history_node.body)
}

/// @constraint selvedge.client.protocol.history_projection.body_validation History node body validation rejects function calls with empty tool names or argument names and function outputs with invalid function call node identifiers.
fn validate_history_node_body(
    body: &LocalHistoryNodeProjectionBody,
) -> Result<(), LocalProtocolValidationError> {
    match body {
        LocalHistoryNodeProjectionBody::Message { .. }
        | LocalHistoryNodeProjectionBody::Reasoning { .. } => Ok(()),
        LocalHistoryNodeProjectionBody::FunctionCall {
            tool_name,
            arguments,
            ..
        } => {
            validate_tool_name(tool_name)?;
            for argument in arguments {
                if argument.name.trim().is_empty() {
                    // @constraint selvedge.client.protocol.history_projection.body_validation.argument Function call history validation reports empty-tool-argument-name for blank argument names.
                    return Err(LocalProtocolValidationError::EmptyToolArgumentName);
                }
            }
            Ok(())
        }
        LocalHistoryNodeProjectionBody::FunctionOutput {
            function_call_node_id,
            tool_name,
            ..
        } => {
            if *function_call_node_id <= 0 {
                // @constraint selvedge.client.protocol.history_projection.body_validation.function_output Function output history validation reports invalid-history-node-id for non-positive function call node references.
                return Err(LocalProtocolValidationError::InvalidHistoryNodeId);
            }
            validate_tool_name(tool_name)
        }
    }
}

/// @constraint selvedge.client.protocol.tool_name.validation Local protocol validation rejects empty tool names.
fn validate_tool_name(tool_name: &str) -> Result<(), LocalProtocolValidationError> {
    if tool_name.trim().is_empty() {
        // @constraint selvedge.client.protocol.tool_name.validation.empty Local protocol validation reports empty-tool-name for blank tool names.
        return Err(LocalProtocolValidationError::EmptyToolName);
    }

    Ok(())
}

/// @constraint selvedge.client.protocol.notice.validation Local protocol validation rejects notices with empty message text.
fn validate_notice(notice: &LocalNotice) -> Result<(), LocalProtocolValidationError> {
    if notice.message_text.trim().is_empty() {
        // @constraint selvedge.client.protocol.notice.validation.empty Local protocol validation reports empty-notice-text for blank notice text.
        return Err(LocalProtocolValidationError::EmptyNoticeText);
    }

    Ok(())
}

/// @constraint selvedge.client.protocol.event.validation Client event validation rejects invalid task identifiers, history nodes, tool status function call node identifiers, tool names, and debug notice text.
fn validate_client_event(event: &LocalClientEvent) -> Result<(), LocalProtocolValidationError> {
    match event {
        LocalClientEvent::TaskChanged(event) => validate_task_projection(&event.task),
        LocalClientEvent::HistoryAppended(event) => {
            validate_task_id(&event.task_id)?;
            for node in &event.appended_nodes {
                validate_history_node(node)?;
            }
            Ok(())
        }
        LocalClientEvent::ModelCallStatus(event) => validate_task_id(&event.task_id),
        LocalClientEvent::ToolExecutionStatus(event) => {
            validate_task_id(&event.task_id)?;
            if event.function_call_node_id <= 0 {
                // @constraint selvedge.client.protocol.event.validation.tool_status_node Tool execution status event validation reports invalid-history-node-id for non-positive function call node identifiers.
                return Err(LocalProtocolValidationError::InvalidHistoryNodeId);
            }
            validate_tool_name(&event.tool_name)
        }
        LocalClientEvent::DebugNotice(event) => {
            if let Some(task_id) = &event.task_id {
                validate_task_id(task_id)?;
            }
            if event.message_text.trim().is_empty() {
                // @constraint selvedge.client.protocol.event.validation.debug_text Debug notice event validation reports empty-notice-text for blank debug message text.
                return Err(LocalProtocolValidationError::EmptyNoticeText);
            }
            Ok(())
        }
    }
}
