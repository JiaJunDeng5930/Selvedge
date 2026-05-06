#![doc = include_str!("../README.md")]

use std::collections::HashMap;
use std::fmt;
use std::fs::{File, OpenOptions};
use std::io;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex as StdMutex};
use std::task::{Context, Poll};

use fs2::FileExt;
use futures_core::Stream;
use selvedge_api::ApiExecutorConfig;
use selvedge_client_sync::{
    CancelHydration, ClientSnapshotBuilder, ClientSyncHandle, ClientSyncIngress,
    ClientSyncStartArgs, SpawnClientSyncError, spawn_client_sync,
};
use selvedge_command_model::{
    BeginClientHydration, ClientCommandId, ClientEvent, ClientFrame, ClientFrameSender, ClientId,
    ClientNotice, ClientNoticeLevel, ClientSnapshot, ClientSubscription, DeliverySeq, DetachClient,
    DetachReason, DetailLevel, EventControlMessage, EventIngress, EventIngressSender,
    HistoryNodeProjection, HistoryNodeProjectionBody, ModelCallStatusPhase,
    RouterAttachAdmissionResult, RouterCommand, RouterCommandEnvelope, RouterIngressMessage,
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
    AttachAccepted, AttachRejectReason, AttachRejected, AttachRequest, CommandOutcome,
    CommandRejectReason, CommandRequest, CommandResponse, LocalClientCommandId, LocalClientEvent,
    LocalClientEventFrame, LocalClientFrame, LocalClientSnapshot, LocalClientSnapshotFrame,
    LocalDebugNoticeEvent, LocalDetailLevel, LocalHistoryAppendedEvent, LocalHistoryNodeProjection,
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

type ActiveAttachRegistry = Arc<StdMutex<HashMap<ClientId, ClientCommandId>>>;

trait AttachFrameChannelFactory: Send + Sync {
    fn create(
        &self,
        capacity: usize,
    ) -> Result<(ClientFrameSender, mpsc::Receiver<ClientFrame>), AttachRejectReason>;
}

struct TokioAttachFrameChannelFactory;

impl AttachFrameChannelFactory for TokioAttachFrameChannelFactory {
    fn create(
        &self,
        capacity: usize,
    ) -> Result<(ClientFrameSender, mpsc::Receiver<ClientFrame>), AttachRejectReason> {
        Ok(mpsc::channel(capacity))
    }
}

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
            return reject(AttachRejectReason::ServerNotReady);
        }

        if validate_attach_request(&request).is_err() {
            if request.protocol_version != current_protocol_version() {
                return reject(AttachRejectReason::ProtocolVersionMismatch);
            }
            return reject(AttachRejectReason::MalformedRequest);
        }

        if self.inner.router_tx.is_closed() {
            self.begin_shutdown_locked().await;
            return reject(AttachRejectReason::RouterMailboxClosed);
        }

        let Some(events_tx) = self.inner.events_tx.lock().await.as_ref().cloned() else {
            return reject(AttachRejectReason::InternalFailure);
        };
        let client_id = ClientId(request.client_id.0.clone());
        let client_command_id = ClientCommandId(request.client_command_id.0.clone());
        let previous_attach = match self
            .inner
            .reserve_active_attach(&client_id, &client_command_id)
        {
            Ok(previous_attach) => previous_attach,
            Err(reason) => return reject(reason),
        };
        let mut reservation = ActiveAttachReservation::new(
            Arc::clone(&self.inner.active_attaches),
            client_id.clone(),
            client_command_id.clone(),
            previous_attach,
            Some(events_tx.clone()),
        );

        let (outbound_tx, outbound_rx) = match self
            .inner
            .frame_channel_factory
            .create(DEFAULT_HYDRATION_BUFFER_CAPACITY)
        {
            Ok(channel) => channel,
            Err(reason) => return reject(reason),
        };
        let subscription = local_subscription_to_command(request.subscription);
        let (admission_tx, admission_rx) = tokio::sync::oneshot::channel();
        if self
            .inner
            .router_tx
            .send(RouterIngressMessage::Command(RouterCommandEnvelope {
                client_id: Some(client_id.clone()),
                client_command_id: Some(client_command_id.clone()),
                command: RouterCommand::AttachClient {
                    client_id: client_id.clone(),
                    client_command_id: client_command_id.clone(),
                    outbound: outbound_tx.clone(),
                    subscription: subscription.clone(),
                    admission_tx,
                },
            }))
            .is_err()
        {
            self.begin_shutdown_locked().await;
            return reject(AttachRejectReason::RouterMailboxClosed);
        }
        reservation.mark_router_attach_sent();

        match admission_rx.await {
            Ok(RouterAttachAdmissionResult::Accepted) => {
                reservation.mark_events_reserved();
            }
            Ok(RouterAttachAdmissionResult::DuplicateAttach) => {
                return reject(AttachRejectReason::DuplicateAttach);
            }
            Ok(RouterAttachAdmissionResult::ClientRegistryFull) => {
                return reject(AttachRejectReason::ClientRegistryFull);
            }
            Ok(RouterAttachAdmissionResult::EventsMailboxClosed) | Err(_) => {
                self.begin_shutdown_locked().await;
                return reject(AttachRejectReason::InternalFailure);
            }
        }

        let begin = BeginClientHydration {
            client_id: client_id.clone(),
            client_command_id: client_command_id.clone(),
            outbound: outbound_tx,
            subscription,
        };
        let client_sync_tx = self.inner.client_sync_tx.lock().await.clone();

        match client_sync_tx.try_send(ClientSyncIngress::StartHydration(begin)) {
            Ok(()) => {}
            Err(tokio::sync::mpsc::error::TrySendError::Full(_)) => {
                reservation.cleanup_events_reservation_before_reject().await;
                return reject(AttachRejectReason::ClientSyncUnavailable);
            }
            Err(tokio::sync::mpsc::error::TrySendError::Closed(_)) => {
                reservation.cleanup_events_reservation_before_reject().await;
                self.begin_shutdown_locked().await;
                return reject(AttachRejectReason::ClientSyncUnavailable);
            }
        }

        if let Some(previous_command_id) = reservation.previous_attach() {
            send_cancel_hydration(
                &client_sync_tx,
                client_id.clone(),
                previous_command_id.clone(),
            );
            send_detach_client(
                &events_tx,
                client_id.clone(),
                previous_command_id,
                DetachReason::ReplacedByNewHydration,
            );
        }

        reservation.commit();

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
                client_sync_tx: client_sync_tx.downgrade(),
                active_attaches: Arc::clone(&self.inner.active_attaches),
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
    active_attaches: ActiveAttachRegistry,
    frame_channel_factory: Arc<dyn AttachFrameChannelFactory>,
    command_mapper: Arc<dyn LocalCommandMapper>,
    web_control: Mutex<Option<selvedge_web::WebControl>>,
}

