#![doc = include_str!("../README.md")]

use std::fmt;
use std::fs::{File, OpenOptions};
use std::io;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::task::{Context, Poll};

use fs2::FileExt;
use futures_core::Stream;
use selvedge_api::ApiExecutorConfig;
use selvedge_client_sync::{
    ClientSnapshotBuilder, ClientSyncHandle, ClientSyncIngress, ClientSyncStartArgs,
    SpawnClientSyncError, spawn_client_sync,
};
use selvedge_command_model::{
    BeginClientHydration, ClientCommandId, ClientEvent, ClientFrame, ClientId, ClientNotice,
    ClientNoticeLevel, ClientSnapshot, ClientSubscription, DeliverySeq, DetachClient, DetachReason,
    DetailLevel, EventControlMessage, EventIngress, EventIngressSender, HistoryNodeProjection,
    HistoryNodeProjectionBody, ModelCallStatusPhase, RouterCommandEnvelope, RouterIngressMessage,
    RouterIngressSender, SnapshotTaskVersion, TaskParentProjection, TaskProjection,
    TaskProjectionStatus, TaskScope, ToolExecutionStatusPhase,
};
use selvedge_core::TaskRuntimeSpawnDeps;
use selvedge_db::{OpenDbOptions, open_db};
use selvedge_domain_model::{
    MessageRole, ReasoningEffort, TaskId, ToolArgumentValue, ToolCallArgument,
};
use selvedge_events::{EventsHandle, EventsStartArgs, SpawnEventsError, spawn_events_task};
use selvedge_local_protocol::{
    AttachAccepted, AttachRejected, AttachRequest, CommandOutcome, CommandRejectReason,
    CommandRequest, CommandResponse, LocalClientCommandId, LocalClientEvent, LocalClientEventFrame,
    LocalClientFrame, LocalClientSnapshot, LocalClientSnapshotFrame, LocalDebugNoticeEvent,
    LocalDetailLevel, LocalHistoryAppendedEvent, LocalHistoryNodeProjection,
    LocalHistoryNodeProjectionBody, LocalMessageRole, LocalModelCallStatusEvent,
    LocalModelCallStatusPhase, LocalNotice, LocalNoticeLevel, LocalReasoningEffort,
    LocalSnapshotTaskVersion, LocalTaskChangedEvent, LocalTaskParentProjection,
    LocalTaskProjection, LocalTaskProjectionStatus, LocalTaskScope, LocalToolArgumentValue,
    LocalToolCallArgument, LocalToolExecutionStatusEvent, LocalToolExecutionStatusPhase,
    ReadyRequest, ReadyResponse, ReadyState, current_protocol_version, validate_attach_request,
    validate_command_request, validate_ready_request,
};
use selvedge_router::{RouterHandle, RouterStartArgs, SpawnRouterError, ToolExecutionSpawner};
use selvedge_web::{
    ReservedWebStartArgs, WebBindReservation, WebBridge, WebHandle, WebLocalhostBind,
    WebLocalhostHost, WebStartError, reserve_web_bind, spawn_reserved_web_surface,
};
use tokio::sync::{Mutex, Notify, RwLock, mpsc};
use tokio::task::JoinHandle;

const SQLITE_FILE_NAME: &str = "selvedge.sqlite";
const LOCK_FILE_NAME: &str = "server.lock";
const DEFAULT_EVENTS_INGRESS_CAPACITY: usize = 64;
const DEFAULT_CLIENT_REGISTRY_CAPACITY: usize = 64;
const DEFAULT_HYDRATION_BUFFER_CAPACITY: usize = 256;
const DEFAULT_CLIENT_SYNC_INGRESS_CAPACITY: usize = 64;

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
        validate_web_bind_target(&web_binding.bind_target)?;
    }

    init_config(args.explicit_home.as_ref())?;
    let home = resolve_home()?;
    let singleton_lock = acquire_singleton_lock(&home)?;
    let web_bind = match reserve_web_binding(args.web_binding.as_ref()) {
        Ok(web_bind) => web_bind,
        Err(error) => {
            cleanup_startup_lock(&home);
            return Err(error);
        }
    };

    let startup_result = start_server_after_lock(args, home, singleton_lock, web_bind);
    if let Err(error) = &startup_result {
        return Err(error.clone());
    }

    startup_result.map(ServerContext::into_handle)
}

