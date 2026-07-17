#![doc = include_str!("../README.md")]

mod command;

use std::collections::{HashMap, HashSet};
use std::fmt;
use std::fs::{File, OpenOptions};
use std::future::Future;
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
    CancelHydration, ClientSnapshotBuilder, ClientSyncExitStatus, ClientSyncHandle,
    ClientSyncIngress, ClientSyncStartArgs, SpawnClientSyncError, spawn_client_sync,
};
use selvedge_command_model::{
    BeginClientHydration, ClientCommandId, ClientEvent, ClientFrame, ClientFrameSender, ClientId,
    ClientNotice, ClientNoticeKind, ClientNoticeLevel, ClientSnapshot, ClientSubscription,
    DeliverySeq, DetachClient, DetachReason, DetailLevel, EventControlMessage, EventIngress,
    EventIngressSender, HistoryNodeProjection, HistoryNodeProjectionBody, ModelCallStatusPhase,
    RouterAttachAdmissionResult, RouterCommand, RouterCommandEnvelope, RouterIngressMessage,
    RouterIngressSender, SnapshotMode, SnapshotTaskVersion, TaskParentProjection, TaskProjection,
    TaskProjectionStatus, TaskScope, ToolExecutionStatusPhase,
};
use selvedge_core::TaskRuntimeSpawnDeps;
use selvedge_db::{OpenDbOptions, open_db, register_global_tool};
use selvedge_domain_model::{MessageRole, ReasoningEffort, TaskId};
use selvedge_events::{EventsHandle, EventsStartArgs, SpawnEventsError, spawn_events_task};
use selvedge_harness::{HarnessToolExecutor, tool_manifest};
use selvedge_local_protocol::{
    AttachAccepted, AttachRejectReason, AttachRejected, AttachRequest, CommandOutcome,
    CommandRejectReason, CommandRequest, CommandResponse, LocalClientCommandId, LocalClientEvent,
    LocalClientEventFrame, LocalClientFrame, LocalClientSnapshot, LocalClientSnapshotFrame,
    LocalDebugNoticeEvent, LocalDetailLevel, LocalHistoryAppendedEvent, LocalHistoryNodeProjection,
    LocalHistoryNodeProjectionBody, LocalMessageRole, LocalModelCallStatusEvent,
    LocalModelCallStatusPhase, LocalNotice, LocalNoticeKind, LocalNoticeLevel,
    LocalReasoningEffort, LocalSnapshotMode, LocalSnapshotTaskVersion, LocalTaskChangedEvent,
    LocalTaskParentProjection, LocalTaskProjection, LocalTaskProjectionStatus, LocalTaskScope,
    LocalToolExecutionStatusEvent, LocalToolExecutionStatusPhase, ReadyRequest, ReadyResponse,
    ReadyState, validate_attach_request, validate_command_request, validate_ready_request,
};
use selvedge_router::{RouterExitStatus, RouterHandle, RouterStartArgs, SpawnRouterError};
use selvedge_web::{
    ReservedWebStartArgs, WebBindReservation, WebBridge, WebHandle, WebLocalhostBind,
    WebLocalhostHost, WebStartError, reserve_web_bind, spawn_reserved_web_surface,
};
use tokio::sync::{Mutex, Notify, OwnedSemaphorePermit, RwLock, Semaphore, mpsc, oneshot};
use tokio::task::{JoinError, JoinHandle};

use command::{ClientCommand, ClientCommandDecodeError};

const SQLITE_FILE_NAME: &str = "selvedge.sqlite";
const LOCK_FILE_NAME: &str = "server.lock";
const DEFAULT_EVENTS_INGRESS_CAPACITY: usize = 64;
const DEFAULT_CLIENT_REGISTRY_CAPACITY: usize = 64;
const DEFAULT_HYDRATION_BUFFER_CAPACITY: usize = 256;
const DEFAULT_CLIENT_SYNC_INGRESS_CAPACITY: usize = 64;

type AttachStateRef = Arc<StdMutex<AttachState>>;
type AttachFrameChannelFactoryRef = Arc<dyn AttachFrameChannelFactory>;
type LocalOperationExecutorRef = Arc<dyn LocalOperationExecutor>;
pub type LocalOperationFuture =
    Pin<Box<dyn Future<Output = Result<LocalOperationSuccess, LocalOperationFailure>> + Send>>;
pub type LocalOperationProgressSender = mpsc::UnboundedSender<LocalOperationProgress>;

#[derive(Default)]
struct AttachState {
    active: HashMap<ClientId, ClientCommandId>,
    hydrated: HashSet<(ClientId, ClientCommandId)>,
    closing: HashSet<(ClientId, ClientCommandId)>,
    cancellations: HashMap<(ClientId, ClientCommandId, ClientCommandId), oneshot::Sender<()>>,
}

impl AttachState {
    fn reserve(
        &mut self,
        client_id: &ClientId,
        client_command_id: &ClientCommandId,
    ) -> Result<Option<ClientCommandId>, AttachRejectReason> {
        if self.active.get(client_id) == Some(client_command_id) {
            return Err(AttachRejectReason::DuplicateAttach);
        }
        if !self.active.contains_key(client_id)
            && self.active.len() >= DEFAULT_CLIENT_REGISTRY_CAPACITY
        {
            return Err(AttachRejectReason::ClientRegistryFull);
        }
        Ok(self
            .active
            .insert(client_id.clone(), client_command_id.clone()))
    }

    fn restore(
        &mut self,
        client_id: &ClientId,
        client_command_id: &ClientCommandId,
        previous_attach: Option<ClientCommandId>,
    ) {
        if self.active.get(client_id) != Some(client_command_id) {
            return;
        }
        match previous_attach {
            Some(previous_command_id) => {
                self.active.insert(client_id.clone(), previous_command_id);
            }
            None => {
                self.active.remove(client_id);
            }
        }
    }

    fn register_cancellation(
        &mut self,
        client_id: ClientId,
        attach_command_id: ClientCommandId,
        submit_command_id: ClientCommandId,
        cancel_tx: oneshot::Sender<()>,
    ) -> bool {
        let attach_key = (client_id.clone(), attach_command_id.clone());
        if self.active.get(&client_id) != Some(&attach_command_id)
            || !self.hydrated.contains(&attach_key)
            || self.closing.contains(&attach_key)
        {
            return false;
        }
        if let Some(previous) = self
            .cancellations
            .insert((client_id, attach_command_id, submit_command_id), cancel_tx)
        {
            let _ = previous.send(());
        }
        true
    }

    fn cancel_for_attach(&mut self, client_id: &ClientId, attach_command_id: &ClientCommandId) {
        self.closing
            .insert((client_id.clone(), attach_command_id.clone()));
        let keys = self
            .cancellations
            .keys()
            .filter(|(registered_client_id, registered_attach_command_id, _)| {
                registered_client_id == client_id
                    && registered_attach_command_id == attach_command_id
            })
            .cloned()
            .collect::<Vec<_>>();
        for key in keys {
            if let Some(cancel_tx) = self.cancellations.remove(&key) {
                let _ = cancel_tx.send(());
            }
        }
    }

    fn clear_attach(&mut self, client_id: &ClientId, attach_command_id: &ClientCommandId) {
        if self.active.get(client_id) == Some(attach_command_id) {
            self.active.remove(client_id);
        }
        self.hydrated
            .remove(&(client_id.clone(), attach_command_id.clone()));
        self.closing
            .remove(&(client_id.clone(), attach_command_id.clone()));
    }