impl ServerInner {
    fn reserve_active_attach(
        &self,
        client_id: &ClientId,
        client_command_id: &ClientCommandId,
    ) -> Result<Option<ClientCommandId>, AttachRejectReason> {
        let mut active = self
            .active_attaches
            .lock()
            .expect("server active attach registry lock");

        if active.get(client_id) == Some(client_command_id) {
            return Err(AttachRejectReason::DuplicateAttach);
        }

        if !active.contains_key(client_id) && active.len() >= DEFAULT_CLIENT_REGISTRY_CAPACITY {
            return Err(AttachRejectReason::ClientRegistryFull);
        }

        Ok(active.insert(client_id.clone(), client_command_id.clone()))
    }
}

struct ActiveAttachReservation {
    active_attaches: ActiveAttachRegistry,
    client_id: ClientId,
    client_command_id: ClientCommandId,
    previous_attach: Option<ClientCommandId>,
    events_tx: Option<EventIngressSender>,
    events_reserved: bool,
    router_attach_sent: bool,
    active: bool,
}

impl ActiveAttachReservation {
    fn new(
        active_attaches: ActiveAttachRegistry,
        client_id: ClientId,
        client_command_id: ClientCommandId,
        previous_attach: Option<ClientCommandId>,
        events_tx: Option<EventIngressSender>,
    ) -> Self {
        Self {
            active_attaches,
            client_id,
            client_command_id,
            previous_attach,
            events_tx,
            events_reserved: false,
            router_attach_sent: false,
            active: true,
        }
    }

    fn previous_attach(&self) -> Option<ClientCommandId> {
        self.previous_attach.clone()
    }

    fn commit(&mut self) {
        self.active = false;
    }

    fn mark_events_reserved(&mut self) {
        self.events_reserved = true;
    }

    fn mark_router_attach_sent(&mut self) {
        self.router_attach_sent = true;
    }

    async fn cleanup_events_reservation_before_reject(&mut self) {
        if self.events_reserved
            && let Some(events_tx) = &self.events_tx
        {
            send_detach_client_await(
                events_tx,
                self.client_id.clone(),
                self.client_command_id.clone(),
                DetachReason::ClientDisconnected,
            )
            .await;
        }
        restore_active_attach(
            &self.active_attaches,
            &self.client_id,
            &self.client_command_id,
            self.previous_attach.clone(),
        );
        self.active = false;
    }
}

impl Drop for ActiveAttachReservation {
    fn drop(&mut self) {
        if self.active {
            if (self.events_reserved || self.router_attach_sent)
                && let Some(events_tx) = &self.events_tx
            {
                send_detach_client_and_restore_active(
                    events_tx,
                    self.client_id.clone(),
                    self.client_command_id.clone(),
                    DetachReason::ClientDisconnected,
                    Arc::clone(&self.active_attaches),
                    self.previous_attach.clone(),
                );
            } else {
                restore_active_attach(
                    &self.active_attaches,
                    &self.client_id,
                    &self.client_command_id,
                    self.previous_attach.clone(),
                );
            }
        }
    }
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
        active_attaches: Arc::new(StdMutex::new(HashMap::new())),
        frame_channel_factory: Arc::new(TokioAttachFrameChannelFactory),
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
    client_sync_tx: mpsc::WeakSender<ClientSyncIngress>,
    active_attaches: ActiveAttachRegistry,
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
                clear_active_attach(
                    &this.active_attaches,
                    &this.client_id,
                    &this.client_command_id,
                );
                this.closed_reported = true;
                Poll::Ready(Some(Err(ServerRequestError::AttachChannelFailed)))
            }
            Poll::Pending => Poll::Pending,
        }
    }
}