impl ServerControl {
    pub async fn state(&self) -> ServerRuntimeState {
        self.inner.state.read().await.clone()
    }

    pub async fn ready(&self, request: ReadyRequest) -> ReadyResponse {
        let state = if validate_ready_request(&request).is_ok()
            && *self.inner.state.read().await == ServerRuntimeState::Ready
        {
            ReadyState::Ready
        } else {
            ReadyState::NotReady
        };

        ReadyResponse {
            protocol_version: current_protocol_version(),
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
        let _request_guard = self.inner.request_gate.lock().await;
        let protocol_version = current_protocol_version();
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

        let (outbound_tx, outbound_rx) = mpsc::channel(DEFAULT_HYDRATION_BUFFER_CAPACITY);
        let client_id = ClientId(request.client_id.0.clone());
        let client_command_id = ClientCommandId(request.client_command_id.0.clone());
        let begin = BeginClientHydration {
            client_id: client_id.clone(),
            client_command_id: client_command_id.clone(),
            outbound: outbound_tx,
            subscription: local_subscription_to_command(request.subscription),
        };
        let Some(events_tx) = self.inner.events_tx.lock().await.as_ref().cloned() else {
            return reject(CommandRejectReason::InternalFailure);
        };
        let client_sync_tx = self.inner.client_sync_tx.lock().await.clone();

        if client_sync_tx
            .send(ClientSyncIngress::StartHydration(begin))
            .await
            .is_err()
        {
            self.begin_shutdown().await;
            return reject(CommandRejectReason::InternalFailure);
        }

        Ok((
            AttachAccepted {
                protocol_version,
                client_id: request.client_id,
                client_command_id: request.client_command_id,
            },
            Box::pin(ServerAttachFrameStream {
                inner: outbound_rx,
                client_id,
                client_command_id,
                events_tx: events_tx.downgrade(),
                closed_reported: false,
            }),
        ))
    }

    pub async fn stop(&self) {
        self.begin_shutdown().await;
    }

    async fn submit_command_outcome(&self, request: CommandRequest) -> CommandOutcome {
        let _request_guard = self.inner.request_gate.lock().await;

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
                self.begin_shutdown_locked().await;
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
            self.begin_shutdown_locked().await;
            return CommandOutcome::Rejected(CommandRejectReason::RouterMailboxClosed);
        }

        CommandOutcome::Accepted
    }

    async fn begin_shutdown(&self) {
        let _request_guard = self.inner.request_gate.lock().await;
        self.begin_shutdown_locked().await;
    }

