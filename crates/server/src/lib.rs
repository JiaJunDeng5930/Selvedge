#![doc = include_str!("../README.md")]

use std::fmt;
use std::fs::{File, OpenOptions};
use std::io;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex as StdMutex};
use std::task::{Context, Poll};

use futures_core::Stream;
use selvedge_api::ApiExecutorConfig;
use selvedge_client_sync::{
    ClientSnapshotBuilder, ClientSyncHandle, ClientSyncIngress, ClientSyncStartArgs,
    SpawnClientSyncError, spawn_client_sync,
};
use selvedge_command_model::{
    BeginClientHydration, ClientCommandId, ClientEvent, ClientFrame, ClientId, ClientNotice,
    ClientNoticeLevel, ClientSnapshot, ClientSubscription, DetailLevel, RouterCommandEnvelope,
    RouterIngressMessage, RouterIngressSender, TaskScope,
};
use selvedge_core::TaskRuntimeSpawnDeps;
use selvedge_db::{OpenDbOptions, open_db};
use selvedge_events::{EventsHandle, EventsStartArgs, SpawnEventsError, spawn_events_task};
use selvedge_local_protocol::{
    AttachAccepted, AttachRejected, AttachRequest, CommandOutcome, CommandRejectReason,
    CommandRequest, CommandResponse, LocalClientEvent, LocalClientFrame, LocalClientNoticeFrame,
    LocalClientSnapshot, LocalClientSnapshotFrame, LocalDetailLevel, LocalHistoryNodeProjection,
    LocalHistoryNodeProjectionBody, LocalMessageRole, LocalModelCallStatusEvent,
    LocalModelCallStatusPhase, LocalNotice, LocalNoticeLevel, LocalReasoningEffort,
    LocalSnapshotTaskVersion, LocalTaskParentProjection, LocalTaskProjection,
    LocalTaskProjectionStatus, LocalTaskScope, LocalToolArgumentValue, LocalToolCallArgument,
    LocalToolExecutionStatusEvent, LocalToolExecutionStatusPhase, ReadyRequest, ReadyResponse,
    ReadyState, current_protocol_version, validate_attach_request, validate_command_request,
    validate_ready_request,
};
use selvedge_router::{RouterHandle, RouterStartArgs, SpawnRouterError, ToolExecutionSpawner};
use selvedge_web::{
    WebBridge, WebHandle, WebLocalhostBind, WebLocalhostHost, WebStartArgs, WebStartError,
    spawn_web_surface,
};
use tokio::sync::{Mutex, Notify, RwLock, mpsc};
use tokio::task::JoinHandle;

const SQLITE_FILE_NAME: &str = "selvedge.sqlite";
const LOCK_FILE_NAME: &str = "server.lock";
const DEFAULT_EVENTS_INGRESS_CAPACITY: usize = 64;
const DEFAULT_CLIENT_REGISTRY_CAPACITY: usize = 64;
const DEFAULT_HYDRATION_BUFFER_CAPACITY: usize = 256;
const DEFAULT_CLIENT_SYNC_INGRESS_CAPACITY: usize = 64;
const DEFAULT_ATTACH_FRAME_CAPACITY: usize = 64;