impl Drop for ServerAttachFrameStream {
    fn drop(&mut self) {
        if self.closed_reported {
            return;
        }

        let client_id = self.client_id.clone();
        let client_command_id = self.client_command_id.clone();

        if let Some(client_sync_tx) = self.client_sync_tx.upgrade() {
            send_cancel_hydration(
                &client_sync_tx,
                client_id.clone(),
                client_command_id.clone(),
            );
        }

        let Some(events_tx) = self.events_tx.upgrade() else {
            clear_active_attach(&self.active_attaches, &client_id, &client_command_id);
            return;
        };
        send_detach_client_and_clear_active(
            &events_tx,
            client_id,
            client_command_id,
            DetachReason::ClientDisconnected,
            Arc::clone(&self.active_attaches),
        );
    }
}

fn send_cancel_hydration(
    client_sync_tx: &selvedge_client_sync::ClientSyncSender,
    client_id: ClientId,
    client_command_id: ClientCommandId,
) {
    let retry_client_sync_tx = client_sync_tx.clone();
    let cancel = ClientSyncIngress::CancelHydration(CancelHydration {
        client_id,
        client_command_id,
    });

    match client_sync_tx.try_send(cancel) {
        Ok(()) => {}
        Err(tokio::sync::mpsc::error::TrySendError::Full(cancel)) => {
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                handle.spawn(async move {
                    let _ = retry_client_sync_tx.send(cancel).await;
                });
            } else {
                let _ = retry_client_sync_tx.blocking_send(cancel);
            }
        }
        Err(tokio::sync::mpsc::error::TrySendError::Closed(_)) => {}
    }
}

fn send_detach_client(
    events_tx: &EventIngressSender,
    client_id: ClientId,
    client_command_id: ClientCommandId,
    reason: DetachReason,
) {
    let retry_events_tx = events_tx.clone();
    let detach = EventIngress::Control(EventControlMessage::DetachClient(DetachClient {
        client_id,
        client_command_id,
        reason,
    }));

    match events_tx.try_send(detach) {
        Ok(()) => {}
        Err(tokio::sync::mpsc::error::TrySendError::Full(detach)) => {
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                handle.spawn(async move {
                    let _ = retry_events_tx.send(detach).await;
                });
            } else {
                let _ = retry_events_tx.blocking_send(detach);
            }
        }
        Err(tokio::sync::mpsc::error::TrySendError::Closed(_)) => {}
    }
}

async fn send_detach_client_await(
    events_tx: &EventIngressSender,
    client_id: ClientId,
    client_command_id: ClientCommandId,
    reason: DetachReason,
) {
    let detach = EventIngress::Control(EventControlMessage::DetachClient(DetachClient {
        client_id,
        client_command_id,
        reason,
    }));
    let _ = events_tx.send(detach).await;
}

fn send_detach_client_and_restore_active(
    events_tx: &EventIngressSender,
    client_id: ClientId,
    client_command_id: ClientCommandId,
    reason: DetachReason,
    active_attaches: ActiveAttachRegistry,
    previous_attach: Option<ClientCommandId>,
) {
    let retry_events_tx = events_tx.clone();
    let detach = EventIngress::Control(EventControlMessage::DetachClient(DetachClient {
        client_id: client_id.clone(),
        client_command_id: client_command_id.clone(),
        reason,
    }));

    match events_tx.try_send(detach) {
        Ok(()) | Err(tokio::sync::mpsc::error::TrySendError::Closed(_)) => {
            restore_active_attach(
                &active_attaches,
                &client_id,
                &client_command_id,
                previous_attach,
            );
        }
        Err(tokio::sync::mpsc::error::TrySendError::Full(detach)) => {
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                handle.spawn(async move {
                    let _ = retry_events_tx.send(detach).await;
                    restore_active_attach(
                        &active_attaches,
                        &client_id,
                        &client_command_id,
                        previous_attach,
                    );
                });
            } else {
                let _ = retry_events_tx.blocking_send(detach);
                restore_active_attach(
                    &active_attaches,
                    &client_id,
                    &client_command_id,
                    previous_attach,
                );
            }
        }
    }
}

fn send_detach_client_and_clear_active(
    events_tx: &EventIngressSender,
    client_id: ClientId,
    client_command_id: ClientCommandId,
    reason: DetachReason,
    active_attaches: ActiveAttachRegistry,
) {
    let retry_events_tx = events_tx.clone();
    let detach = EventIngress::Control(EventControlMessage::DetachClient(DetachClient {
        client_id: client_id.clone(),
        client_command_id: client_command_id.clone(),
        reason,
    }));

    match events_tx.try_send(detach) {
        Ok(()) | Err(tokio::sync::mpsc::error::TrySendError::Closed(_)) => {
            clear_active_attach(&active_attaches, &client_id, &client_command_id);
        }
        Err(tokio::sync::mpsc::error::TrySendError::Full(detach)) => {
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                handle.spawn(async move {
                    let _ = retry_events_tx.send(detach).await;
                    clear_active_attach(&active_attaches, &client_id, &client_command_id);
                });
            } else {
                let _ = retry_events_tx.blocking_send(detach);
                clear_active_attach(&active_attaches, &client_id, &client_command_id);
            }
        }
    }
}