    async fn begin_shutdown_locked(&self) {
        if self.inner.closing.swap(true, Ordering::SeqCst) {
            return;
        }

        *self.inner.state.write().await = ServerRuntimeState::Closing;
        let _ = self.inner.router_tx.send(RouterIngressMessage::StopRouter);
        let client_sync_tx = self.inner.client_sync_tx.lock().await.clone();
        let _ = client_sync_tx.send(ClientSyncIngress::Shutdown).await;
        if let Some(web_control) = self.inner.web_control.lock().await.as_ref() {
            web_control.stop().await;
        }
        let _ = self.inner.events_tx.lock().await.take();
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
    request_gate: Mutex<()>,
    stop_notify: Notify,
    lock_path: PathBuf,
    _singleton_lock: File,
    router_tx: RouterIngressSender,
    events_tx: Mutex<Option<EventIngressSender>>,
    client_sync_tx: Mutex<selvedge_client_sync::ClientSyncSender>,
    command_mapper: Arc<dyn LocalCommandMapper>,
    web_control: Mutex<Option<selvedge_web::WebControl>>,
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
    web_bind: Option<WebBindReservation>,
) -> Result<ServerContext, ServerStartupError> {
    if let Err(error) = init_logging() {
        cleanup_startup_lock(&home);
        return Err(error);
    }

    let db = match open_db(OpenDbOptions {
        sqlite_path: sqlite_path_for_home(&home).to_string_lossy().to_string(),
    }) {
        Ok(db) => db,
        Err(error) => {
            cleanup_startup_lock(&home);
            return Err(ServerStartupError::DbOpenFailed(error.to_string()));
        }
    };

    let events = match spawn_events_task(EventsStartArgs {
        ingress_capacity: DEFAULT_EVENTS_INGRESS_CAPACITY,
        client_registry_capacity: DEFAULT_CLIENT_REGISTRY_CAPACITY,
        hydration_buffer_capacity: DEFAULT_HYDRATION_BUFFER_CAPACITY,
    }) {
        Ok(events) => events,
        Err(error) => {
            cleanup_startup_lock(&home);
            return Err(map_events_start_error(error));
        }
    };

    let client_sync = match spawn_client_sync(ClientSyncStartArgs {
        events_tx: events.ingress_tx.clone(),
        snapshot_builder: args.snapshot_builder,
        ingress_capacity: DEFAULT_CLIENT_SYNC_INGRESS_CAPACITY,
    }) {
        Ok(client_sync) => client_sync,
        Err(error) => {
            cleanup_startup_lock(&home);
            return Err(map_client_sync_start_error(error));
        }
    };

    let router = match selvedge_router::spawn_router(RouterStartArgs {
        db,
        events_tx: events.ingress_tx.clone(),
        api_config: args.api_config,
        tool_executor: args.tool_executor,
        core_spawn_deps: args.core_spawn_deps,
    }) {
        Ok(router) => router,
        Err(error) => {
            cleanup_startup_lock(&home);
            return Err(map_router_start_error(error));
        }
    };

    let web = match start_web(web_bind, &args.command_mapper) {
        Ok(web) => web,
        Err(error) => {
            cleanup_startup_lock(&home);
            return Err(error);
        }
    };

    let inner = Arc::new(ServerInner {
        state: RwLock::new(ServerRuntimeState::Ready),
        closing: AtomicBool::new(false),
        request_gate: Mutex::new(()),
        stop_notify: Notify::new(),
        lock_path: lock_path_for_home(&home),
        _singleton_lock: singleton_lock,
        router_tx: router.ingress_tx.clone(),
        events_tx: Mutex::new(Some(events.ingress_tx.clone())),
        client_sync_tx: Mutex::new(client_sync.ingress_tx.clone()),
        command_mapper: args.command_mapper,
        web_control: Mutex::new(web.as_ref().map(|handle| handle.control.clone())),
    });
    let join_handle = spawn_server_join_task(inner.clone(), router, events, client_sync, web);

    Ok(ServerContext { inner, join_handle })
}

fn cleanup_startup_lock(home: &Path) {
    let _ = std::fs::remove_file(lock_path_for_home(home));
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

struct ServerAttachFrameStream {
    inner: mpsc::Receiver<ClientFrame>,
    client_id: ClientId,
    client_command_id: ClientCommandId,
    // NOTE: Weak sender lets server shutdown close events while callers still hold frame streams;
    // Drop upgrades it only to report client detach.
    events_tx: mpsc::WeakSender<EventIngress>,
    closed_reported: bool,
}

impl futures_core::Stream for ServerAttachFrameStream {
    type Item = Result<LocalClientFrame, ServerRequestError>;

    fn poll_next(self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let this = self.get_mut();
        if this.closed_reported {
            return Poll::Ready(None);
        }
        match this.inner.poll_recv(context) {
            Poll::Ready(Some(frame)) => Poll::Ready(Some(Ok(client_frame_to_local(frame)))),
            Poll::Ready(None) => {
                this.closed_reported = true;
                Poll::Ready(Some(Err(ServerRequestError::AttachChannelFailed)))
            }
            Poll::Pending => Poll::Pending,
        }
    }
}

impl Drop for ServerAttachFrameStream {
    fn drop(&mut self) {
        let Some(events_tx) = self.events_tx.upgrade() else {
            return;
        };
        let retry_events_tx = events_tx.clone();
        let client_id = self.client_id.clone();
        let client_command_id = self.client_command_id.clone();
        let detach = EventIngress::Control(EventControlMessage::DetachClient(DetachClient {
            client_id,
            client_command_id,
            reason: DetachReason::ClientRequested,
        }));

        match events_tx.try_send(detach) {
            Ok(()) => {}
            Err(error) => {
                if let Ok(handle) = tokio::runtime::Handle::try_current() {
                    handle.spawn(async move {
                        let _ = retry_events_tx.send(error.into_inner()).await;
                    });
                }
            }
        }
    }
}

fn local_subscription_to_command(
    subscription: selvedge_local_protocol::LocalClientSubscription,
) -> ClientSubscription {
    ClientSubscription {
        task_scope: match subscription.task_scope {
            LocalTaskScope::AllTasks => TaskScope::AllTasks,
            LocalTaskScope::TaskIds(task_ids) => {
                TaskScope::TaskIds(task_ids.into_iter().map(TaskId).collect())
            }
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

fn client_frame_to_local(frame: ClientFrame) -> LocalClientFrame {
    match frame {
        ClientFrame::Snapshot(frame) => LocalClientFrame::Snapshot(LocalClientSnapshotFrame {
            delivery_seq: local_delivery_seq(frame.delivery_seq),
            client_command_id: LocalClientCommandId(frame.client_command_id.0),
            snapshot: client_snapshot_to_local(frame.snapshot),
        }),
        ClientFrame::Event(frame) => LocalClientFrame::Event(LocalClientEventFrame {
            delivery_seq: local_delivery_seq(frame.delivery_seq),
            event: client_event_to_local(frame.event),
        }),
        ClientFrame::Notice(frame) => {
            LocalClientFrame::Notice(selvedge_local_protocol::LocalClientNoticeFrame {
                delivery_seq: local_delivery_seq(frame.delivery_seq),
                client_command_id: LocalClientCommandId(frame.client_command_id.0),
                notice: client_notice_to_local(frame.notice),
            })
        }
    }
}

fn local_delivery_seq(delivery_seq: DeliverySeq) -> u64 {
    delivery_seq.0
}

fn client_snapshot_to_local(snapshot: ClientSnapshot) -> LocalClientSnapshot {
    LocalClientSnapshot {
        generated_at: snapshot.generated_at.0,
        tasks: snapshot.tasks.into_iter().map(task_to_local).collect(),
        task_parent_edges: snapshot
            .task_parent_edges
            .into_iter()
            .map(parent_edge_to_local)
            .collect(),
        history_nodes: snapshot
            .history_nodes
            .into_iter()
            .map(history_node_to_local)
            .collect(),
        task_versions: snapshot
            .task_versions
            .into_iter()
            .map(snapshot_task_version_to_local)
            .collect(),
    }
}

fn snapshot_task_version_to_local(version: SnapshotTaskVersion) -> LocalSnapshotTaskVersion {
    LocalSnapshotTaskVersion {
        task_id: version.task_id.0,
        state_version: version.state_version,
    }
}

fn task_to_local(task: TaskProjection) -> LocalTaskProjection {
    LocalTaskProjection {
        task_id: task.task_id.0,
        status: match task.status {
            TaskProjectionStatus::Active => LocalTaskProjectionStatus::Active,
            TaskProjectionStatus::Archived => LocalTaskProjectionStatus::Archived,
        },
        cursor_node_id: task.cursor_node_id.0,
        model_profile_key: task.model_profile_key.0,
        reasoning_effort: reasoning_effort_to_local(task.reasoning_effort),
        state_version: task.state_version,
        created_at: task.created_at.0,
        updated_at: task.updated_at.0,
    }
}

fn parent_edge_to_local(edge: TaskParentProjection) -> LocalTaskParentProjection {
    LocalTaskParentProjection {
        parent_task_id: edge.parent_task_id.0,
        child_task_id: edge.child_task_id.0,
    }
}

fn history_node_to_local(node: HistoryNodeProjection) -> LocalHistoryNodeProjection {
    LocalHistoryNodeProjection {
        node_id: node.node_id.0,
        parent_node_id: node.parent_node_id.map(|node_id| node_id.0),
        created_at: node.created_at.0,
        body: history_node_body_to_local(node.body),
    }
}

fn history_node_body_to_local(body: HistoryNodeProjectionBody) -> LocalHistoryNodeProjectionBody {
    match body {
        HistoryNodeProjectionBody::Message { role, text } => {
            LocalHistoryNodeProjectionBody::Message {
                role: message_role_to_local(role),
                text,
            }
        }
        HistoryNodeProjectionBody::Reasoning { text } => {
            LocalHistoryNodeProjectionBody::Reasoning { text }
        }
        HistoryNodeProjectionBody::FunctionCall {
            function_call_id,
            tool_name,
            arguments,
        } => LocalHistoryNodeProjectionBody::FunctionCall {
            function_call_id: function_call_id.0,
            tool_name: tool_name.0,
            arguments: arguments.into_iter().map(tool_argument_to_local).collect(),
        },
        HistoryNodeProjectionBody::FunctionOutput {
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
    }
}

fn client_event_to_local(event: ClientEvent) -> LocalClientEvent {
    match event {
        ClientEvent::TaskChanged(event) => LocalClientEvent::TaskChanged(LocalTaskChangedEvent {
            task: task_to_local(event.task),
        }),
        ClientEvent::HistoryAppended(event) => {
            LocalClientEvent::HistoryAppended(LocalHistoryAppendedEvent {
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
                phase: model_call_status_phase_to_local(event.phase),
            })
        }
        ClientEvent::ToolExecutionStatus(event) => {
            LocalClientEvent::ToolExecutionStatus(LocalToolExecutionStatusEvent {
                task_id: event.task_id.0,
                tool_execution_run_id: event.tool_execution_run_id.0,
                function_call_node_id: event.function_call_node_id.0,
                tool_name: event.tool_name.0,
                phase: tool_execution_status_phase_to_local(event.phase),
            })
        }
        ClientEvent::DebugNotice(event) => LocalClientEvent::DebugNotice(LocalDebugNoticeEvent {
            task_id: event.task_id.map(|task_id| task_id.0),
            message_text: event.message_text,
        }),
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

fn model_call_status_phase_to_local(phase: ModelCallStatusPhase) -> LocalModelCallStatusPhase {
    match phase {
        ModelCallStatusPhase::Requested => LocalModelCallStatusPhase::Requested,
        ModelCallStatusPhase::Completed => LocalModelCallStatusPhase::Completed,
        ModelCallStatusPhase::Failed => LocalModelCallStatusPhase::Failed,
        ModelCallStatusPhase::Discarded => LocalModelCallStatusPhase::Discarded,
    }
}

fn tool_execution_status_phase_to_local(
    phase: ToolExecutionStatusPhase,
) -> LocalToolExecutionStatusPhase {
    match phase {
        ToolExecutionStatusPhase::Requested => LocalToolExecutionStatusPhase::Requested,
        ToolExecutionStatusPhase::Completed => LocalToolExecutionStatusPhase::Completed,
        ToolExecutionStatusPhase::Failed => LocalToolExecutionStatusPhase::Failed,
        ToolExecutionStatusPhase::Discarded => LocalToolExecutionStatusPhase::Discarded,
    }
}

fn reasoning_effort_to_local(reasoning_effort: ReasoningEffort) -> LocalReasoningEffort {
    match reasoning_effort {
        ReasoningEffort::Minimal => LocalReasoningEffort::Minimal,
        ReasoningEffort::Low => LocalReasoningEffort::Low,
        ReasoningEffort::Medium => LocalReasoningEffort::Medium,
        ReasoningEffort::High => LocalReasoningEffort::High,
    }
}

fn message_role_to_local(role: MessageRole) -> LocalMessageRole {
    match role {
        MessageRole::System => LocalMessageRole::System,
        MessageRole::Developer => LocalMessageRole::Developer,
        MessageRole::User => LocalMessageRole::User,
        MessageRole::Assistant => LocalMessageRole::Assistant,
        MessageRole::Tool => LocalMessageRole::Tool,
    }
}

fn tool_argument_to_local(argument: ToolCallArgument) -> LocalToolCallArgument {
    LocalToolCallArgument {
        name: argument.name.0,
        value: tool_argument_value_to_local(argument.value),
    }
}

fn tool_argument_value_to_local(value: ToolArgumentValue) -> LocalToolArgumentValue {
    match value {
        ToolArgumentValue::String(value) => LocalToolArgumentValue::String(value),
        ToolArgumentValue::Integer(value) => LocalToolArgumentValue::Integer(value),
        ToolArgumentValue::Number(value) => LocalToolArgumentValue::Number(value),
        ToolArgumentValue::Boolean(value) => LocalToolArgumentValue::Boolean(value),
    }
}

fn start_web(
    web_bind: Option<WebBindReservation>,
    bridge: &Arc<dyn LocalCommandMapper>,
) -> Result<Option<WebHandle>, ServerStartupError> {
    let Some(bind) = web_bind else {
        return Ok(None);
    };

    let bridge = Arc::new(ServerWebBridge {
        _command_mapper: Arc::clone(bridge),
    });
    spawn_reserved_web_surface(ReservedWebStartArgs { bind, bridge })
        .map(Some)
        .map_err(map_web_start_error)
}

fn reserve_web_binding(
    web_binding: Option<&WebBindingConfig>,
) -> Result<Option<WebBindReservation>, ServerStartupError> {
    let Some(web_binding) = web_binding else {
        return Ok(None);
    };

    let bind = local_bind_to_web_bind(web_binding.bind_target.clone())?;
    reserve_web_bind(bind)
        .map(Some)
        .map_err(map_web_start_error)
}

struct ServerWebBridge {
    _command_mapper: Arc<dyn LocalCommandMapper>,
}

impl WebBridge for ServerWebBridge {
    fn ready(&self, _request: ReadyRequest) -> selvedge_web::WebBridgeFuture<ReadyResponse> {
        Box::pin(async {
            Ok(ReadyResponse {
                protocol_version: current_protocol_version(),
                state: ReadyState::Ready,
            })
        })
    }

    fn submit_command(
        &self,
        request: CommandRequest,
    ) -> selvedge_web::WebBridgeFuture<CommandResponse> {
        Box::pin(async move {
            Ok(CommandResponse {
                protocol_version: current_protocol_version(),
                client_command_id: request.client_command_id,
                outcome: CommandOutcome::Rejected(CommandRejectReason::InternalFailure),
            })
        })
    }

    fn attach(&self, _request: AttachRequest) -> selvedge_web::WebAttachFuture {
        Box::pin(async {
            Err(selvedge_web::AttachRejectedOrBridgeError::Bridge(
                selvedge_web::WebBridgeError::InternalFailure(
                    "server web bridge is owned by the server runtime".to_owned(),
                ),
            ))
        })
    }
}

fn validate_bind_target(bind_target: &LocalhostBindTarget) -> Result<(), ServerStartupError> {
    match bind_target {
        LocalhostBindTarget::Ipv4 { .. } | LocalhostBindTarget::Ipv6 { .. } => Ok(()),
    }
}

fn validate_web_bind_target(bind_target: &LocalhostBindTarget) -> Result<(), ServerStartupError> {
    match bind_target {
        LocalhostBindTarget::Ipv4 { port } | LocalhostBindTarget::Ipv6 { port } if *port == 0 => {
            Err(ServerStartupError::InvalidBindTarget)
        }
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

fn resolve_home() -> Result<PathBuf, ServerStartupError> {
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
        .create(true)
        .truncate(false)
        .write(true)
        .read(true)
        .open(lock_path_for_home(home))
    {
        Ok(file) => match file.try_lock_exclusive() {
            Ok(()) => Ok(file),
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                Err(ServerStartupError::SingletonAlreadyRunning)
            }
            Err(error) => Err(ServerStartupError::ConfigInitFailed(error.to_string())),
        },
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