pub struct ServerStartArgs {
    pub explicit_home: Option<PathBuf>,
    pub api_config: ApiExecutorConfig,
    pub tool_executor: Arc<dyn ToolExecutionSpawner>,
    pub core_spawn_deps: TaskRuntimeSpawnDeps,
    pub snapshot_builder: Arc<dyn ClientSnapshotBuilder>,
    pub command_mapper: Arc<dyn LocalCommandMapper>,
    pub local_binding: LocalBindingConfig,
    pub web_binding: Option<WebBindingConfig>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LocalBindingConfig {
    pub bind_target: LocalhostBindTarget,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WebBindingConfig {
    pub bind_target: LocalhostBindTarget,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LocalhostBindTarget {
    Ipv4 { port: u16 },
    Ipv6 { port: u16 },
}

#[derive(Debug)]
pub struct ServerHandle {
    pub control: ServerControl,
    pub join_handle: JoinHandle<ServerExitStatus>,
}

pub type ServerFrameStream =
    Pin<Box<dyn Stream<Item = Result<LocalClientFrame, ServerRequestError>> + Send>>;

#[derive(Clone)]
pub struct ServerControl {
    inner: Arc<ServerInner>,
}

impl fmt::Debug for ServerControl {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("ServerControl")
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ServerRuntimeState {
    Starting,
    Ready,
    Closing,
    Stopped,
    Failed,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ServerExitStatus {
    Stopped,
    StartupFailed(ServerStartupError),
    RouterStopped,
    Fatal(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ServerStartupError {
    SingletonAlreadyRunning,
    InvalidBindTarget,
    ConfigInitFailed(String),
    LoggingInitFailed(String),
    DbOpenFailed(String),
    EventsStartFailed(String),
    ClientSyncStartFailed(String),
    RouterStartFailed(String),
    LocalhostBindFailed(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ServerRequestError {
    NotReady,
    ProtocolValidationFailed,
    UnsupportedCommand,
    RouterMailboxClosed,
    AttachChannelFailed,
    InternalFailure(String),
}

pub trait LocalCommandMapper: Send + Sync {
    fn map_command(
        &self,
        request: CommandRequest,
    ) -> Result<RouterCommandEnvelope, ServerRequestError>;
}

pub async fn run_server(args: ServerStartArgs) -> ServerExitStatus {
    match spawn_server(args) {
        Ok(handle) => handle
            .join_handle
            .await
            .unwrap_or_else(|error| ServerExitStatus::Fatal(error.to_string())),
        Err(error) => ServerExitStatus::StartupFailed(error),
    }
}

pub fn spawn_server(args: ServerStartArgs) -> Result<ServerHandle, ServerStartupError> {
    validate_bind_target(&args.local_binding.bind_target)?;
    if let Some(web_binding) = &args.web_binding {
        validate_bind_target(&web_binding.bind_target)?;
    }

    init_config(args.explicit_home.as_ref())?;
    let home = resolve_home(args.explicit_home.clone())?;
    let singleton_lock = acquire_singleton_lock(&home)?;

    let startup_home = home.clone();
    let startup_result = start_server_after_lock(args, home, singleton_lock);
    if let Err(error) = &startup_result {
        let _ = std::fs::remove_file(lock_path_for_home(&startup_home));
        return Err(error.clone());
    }

    startup_result.map(ServerContext::into_handle)
}

impl ServerControl {
    pub async fn state(&self) -> ServerRuntimeState {
        self.inner.state.read().await.clone()
    }

    pub async fn ready(&self, request: ReadyRequest) -> ReadyResponse {
        let protocol_version = request.protocol_version;
        let state = if validate_ready_request(&request).is_ok()
            && *self.inner.state.read().await == ServerRuntimeState::Ready
        {
            ReadyState::Ready
        } else {
            ReadyState::NotReady
        };

        ReadyResponse {
            protocol_version,
            state,
        }
    }

    pub async fn submit_command(&self, request: CommandRequest) -> CommandResponse {
        let protocol_version = current_protocol_version();
        let client_command_id = request.client_command_id.clone();
        let outcome = self.submit_command_outcome(request).await;

        CommandResponse {
            protocol_version,
            client_command_id,
            outcome,
        }
    }

    pub async fn attach_client(
        &self,
        request: AttachRequest,
    ) -> Result<(AttachAccepted, ServerFrameStream), AttachRejected> {
        let protocol_version = current_protocol_version();
        let client_id = request.client_id.clone();
        let client_command_id = request.client_command_id.clone();

        let reject = |reason| {
            Err(AttachRejected {
                protocol_version,
                client_command_id: client_command_id.clone(),
                reason,
            })
        };

        if *self.inner.state.read().await != ServerRuntimeState::Ready {
            return reject(CommandRejectReason::ServerNotReady);
        }

        if validate_attach_request(&request).is_err() {
            if request.protocol_version != current_protocol_version() {
                return reject(CommandRejectReason::ProtocolVersionMismatch);
            }
            return reject(CommandRejectReason::MalformedRequest);
        }

        if self.inner.router_tx.is_closed() {
            self.begin_shutdown().await;
            return reject(CommandRejectReason::RouterMailboxClosed);
        }

        let (outbound, inbound) = mpsc::channel(DEFAULT_ATTACH_FRAME_CAPACITY);
        let hydration = BeginClientHydration {
            client_id: ClientId(client_id.0.clone()),
            client_command_id: ClientCommandId(client_command_id.0.clone()),
            outbound,
            subscription: local_subscription_to_command(&request.subscription),
        };

        let client_sync_tx = self.inner.client_sync_tx.lock().await.clone();
        if client_sync_tx
            .send(ClientSyncIngress::StartHydration(hydration))
            .await
            .is_err()
        {
            return reject(CommandRejectReason::InternalFailure);
        }

        let accepted = AttachAccepted {
            protocol_version,
            client_id,
            client_command_id,
        };
        let stream = Box::pin(ServerMpscFrameStream { inbound });
        Ok((accepted, stream))
    }

    pub async fn stop(&self) {
        self.begin_shutdown().await;
    }

    async fn submit_command_outcome(&self, request: CommandRequest) -> CommandOutcome {
        if *self.inner.state.read().await != ServerRuntimeState::Ready {
            return CommandOutcome::Rejected(CommandRejectReason::ServerNotReady);
        }

        if validate_command_request(&request).is_err() {
            if request.protocol_version != current_protocol_version() {
                return CommandOutcome::Rejected(CommandRejectReason::ProtocolVersionMismatch);
            }
            return CommandOutcome::Rejected(CommandRejectReason::MalformedRequest);
        }

        let command = match self.inner.command_mapper.map_command(request) {
            Ok(command) => command,
            Err(ServerRequestError::UnsupportedCommand) => {
                return CommandOutcome::Rejected(CommandRejectReason::UnsupportedCommand);
            }
            Err(ServerRequestError::RouterMailboxClosed) => {
                self.begin_shutdown().await;
                return CommandOutcome::Rejected(CommandRejectReason::RouterMailboxClosed);
            }
            Err(ServerRequestError::NotReady) => {
                return CommandOutcome::Rejected(CommandRejectReason::ServerNotReady);
            }
            Err(ServerRequestError::ProtocolValidationFailed) => {
                return CommandOutcome::Rejected(CommandRejectReason::MalformedRequest);
            }
            Err(
                ServerRequestError::AttachChannelFailed | ServerRequestError::InternalFailure(_),
            ) => {
                return CommandOutcome::Rejected(CommandRejectReason::InternalFailure);
            }
        };

        if self
            .inner
            .router_tx
            .send(RouterIngressMessage::Command(command))
            .is_err()
        {
            self.begin_shutdown().await;
            return CommandOutcome::Rejected(CommandRejectReason::RouterMailboxClosed);
        }

        CommandOutcome::Accepted
    }

    async fn begin_shutdown(&self) {
        if self.inner.closing.swap(true, Ordering::SeqCst) {
            return;
        }

        *self.inner.state.write().await = ServerRuntimeState::Closing;
        let _ = self.inner.router_tx.send(RouterIngressMessage::StopRouter);
        let client_sync_tx = self.inner.client_sync_tx.lock().await.clone();
        let _ = client_sync_tx.send(ClientSyncIngress::Shutdown).await;
        let web_control = self
            .inner
            .web_control
            .lock()
            .expect("web control lock")
            .clone();
        if let Some(web_control) = web_control {
            web_control.stop().await;
        }
        self.inner.stop_notify.notify_waiters();
    }
}

struct ServerContext {
    inner: Arc<ServerInner>,
    join_handle: JoinHandle<ServerExitStatus>,
}

struct ServerInner {
    state: RwLock<ServerRuntimeState>,
    closing: AtomicBool,
    stop_notify: Notify,
    lock_path: PathBuf,
    _singleton_lock: File,
    router_tx: RouterIngressSender,
    client_sync_tx: Mutex<selvedge_client_sync::ClientSyncSender>,
    command_mapper: Arc<dyn LocalCommandMapper>,
    web_control: StdMutex<Option<selvedge_web::WebControl>>,
}

impl ServerContext {
    fn into_handle(self) -> ServerHandle {
        ServerHandle {
            control: ServerControl { inner: self.inner },
            join_handle: self.join_handle,
        }
    }
}

fn start_server_after_lock(
    args: ServerStartArgs,
    home: PathBuf,
    singleton_lock: File,
) -> Result<ServerContext, ServerStartupError> {
    init_logging()?;

    let db = open_db(OpenDbOptions {
        sqlite_path: sqlite_path_for_home(&home).to_string_lossy().to_string(),
    })
    .map_err(|error| ServerStartupError::DbOpenFailed(error.to_string()))?;

    let events = spawn_events_task(EventsStartArgs {
        ingress_capacity: DEFAULT_EVENTS_INGRESS_CAPACITY,
        client_registry_capacity: DEFAULT_CLIENT_REGISTRY_CAPACITY,
        hydration_buffer_capacity: DEFAULT_HYDRATION_BUFFER_CAPACITY,
    })
    .map_err(map_events_start_error)?;

    let client_sync = spawn_client_sync(ClientSyncStartArgs {
        events_tx: events.ingress_tx.clone(),
        snapshot_builder: args.snapshot_builder,
        ingress_capacity: DEFAULT_CLIENT_SYNC_INGRESS_CAPACITY,
    })
    .map_err(map_client_sync_start_error)?;

    let router = selvedge_router::spawn_router(RouterStartArgs {
        db,
        events_tx: events.ingress_tx.clone(),
        api_config: args.api_config,
        tool_executor: args.tool_executor,
        core_spawn_deps: args.core_spawn_deps,
    })
    .map_err(map_router_start_error)?;

    let inner = Arc::new(ServerInner {
        state: RwLock::new(ServerRuntimeState::Ready),
        closing: AtomicBool::new(false),
        stop_notify: Notify::new(),
        lock_path: lock_path_for_home(&home),
        _singleton_lock: singleton_lock,
        router_tx: router.ingress_tx.clone(),
        client_sync_tx: Mutex::new(client_sync.ingress_tx.clone()),
        command_mapper: args.command_mapper,
        web_control: StdMutex::new(None),
    });
    let control = ServerControl {
        inner: inner.clone(),
    };
    let web = start_web(args.web_binding, control)?;
    if let Some(web_handle) = &web {
        *inner.web_control.lock().expect("web control lock") = Some(web_handle.control.clone());
    }
    let join_handle = spawn_server_join_task(inner.clone(), router, events, client_sync, web);

    Ok(ServerContext { inner, join_handle })
}

fn spawn_server_join_task(
    inner: Arc<ServerInner>,
    router: RouterHandle,
    events: EventsHandle,
    client_sync: ClientSyncHandle,
    web: Option<WebHandle>,
) -> JoinHandle<ServerExitStatus> {
    tokio::spawn(async move {
        loop {
            if inner.closing.load(Ordering::SeqCst) {
                break;
            }
            let notified = inner.stop_notify.notified();
            if inner.closing.load(Ordering::SeqCst) {
                break;
            }
            notified.await;
        }
        let _ = router.join_handle.await;
        drop(events.ingress_tx);
        let _ = events.join_handle.await;
        let _ = client_sync.join_handle.await;
        if let Some(web) = web {
            let _ = web.join_handle.await;
        }
        let _ = std::fs::remove_file(&inner.lock_path);
        *inner.state.write().await = ServerRuntimeState::Stopped;
        ServerExitStatus::Stopped
    })
}

fn start_web(
    web_binding: Option<WebBindingConfig>,
    control: ServerControl,
) -> Result<Option<WebHandle>, ServerStartupError> {
    let Some(web_binding) = web_binding else {
        return Ok(None);
    };

    let bind = local_bind_to_web_bind(web_binding.bind_target)?;
    let bridge = Arc::new(ServerWebBridge { control });
    spawn_web_surface(WebStartArgs { bind, bridge })
        .map(Some)
        .map_err(map_web_start_error)
}

struct ServerWebBridge {
    control: ServerControl,
}

impl WebBridge for ServerWebBridge {
    fn ready(&self, request: ReadyRequest) -> selvedge_web::WebBridgeFuture<ReadyResponse> {
        let control = self.control.clone();
        Box::pin(async move { Ok(control.ready(request).await) })
    }

    fn submit_command(
        &self,
        request: CommandRequest,
    ) -> selvedge_web::WebBridgeFuture<CommandResponse> {
        let control = self.control.clone();
        Box::pin(async move { Ok(control.submit_command(request).await) })
    }

    fn attach(&self, request: AttachRequest) -> selvedge_web::WebAttachFuture {
        let control = self.control.clone();
        Box::pin(async move {
            match control.attach_client(request).await {
                Ok((accepted, stream)) => Ok((
                    accepted,
                    Box::pin(WebServerFrameStream { inner: stream })
                        as selvedge_web::WebFrameStream,
                )),
                Err(rejected) => Err(selvedge_web::AttachRejectedOrBridgeError::Rejected(
                    rejected,
                )),
            }
        })
    }
}

struct WebServerFrameStream {
    inner: ServerFrameStream,
}

impl Stream for WebServerFrameStream {
    type Item = Result<LocalClientFrame, selvedge_web::WebBridgeError>;

    fn poll_next(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let this = self.get_mut();
        match this.inner.as_mut().poll_next(cx) {
            Poll::Ready(Some(Ok(frame))) => Poll::Ready(Some(Ok(frame))),
            Poll::Ready(Some(Err(error))) => {
                Poll::Ready(Some(Err(server_request_error_to_web_bridge(error))))
            }
            Poll::Ready(None) => Poll::Ready(None),
            Poll::Pending => Poll::Pending,
        }
    }
}

fn server_request_error_to_web_bridge(error: ServerRequestError) -> selvedge_web::WebBridgeError {
    match error {
        ServerRequestError::NotReady => selvedge_web::WebBridgeError::ServerNotReady,
        ServerRequestError::ProtocolValidationFailed => {
            selvedge_web::WebBridgeError::ProtocolValidationFailed
        }
        ServerRequestError::UnsupportedCommand => {
            selvedge_web::WebBridgeError::CommandRejected("unsupported command".to_owned())
        }
        ServerRequestError::RouterMailboxClosed => selvedge_web::WebBridgeError::StreamClosed,
        ServerRequestError::AttachChannelFailed => selvedge_web::WebBridgeError::StreamClosed,
        ServerRequestError::InternalFailure(message) => {
            selvedge_web::WebBridgeError::InternalFailure(message)
        }
    }
}

struct ServerMpscFrameStream {
    inbound: mpsc::Receiver<ClientFrame>,
}

impl Stream for ServerMpscFrameStream {
    type Item = Result<LocalClientFrame, ServerRequestError>;

    fn poll_next(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let this = self.get_mut();
        match this.inbound.poll_recv(cx) {
            Poll::Ready(Some(frame)) => Poll::Ready(Some(command_frame_to_local(frame))),
            Poll::Ready(None) => Poll::Ready(None),
            Poll::Pending => Poll::Pending,
        }
    }
}

fn command_frame_to_local(frame: ClientFrame) -> Result<LocalClientFrame, ServerRequestError> {
    match frame {
        ClientFrame::Snapshot(frame) => Ok(LocalClientFrame::Snapshot(LocalClientSnapshotFrame {
            delivery_seq: frame.delivery_seq.0,
            client_command_id: selvedge_local_protocol::LocalClientCommandId(
                frame.client_command_id.0,
            ),
            snapshot: client_snapshot_to_local(frame.snapshot),
        })),
        ClientFrame::Event(frame) => Ok(LocalClientFrame::Event(
            selvedge_local_protocol::LocalClientEventFrame {
                delivery_seq: frame.delivery_seq.0,
                event: client_event_to_local(frame.event),
            },
        )),
        ClientFrame::Notice(frame) => Ok(LocalClientFrame::Notice(LocalClientNoticeFrame {
            delivery_seq: frame.delivery_seq.0,
            client_command_id: selvedge_local_protocol::LocalClientCommandId(
                frame.client_command_id.0,
            ),
            notice: client_notice_to_local(frame.notice),
        })),
    }
}

fn client_snapshot_to_local(snapshot: ClientSnapshot) -> LocalClientSnapshot {
    LocalClientSnapshot {
        generated_at: snapshot.generated_at.0,
        tasks: snapshot
            .tasks
            .into_iter()
            .map(|task| LocalTaskProjection {
                task_id: task.task_id.0,
                status: match task.status {
                    selvedge_command_model::TaskProjectionStatus::Active => {
                        LocalTaskProjectionStatus::Active
                    }
                    selvedge_command_model::TaskProjectionStatus::Archived => {
                        LocalTaskProjectionStatus::Archived
                    }
                },
                cursor_node_id: task.cursor_node_id.0,
                model_profile_key: task.model_profile_key.0,
                reasoning_effort: reasoning_effort_to_local(task.reasoning_effort),
                state_version: task.state_version,
                created_at: task.created_at.0,
                updated_at: task.updated_at.0,
            })
            .collect(),
        task_parent_edges: snapshot
            .task_parent_edges
            .into_iter()
            .map(|edge| LocalTaskParentProjection {
                parent_task_id: edge.parent_task_id.0,
                child_task_id: edge.child_task_id.0,
            })
            .collect(),
        history_nodes: snapshot
            .history_nodes
            .into_iter()
            .map(history_node_to_local)
            .collect(),
        task_versions: snapshot
            .task_versions
            .into_iter()
            .map(|version| LocalSnapshotTaskVersion {
                task_id: version.task_id.0,
                state_version: version.state_version,
            })
            .collect(),
    }
}

fn history_node_to_local(
    node: selvedge_command_model::HistoryNodeProjection,
) -> LocalHistoryNodeProjection {
    LocalHistoryNodeProjection {
        node_id: node.node_id.0,
        parent_node_id: node.parent_node_id.map(|id| id.0),
        created_at: node.created_at.0,
        body: match node.body {
            selvedge_command_model::HistoryNodeProjectionBody::Message { role, text } => {
                LocalHistoryNodeProjectionBody::Message {
                    role: message_role_to_local(role),
                    text,
                }
            }
            selvedge_command_model::HistoryNodeProjectionBody::Reasoning { text } => {
                LocalHistoryNodeProjectionBody::Reasoning { text }
            }
            selvedge_command_model::HistoryNodeProjectionBody::FunctionCall {
                function_call_id,
                tool_name,
                arguments,
            } => LocalHistoryNodeProjectionBody::FunctionCall {
                function_call_id: function_call_id.0,
                tool_name: tool_name.0,
                arguments: arguments
                    .into_iter()
                    .map(|argument| LocalToolCallArgument {
                        name: argument.name.0,
                        value: tool_argument_value_to_local(argument.value),
                    })
                    .collect(),
            },
            selvedge_command_model::HistoryNodeProjectionBody::FunctionOutput {
                function_call_node_id,
                function_call_id,
                tool_name,
                output_text,
                is_error,
            } => LocalHistoryNodeProjectionBody::FunctionOutput {
                function_call_node_id: function_call_node_id.0,
                function_call_id: function_call_id.0,
                tool_name: tool_name.0,
                output_text,
                is_error,
            },
        },
    }
}

fn client_event_to_local(event: ClientEvent) -> LocalClientEvent {
    match event {
        ClientEvent::TaskChanged(event) => {
            LocalClientEvent::TaskChanged(selvedge_local_protocol::LocalTaskChangedEvent {
                task: client_snapshot_to_local(ClientSnapshot {
                    generated_at: selvedge_domain_model::UnixTs(0),
                    tasks: vec![event.task],
                    task_parent_edges: Vec::new(),
                    history_nodes: Vec::new(),
                    task_versions: Vec::new(),
                })
                .tasks
                .remove(0),
            })
        }
        ClientEvent::HistoryAppended(event) => {
            LocalClientEvent::HistoryAppended(selvedge_local_protocol::LocalHistoryAppendedEvent {
                task_id: event.task_id.0,
                task_state_version: event.task_state_version,
                appended_nodes: event
                    .appended_nodes
                    .into_iter()
                    .map(history_node_to_local)
                    .collect(),
            })
        }
        ClientEvent::ModelCallStatus(event) => {
            LocalClientEvent::ModelCallStatus(LocalModelCallStatusEvent {
                task_id: event.task_id.0,
                model_call_id: event.model_call_id.0,
                phase: model_phase_to_local(event.phase),
            })
        }
        ClientEvent::ToolExecutionStatus(event) => {
            LocalClientEvent::ToolExecutionStatus(LocalToolExecutionStatusEvent {
                task_id: event.task_id.0,
                tool_execution_run_id: event.tool_execution_run_id.0,
                function_call_node_id: event.function_call_node_id.0,
                tool_name: event.tool_name.0,
                phase: tool_phase_to_local(event.phase),
            })
        }
        ClientEvent::DebugNotice(event) => {
            LocalClientEvent::DebugNotice(selvedge_local_protocol::LocalDebugNoticeEvent {
                task_id: event.task_id.map(|id| id.0),
                message_text: event.message_text,
            })
        }
    }
}

fn local_subscription_to_command(
    subscription: &selvedge_local_protocol::LocalClientSubscription,
) -> ClientSubscription {
    ClientSubscription {
        task_scope: match &subscription.task_scope {
            LocalTaskScope::AllTasks => TaskScope::AllTasks,
            LocalTaskScope::TaskIds(task_ids) => TaskScope::TaskIds(
                task_ids
                    .iter()
                    .map(|task_id| selvedge_command_model::TaskId(task_id.clone()))
                    .collect(),
            ),
        },
        detail_level: match subscription.detail_level {
            LocalDetailLevel::Summary => DetailLevel::Summary,
            LocalDetailLevel::Verbose => DetailLevel::Verbose,
        },
        include_model_call_status: subscription.include_model_call_status,
        include_tool_execution_status: subscription.include_tool_execution_status,
        include_debug_notices: subscription.include_debug_notices,
    }
}

fn client_notice_to_local(notice: ClientNotice) -> LocalNotice {
    LocalNotice {
        level: match notice.level {
            ClientNoticeLevel::Info => LocalNoticeLevel::Info,
            ClientNoticeLevel::Warning => LocalNoticeLevel::Warning,
            ClientNoticeLevel::Error => LocalNoticeLevel::Error,
        },
        message_text: notice.message_text,
    }
}

fn reasoning_effort_to_local(
    effort: selvedge_domain_model::ReasoningEffort,
) -> LocalReasoningEffort {
    match effort {
        selvedge_domain_model::ReasoningEffort::Minimal => LocalReasoningEffort::Minimal,
        selvedge_domain_model::ReasoningEffort::Low => LocalReasoningEffort::Low,
        selvedge_domain_model::ReasoningEffort::Medium => LocalReasoningEffort::Medium,
        selvedge_domain_model::ReasoningEffort::High => LocalReasoningEffort::High,
    }
}

fn message_role_to_local(role: selvedge_domain_model::MessageRole) -> LocalMessageRole {
    match role {
        selvedge_domain_model::MessageRole::System => LocalMessageRole::System,
        selvedge_domain_model::MessageRole::Developer => LocalMessageRole::Developer,
        selvedge_domain_model::MessageRole::User => LocalMessageRole::User,
        selvedge_domain_model::MessageRole::Assistant => LocalMessageRole::Assistant,
        selvedge_domain_model::MessageRole::Tool => LocalMessageRole::Tool,
    }
}

fn tool_argument_value_to_local(
    value: selvedge_domain_model::ToolArgumentValue,
) -> LocalToolArgumentValue {
    match value {
        selvedge_domain_model::ToolArgumentValue::String(value) => {
            LocalToolArgumentValue::String(value)
        }
        selvedge_domain_model::ToolArgumentValue::Integer(value) => {
            LocalToolArgumentValue::Integer(value)
        }
        selvedge_domain_model::ToolArgumentValue::Number(value) => {
            LocalToolArgumentValue::Number(value)
        }
        selvedge_domain_model::ToolArgumentValue::Boolean(value) => {
            LocalToolArgumentValue::Boolean(value)
        }
    }
}

fn model_phase_to_local(
    phase: selvedge_command_model::ModelCallStatusPhase,
) -> LocalModelCallStatusPhase {
    match phase {
        selvedge_command_model::ModelCallStatusPhase::Requested => {
            LocalModelCallStatusPhase::Requested
        }
        selvedge_command_model::ModelCallStatusPhase::Completed => {
            LocalModelCallStatusPhase::Completed
        }
        selvedge_command_model::ModelCallStatusPhase::Failed => LocalModelCallStatusPhase::Failed,
        selvedge_command_model::ModelCallStatusPhase::Discarded => {
            LocalModelCallStatusPhase::Discarded
        }
    }
}

fn tool_phase_to_local(
    phase: selvedge_command_model::ToolExecutionStatusPhase,
) -> LocalToolExecutionStatusPhase {
    match phase {
        selvedge_command_model::ToolExecutionStatusPhase::Requested => {
            LocalToolExecutionStatusPhase::Requested
        }
        selvedge_command_model::ToolExecutionStatusPhase::Completed => {
            LocalToolExecutionStatusPhase::Completed
        }
        selvedge_command_model::ToolExecutionStatusPhase::Failed => {
            LocalToolExecutionStatusPhase::Failed
        }
        selvedge_command_model::ToolExecutionStatusPhase::Discarded => {
            LocalToolExecutionStatusPhase::Discarded
        }
    }
}

fn validate_bind_target(bind_target: &LocalhostBindTarget) -> Result<(), ServerStartupError> {
    match bind_target {
        LocalhostBindTarget::Ipv4 { .. } | LocalhostBindTarget::Ipv6 { .. } => Ok(()),
    }
}

fn local_bind_to_web_bind(
    bind_target: LocalhostBindTarget,
) -> Result<WebLocalhostBind, ServerStartupError> {
    Ok(match bind_target {
        LocalhostBindTarget::Ipv4 { port } => WebLocalhostBind {
            host: WebLocalhostHost::Ipv4Loopback,
            port,
        },
        LocalhostBindTarget::Ipv6 { port } => WebLocalhostBind {
            host: WebLocalhostHost::Ipv6Loopback,
            port,
        },
    })
}

fn resolve_home(explicit_home: Option<PathBuf>) -> Result<PathBuf, ServerStartupError> {
    if let Some(home) = explicit_home {
        return Ok(home);
    }

    selvedge_config::selvedge_home()
        .map_err(|error| ServerStartupError::ConfigInitFailed(error.to_string()))
}

fn init_config(explicit_home: Option<&PathBuf>) -> Result<(), ServerStartupError> {
    let result = if let Some(home) = explicit_home {
        selvedge_config::init_with_home(home)
    } else {
        selvedge_config::init()
    };

    match result {
        Ok(()) => Ok(()),
        Err(error) if error.to_string().contains("already") => {
            if let Some(home) = explicit_home {
                let selected_home = selvedge_config::selvedge_home()
                    .map_err(|error| ServerStartupError::ConfigInitFailed(error.to_string()))?;
                let requested_home = std::fs::canonicalize(home)
                    .map_err(|error| ServerStartupError::ConfigInitFailed(error.to_string()))?;
                if selected_home != requested_home {
                    return Err(ServerStartupError::ConfigInitFailed(format!(
                        "config service is initialized for {}, requested {}",
                        selected_home.display(),
                        requested_home.display()
                    )));
                }
            }

            Ok(())
        }
        Err(error) => Err(ServerStartupError::ConfigInitFailed(error.to_string())),
    }
}

fn init_logging() -> Result<(), ServerStartupError> {
    match selvedge_logging::init() {
        Ok(()) => Ok(()),
        Err(error) if error.to_string().contains("already") => Ok(()),
        Err(error) => Err(ServerStartupError::LoggingInitFailed(error.to_string())),
    }
}

fn acquire_singleton_lock(home: &Path) -> Result<File, ServerStartupError> {
    std::fs::create_dir_all(home).map_err(|error| {
        ServerStartupError::ConfigInitFailed(format!("failed to create home directory: {error}"))
    })?;

    match OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(lock_path_for_home(home))
    {
        Ok(file) => Ok(file),
        Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {
            Err(ServerStartupError::SingletonAlreadyRunning)
        }
        Err(error) => Err(ServerStartupError::ConfigInitFailed(error.to_string())),
    }
}

fn sqlite_path_for_home(home: &Path) -> PathBuf {
    home.join(SQLITE_FILE_NAME)
}

fn lock_path_for_home(home: &Path) -> PathBuf {
    home.join(LOCK_FILE_NAME)
}

fn map_events_start_error(error: SpawnEventsError) -> ServerStartupError {
    ServerStartupError::EventsStartFailed(format!("{error:?}"))
}

fn map_client_sync_start_error(error: SpawnClientSyncError) -> ServerStartupError {
    ServerStartupError::ClientSyncStartFailed(format!("{error:?}"))
}

fn map_router_start_error(error: SpawnRouterError) -> ServerStartupError {
    ServerStartupError::RouterStartFailed(format!("{error:?}"))
}

fn map_web_start_error(error: WebStartError) -> ServerStartupError {
    match error {
        WebStartError::InvalidBindTarget => ServerStartupError::InvalidBindTarget,
        WebStartError::BindFailed(message) => ServerStartupError::LocalhostBindFailed(message),
        WebStartError::TokioSpawnFailed => {
            ServerStartupError::LocalhostBindFailed("tokio spawn failed".to_owned())
        }
    }
}
