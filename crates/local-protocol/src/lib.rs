#![doc = include_str!("../README.md")]

use std::collections::BTreeSet;

use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;

#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct LocalClientId(pub String);

#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct LocalClientCommandId(pub String);

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReadyRequest {}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReadyResponse {
    pub state: ReadyState,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum ReadyState {
    Ready,
    NotReady,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct CommandRequest {
    pub client_id: LocalClientId,
    pub client_command_id: LocalClientCommandId,
    pub command_name: String,
    pub payload: JsonValue,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CommandResponse {
    pub client_command_id: LocalClientCommandId,
    pub outcome: CommandOutcome,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum CommandOutcome {
    Accepted,
    Rejected(CommandRejectReason),
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum CommandRejectReason {
    MalformedRequest,
    ServerNotReady,
    ClientNotAttached,
    LoginAlreadyRunning,
    UnsupportedCommand,
    RouterMailboxClosed,
    InternalFailure,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum AttachRejectReason {
    MalformedRequest,
    ServerNotReady,
    DuplicateAttach,
    ClientRegistryFull,
    RouterMailboxClosed,
    ClientSyncUnavailable,
    AttachChannelFailed,
    InternalFailure,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AttachRequest {
    pub client_id: LocalClientId,
    pub client_command_id: LocalClientCommandId,
    pub subscription: LocalClientSubscription,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AttachAccepted {
    pub client_id: LocalClientId,
    pub client_command_id: LocalClientCommandId,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AttachRejected {
    pub client_command_id: LocalClientCommandId,
    pub reason: AttachRejectReason,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalClientSubscription {
    pub task_scope: LocalTaskScope,
    pub detail_level: LocalDetailLevel,
    pub snapshot_mode: LocalSnapshotMode,
    pub include_model_call_status: bool,
    pub include_tool_execution_status: bool,
    pub include_debug_notices: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalTaskScope {
    AllTasks,
    TaskIds(Vec<String>),
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalDetailLevel {
    Summary,
    Verbose,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalSnapshotMode {
    CurrentState,
    Empty,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub enum LocalClientFrame {
    Snapshot(LocalClientSnapshotFrame),
    Event(LocalClientEventFrame),
    Notice(LocalClientNoticeFrame),
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct LocalClientSnapshotFrame {
    pub delivery_seq: u64,
    pub client_command_id: LocalClientCommandId,
    pub snapshot: LocalClientSnapshot,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct LocalClientEventFrame {
    pub delivery_seq: u64,
    pub event: LocalClientEvent,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalClientNoticeFrame {
    pub delivery_seq: u64,
    pub client_command_id: LocalClientCommandId,
    pub notice: LocalNotice,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct LocalClientSnapshot {
    pub generated_at: i64,
    pub tasks: Vec<LocalTaskProjection>,
    pub task_parent_edges: Vec<LocalTaskParentProjection>,
    pub history_nodes: Vec<LocalHistoryNodeProjection>,
    pub task_versions: Vec<LocalSnapshotTaskVersion>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalSnapshotTaskVersion {
    pub task_id: String,
    pub state_version: u64,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalTaskProjection {
    pub task_id: String,
    pub status: LocalTaskProjectionStatus,
    pub cursor_node_id: i64,
    pub model_profile_key: String,
    pub reasoning_effort: LocalReasoningEffort,
    pub state_version: u64,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalTaskProjectionStatus {
    Active,
    Archived,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalTaskParentProjection {
    pub parent_task_id: String,
    pub child_task_id: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct LocalHistoryNodeProjection {
    pub node_id: i64,
    pub parent_node_id: Option<i64>,
    pub created_at: i64,
    pub body: LocalHistoryNodeProjectionBody,
}

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

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub enum LocalClientEvent {
    TaskChanged(LocalTaskChangedEvent),
    HistoryAppended(LocalHistoryAppendedEvent),
    ModelCallStatus(LocalModelCallStatusEvent),
    ToolExecutionStatus(LocalToolExecutionStatusEvent),
    DebugNotice(LocalDebugNoticeEvent),
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct LocalTaskChangedEvent {
    pub task: LocalTaskProjection,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct LocalHistoryAppendedEvent {
    pub task_id: String,
    pub task_state_version: u64,
    pub appended_nodes: Vec<LocalHistoryNodeProjection>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalModelCallStatusEvent {
    pub task_id: String,
    pub model_call_id: String,
    pub phase: LocalModelCallStatusPhase,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalToolExecutionStatusEvent {
    pub task_id: String,
    pub tool_execution_run_id: String,
    pub function_call_node_id: i64,
    pub tool_name: String,
    pub phase: LocalToolExecutionStatusPhase,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalDebugNoticeEvent {
    pub task_id: Option<String>,
    pub message_text: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalNotice {
    pub level: LocalNoticeLevel,
    pub kind: LocalNoticeKind,
    pub message_text: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalNoticeKind {
    Text,
    LoginUserCode {
        client_command_id: LocalClientCommandId,
        verification_url: String,
        user_code: String,
    },
    CommandCompleted {
        client_command_id: LocalClientCommandId,
        command_name: String,
    },
    CommandFailed {
        client_command_id: LocalClientCommandId,
        command_name: String,
    },
    Diagnostic {
        client_command_id: Option<LocalClientCommandId>,
    },
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalNoticeLevel {
    Info,
    Warning,
    Error,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalModelCallStatusPhase {
    Requested,
    Completed,
    Failed,
    Discarded,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalToolExecutionStatusPhase {
    Requested,
    Completed,
    Failed,
    Discarded,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalMessageRole {
    System,
    Developer,
    User,
    Assistant,
    Tool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalReasoningEffort {
    Minimal,
    Low,
    Medium,
    High,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct LocalToolCallArgument {
    pub name: String,
    pub value: LocalToolArgumentValue,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub enum LocalToolArgumentValue {
    String(String),
    Integer(i64),
    Number(f64),
    Boolean(bool),
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalProtocolValidationError {
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
    EmptyVerificationUrl,
    EmptyUserCode,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalHttpProblem {
    pub code: LocalHttpProblemCode,
    pub message_text: String,
}

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

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub enum LocalAttachStreamItem {
    Accepted(AttachAccepted),
    Frame(LocalClientFrame),
    StreamError(LocalStreamError),
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalStreamError {
    pub client_command_id: LocalClientCommandId,
    pub reason: LocalStreamErrorReason,
    pub message_text: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalStreamErrorReason {
    StreamClosed,
    ServerShuttingDown,
    EncodeFailed,
    InternalFailure,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LocalAttachStreamValidationState {
    WaitingAccepted,
    Streaming,
    Ended,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LocalAttachStreamOrderError {
    ExpectedAcceptedFirst,
    DuplicateAccepted,
    RejectedInsideStream,
    FrameBeforeAccepted,
    ItemAfterEnded,
}

#[derive(Clone, Debug)]
pub struct LocalAttachStreamValidator {
    state: LocalAttachStreamValidationState,
}

impl LocalClientId {
    pub fn new(value: impl Into<String>) -> Result<Self, LocalProtocolValidationError> {
        let value = value.into();
        if value.trim().is_empty() {
            return Err(LocalProtocolValidationError::EmptyClientId);
        }

        Ok(Self(value))
    }
}

impl LocalClientCommandId {
    pub fn new(value: impl Into<String>) -> Result<Self, LocalProtocolValidationError> {
        let value = value.into();
        if value.trim().is_empty() {
            return Err(LocalProtocolValidationError::EmptyClientCommandId);
        }

        Ok(Self(value))
    }
}

pub fn validate_ready_request(request: &ReadyRequest) -> Result<(), LocalProtocolValidationError> {
    let _ = request;

    Ok(())
}

pub fn validate_command_request(
    request: &CommandRequest,
) -> Result<(), LocalProtocolValidationError> {
    validate_client_id(&request.client_id)?;
    validate_client_command_id(&request.client_command_id)?;
    if request.command_name.trim().is_empty() {
        return Err(LocalProtocolValidationError::EmptyCommandName);
    }

    Ok(())
}

pub fn validate_attach_request(
    request: &AttachRequest,
) -> Result<(), LocalProtocolValidationError> {
    validate_client_id(&request.client_id)?;
    validate_client_command_id(&request.client_command_id)?;
    validate_subscription(&request.subscription)?;

    Ok(())
}

pub fn validate_subscription(
    subscription: &LocalClientSubscription,
) -> Result<(), LocalProtocolValidationError> {
    if let LocalTaskScope::TaskIds(task_ids) = &subscription.task_scope {
        let mut seen = BTreeSet::new();
        for task_id in task_ids {
            let task_id = task_id.trim();
            if task_id.is_empty() {
                return Err(LocalProtocolValidationError::EmptyTaskId);
            }
            if !seen.insert(task_id) {
                return Err(LocalProtocolValidationError::DuplicateTaskId);
            }
        }
    }

    Ok(())
}

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
            return Err(LocalProtocolValidationError::DuplicateSnapshotTaskVersion);
        }
    }

    Ok(())
}

pub fn validate_attach_stream_item(
    item: &LocalAttachStreamItem,
) -> Result<(), LocalProtocolValidationError> {
    match item {
        LocalAttachStreamItem::Accepted(accepted) => {
            validate_client_id(&accepted.client_id)?;
            validate_client_command_id(&accepted.client_command_id)
        }
        LocalAttachStreamItem::Frame(frame) => validate_client_frame(frame),
        LocalAttachStreamItem::StreamError(error) => {
            validate_client_command_id(&error.client_command_id)?;
            if error.message_text.trim().is_empty() {
                return Err(LocalProtocolValidationError::EmptyNoticeText);
            }
            Ok(())
        }
    }
}

pub fn http_problem(
    code: LocalHttpProblemCode,
    message_text: impl Into<String>,
) -> LocalHttpProblem {
    LocalHttpProblem {
        code,
        message_text: message_text.into(),
    }
}

impl LocalAttachStreamValidator {
    pub fn new() -> Self {
        Self {
            state: LocalAttachStreamValidationState::WaitingAccepted,
        }
    }

    pub fn state(&self) -> LocalAttachStreamValidationState {
        self.state.clone()
    }

    pub fn validate_next(
        &mut self,
        item: &LocalAttachStreamItem,
    ) -> Result<(), LocalAttachStreamOrderError> {
        if self.state == LocalAttachStreamValidationState::Ended {
            return Err(LocalAttachStreamOrderError::ItemAfterEnded);
        }

        match self.state {
            LocalAttachStreamValidationState::WaitingAccepted => match item {
                LocalAttachStreamItem::Accepted(_) => {
                    self.state = LocalAttachStreamValidationState::Streaming;
                    Ok(())
                }
                LocalAttachStreamItem::Frame(_) => {
                    Err(LocalAttachStreamOrderError::FrameBeforeAccepted)
                }
                LocalAttachStreamItem::StreamError(_) => {
                    Err(LocalAttachStreamOrderError::ExpectedAcceptedFirst)
                }
            },
            LocalAttachStreamValidationState::Streaming => match item {
                LocalAttachStreamItem::Accepted(_) => {
                    Err(LocalAttachStreamOrderError::DuplicateAccepted)
                }
                LocalAttachStreamItem::Frame(_) => Ok(()),
                LocalAttachStreamItem::StreamError(_) => {
                    self.state = LocalAttachStreamValidationState::Ended;
                    Ok(())
                }
            },
            LocalAttachStreamValidationState::Ended => {
                Err(LocalAttachStreamOrderError::ItemAfterEnded)
            }
        }
    }
}

impl Default for LocalAttachStreamValidator {
    fn default() -> Self {
        Self::new()
    }
}

fn validate_client_id(client_id: &LocalClientId) -> Result<(), LocalProtocolValidationError> {
    if client_id.0.trim().is_empty() {
        return Err(LocalProtocolValidationError::EmptyClientId);
    }

    Ok(())
}

fn validate_client_command_id(
    client_command_id: &LocalClientCommandId,
) -> Result<(), LocalProtocolValidationError> {
    if client_command_id.0.trim().is_empty() {
        return Err(LocalProtocolValidationError::EmptyClientCommandId);
    }

    Ok(())
}

fn validate_task_id(task_id: &str) -> Result<(), LocalProtocolValidationError> {
    if task_id.trim().is_empty() {
        return Err(LocalProtocolValidationError::EmptyTaskId);
    }

    Ok(())
}

fn validate_delivery_seq(delivery_seq: u64) -> Result<(), LocalProtocolValidationError> {
    if delivery_seq == 0 {
        return Err(LocalProtocolValidationError::InvalidDeliverySeq);
    }

    Ok(())
}

fn validate_task_projection(
    task: &LocalTaskProjection,
) -> Result<(), LocalProtocolValidationError> {
    validate_task_id(&task.task_id)?;
    if task.cursor_node_id <= 0 {
        return Err(LocalProtocolValidationError::InvalidHistoryNodeId);
    }
    if task.model_profile_key.trim().is_empty() {
        return Err(LocalProtocolValidationError::EmptyModelProfileKey);
    }

    Ok(())
}

fn validate_history_node(
    history_node: &LocalHistoryNodeProjection,
) -> Result<(), LocalProtocolValidationError> {
    if history_node.node_id <= 0 {
        return Err(LocalProtocolValidationError::InvalidHistoryNodeId);
    }
    if history_node
        .parent_node_id
        .is_some_and(|node_id| node_id <= 0)
    {
        return Err(LocalProtocolValidationError::InvalidParentHistoryNodeId);
    }
    validate_history_node_body(&history_node.body)
}

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
                return Err(LocalProtocolValidationError::InvalidHistoryNodeId);
            }
            validate_tool_name(tool_name)
        }
    }
}

fn validate_tool_name(tool_name: &str) -> Result<(), LocalProtocolValidationError> {
    if tool_name.trim().is_empty() {
        return Err(LocalProtocolValidationError::EmptyToolName);
    }

    Ok(())
}

fn validate_notice(notice: &LocalNotice) -> Result<(), LocalProtocolValidationError> {
    if notice.message_text.trim().is_empty() {
        return Err(LocalProtocolValidationError::EmptyNoticeText);
    }
    match &notice.kind {
        LocalNoticeKind::Text => {}
        LocalNoticeKind::LoginUserCode {
            client_command_id,
            verification_url,
            user_code,
        } => {
            validate_client_command_id(client_command_id)?;
            if verification_url.trim().is_empty() {
                return Err(LocalProtocolValidationError::EmptyVerificationUrl);
            }
            if user_code.trim().is_empty() {
                return Err(LocalProtocolValidationError::EmptyUserCode);
            }
        }
        LocalNoticeKind::CommandCompleted {
            client_command_id,
            command_name,
        }
        | LocalNoticeKind::CommandFailed {
            client_command_id,
            command_name,
        } => {
            validate_client_command_id(client_command_id)?;
            if command_name.trim().is_empty() {
                return Err(LocalProtocolValidationError::EmptyCommandName);
            }
        }
        LocalNoticeKind::Diagnostic { client_command_id } => {
            if let Some(client_command_id) = client_command_id {
                validate_client_command_id(client_command_id)?;
            }
        }
    }

    Ok(())
}

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
                return Err(LocalProtocolValidationError::InvalidHistoryNodeId);
            }
            validate_tool_name(&event.tool_name)
        }
        LocalClientEvent::DebugNotice(event) => {
            if let Some(task_id) = &event.task_id {
                validate_task_id(task_id)?;
            }
            if event.message_text.trim().is_empty() {
                return Err(LocalProtocolValidationError::EmptyNoticeText);
            }
            Ok(())
        }
    }
}