fn clear_active_attach(
    active_attaches: &ActiveAttachRegistry,
    client_id: &ClientId,
    client_command_id: &ClientCommandId,
) {
    let mut active = active_attaches
        .lock()
        .expect("server active attach registry lock");
    if active.get(client_id) == Some(client_command_id) {
        active.remove(client_id);
    }
}

fn restore_active_attach(
    active_attaches: &ActiveAttachRegistry,
    client_id: &ClientId,
    client_command_id: &ClientCommandId,
    previous_attach: Option<ClientCommandId>,
) {
    let mut active = active_attaches
        .lock()
        .expect("server active attach registry lock");
    if active.get(client_id) != Some(client_command_id) {
        return;
    }

    if let Some(previous_command_id) = previous_attach {
        active.insert(client_id.clone(), previous_command_id);
    } else {
        active.remove(client_id);
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

#[cfg(test)]
mod tests {
    use super::*;
    use futures_util::StreamExt;
    use std::time::Duration;
    use tokio::time::timeout;

    struct UnusedMapper;

    impl LocalCommandMapper for UnusedMapper {
        fn map_command(
            &self,
            _request: CommandRequest,
        ) -> Result<RouterCommandEnvelope, ServerRequestError> {
            unreachable!("attach shutdown-path tests never submit commands")
        }
    }

    struct FailOnceAttachFrameChannelFactory {
        failed: AtomicBool,
    }

    impl FailOnceAttachFrameChannelFactory {
        fn new() -> Self {
            Self {
                failed: AtomicBool::new(false),
            }
        }
    }

    impl AttachFrameChannelFactory for FailOnceAttachFrameChannelFactory {
        fn create(
            &self,
            capacity: usize,
        ) -> Result<(ClientFrameSender, mpsc::Receiver<ClientFrame>), AttachRejectReason> {
            if !self.failed.swap(true, Ordering::SeqCst) {
                return Err(AttachRejectReason::AttachChannelFailed);
            }

            Ok(mpsc::channel(capacity))
        }
    }

    #[tokio::test]
    async fn attach_closed_router_shutdown_path_returns_rejection() {
        let (router_tx, router_rx) = mpsc::unbounded_channel();
        drop(router_rx);
        let (client_sync_tx, _client_sync_rx) = mpsc::channel(1);
        let (events_tx, _events_rx) = mpsc::channel(1);
        let control = test_control(router_tx, client_sync_tx, events_tx);

        let rejected = match timeout(
            Duration::from_millis(100),
            control.attach_client(test_attach_request()),
        )
        .await
        .expect("attach returns")
        {
            Ok(_) => panic!("attach should reject after router mailbox closes"),
            Err(rejected) => rejected,
        };

        assert_eq!(rejected.reason, AttachRejectReason::RouterMailboxClosed);
        assert_eq!(control.state().await, ServerRuntimeState::Closing);
    }

    #[tokio::test]
    async fn attach_closed_client_sync_shutdown_path_returns_rejection() {
        let router_tx = accepting_router_sender();
        let (client_sync_tx, client_sync_rx) = mpsc::channel(1);
        drop(client_sync_rx);
        let (events_tx, _events_rx) = mpsc::channel(1);
        let control = test_control(router_tx, client_sync_tx, events_tx);

        let rejected = match timeout(
            Duration::from_millis(100),
            control.attach_client(test_attach_request()),
        )
        .await
        .expect("attach returns")
        {
            Ok(_) => panic!("attach should reject after client-sync mailbox closes"),
            Err(rejected) => rejected,
        };

        assert_eq!(rejected.reason, AttachRejectReason::ClientSyncUnavailable);
        assert_eq!(control.state().await, ServerRuntimeState::Closing);
    }

    #[tokio::test]
    async fn attach_closed_events_admission_starts_shutdown() {
        let router_tx = events_closed_router_sender();
        let (client_sync_tx, _client_sync_rx) = mpsc::channel(1);
        let (events_tx, _events_rx) = mpsc::channel(1);
        let control = test_control(router_tx, client_sync_tx, events_tx);

        let rejected = match timeout(
            Duration::from_millis(100),
            control.attach_client(test_attach_request()),
        )
        .await
        .expect("attach returns")
        {
            Ok(_) => panic!("attach should reject after events admission closes"),
            Err(rejected) => rejected,
        };

        assert_eq!(rejected.reason, AttachRejectReason::InternalFailure);
        assert_eq!(control.state().await, ServerRuntimeState::Closing);
    }

    #[tokio::test]
    async fn duplicate_active_attach_rejects_without_second_start() {
        let router_tx = accepting_router_sender();
        let (client_sync_tx, mut client_sync_rx) = mpsc::channel(4);
        let (events_tx, _events_rx) = mpsc::channel(4);
        let control = test_control(router_tx, client_sync_tx, events_tx);

        let (_accepted, _stream) = control
            .attach_client(test_attach_request())
            .await
            .expect("attach accepted");
        let _ = timeout(Duration::from_millis(100), client_sync_rx.recv())
            .await
            .expect("start hydration arrives")
            .expect("start hydration");

        let rejected = match control.attach_client(test_attach_request()).await {
            Ok(_) => panic!("duplicate attach should reject"),
            Err(rejected) => rejected,
        };

        assert_eq!(rejected.reason, AttachRejectReason::DuplicateAttach);
        assert!(matches!(
            client_sync_rx.try_recv(),
            Err(tokio::sync::mpsc::error::TryRecvError::Empty)
        ));
    }

    #[tokio::test]
    async fn new_client_attach_rejects_when_registry_capacity_is_reserved() {
        let router_tx = accepting_router_sender();
        let (client_sync_tx, mut client_sync_rx) =
            mpsc::channel(DEFAULT_CLIENT_REGISTRY_CAPACITY + 1);
        let (events_tx, _events_rx) = mpsc::channel(4);
        let control = test_control(router_tx, client_sync_tx, events_tx);
        let mut streams = Vec::new();

        for index in 0..DEFAULT_CLIENT_REGISTRY_CAPACITY {
            let (_accepted, stream) = control
                .attach_client(test_attach_request_for(
                    &format!("client-{index}"),
                    &format!("attach-{index}"),
                ))
                .await
                .expect("attach accepted");
            streams.push(stream);
            let _ = timeout(Duration::from_millis(100), client_sync_rx.recv())
                .await
                .expect("start hydration arrives")
                .expect("start hydration");
        }

        let rejected = match control
            .attach_client(test_attach_request_for(
                "client-overflow",
                "attach-overflow",
            ))
            .await
        {
            Ok(_) => panic!("full registry should reject"),
            Err(rejected) => rejected,
        };

        assert_eq!(rejected.reason, AttachRejectReason::ClientRegistryFull);
        assert!(matches!(
            client_sync_rx.try_recv(),
            Err(tokio::sync::mpsc::error::TryRecvError::Empty)
        ));
    }

    #[tokio::test]
    async fn frame_channel_creation_failure_rejects_and_restores_attach_slot() {
        let router_tx = accepting_router_sender();
        let (client_sync_tx, mut client_sync_rx) = mpsc::channel(4);
        let (events_tx, _events_rx) = mpsc::channel(4);
        let control = test_control_with_frame_channel_factory(
            router_tx,
            client_sync_tx,
            events_tx,
            Arc::new(FailOnceAttachFrameChannelFactory::new()),
        );

        let rejected = match control.attach_client(test_attach_request()).await {
            Ok(_) => panic!("frame channel failure should reject"),
            Err(rejected) => rejected,
        };

        assert_eq!(rejected.reason, AttachRejectReason::AttachChannelFailed);
        assert!(matches!(
            client_sync_rx.try_recv(),
            Err(tokio::sync::mpsc::error::TryRecvError::Empty)
        ));

        let (_accepted, _stream) = control
            .attach_client(test_attach_request())
            .await
            .expect("retry attach accepted after failed channel creation");
        let _ = timeout(Duration::from_millis(100), client_sync_rx.recv())
            .await
            .expect("retry start hydration arrives")
            .expect("retry start hydration");
    }

    #[tokio::test]
    async fn stale_stream_drop_after_replacement_preserves_new_active_attach() {
        let router_tx = accepting_router_sender();
        let (client_sync_tx, mut client_sync_rx) = mpsc::channel(8);
        let (events_tx, mut events_rx) = mpsc::channel(8);
        let control = test_control(router_tx, client_sync_tx, events_tx);

        let (_accepted, old_stream) = control
            .attach_client(test_attach_request_for("client-1", "attach-1"))
            .await
            .expect("first attach accepted");
        let _ = timeout(Duration::from_millis(100), client_sync_rx.recv())
            .await
            .expect("first start hydration arrives")
            .expect("first start hydration");

        let (_accepted, _new_stream) = control
            .attach_client(test_attach_request_for("client-1", "attach-2"))
            .await
            .expect("replacement attach accepted");
        let _ = timeout(Duration::from_millis(100), client_sync_rx.recv())
            .await
            .expect("replacement start hydration arrives")
            .expect("replacement start hydration");
        let _ = timeout(Duration::from_millis(100), client_sync_rx.recv())
            .await
            .expect("old cancel hydration arrives")
            .expect("old cancel hydration");
        let _ = timeout(Duration::from_millis(100), events_rx.recv())
            .await
            .expect("old detach arrives")
            .expect("old detach");

        drop(old_stream);

        let rejected = match control
            .attach_client(test_attach_request_for("client-1", "attach-2"))
            .await
        {
            Ok(_) => panic!("new attach should remain active"),
            Err(rejected) => rejected,
        };

        assert_eq!(rejected.reason, AttachRejectReason::DuplicateAttach);
    }

    #[tokio::test]
    async fn closed_frame_channel_clears_active_attach_before_stream_drop() {
        let router_tx = accepting_router_sender();
        let (client_sync_tx, mut client_sync_rx) = mpsc::channel(4);
        let (events_tx, _events_rx) = mpsc::channel(4);
        let control = test_control(router_tx, client_sync_tx, events_tx);

        let (_accepted, mut stream) = control
            .attach_client(test_attach_request())
            .await
            .expect("attach accepted");
        let start = timeout(Duration::from_millis(100), client_sync_rx.recv())
            .await
            .expect("start hydration arrives")
            .expect("start hydration");
        drop(start);

        let error = timeout(Duration::from_millis(100), stream.next())
            .await
            .expect("stream terminal item arrives")
            .expect("stream terminal item")
            .expect_err("closed frame channel reports error");
        assert_eq!(error, ServerRequestError::AttachChannelFailed);

        let (_accepted, _retry_stream) = control
            .attach_client(test_attach_request())
            .await
            .expect("retry attach accepted after channel close");
        let _ = timeout(Duration::from_millis(100), client_sync_rx.recv())
            .await
            .expect("retry start hydration arrives")
            .expect("retry start hydration");
        drop(stream);
        assert!(matches!(
            client_sync_rx.try_recv(),
            Err(tokio::sync::mpsc::error::TryRecvError::Empty)
        ));
    }

    #[tokio::test]
    async fn backpressured_client_sync_rejects_and_restores_attach_slot() {
        let router_tx = accepting_router_sender();
        let (client_sync_tx, mut client_sync_rx) = mpsc::channel(1);
        client_sync_tx
            .send(ClientSyncIngress::Shutdown)
            .await
            .expect("fill client-sync mailbox");
        let (events_tx, mut events_rx) = mpsc::channel(4);
        let control = test_control(router_tx, client_sync_tx, events_tx);

        let rejected = match control.attach_client(test_attach_request()).await {
            Ok(_) => panic!("backpressured client-sync should reject"),
            Err(rejected) => rejected,
        };
        assert_eq!(rejected.reason, AttachRejectReason::ClientSyncUnavailable);
        match timeout(Duration::from_millis(100), events_rx.recv())
            .await
            .expect("reservation cleanup detach arrives")
            .expect("reservation cleanup detach")
        {
            EventIngress::Control(EventControlMessage::DetachClient(detach)) => {
                assert_eq!(detach.client_id, ClientId("client-1".to_owned()));
                assert_eq!(
                    detach.client_command_id,
                    ClientCommandId("attach-1".to_owned())
                );
                assert_eq!(detach.reason, DetachReason::ClientDisconnected);
            }
            _ => panic!("unexpected events ingress"),
        }
        let _ = client_sync_rx.recv().await.expect("drain filled mailbox");

        let (_accepted, _stream) = control
            .attach_client(test_attach_request())
            .await
            .expect("attach accepted after cancelled future");
    }

    #[tokio::test]
    async fn rejected_attach_waits_for_full_events_cleanup_before_returning() {
        let router_tx = accepting_router_sender();
        let (client_sync_tx, mut client_sync_rx) = mpsc::channel(1);
        client_sync_tx
            .send(ClientSyncIngress::Shutdown)
            .await
            .expect("fill client-sync mailbox");
        let (events_tx, mut events_rx) = mpsc::channel(1);
        events_tx
            .try_send(EventIngress::Control(EventControlMessage::DetachClient(
                DetachClient {
                    client_id: ClientId("occupied-client".to_owned()),
                    client_command_id: ClientCommandId("occupied-attach".to_owned()),
                    reason: DetachReason::ClientRequested,
                },
            )))
            .expect("fill events mailbox");
        let control = test_control(router_tx, client_sync_tx, events_tx);

        let mut attach_task = tokio::spawn({
            let control = control.clone();
            async move { control.attach_client(test_attach_request()).await }
        });
        assert!(
            timeout(Duration::from_millis(10), &mut attach_task)
                .await
                .is_err()
        );

        let _ = events_rx.recv().await.expect("drain occupied events slot");
        match timeout(Duration::from_millis(100), events_rx.recv())
            .await
            .expect("reservation cleanup detach arrives")
            .expect("reservation cleanup detach")
        {
            EventIngress::Control(EventControlMessage::DetachClient(detach)) => {
                assert_eq!(detach.client_id, ClientId("client-1".to_owned()));
                assert_eq!(
                    detach.client_command_id,
                    ClientCommandId("attach-1".to_owned())
                );
                assert_eq!(detach.reason, DetachReason::ClientDisconnected);
            }
            _ => panic!("unexpected events ingress"),
        }
        let rejected = match attach_task.await.expect("attach task joins") {
            Ok(_) => panic!("backpressured client-sync should reject"),
            Err(rejected) => rejected,
        };
        assert_eq!(rejected.reason, AttachRejectReason::ClientSyncUnavailable);

        let _ = client_sync_rx.recv().await.expect("drain filled mailbox");
        let (_accepted, _stream) = control
            .attach_client(test_attach_request())
            .await
            .expect("attach accepted after queued cleanup");
    }

    #[tokio::test]
    async fn cancelled_attach_after_router_send_detaches_possible_reservation() {
        let (router_tx, mut router_rx) = mpsc::unbounded_channel();
        let (router_seen_tx, router_seen_rx) = tokio::sync::oneshot::channel();
        tokio::spawn(async move {
            let mut router_seen_tx = Some(router_seen_tx);
            while let Some(message) = router_rx.recv().await {
                match message {
                    RouterIngressMessage::Command(RouterCommandEnvelope {
                        command: RouterCommand::AttachClient { admission_tx, .. },
                        ..
                    }) => {
                        if let Some(router_seen_tx) = router_seen_tx.take() {
                            let _ = router_seen_tx.send(());
                        }
                        let _admission_tx = admission_tx;
                        std::future::pending::<()>().await;
                    }
                    RouterIngressMessage::StopRouter => break,
                    _ => {}
                }
            }
        });
        let (client_sync_tx, mut client_sync_rx) = mpsc::channel(4);
        let (events_tx, mut events_rx) = mpsc::channel(4);
        let control = test_control(router_tx, client_sync_tx, events_tx);
        let attach_task = tokio::spawn({
            let control = control.clone();
            async move { control.attach_client(test_attach_request()).await }
        });

        router_seen_rx.await.expect("router attach command arrives");
        attach_task.abort();
        match attach_task.await {
            Ok(_) => panic!("attach task should abort"),
            Err(error) => assert!(error.is_cancelled()),
        }

        match timeout(Duration::from_millis(100), events_rx.recv())
            .await
            .expect("cancelled attach detach arrives")
            .expect("cancelled attach detach")
        {
            EventIngress::Control(EventControlMessage::DetachClient(detach)) => {
                assert_eq!(detach.client_id, ClientId("client-1".to_owned()));
                assert_eq!(
                    detach.client_command_id,
                    ClientCommandId("attach-1".to_owned())
                );
                assert_eq!(detach.reason, DetachReason::ClientDisconnected);
            }
            _ => panic!("unexpected events ingress"),
        }
        assert!(matches!(
            client_sync_rx.try_recv(),
            Err(tokio::sync::mpsc::error::TryRecvError::Empty)
        ));
    }

    #[tokio::test]
    async fn dropped_attach_stream_sends_cancel_and_client_disconnect_detach() {
        let router_tx = accepting_router_sender();
        let (client_sync_tx, mut client_sync_rx) = mpsc::channel(4);
        let (events_tx, mut events_rx) = mpsc::channel(4);
        let control = test_control(router_tx, client_sync_tx, events_tx);

        let (_accepted, stream) = control
            .attach_client(test_attach_request())
            .await
            .expect("attach accepted");
        match timeout(Duration::from_millis(100), client_sync_rx.recv())
            .await
            .expect("start hydration arrives")
            .expect("start hydration")
        {
            ClientSyncIngress::StartHydration(begin) => {
                assert_eq!(begin.client_id, ClientId("client-1".to_owned()));
                assert_eq!(
                    begin.client_command_id,
                    ClientCommandId("attach-1".to_owned())
                );
            }
            _ => panic!("unexpected client-sync ingress"),
        }

        drop(stream);

        match timeout(Duration::from_millis(100), client_sync_rx.recv())
            .await
            .expect("cancel hydration arrives")
            .expect("cancel hydration")
        {
            ClientSyncIngress::CancelHydration(cancel) => {
                assert_eq!(cancel.client_id, ClientId("client-1".to_owned()));
                assert_eq!(
                    cancel.client_command_id,
                    ClientCommandId("attach-1".to_owned())
                );
            }
            _ => panic!("unexpected client-sync ingress"),
        }

        match timeout(Duration::from_millis(100), events_rx.recv())
            .await
            .expect("detach arrives")
            .expect("detach")
        {
            EventIngress::Control(EventControlMessage::DetachClient(detach)) => {
                assert_eq!(detach.client_id, ClientId("client-1".to_owned()));
                assert_eq!(
                    detach.client_command_id,
                    ClientCommandId("attach-1".to_owned())
                );
                assert_eq!(detach.reason, DetachReason::ClientDisconnected);
            }
            _ => panic!("unexpected events ingress"),
        }
    }

    #[tokio::test]
    async fn full_events_mailbox_delays_active_attach_release_until_detach_is_queued() {
        let router_tx = accepting_router_sender();
        let (client_sync_tx, mut client_sync_rx) = mpsc::channel(4);
        let (events_tx, mut events_rx) = mpsc::channel(1);
        events_tx
            .try_send(EventIngress::Control(EventControlMessage::DetachClient(
                DetachClient {
                    client_id: ClientId("occupied-client".to_owned()),
                    client_command_id: ClientCommandId("occupied-attach".to_owned()),
                    reason: DetachReason::ClientRequested,
                },
            )))
            .expect("fill events mailbox");
        let control = test_control(router_tx, client_sync_tx, events_tx);

        let (_accepted, stream) = control
            .attach_client(test_attach_request())
            .await
            .expect("attach accepted");
        let _ = timeout(Duration::from_millis(100), client_sync_rx.recv())
            .await
            .expect("start hydration arrives")
            .expect("start hydration");
        let drop_thread = std::thread::spawn(move || drop(stream));
        tokio::time::sleep(Duration::from_millis(10)).await;

        let rejected = match control.attach_client(test_attach_request()).await {
            Ok(_) => panic!("attach should remain active until detach is queued"),
            Err(rejected) => rejected,
        };
        assert_eq!(rejected.reason, AttachRejectReason::DuplicateAttach);

        let _ = events_rx.recv().await.expect("drain occupied events slot");
        drop_thread.join().expect("drop thread completes");
        match timeout(Duration::from_millis(100), events_rx.recv())
            .await
            .expect("client detach arrives")
            .expect("client detach")
        {
            EventIngress::Control(EventControlMessage::DetachClient(detach)) => {
                assert_eq!(detach.client_id, ClientId("client-1".to_owned()));
                assert_eq!(
                    detach.client_command_id,
                    ClientCommandId("attach-1".to_owned())
                );
                assert_eq!(detach.reason, DetachReason::ClientDisconnected);
            }
            _ => panic!("unexpected events ingress"),
        }

        timeout(Duration::from_millis(100), async {
            loop {
                if control
                    .inner
                    .active_attaches
                    .lock()
                    .expect("active attach registry")
                    .is_empty()
                {
                    break;
                }
                tokio::task::yield_now().await;
            }
        })
        .await
        .expect("active attach clears after detach is queued");

        let (_accepted, _stream) = control
            .attach_client(test_attach_request())
            .await
            .expect("attach accepted after detach queued");
    }

    fn accepting_router_sender() -> RouterIngressSender {
        let (router_tx, mut router_rx) = mpsc::unbounded_channel();
        tokio::spawn(async move {
            while let Some(message) = router_rx.recv().await {
                match message {
                    RouterIngressMessage::Command(RouterCommandEnvelope {
                        command: RouterCommand::AttachClient { admission_tx, .. },
                        ..
                    }) => {
                        let _ = admission_tx.send(RouterAttachAdmissionResult::Accepted);
                    }
                    RouterIngressMessage::StopRouter => break,
                    _ => {}
                }
            }
        });
        router_tx
    }

    fn events_closed_router_sender() -> RouterIngressSender {
        let (router_tx, mut router_rx) = mpsc::unbounded_channel();
        tokio::spawn(async move {
            while let Some(message) = router_rx.recv().await {
                match message {
                    RouterIngressMessage::Command(RouterCommandEnvelope {
                        command: RouterCommand::AttachClient { admission_tx, .. },
                        ..
                    }) => {
                        let _ = admission_tx.send(RouterAttachAdmissionResult::EventsMailboxClosed);
                    }
                    RouterIngressMessage::StopRouter => break,
                    _ => {}
                }
            }
        });
        router_tx
    }

    fn test_control(
        router_tx: RouterIngressSender,
        client_sync_tx: selvedge_client_sync::ClientSyncSender,
        events_tx: EventIngressSender,
    ) -> ServerControl {
        test_control_with_frame_channel_factory(
            router_tx,
            client_sync_tx,
            events_tx,
            Arc::new(TokioAttachFrameChannelFactory),
        )
    }

    fn test_control_with_frame_channel_factory(
        router_tx: RouterIngressSender,
        client_sync_tx: selvedge_client_sync::ClientSyncSender,
        events_tx: EventIngressSender,
        frame_channel_factory: Arc<dyn AttachFrameChannelFactory>,
    ) -> ServerControl {
        ServerControl {
            inner: Arc::new(ServerInner {
                state: RwLock::new(ServerRuntimeState::Ready),
                closing: AtomicBool::new(false),
                request_gate: Mutex::new(()),
                stop_notify: Notify::new(),
                lock_path: std::env::temp_dir().join("selvedge-server-unit-test.lock"),
                _singleton_lock: tempfile::tempfile().expect("temp singleton lock"),
                router_tx,
                events_tx: Mutex::new(Some(events_tx)),
                client_sync_tx: Mutex::new(client_sync_tx),
                active_attaches: Arc::new(StdMutex::new(HashMap::new())),
                frame_channel_factory,
                command_mapper: Arc::new(UnusedMapper),
                web_control: Mutex::new(None),
            }),
        }
    }

    fn test_attach_request() -> AttachRequest {
        test_attach_request_for("client-1", "attach-1")
    }

    fn test_attach_request_for(client_id: &str, client_command_id: &str) -> AttachRequest {
        AttachRequest {
            protocol_version: current_protocol_version(),
            client_id: selvedge_local_protocol::LocalClientId::new(client_id)
                .expect("valid client id"),
            client_command_id: LocalClientCommandId::new(client_command_id)
                .expect("valid command id"),
            subscription: selvedge_local_protocol::LocalClientSubscription {
                task_scope: LocalTaskScope::AllTasks,
                detail_level: LocalDetailLevel::Summary,
                include_model_call_status: false,
                include_tool_execution_status: false,
                include_debug_notices: false,
            },
        }
    }
}