    fn clear_cancellation(
        &mut self,
        client_id: &ClientId,
        attach_command_id: &ClientCommandId,
        submit_command_id: &ClientCommandId,
    ) {
        self.cancellations.remove(&(
            client_id.clone(),
            attach_command_id.clone(),
            submit_command_id.clone(),
        ));
    }
}

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
    pub core_spawn_deps: TaskRuntimeSpawnDeps,
    pub snapshot_builder: Arc<dyn ClientSnapshotBuilder>,
    pub local_operation_executor: Arc<dyn LocalOperationExecutor>,
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
    ToolRegistrationFailed(String),
    EventsStartFailed(String),
    ClientSyncStartFailed(String),
    RouterStartFailed(String),
    LocalhostBindFailed(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ServerRequestError {
    NotReady,
    ProtocolValidationFailed,
    RouterMailboxClosed,
    AttachChannelFailed,
    InternalFailure(String),
}

pub trait LocalOperationExecutor: Send + Sync {
    fn execute(
        &self,
        command: LocalOperationCommand,
        progress_tx: LocalOperationProgressSender,
    ) -> LocalOperationFuture;
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LocalOperationCommand {
    LoginChatgpt,
    ListModels,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LocalOperationProgress {
    LoginUserCode {
        verification_url: String,
        user_code: String,
    },
    Diagnostic {
        message_text: String,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LocalOperationSuccess {
    pub message_text: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LocalOperationFailure {
    pub message_text: String,
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

        ReadyResponse { state }
    }

    pub async fn submit_command(&self, request: CommandRequest) -> CommandResponse {
        let client_command_id = request.client_command_id.clone();
        let outcome = self.submit_command_outcome(request).await;

        CommandResponse {
            client_command_id,
            outcome,
        }
    }

    pub async fn attach_client(
        &self,
        request: AttachRequest,
    ) -> Result<(AttachAccepted, ServerFrameStream), AttachRejected> {
        let _request_guard = self.inner.request_gate.lock().await;
        let client_command_id = request.client_command_id.clone();

        let reject = |reason| {
            Err(AttachRejected {
                client_command_id: client_command_id.clone(),
                reason,
            })
        };

        if *self.inner.state.read().await != ServerRuntimeState::Ready {
            return reject(AttachRejectReason::ServerNotReady);
        }

        if validate_attach_request(&request).is_err() {
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
            Arc::clone(&self.inner.attach_state),
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
            {
                let mut attach_state = self
                    .inner
                    .attach_state
                    .lock()
                    .expect("server attach state lock");
                attach_state.cancel_for_attach(&client_id, &previous_command_id);
                attach_state
                    .hydrated
                    .remove(&(client_id.clone(), previous_command_id.clone()));
            }
            send_detach_client_and_cleanup(
                &events_tx,
                client_id.clone(),
                previous_command_id,
                DetachReason::ReplacedByNewHydration,
                Arc::clone(&self.inner.attach_state),
                DetachCleanup::ClearClosing,
            );
        }

        reservation.commit();

        Ok((
            AttachAccepted {
                client_id: request.client_id,
                client_command_id: request.client_command_id,
            },
            Box::pin(ServerAttachFrameStream {
                inner: outbound_rx,
                client_id,
                client_command_id,
                events_tx: events_tx.downgrade(),
                client_sync_tx: client_sync_tx.downgrade(),
                attach_state: Arc::clone(&self.inner.attach_state),
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
            return CommandOutcome::Rejected(CommandRejectReason::MalformedRequest);
        }

        let command = match ClientCommand::try_from(&request) {
            Ok(command) => command,
            Err(ClientCommandDecodeError::MalformedPayload) => {
                return CommandOutcome::Rejected(CommandRejectReason::MalformedRequest);
            }
            Err(ClientCommandDecodeError::UnsupportedCommand) => {
                return CommandOutcome::Rejected(CommandRejectReason::UnsupportedCommand);
            }
        };

        match command {
            ClientCommand::LoginChatgpt => {
                self.submit_local_operation(request, LocalOperationCommand::LoginChatgpt)
                    .await
            }
            ClientCommand::ListModels => {
                self.submit_local_operation(request, LocalOperationCommand::ListModels)
                    .await
            }
        }
    }

    async fn submit_local_operation(
        &self,
        request: CommandRequest,
        operation_command: LocalOperationCommand,
    ) -> CommandOutcome {
        let client_id = ClientId(request.client_id.0);
        let submit_command_id = ClientCommandId(request.client_command_id.0);
        let Some(attach_command_id) = self.inner.active_attach_for_client(&client_id) else {
            return CommandOutcome::Rejected(CommandRejectReason::ClientNotAttached);
        };
        let login_permit = if matches!(&operation_command, LocalOperationCommand::LoginChatgpt) {
            match self.inner.login_gate.clone().try_acquire_owned() {
                Ok(permit) => Some(permit),
                Err(_) => {
                    return CommandOutcome::Rejected(CommandRejectReason::LoginAlreadyRunning);
                }
            }
        } else {
            None
        };
        let Some(events_tx) = self.inner.events_tx.lock().await.as_ref().cloned() else {
            return CommandOutcome::Rejected(CommandRejectReason::InternalFailure);
        };
        let executor = Arc::clone(&self.inner.local_operation_executor);
        let (progress_tx, progress_rx) = mpsc::unbounded_channel();
        let (attach_closed_tx, attach_closed_rx) = oneshot::channel();
        if !self.inner.register_local_operation_cancellation(
            client_id.clone(),
            attach_command_id.clone(),
            submit_command_id.clone(),
            attach_closed_tx,
        ) {
            return CommandOutcome::Rejected(CommandRejectReason::ClientNotAttached);
        }
        let command_name = request.command_name;
        let operation = executor.execute(operation_command, progress_tx);
        let task = tokio::spawn(run_local_operation_task(LocalOperationTask {
            operation,
            progress_rx,
            attach_closed_rx,
            events_tx,
            client_id,
            attach_command_id,
            submit_command_id,
            command_name,
            _login_permit: login_permit,
            attach_state: Arc::clone(&self.inner.attach_state),
        }));
        self.inner.track_local_operation_task(task);

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
        let web_control = self
            .inner
            .web_control
            .lock()
            .expect("server web control lock")
            .clone();
        if let Some(web_control) = web_control {
            web_control.stop().await;
        }
        self.inner.abort_local_operation_tasks();
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
    attach_state: AttachStateRef,
    frame_channel_factory: AttachFrameChannelFactoryRef,
    local_operation_executor: LocalOperationExecutorRef,
    login_gate: Arc<Semaphore>,
    local_operation_tasks: StdMutex<Vec<JoinHandle<()>>>,
    web_control: StdMutex<Option<selvedge_web::WebControl>>,
}

impl ServerInner {
    fn register_local_operation_cancellation(
        &self,
        client_id: ClientId,
        attach_command_id: ClientCommandId,
        submit_command_id: ClientCommandId,
        cancel_tx: oneshot::Sender<()>,
    ) -> bool {
        self.attach_state
            .lock()
            .expect("server attach state lock")
            .register_cancellation(client_id, attach_command_id, submit_command_id, cancel_tx)
    }

    fn track_local_operation_task(&self, task: JoinHandle<()>) {
        let mut tasks = self
            .local_operation_tasks
            .lock()
            .expect("server local operation task lock");
        tasks.retain(|task| !task.is_finished());
        tasks.push(task);
    }

    fn abort_local_operation_tasks(&self) {
        for task in self
            .local_operation_tasks
            .lock()
            .expect("server local operation task lock")
            .drain(..)
        {
            task.abort();
        }
    }

    fn reserve_active_attach(
        &self,
        client_id: &ClientId,
        client_command_id: &ClientCommandId,
    ) -> Result<Option<ClientCommandId>, AttachRejectReason> {
        self.attach_state
            .lock()
            .expect("server attach state lock")
            .reserve(client_id, client_command_id)
    }

    fn active_attach_for_client(&self, client_id: &ClientId) -> Option<ClientCommandId> {
        self.attach_state
            .lock()
            .expect("server attach state lock")
            .active
            .get(client_id)
            .cloned()
    }
}

struct LocalOperationTask {
    operation: LocalOperationFuture,
    progress_rx: mpsc::UnboundedReceiver<LocalOperationProgress>,
    attach_closed_rx: oneshot::Receiver<()>,
    events_tx: EventIngressSender,
    client_id: ClientId,
    attach_command_id: ClientCommandId,
    submit_command_id: ClientCommandId,
    command_name: String,
    _login_permit: Option<OwnedSemaphorePermit>,
    attach_state: AttachStateRef,
}

struct LocalOperationCancellationGuard {
    attach_state: AttachStateRef,
    client_id: ClientId,
    attach_command_id: ClientCommandId,
    submit_command_id: ClientCommandId,
}

impl Drop for LocalOperationCancellationGuard {
    fn drop(&mut self) {
        self.attach_state
            .lock()
            .expect("server attach state lock")
            .clear_cancellation(
                &self.client_id,
                &self.attach_command_id,
                &self.submit_command_id,
            );
    }
}

async fn run_local_operation_task(task: LocalOperationTask) {
    let LocalOperationTask {
        operation,
        mut progress_rx,
        mut attach_closed_rx,
        events_tx,
        client_id,
        attach_command_id,
        submit_command_id,
        command_name,
        _login_permit,
        attach_state,
    } = task;
    let operation_client_id = client_id.clone();
    let operation_attach_command_id = attach_command_id.clone();
    let operation_submit_command_id = submit_command_id.clone();
    let operation_command_name = command_name.clone();
    let operation_events_tx = events_tx.clone();
    let _cancellation = LocalOperationCancellationGuard {
        attach_state,
        client_id: operation_client_id.clone(),
        attach_command_id: operation_attach_command_id.clone(),
        submit_command_id: operation_submit_command_id.clone(),
    };

    tokio::pin!(operation);
    let mut progress_open = true;
    loop {
        tokio::select! {
            _ = &mut attach_closed_rx => {
                return;
            }
            progress = progress_rx.recv(), if progress_open => {
                match progress {
                    Some(progress) => {
                        let notice = local_operation_progress_notice(progress, submit_command_id.clone());
                        let send_result = tokio::select! {
                            result = send_local_operation_notice(&events_tx, &client_id, &attach_command_id, notice) => result,
                            _ = &mut attach_closed_rx => {
                                return;
                            }
                        };
                        if send_result.is_err() {
                            return;
                        }
                    }
                    None => {
                        progress_open = false;
                    }
                }
            }
            result = &mut operation => {
                let notice = match result {
                    Ok(success) => ClientNotice {
                        level: ClientNoticeLevel::Info,
                        kind: ClientNoticeKind::CommandCompleted {
                            client_command_id: operation_submit_command_id.clone(),
                            command_name: operation_command_name,
                        },
                        message_text: success.message_text,
                    },
                    Err(failure) => ClientNotice {
                        level: ClientNoticeLevel::Error,
                        kind: ClientNoticeKind::CommandFailed {
                            client_command_id: operation_submit_command_id.clone(),
                            command_name: operation_command_name,
                        },
                        message_text: failure.message_text,
                    },
                };
                let _terminal_notice_delivery = tokio::select! {
                    result = send_local_operation_notice(
                        &operation_events_tx,
                        &operation_client_id,
                        &operation_attach_command_id,
                        notice,
                    ) => result,
                    _ = &mut attach_closed_rx => {
                        return;
                    }
                };
                return;
            }
        }
    }
}

fn local_operation_progress_notice(
    progress: LocalOperationProgress,
    submit_command_id: ClientCommandId,
) -> ClientNotice {
    match progress {
        LocalOperationProgress::LoginUserCode {
            verification_url,
            user_code,
        } => ClientNotice {
            level: ClientNoticeLevel::Info,
            kind: ClientNoticeKind::LoginUserCode {
                client_command_id: submit_command_id,
                verification_url: verification_url.clone(),
                user_code: user_code.clone(),
            },
            message_text: format!(
                "Open this URL to authenticate ChatGPT:\n{verification_url}\nUser code: {user_code}"
            ),
        },
        LocalOperationProgress::Diagnostic { message_text } => ClientNotice {
            level: ClientNoticeLevel::Info,
            kind: ClientNoticeKind::Diagnostic {
                client_command_id: Some(submit_command_id),
            },
            message_text,
        },
    }
}

async fn send_local_operation_notice(
    events_tx: &EventIngressSender,
    client_id: &ClientId,
    attach_command_id: &ClientCommandId,
    notice: ClientNotice,
) -> Result<(), ()> {
    match events_tx
        .send(EventIngress::Control(EventControlMessage::DeliverNotice(
            selvedge_command_model::DeliverNotice {
                client_id: client_id.clone(),
                client_command_id: attach_command_id.clone(),
                notice,
            },
        )))
        .await
    {
        Ok(()) => Ok(()),
        Err(_) => Err(()),
    }
}

struct ActiveAttachReservation {
    attach_state: AttachStateRef,
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
        attach_state: AttachStateRef,
        client_id: ClientId,
        client_command_id: ClientCommandId,
        previous_attach: Option<ClientCommandId>,
        events_tx: Option<EventIngressSender>,
    ) -> Self {
        Self {
            attach_state,
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
        self.attach_state
            .lock()
            .expect("server attach state lock")
            .restore(
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
                send_detach_client_and_cleanup(
                    events_tx,
                    self.client_id.clone(),
                    self.client_command_id.clone(),
                    DetachReason::ClientDisconnected,
                    Arc::clone(&self.attach_state),
                    DetachCleanup::Restore(self.previous_attach.clone()),
                );
            } else {
                self.attach_state
                    .lock()
                    .expect("server attach state lock")
                    .restore(
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
    for tool in tool_manifest().tools {
        if let Err(error) = register_global_tool(&db, tool) {
            cleanup_startup_lock(&home);
            return Err(ServerStartupError::ToolRegistrationFailed(
                error.to_string(),
            ));
        }
    }

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
        db: db.clone(),
        events_tx: events.ingress_tx.clone(),
        api_config: args.api_config,
        tool_executor: Arc::new(HarnessToolExecutor::new(db)),
        core_spawn_deps: args.core_spawn_deps,
    }) {
        Ok(router) => router,
        Err(error) => {
            cleanup_startup_lock(&home);
            return Err(map_router_start_error(error));
        }
    };
    if router
        .ingress_tx
        .send(RouterIngressMessage::Command(RouterCommandEnvelope {
            client_id: None,
            client_command_id: None,
            command: RouterCommand::EnsureMissingTaskRuntimes,
        }))
        .is_err()
    {
        cleanup_startup_lock(&home);
        return Err(ServerStartupError::RouterStartFailed(
            "router closed before active runtime recovery".to_owned(),
        ));
    }

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
        attach_state: Arc::new(StdMutex::new(AttachState::default())),
        frame_channel_factory: Arc::new(TokioAttachFrameChannelFactory),
        local_operation_executor: args.local_operation_executor,
        login_gate: Arc::new(Semaphore::new(1)),
        local_operation_tasks: StdMutex::new(Vec::new()),
        web_control: StdMutex::new(None),
    });
    let web = match start_web(
        web_bind,
        ServerControl {
            inner: inner.clone(),
        },
    ) {
        Ok(web) => web,
        Err(error) => {
            cleanup_startup_lock(&home);
            return Err(error);
        }
    };
    *inner.web_control.lock().expect("server web control lock") =
        web.as_ref().map(|handle| handle.control.clone());
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
        let router_tx = router.ingress_tx;
        let mut router_join = Some(router.join_handle);
        let mut events_join = Some(events.join_handle);
        let mut client_sync_join = Some(client_sync.join_handle);
        let client_sync_tx = client_sync.ingress_tx;
        let (web_control, mut web_join) = web
            .map(|handle| (Some(handle.control), Some(handle.join_handle)))
            .unwrap_or((None, None));

        let first_worker_exit = tokio::select! {
            _ = wait_for_server_stop(inner.clone()) => None,
            result = wait_for_join(&mut router_join) => {
                router_join = None;
                Some(ServerWorkerExit::Router(result))
            },
            result = wait_for_join(&mut events_join) => {
                events_join = None;
                Some(ServerWorkerExit::Events(result))
            },
            result = wait_for_join(&mut client_sync_join) => {
                client_sync_join = None;
                Some(ServerWorkerExit::ClientSync(result))
            },
            result = wait_for_join(&mut web_join) => {
                web_join = None;
                Some(ServerWorkerExit::Web(result))
            },
        };

        let first_worker_expected_shutdown = inner.closing.load(Ordering::SeqCst);
        if first_worker_exit.is_some() && !first_worker_expected_shutdown {
            begin_supervised_shutdown(&inner, &router_tx, &client_sync_tx, web_control.as_ref())
                .await;
        }

        let status = collect_server_exit_status(
            first_worker_exit,
            first_worker_expected_shutdown,
            router_join,
            events_join,
            client_sync_join,
            web_join,
            events.ingress_tx,
        )
        .await;

        let _ = std::fs::remove_file(&inner.lock_path);
        *inner.state.write().await = match status {
            ServerExitStatus::Stopped => ServerRuntimeState::Stopped,
            ServerExitStatus::StartupFailed(_)
            | ServerExitStatus::RouterStopped
            | ServerExitStatus::Fatal(_) => ServerRuntimeState::Failed,
        };
        status
    })
}

enum ServerWorkerExit {
    Router(Result<RouterExitStatus, JoinError>),
    Events(Result<(), JoinError>),
    ClientSync(Result<ClientSyncExitStatus, JoinError>),
    Web(Result<selvedge_web::WebExitStatus, JoinError>),
}

async fn wait_for_server_stop(inner: Arc<ServerInner>) {
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
}

async fn wait_for_join<T>(join_handle: &mut Option<JoinHandle<T>>) -> Result<T, JoinError> {
    match join_handle.as_mut() {
        Some(join_handle) => join_handle.await,
        None => std::future::pending().await,
    }
}

async fn begin_supervised_shutdown(
    inner: &ServerInner,
    router_tx: &RouterIngressSender,
    client_sync_tx: &selvedge_client_sync::ClientSyncSender,
    web_control: Option<&selvedge_web::WebControl>,
) {
    if inner.closing.swap(true, Ordering::SeqCst) {
        return;
    }

    *inner.state.write().await = ServerRuntimeState::Closing;
    let _ = router_tx.send(RouterIngressMessage::StopRouter);
    let _ = client_sync_tx.send(ClientSyncIngress::Shutdown).await;
    if let Some(web_control) = web_control {
        web_control.stop().await;
    }
    inner.abort_local_operation_tasks();
    let _ = inner.events_tx.lock().await.take();
    inner.stop_notify.notify_waiters();
}

async fn collect_server_exit_status(
    first_worker_exit: Option<ServerWorkerExit>,
    first_worker_expected_shutdown: bool,
    router_join: Option<JoinHandle<RouterExitStatus>>,
    events_join: Option<JoinHandle<()>>,
    client_sync_join: Option<JoinHandle<ClientSyncExitStatus>>,
    web_join: Option<JoinHandle<selvedge_web::WebExitStatus>>,
    events_tx: EventIngressSender,
) -> ServerExitStatus {
    let mut status = first_worker_exit
        .map(|exit| server_worker_exit_status(exit, first_worker_expected_shutdown))
        .unwrap_or(ServerExitStatus::Stopped);

    let router_status = match router_join {
        Some(join_handle) => router_join_status(join_handle.await, true),
        None => ServerExitStatus::Stopped,
    };
    status = merge_server_exit_status(status, router_status);

    drop(events_tx);

    let events_status = match events_join {
        Some(join_handle) => events_join_status(join_handle.await, true),
        None => ServerExitStatus::Stopped,
    };
    status = merge_server_exit_status(status, events_status);

    let client_sync_status = match client_sync_join {
        Some(join_handle) => client_sync_join_status(join_handle.await, true),
        None => ServerExitStatus::Stopped,
    };
    status = merge_server_exit_status(status, client_sync_status);

    let web_status = match web_join {
        Some(join_handle) => web_join_status(join_handle.await, true),
        None => ServerExitStatus::Stopped,
    };
    merge_server_exit_status(status, web_status)
}

fn server_worker_exit_status(exit: ServerWorkerExit, expected_shutdown: bool) -> ServerExitStatus {
    match exit {
        ServerWorkerExit::Router(result) => router_join_status(result, expected_shutdown),
        ServerWorkerExit::Events(result) => events_join_status(result, expected_shutdown),
        ServerWorkerExit::ClientSync(result) => client_sync_join_status(result, expected_shutdown),
        ServerWorkerExit::Web(result) => web_join_status(result, expected_shutdown),
    }
}

fn router_join_status(
    result: Result<RouterExitStatus, JoinError>,
    expected_shutdown: bool,
) -> ServerExitStatus {
    match result {
        Ok(RouterExitStatus::Stopped) if expected_shutdown => ServerExitStatus::Stopped,
        Ok(RouterExitStatus::Stopped | RouterExitStatus::RouterMailboxClosed) => {
            ServerExitStatus::RouterStopped
        }
        Ok(RouterExitStatus::EventsMailboxClosed) => {
            ServerExitStatus::Fatal("router events mailbox closed".to_owned())
        }
        Ok(RouterExitStatus::FatalError(message)) => ServerExitStatus::Fatal(message),
        Err(error) => ServerExitStatus::Fatal(format!("router task join failed: {error}")),
    }
}

fn events_join_status(result: Result<(), JoinError>, expected_shutdown: bool) -> ServerExitStatus {
    match result {
        Ok(()) if expected_shutdown => ServerExitStatus::Stopped,
        Ok(()) => ServerExitStatus::Fatal("events task exited unexpectedly".to_owned()),
        Err(error) => ServerExitStatus::Fatal(format!("events task join failed: {error}")),
    }
}

fn client_sync_join_status(
    result: Result<ClientSyncExitStatus, JoinError>,
    expected_shutdown: bool,
) -> ServerExitStatus {
    match result {
        Ok(ClientSyncExitStatus::Stopped) if expected_shutdown => ServerExitStatus::Stopped,
        Ok(ClientSyncExitStatus::Stopped) => {
            ServerExitStatus::Fatal("client-sync task exited unexpectedly".to_owned())
        }
        Ok(ClientSyncExitStatus::IngressClosed) => {
            ServerExitStatus::Fatal("client-sync ingress closed".to_owned())
        }
        Ok(ClientSyncExitStatus::Fatal(message)) => ServerExitStatus::Fatal(message),
        Err(error) => ServerExitStatus::Fatal(format!("client-sync task join failed: {error}")),
    }
}

fn web_join_status(
    result: Result<selvedge_web::WebExitStatus, JoinError>,
    expected_shutdown: bool,
) -> ServerExitStatus {
    match result {
        Ok(selvedge_web::WebExitStatus::Stopped) if expected_shutdown => ServerExitStatus::Stopped,
        Ok(selvedge_web::WebExitStatus::Stopped) => {
            ServerExitStatus::Fatal("web task exited unexpectedly".to_owned())
        }
        Ok(selvedge_web::WebExitStatus::Fatal(message)) => ServerExitStatus::Fatal(message),
        Err(error) => ServerExitStatus::Fatal(format!("web task join failed: {error}")),
    }
}

fn merge_server_exit_status(current: ServerExitStatus, next: ServerExitStatus) -> ServerExitStatus {
    match (current, next) {
        (ServerExitStatus::Fatal(message), _) | (_, ServerExitStatus::Fatal(message)) => {
            ServerExitStatus::Fatal(message)
        }
        (ServerExitStatus::RouterStopped, _) | (_, ServerExitStatus::RouterStopped) => {
            ServerExitStatus::RouterStopped
        }
        (ServerExitStatus::StartupFailed(error), _)
        | (_, ServerExitStatus::StartupFailed(error)) => ServerExitStatus::StartupFailed(error),
        (ServerExitStatus::Stopped, ServerExitStatus::Stopped) => ServerExitStatus::Stopped,
    }
}

struct ServerAttachFrameStream {
    inner: mpsc::Receiver<ClientFrame>,
    client_id: ClientId,
    client_command_id: ClientCommandId,
    // NOTE: Weak sender lets server shutdown close events while callers still hold frame streams;
    // Drop upgrades it only to report client detach.
    events_tx: mpsc::WeakSender<EventIngress>,
    client_sync_tx: mpsc::WeakSender<ClientSyncIngress>,
    attach_state: AttachStateRef,
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
            Poll::Ready(Some(frame)) => {
                if matches!(
                    &frame,
                    ClientFrame::Snapshot(snapshot)
                        if snapshot.client_command_id == this.client_command_id
                ) {
                    this.attach_state
                        .lock()
                        .expect("server attach state lock")
                        .hydrated
                        .insert((this.client_id.clone(), this.client_command_id.clone()));
                }
                Poll::Ready(Some(Ok(client_frame_to_local(frame))))
            }
            Poll::Ready(None) => {
                let client_id = this.client_id.clone();
                let client_command_id = this.client_command_id.clone();
                if let Some(client_sync_tx) = this.client_sync_tx.upgrade() {
                    send_cancel_hydration(
                        &client_sync_tx,
                        client_id.clone(),
                        client_command_id.clone(),
                    );
                }
                this.attach_state
                    .lock()
                    .expect("server attach state lock")
                    .cancel_for_attach(&client_id, &client_command_id);
                if let Some(events_tx) = this.events_tx.upgrade() {
                    send_detach_client_and_cleanup(
                        &events_tx,
                        client_id,
                        client_command_id,
                        DetachReason::ClientDisconnected,
                        Arc::clone(&this.attach_state),
                        DetachCleanup::ClearAttach,
                    );
                } else {
                    this.attach_state
                        .lock()
                        .expect("server attach state lock")
                        .clear_attach(&client_id, &client_command_id);
                }
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

        self.attach_state
            .lock()
            .expect("server attach state lock")
            .cancel_for_attach(&client_id, &client_command_id);

        let Some(events_tx) = self.events_tx.upgrade() else {
            self.attach_state
                .lock()
                .expect("server attach state lock")
                .clear_attach(&client_id, &client_command_id);
            return;
        };
        send_detach_client_and_cleanup(
            &events_tx,
            client_id,
            client_command_id,
            DetachReason::ClientDisconnected,
            Arc::clone(&self.attach_state),
            DetachCleanup::ClearAttach,
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

enum DetachCleanup {
    ClearClosing,
    Restore(Option<ClientCommandId>),
    ClearAttach,
}

impl DetachCleanup {
    fn apply(
        self,
        attach_state: &AttachStateRef,
        client_id: &ClientId,
        client_command_id: &ClientCommandId,
    ) {
        let mut state = attach_state.lock().expect("server attach state lock");
        match self {
            Self::ClearClosing => {
                state
                    .closing
                    .remove(&(client_id.clone(), client_command_id.clone()));
            }
            Self::Restore(previous_attach) => {
                state.restore(client_id, client_command_id, previous_attach);
            }
            Self::ClearAttach => state.clear_attach(client_id, client_command_id),
        }
    }
}

fn send_detach_client_and_cleanup(
    events_tx: &EventIngressSender,
    client_id: ClientId,
    client_command_id: ClientCommandId,
    reason: DetachReason,
    attach_state: AttachStateRef,
    cleanup: DetachCleanup,
) {
    let retry_events_tx = events_tx.clone();
    let detach = EventIngress::Control(EventControlMessage::DetachClient(DetachClient {
        client_id: client_id.clone(),
        client_command_id: client_command_id.clone(),
        reason,
    }));

    match events_tx.try_send(detach) {
        Ok(()) | Err(tokio::sync::mpsc::error::TrySendError::Closed(_)) => {
            cleanup.apply(&attach_state, &client_id, &client_command_id);
        }
        Err(tokio::sync::mpsc::error::TrySendError::Full(detach)) => {
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                handle.spawn(async move {
                    let _ = retry_events_tx.send(detach).await;
                    cleanup.apply(&attach_state, &client_id, &client_command_id);
                });
            } else {
                let _ = retry_events_tx.blocking_send(detach);
                cleanup.apply(&attach_state, &client_id, &client_command_id);
            }
        }
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
        snapshot_mode: match subscription.snapshot_mode {
            LocalSnapshotMode::CurrentState => SnapshotMode::CurrentState,
            LocalSnapshotMode::Empty => SnapshotMode::Empty,
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
            arguments,
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
        kind: client_notice_kind_to_local(notice.kind),
        message_text: notice.message_text,
    }
}

fn client_notice_kind_to_local(kind: ClientNoticeKind) -> LocalNoticeKind {
    match kind {
        ClientNoticeKind::Text => LocalNoticeKind::Text,
        ClientNoticeKind::LoginUserCode {
            client_command_id,
            verification_url,
            user_code,
        } => LocalNoticeKind::LoginUserCode {
            client_command_id: LocalClientCommandId(client_command_id.0),
            verification_url,
            user_code,
        },
        ClientNoticeKind::CommandCompleted {
            client_command_id,
            command_name,
        } => LocalNoticeKind::CommandCompleted {
            client_command_id: LocalClientCommandId(client_command_id.0),
            command_name,
        },
        ClientNoticeKind::CommandFailed {
            client_command_id,
            command_name,
        } => LocalNoticeKind::CommandFailed {
            client_command_id: LocalClientCommandId(client_command_id.0),
            command_name,
        },
        ClientNoticeKind::Diagnostic { client_command_id } => LocalNoticeKind::Diagnostic {
            client_command_id: client_command_id.map(|id| LocalClientCommandId(id.0)),
        },
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

fn start_web(
    web_bind: Option<WebBindReservation>,
    control: ServerControl,
) -> Result<Option<WebHandle>, ServerStartupError> {
    let Some(bind) = web_bind else {
        return Ok(None);
    };

    let bridge = Arc::new(ServerWebBridge { control });
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
            control
                .attach_client(request)
                .await
                .map(|(accepted, stream)| {
                    (
                        accepted,
                        Box::pin(ServerWebFrameStream { inner: stream })
                            as selvedge_web::WebFrameStream,
                    )
                })
                .map_err(selvedge_web::AttachRejectedOrBridgeError::Rejected)
        })
    }
}

struct ServerWebFrameStream {
    inner: ServerFrameStream,
}

impl Stream for ServerWebFrameStream {
    type Item = Result<LocalClientFrame, selvedge_web::WebBridgeError>;

    fn poll_next(self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let this = self.get_mut();
        this.inner
            .as_mut()
            .poll_next(context)
            .map(|item| item.map(|frame| frame.map_err(server_request_error_to_web_bridge_error)))
    }
}

fn server_request_error_to_web_bridge_error(
    error: ServerRequestError,
) -> selvedge_web::WebBridgeError {
    match error {
        ServerRequestError::NotReady => selvedge_web::WebBridgeError::ServerNotReady,
        ServerRequestError::ProtocolValidationFailed => {
            selvedge_web::WebBridgeError::ProtocolValidationFailed
        }
        ServerRequestError::RouterMailboxClosed => selvedge_web::WebBridgeError::ServerNotReady,
        ServerRequestError::AttachChannelFailed => {
            selvedge_web::WebBridgeError::AttachRejected("attach channel failed".to_owned())
        }
        ServerRequestError::InternalFailure(message) => {
            selvedge_web::WebBridgeError::InternalFailure(message)
        }
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
        Err(selvedge_config::ConfigError::AlreadyInitialized) => {
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
        Err(selvedge_logging::InitError::AlreadyInitialized) => Ok(()),
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
    use selvedge_command_model::ClientSnapshotFrame;
    use selvedge_domain_model::{FunctionCallId, ToolName, UnixTs};
    use std::time::Duration;
    use tokio::sync::oneshot;
    use tokio::time::timeout;

    struct NoopLocalOperationExecutor;

    impl LocalOperationExecutor for NoopLocalOperationExecutor {
        fn execute(
            &self,
            _command: LocalOperationCommand,
            _progress_tx: LocalOperationProgressSender,
        ) -> LocalOperationFuture {
            Box::pin(async {
                Ok(LocalOperationSuccess {
                    message_text: "noop".to_owned(),
                })
            })
        }
    }

    #[test]
    fn function_call_projection_preserves_nested_json_arguments() {
        let serde_json::Value::Object(arguments) = serde_json::json!({
            "large_integer": 9_007_199_254_740_993_u64,
            "nested": {
                "nullable": null,
                "choices": ["fast", {"retries": 3}]
            }
        }) else {
            panic!("test arguments must be an object");
        };

        let projected = history_node_body_to_local(HistoryNodeProjectionBody::FunctionCall {
            function_call_id: FunctionCallId("call-1".to_owned()),
            tool_name: ToolName("nested_tool".to_owned()),
            arguments: arguments.clone(),
        });

        assert_eq!(
            projected,
            LocalHistoryNodeProjectionBody::FunctionCall {
                function_call_id: "call-1".to_owned(),
                tool_name: "nested_tool".to_owned(),
                arguments,
            }
        );
    }

    struct PendingLocalOperationExecutor;

    impl LocalOperationExecutor for PendingLocalOperationExecutor {
        fn execute(
            &self,
            _command: LocalOperationCommand,
            _progress_tx: LocalOperationProgressSender,
        ) -> LocalOperationFuture {
            Box::pin(std::future::pending())
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
    async fn login_command_requires_active_attach() {
        let (router_tx, _router_rx) = mpsc::unbounded_channel();
        let (client_sync_tx, _client_sync_rx) = mpsc::channel(1);
        let (events_tx, _events_rx) = mpsc::channel(8);
        let control = test_control(router_tx, client_sync_tx, events_tx);

        let response = control.submit_command(login_command("command-1")).await;

        assert_eq!(
            response.outcome,
            CommandOutcome::Rejected(CommandRejectReason::ClientNotAttached)
        );
    }

    #[tokio::test]
    async fn login_command_runs_as_local_operation_without_router_command() {
        let (router_tx, mut router_rx) = mpsc::unbounded_channel();
        let (client_sync_tx, _client_sync_rx) = mpsc::channel(1);
        let (events_tx, mut events_rx) = mpsc::channel(8);
        let control = test_control(router_tx, client_sync_tx, events_tx);
        activate_attach(&control, "client-1", "attach-1");

        let response = control.submit_command(login_command("command-1")).await;

        assert_eq!(response.outcome, CommandOutcome::Accepted);
        assert!(router_rx.try_recv().is_err());
        let notice = timeout(Duration::from_millis(100), events_rx.recv())
            .await
            .expect("terminal notice timeout")
            .expect("terminal notice");
        let EventIngress::Control(EventControlMessage::DeliverNotice(notice)) = notice else {
            panic!("expected terminal notice");
        };
        assert_eq!(
            notice.client_command_id,
            ClientCommandId("attach-1".to_owned())
        );
        assert!(matches!(
            notice.notice.kind,
            ClientNoticeKind::CommandCompleted { .. }
        ));
    }

    #[tokio::test]
    async fn concurrent_login_command_is_rejected() {
        let (router_tx, _router_rx) = mpsc::unbounded_channel();
        let (client_sync_tx, _client_sync_rx) = mpsc::channel(1);
        let (events_tx, _events_rx) = mpsc::channel(8);
        let control = test_control_with_frame_channel_factory_and_executor(
            router_tx,
            client_sync_tx,
            events_tx,
            Arc::new(TokioAttachFrameChannelFactory),
            Arc::new(PendingLocalOperationExecutor),
        );
        activate_attach(&control, "client-1", "attach-1");

        let first = control.submit_command(login_command("command-1")).await;
        let second = control.submit_command(login_command("command-2")).await;

        assert_eq!(first.outcome, CommandOutcome::Accepted);
        assert_eq!(
            second.outcome,
            CommandOutcome::Rejected(CommandRejectReason::LoginAlreadyRunning)
        );
    }

    #[tokio::test]
    async fn list_models_command_is_accepted_while_login_is_running() {
        let (router_tx, _router_rx) = mpsc::unbounded_channel();
        let (client_sync_tx, _client_sync_rx) = mpsc::channel(1);
        let (events_tx, _events_rx) = mpsc::channel(8);
        let control = test_control_with_frame_channel_factory_and_executor(
            router_tx,
            client_sync_tx,
            events_tx,
            Arc::new(TokioAttachFrameChannelFactory),
            Arc::new(PendingLocalOperationExecutor),
        );
        activate_attach(&control, "client-1", "attach-1");
        activate_attach(&control, "client-2", "attach-2");

        let login = control.submit_command(login_command("command-1")).await;
        let list_models = control
            .submit_command(local_operation_command(
                "client-2",
                "command-2",
                "list-models",
            ))
            .await;

        assert_eq!(login.outcome, CommandOutcome::Accepted);
        assert_eq!(list_models.outcome, CommandOutcome::Accepted);
    }

    #[tokio::test]
    async fn local_operations_on_same_attach_keep_separate_cancellation_entries() {
        let (router_tx, _router_rx) = mpsc::unbounded_channel();
        let (client_sync_tx, _client_sync_rx) = mpsc::channel(1);
        let (events_tx, _events_rx) = mpsc::channel(8);
        let control = test_control_with_frame_channel_factory_and_executor(
            router_tx,
            client_sync_tx,
            events_tx,
            Arc::new(TokioAttachFrameChannelFactory),
            Arc::new(PendingLocalOperationExecutor),
        );
        activate_attach(&control, "client-1", "attach-1");

        let login = control.submit_command(login_command("command-1")).await;
        let list_models = control
            .submit_command(local_operation_command(
                "client-1",
                "command-2",
                "list-models",
            ))
            .await;

        assert_eq!(login.outcome, CommandOutcome::Accepted);
        assert_eq!(list_models.outcome, CommandOutcome::Accepted);
        assert_eq!(
            control
                .inner
                .attach_state
                .lock()
                .expect("attach state")
                .cancellations
                .len(),
            2
        );
    }

    #[tokio::test]
    async fn local_operation_cancellation_registration_requires_active_attach() {
        let control = test_control(
            accepting_router_sender(),
            mpsc::channel(1).0,
            mpsc::channel(1).0,
        );
        let (cancel_tx, _cancel_rx) = oneshot::channel();

        let registered = control.inner.register_local_operation_cancellation(
            ClientId("client-1".to_owned()),
            ClientCommandId("attach-1".to_owned()),
            ClientCommandId("command-1".to_owned()),
            cancel_tx,
        );

        assert!(!registered);
        assert!(
            control
                .inner
                .attach_state
                .lock()
                .expect("attach state")
                .cancellations
                .is_empty()
        );
    }

    #[tokio::test]
    async fn local_operation_submission_requires_hydrated_attach() {
        let (router_tx, _router_rx) = mpsc::unbounded_channel();
        let (client_sync_tx, _client_sync_rx) = mpsc::channel(1);
        let (events_tx, _events_rx) = mpsc::channel(8);
        let control = test_control(router_tx, client_sync_tx, events_tx);
        activate_unhydrated_attach(&control, "client-1", "attach-1");

        let response = control
            .submit_command(local_operation_command(
                "client-1",
                "command-1",
                "list-models",
            ))
            .await;

        assert_eq!(
            response.outcome,
            CommandOutcome::Rejected(CommandRejectReason::ClientNotAttached)
        );
        assert!(
            control
                .inner
                .attach_state
                .lock()
                .expect("attach state")
                .cancellations
                .is_empty()
        );
    }

    #[tokio::test]
    async fn replacement_attach_clears_previous_hydration_before_command_id_reuse() {
        let router_tx = accepting_router_sender();
        let (client_sync_tx, _client_sync_rx) = mpsc::channel(4);
        let (events_tx, _events_rx) = mpsc::channel(4);
        let control = test_control(router_tx, client_sync_tx, events_tx);
        activate_attach(&control, "client-1", "attach-1");

        let (_accepted, _stream) = control
            .attach_client(test_attach_request_for("client-1", "attach-2"))
            .await
            .expect("replacement attach accepted");
        let (_accepted, _stream) = control
            .attach_client(test_attach_request_for("client-1", "attach-1"))
            .await
            .expect("command id reuse attach accepted");
        let response = control.submit_command(login_command("command-1")).await;

        assert_eq!(
            response.outcome,
            CommandOutcome::Rejected(CommandRejectReason::ClientNotAttached)
        );
    }

    #[tokio::test]
    async fn local_operation_cancellation_registration_rejects_closing_attach() {
        let control = test_control(
            accepting_router_sender(),
            mpsc::channel(1).0,
            mpsc::channel(1).0,
        );
        activate_attach(&control, "client-1", "attach-1");
        control
            .inner
            .attach_state
            .lock()
            .expect("attach state")
            .closing
            .insert((
                ClientId("client-1".to_owned()),
                ClientCommandId("attach-1".to_owned()),
            ));
        let (cancel_tx, _cancel_rx) = oneshot::channel();

        let registered = control.inner.register_local_operation_cancellation(
            ClientId("client-1".to_owned()),
            ClientCommandId("attach-1".to_owned()),
            ClientCommandId("command-1".to_owned()),
            cancel_tx,
        );

        assert!(!registered);
        assert!(
            control
                .inner
                .attach_state
                .lock()
                .expect("attach state")
                .cancellations
                .is_empty()
        );
    }

    #[tokio::test]
    async fn dropped_login_attach_releases_single_flight_gate() {
        let router_tx = accepting_router_sender();
        let (client_sync_tx, _client_sync_rx) = mpsc::channel(4);
        let (events_tx, _events_rx) = mpsc::channel(8);
        let control = test_control_with_frame_channel_factory_and_executor(
            router_tx,
            client_sync_tx,
            events_tx,
            Arc::new(TokioAttachFrameChannelFactory),
            Arc::new(PendingLocalOperationExecutor),
        );

        let (_accepted, stream) = control
            .attach_client(test_attach_request())
            .await
            .expect("first attach accepted");
        control
            .inner
            .attach_state
            .lock()
            .expect("attach state")
            .hydrated
            .insert((
                ClientId("client-1".to_owned()),
                ClientCommandId("attach-1".to_owned()),
            ));
        let first = control.submit_command(login_command("command-1")).await;
        drop(stream);
        let (_accepted, _stream) = control
            .attach_client(test_attach_request_for("client-1", "attach-2"))
            .await
            .expect("second attach accepted");
        control
            .inner
            .attach_state
            .lock()
            .expect("attach state")
            .hydrated
            .insert((
                ClientId("client-1".to_owned()),
                ClientCommandId("attach-2".to_owned()),
            ));

        let mut second = control.submit_command(login_command("command-2")).await;
        for _ in 0..20 {
            if second.outcome == CommandOutcome::Accepted {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
            second = control.submit_command(login_command("command-2")).await;
        }

        assert_eq!(first.outcome, CommandOutcome::Accepted);
        assert_eq!(second.outcome, CommandOutcome::Accepted);
    }

    #[tokio::test]
    async fn shutdown_aborts_pending_login_operation() {
        let (router_tx, _router_rx) = mpsc::unbounded_channel();
        let (client_sync_tx, _client_sync_rx) = mpsc::channel(1);
        let (events_tx, _events_rx) = mpsc::channel(8);
        let control = test_control_with_frame_channel_factory_and_executor(
            router_tx,
            client_sync_tx,
            events_tx,
            Arc::new(TokioAttachFrameChannelFactory),
            Arc::new(PendingLocalOperationExecutor),
        );
        activate_attach(&control, "client-1", "attach-1");

        let response = control.submit_command(login_command("command-1")).await;
        control.stop().await;

        assert_eq!(response.outcome, CommandOutcome::Accepted);
        assert!(
            control
                .inner
                .local_operation_tasks
                .lock()
                .expect("local operation tasks")
                .is_empty()
        );
    }

    #[tokio::test]
    async fn server_web_bridge_forwards_commands_to_server_control() {
        let router_tx = accepting_router_sender();
        let (client_sync_tx, _client_sync_rx) = mpsc::channel(1);
        let (events_tx, _events_rx) = mpsc::channel(1);
        let control = test_control(router_tx, client_sync_tx, events_tx);
        activate_attach(&control, "client-1", "attach-1");
        let bridge = ServerWebBridge { control };

        let response = bridge
            .submit_command(login_command("command-1"))
            .await
            .expect("web command forwards");

        assert_eq!(response.outcome, CommandOutcome::Accepted);
    }

    #[tokio::test]
    async fn server_web_bridge_forwards_attach_to_server_control() {
        let router_tx = accepting_router_sender();
        let (client_sync_tx, mut client_sync_rx) = mpsc::channel(1);
        let (events_tx, _events_rx) = mpsc::channel(1);
        let control = test_control(router_tx, client_sync_tx, events_tx);
        let bridge = ServerWebBridge { control };

        let (accepted, _stream) = bridge
            .attach(test_attach_request())
            .await
            .expect("web attach forwards");

        assert_eq!(
            accepted.client_command_id,
            test_attach_request().client_command_id
        );
        match client_sync_rx.recv().await.expect("start hydration") {
            ClientSyncIngress::StartHydration(begin) => {
                assert_eq!(begin.client_id, ClientId("client-1".to_owned()));
                assert_eq!(
                    begin.client_command_id,
                    ClientCommandId("attach-1".to_owned())
                );
            }
            ClientSyncIngress::CancelHydration(_) | ClientSyncIngress::Shutdown => {
                panic!("expected start hydration")
            }
        }
    }

    #[tokio::test]
    async fn server_join_task_reports_unexpected_router_failure() {
        let (router_tx, _router_rx) = mpsc::unbounded_channel();
        let (events_tx, events_rx) = mpsc::channel(1);
        let (client_sync_tx, client_sync_rx) = mpsc::channel(1);
        let control = test_control(router_tx.clone(), client_sync_tx.clone(), events_tx.clone());
        let join_handle = spawn_server_join_task(
            control.inner.clone(),
            RouterHandle {
                ingress_tx: router_tx,
                join_handle: tokio::spawn(async {
                    RouterExitStatus::FatalError("router failed".to_owned())
                }),
            },
            EventsHandle {
                ingress_tx: events_tx,
                join_handle: events_join_for_test(events_rx),
            },
            ClientSyncHandle {
                ingress_tx: client_sync_tx,
                join_handle: client_sync_join_for_test(client_sync_rx),
            },
            None,
        );

        let status = timeout(Duration::from_millis(100), join_handle)
            .await
            .expect("server join returns")
            .expect("server join succeeds");

        assert_eq!(status, ServerExitStatus::Fatal("router failed".to_owned()));
        assert_eq!(control.state().await, ServerRuntimeState::Failed);
    }

    #[tokio::test]
    async fn server_join_task_preserves_router_failure_during_shutdown() {
        let (router_tx, _router_rx) = mpsc::unbounded_channel();
        let (events_tx, events_rx) = mpsc::channel(1);
        let (client_sync_tx, client_sync_rx) = mpsc::channel(1);
        let (release_router_tx, release_router_rx) = oneshot::channel();
        let control = test_control(router_tx.clone(), client_sync_tx.clone(), events_tx.clone());
        let join_handle = spawn_server_join_task(
            control.inner.clone(),
            RouterHandle {
                ingress_tx: router_tx,
                join_handle: tokio::spawn(async {
                    release_router_rx.await.expect("release router");
                    RouterExitStatus::EventsMailboxClosed
                }),
            },
            EventsHandle {
                ingress_tx: events_tx,
                join_handle: events_join_for_test(events_rx),
            },
            ClientSyncHandle {
                ingress_tx: client_sync_tx,
                join_handle: client_sync_join_for_test(client_sync_rx),
            },
            None,
        );

        control.stop().await;
        release_router_tx.send(()).expect("release router");
        let status = timeout(Duration::from_millis(100), join_handle)
            .await
            .expect("server join returns")
            .expect("server join succeeds");

        assert_eq!(
            status,
            ServerExitStatus::Fatal("router events mailbox closed".to_owned())
        );
        assert_eq!(control.state().await, ServerRuntimeState::Failed);
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
        let (events_tx, mut events_rx) = mpsc::channel(4);
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
        match timeout(Duration::from_millis(100), client_sync_rx.recv())
            .await
            .expect("channel close cancel arrives")
            .expect("channel close cancel")
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
            .expect("channel close detach arrives")
            .expect("channel close detach")
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
    async fn attach_snapshot_marks_local_operation_hydration_ready() {
        let (frame_tx, frame_rx) = mpsc::channel(1);
        let (events_tx, _events_rx) = mpsc::channel(1);
        let (client_sync_tx, _client_sync_rx) = mpsc::channel(1);
        let attach_state = Arc::new(StdMutex::new(AttachState::default()));
        let client_id = ClientId("client-1".to_owned());
        let attach_command_id = ClientCommandId("attach-1".to_owned());
        let mut stream = ServerAttachFrameStream {
            inner: frame_rx,
            client_id: client_id.clone(),
            client_command_id: attach_command_id.clone(),
            events_tx: events_tx.downgrade(),
            client_sync_tx: client_sync_tx.downgrade(),
            attach_state: Arc::clone(&attach_state),
            closed_reported: false,
        };

        frame_tx
            .send(ClientFrame::Snapshot(ClientSnapshotFrame {
                delivery_seq: DeliverySeq(1),
                client_command_id: attach_command_id.clone(),
                snapshot: empty_client_snapshot(),
            }))
            .await
            .expect("snapshot sends");
        let frame = stream
            .next()
            .await
            .expect("snapshot frame")
            .expect("frame ok");

        assert!(matches!(frame, LocalClientFrame::Snapshot(_)));
        assert!(
            attach_state
                .lock()
                .expect("attach state")
                .hydrated
                .contains(&(client_id, attach_command_id))
        );
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
                    .attach_state
                    .lock()
                    .expect("attach state")
                    .active
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

    #[tokio::test]
    async fn local_operation_terminal_notice_send_stops_when_attach_closes() {
        let (events_tx, _events_rx) = mpsc::channel(1);
        events_tx
            .try_send(EventIngress::Control(EventControlMessage::DetachClient(
                DetachClient {
                    client_id: ClientId("occupied-client".to_owned()),
                    client_command_id: ClientCommandId("occupied-attach".to_owned()),
                    reason: DetachReason::ClientRequested,
                },
            )))
            .expect("fill events mailbox");
        let (progress_tx, progress_rx) = mpsc::unbounded_channel();
        drop(progress_tx);
        let (attach_closed_tx, attach_closed_rx) = oneshot::channel();
        let attach_state = Arc::new(StdMutex::new(AttachState::default()));
        let client_id = ClientId("client-1".to_owned());
        let attach_command_id = ClientCommandId("attach-1".to_owned());
        let submit_command_id = ClientCommandId("command-1".to_owned());
        let (cancel_tx, _cancel_rx) = oneshot::channel();
        attach_state
            .lock()
            .expect("attach state")
            .cancellations
            .insert(
                (
                    client_id.clone(),
                    attach_command_id.clone(),
                    submit_command_id.clone(),
                ),
                cancel_tx,
            );

        let handle = tokio::spawn(run_local_operation_task(LocalOperationTask {
            operation: Box::pin(async {
                Ok(LocalOperationSuccess {
                    message_text: "done".to_owned(),
                })
            }),
            progress_rx,
            attach_closed_rx,
            events_tx,
            client_id,
            attach_command_id,
            submit_command_id,
            command_name: "login-chatgpt".to_owned(),
            _login_permit: None,
            attach_state: Arc::clone(&attach_state),
        }));
        tokio::time::sleep(Duration::from_millis(10)).await;
        attach_closed_tx
            .send(())
            .expect("attach close signal sends");

        timeout(Duration::from_millis(100), handle)
            .await
            .expect("local operation task exits")
            .expect("local operation task joins");
        assert!(
            attach_state
                .lock()
                .expect("attach state")
                .cancellations
                .is_empty()
        );
    }

    #[tokio::test]
    async fn full_events_mailbox_delays_closing_attach_marker_clear_until_detach_is_queued() {
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
        let attach_state = Arc::new(StdMutex::new(AttachState::default()));
        let client_id = ClientId("client-1".to_owned());
        let attach_command_id = ClientCommandId("attach-1".to_owned());
        {
            let mut state = attach_state.lock().expect("attach state");
            state
                .active
                .insert(client_id.clone(), attach_command_id.clone());
            state
                .hydrated
                .insert((client_id.clone(), attach_command_id.clone()));
            state
                .closing
                .insert((client_id.clone(), attach_command_id.clone()));
        }

        send_detach_client_and_cleanup(
            &events_tx,
            client_id.clone(),
            attach_command_id.clone(),
            DetachReason::ClientDisconnected,
            Arc::clone(&attach_state),
            DetachCleanup::ClearAttach,
        );
        assert!(
            attach_state
                .lock()
                .expect("attach state")
                .closing
                .contains(&(client_id.clone(), attach_command_id.clone()))
        );

        let _ = events_rx.recv().await.expect("drain occupied events slot");
        let detach = timeout(Duration::from_millis(100), events_rx.recv())
            .await
            .expect("client detach arrives")
            .expect("client detach");
        assert!(matches!(
            detach,
            EventIngress::Control(EventControlMessage::DetachClient(_))
        ));
        timeout(Duration::from_millis(100), async {
            loop {
                if attach_state
                    .lock()
                    .expect("attach state")
                    .closing
                    .is_empty()
                {
                    break;
                }
                tokio::task::yield_now().await;
            }
        })
        .await
        .expect("closing attach marker clears after detach is queued");
        assert!(
            attach_state
                .lock()
                .expect("attach state")
                .closing
                .is_empty()
        );
        assert!(attach_state.lock().expect("attach state").active.is_empty());
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
        test_control_with_frame_channel_factory_and_executor(
            router_tx,
            client_sync_tx,
            events_tx,
            frame_channel_factory,
            Arc::new(NoopLocalOperationExecutor),
        )
    }

    fn test_control_with_frame_channel_factory_and_executor(
        router_tx: RouterIngressSender,
        client_sync_tx: selvedge_client_sync::ClientSyncSender,
        events_tx: EventIngressSender,
        frame_channel_factory: Arc<dyn AttachFrameChannelFactory>,
        local_operation_executor: Arc<dyn LocalOperationExecutor>,
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
                attach_state: Arc::new(StdMutex::new(AttachState::default())),
                frame_channel_factory,
                local_operation_executor,
                login_gate: Arc::new(Semaphore::new(1)),
                local_operation_tasks: StdMutex::new(Vec::new()),
                web_control: StdMutex::new(None),
            }),
        }
    }

    fn events_join_for_test(mut events_rx: mpsc::Receiver<EventIngress>) -> JoinHandle<()> {
        tokio::spawn(async move { while events_rx.recv().await.is_some() {} })
    }

    fn client_sync_join_for_test(
        mut client_sync_rx: mpsc::Receiver<ClientSyncIngress>,
    ) -> JoinHandle<ClientSyncExitStatus> {
        tokio::spawn(async move {
            while let Some(message) = client_sync_rx.recv().await {
                if matches!(message, ClientSyncIngress::Shutdown) {
                    return ClientSyncExitStatus::Stopped;
                }
            }
            ClientSyncExitStatus::IngressClosed
        })
    }

    fn login_command(client_command_id: &str) -> CommandRequest {
        local_operation_command("client-1", client_command_id, "login-chatgpt")
    }

    fn local_operation_command(
        client_id: &str,
        client_command_id: &str,
        command_name: &str,
    ) -> CommandRequest {
        CommandRequest {
            client_id: selvedge_local_protocol::LocalClientId::new(client_id)
                .expect("valid client id"),
            client_command_id: LocalClientCommandId::new(client_command_id)
                .expect("valid command id"),
            command_name: command_name.to_owned(),
            payload: serde_json::json!({}),
        }
    }

    fn activate_attach(control: &ServerControl, client_id: &str, client_command_id: &str) {
        let client_id = ClientId(client_id.to_owned());
        let client_command_id = ClientCommandId(client_command_id.to_owned());
        let mut state = control.inner.attach_state.lock().expect("attach state");
        state
            .active
            .insert(client_id.clone(), client_command_id.clone());
        state.hydrated.insert((client_id, client_command_id));
    }

    fn activate_unhydrated_attach(
        control: &ServerControl,
        client_id: &str,
        client_command_id: &str,
    ) {
        control
            .inner
            .attach_state
            .lock()
            .expect("attach state")
            .active
            .insert(
                ClientId(client_id.to_owned()),
                ClientCommandId(client_command_id.to_owned()),
            );
    }

    fn empty_client_snapshot() -> ClientSnapshot {
        ClientSnapshot {
            generated_at: UnixTs(0),
            tasks: Vec::new(),
            task_parent_edges: Vec::new(),
            history_nodes: Vec::new(),
            task_versions: Vec::new(),
        }
    }

    fn test_attach_request() -> AttachRequest {
        test_attach_request_for("client-1", "attach-1")
    }

    fn test_attach_request_for(client_id: &str, client_command_id: &str) -> AttachRequest {
        AttachRequest {
            client_id: selvedge_local_protocol::LocalClientId::new(client_id)
                .expect("valid client id"),
            client_command_id: LocalClientCommandId::new(client_command_id)
                .expect("valid command id"),
            subscription: selvedge_local_protocol::LocalClientSubscription {
                task_scope: LocalTaskScope::AllTasks,
                detail_level: LocalDetailLevel::Summary,
                snapshot_mode: selvedge_local_protocol::LocalSnapshotMode::CurrentState,
                include_model_call_status: false,
                include_tool_execution_status: false,
                include_debug_notices: false,
            },
        }
    }
}
