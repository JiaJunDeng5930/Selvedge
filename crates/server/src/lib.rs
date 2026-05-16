#![doc = include_str!("../README.md")]
//! @behavior selvedge.startup.server The server starts singleton-owned local runtime services and exposes ready, command, attach, stop, and optional web control behavior.
//! @behavior selvedge.startup.server.lifecycle Server processing preserves startup, readiness, command, attach, shutdown, and local protocol conversion behavior.
//! @behavior selvedge.startup.server.startup Server startup prepares configuration, lock, database, events, client-sync, router, and optional web services before returning control.
//! @behavior selvedge.startup.server.startup.config Startup config handling initializes or reuses the selected Selvedge home.
//! @behavior selvedge.startup.server.ready Ready handling reports protocol version and readiness state for local callers.
//! @behavior selvedge.startup.server.lock Server lock handling enforces one active server per Selvedge home and removes the lock file on cleanup.
//! @behavior selvedge.startup.server.local_protocol Local protocol handling exposes ready, command, attach, event conversion, and request error behavior to local clients.
//! @behavior selvedge.startup.server.local_protocol.attach Attach handling admits local clients, starts hydration, streams frames, and cleans up detach state.
//! @behavior selvedge.startup.server.local_protocol.command Command handling validates local requests, maps them to router envelopes, and reports accepted or rejected outcomes.
//! @behavior selvedge.startup.server.local_protocol.event Event conversion maps command-model client frames into local protocol frames.
//! @behavior selvedge.startup.server.client_sync Client-sync handling starts hydration, cancels hydration, and participates in shutdown for attached clients.
//! @behavior selvedge.startup.server.client_sync.start_hydration Attach admission sends StartHydration to client-sync after router admission succeeds.
//! @behavior selvedge.startup.server.event_delivery Event delivery cleanup sends detach notifications for local client attach lifecycles.
//! @behavior selvedge.startup.server.shutdown Shutdown handling stops runtime workers, closes ingress, removes the lock file, and reports final server status.
//! @behavior selvedge.startup.server.shutdown.events_status Events worker exits map into stopped or fatal server exit statuses.
//! @behavior selvedge.startup.server.shutdown.client_sync_status Client-sync worker exits map into stopped or fatal server exit statuses.
//! @behavior selvedge.startup.server.shutdown.web_status Web worker exits map into stopped or fatal server exit statuses.
//! @behavior selvedge.startup.server.web Web handling reserves localhost binding, forwards ready, command, and attach requests, and maps bridge errors.
//! @behavior selvedge.startup.server.web.reserve Web binding reservation validates and reserves the optional localhost web surface before runtime startup.
//! @behavior selvedge.startup.server.web.attach_forward Web attach forwarding returns server attach acceptance or rejection through the web bridge.
//! @behavior selvedge.startup.server.web.frame_stream Web frame streaming forwards local protocol frames and maps server stream errors into web bridge errors.
//! @behavior selvedge.startup.server.web.bind_target Web bind target validation rejects invalid localhost ports before durable startup side effects.
//! @behavior selvedge.startup.server.local_operation Server local operations execute server-owned commands outside the router mailbox and deliver user-visible notices to attached clients.

use std::collections::HashMap;
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
    LocalModelCallStatusPhase, LocalNotice, LocalNoticeKind, LocalNoticeLevel,
    LocalReasoningEffort, LocalSnapshotMode, LocalSnapshotTaskVersion, LocalTaskChangedEvent,
    LocalTaskParentProjection, LocalTaskProjection, LocalTaskProjectionStatus, LocalTaskScope,
    LocalToolArgumentValue, LocalToolCallArgument, LocalToolExecutionStatusEvent,
    LocalToolExecutionStatusPhase, ReadyRequest, ReadyResponse, ReadyState,
    current_protocol_version, validate_attach_request, validate_command_request,
    validate_ready_request,
};
use selvedge_router::{
    RouterExitStatus, RouterHandle, RouterStartArgs, SpawnRouterError, ToolExecutionSpawner,
};
use selvedge_web::{
    ReservedWebStartArgs, WebBindReservation, WebBridge, WebHandle, WebLocalhostBind,
    WebLocalhostHost, WebStartError, reserve_web_bind, spawn_reserved_web_surface,
};
use tokio::sync::{Mutex, Notify, OwnedSemaphorePermit, RwLock, Semaphore, mpsc};
use tokio::task::{JoinError, JoinHandle};

const SQLITE_FILE_NAME: &str = "selvedge.sqlite";
const LOCK_FILE_NAME: &str = "server.lock";
const DEFAULT_EVENTS_INGRESS_CAPACITY: usize = 64;
const DEFAULT_CLIENT_REGISTRY_CAPACITY: usize = 64;
const DEFAULT_HYDRATION_BUFFER_CAPACITY: usize = 256;
const DEFAULT_CLIENT_SYNC_INGRESS_CAPACITY: usize = 64;

type ActiveAttachRegistry = Arc<StdMutex<HashMap<ClientId, ClientCommandId>>>;
// @intent selvedge.startup.server.local_protocol.attach.channel_factory AttachFrameChannelFactoryRef stores the server-owned client frame channel factory boundary for attach admission.
type AttachFrameChannelFactoryRef = Arc<dyn AttachFrameChannelFactory>;
// @intent selvedge.startup.server.local_protocol.command.mapper_ref LocalCommandMapperRef stores the local protocol to router command mapping boundary.
type LocalCommandMapperRef = Arc<dyn LocalCommandMapper>;
// @intent selvedge.startup.server.local_operation.executor_ref LocalOperationExecutorRef stores the server-owned local operation execution boundary.
type LocalOperationExecutorRef = Arc<dyn LocalOperationExecutor>;
// @behavior selvedge.startup.server.local_operation.future Local operation futures resolve to terminal success or terminal failure for server-owned commands.
// @intent selvedge.startup.server.local_operation.future.abstraction LocalOperationFuture abstracts completion of a server-owned local operation.
pub type LocalOperationFuture =
    Pin<Box<dyn Future<Output = Result<LocalOperationSuccess, LocalOperationFailure>> + Send>>;
// @behavior selvedge.startup.server.local_operation.progress_sender Local operation progress senders accept user-code prompts and diagnostics from running operations.
// @intent selvedge.startup.server.local_operation.progress_sender.abstraction LocalOperationProgressSender carries server-owned operation progress into notice delivery.
pub type LocalOperationProgressSender = mpsc::UnboundedSender<LocalOperationProgress>;

// @intent selvedge.startup.server.lifecycle.coordinator The server abstraction owns process-local lifecycle coordination across config, storage, router, events, and web boundaries.
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
        // @behavior selvedge.startup.server.local_protocol.attach.channel_factory.create Attach channel creation returns a sender and receiver used for accepted local client frame streams.
    ) -> Result<(ClientFrameSender, mpsc::Receiver<ClientFrame>), AttachRejectReason> {
        Ok(mpsc::channel(capacity))
    }
}

// @behavior selvedge.startup.server.startup.args Server startup arguments select the home directory, API execution config, runtime spawners, command mapping, local binding, and optional web binding.
pub struct ServerStartArgs {
    // @behavior selvedge.startup.server.startup.args.home An explicit home path directs startup to initialize and lock that Selvedge home.
    pub explicit_home: Option<PathBuf>,
    // @behavior selvedge.startup.server.startup.args.api_config Startup passes API executor configuration into router command handling.
    pub api_config: ApiExecutorConfig,
    // @behavior selvedge.startup.server.startup.args.tool_executor Startup passes the tool execution spawner into router command handling.
    pub tool_executor: Arc<dyn ToolExecutionSpawner>,
    // @behavior selvedge.startup.server.startup.args.core_spawn_deps Startup passes core runtime spawn dependencies into router command handling.
    pub core_spawn_deps: TaskRuntimeSpawnDeps,
    // @behavior selvedge.startup.server.startup.args.snapshot_builder Startup passes the client snapshot builder into client hydration.
    pub snapshot_builder: Arc<dyn ClientSnapshotBuilder>,
    // @behavior selvedge.startup.server.startup.args.command_mapper Startup uses the supplied command mapper to convert local protocol commands into router envelopes.
    pub command_mapper: Arc<dyn LocalCommandMapper>,
    // @behavior selvedge.startup.server.startup.args.local_operation_executor Startup uses the supplied local operation executor for server-owned local commands.
    pub local_operation_executor: Arc<dyn LocalOperationExecutor>,
    // @behavior selvedge.startup.server.startup.args.local_binding Startup validates and stores the local bind target for local control surfaces.
    pub local_binding: LocalBindingConfig,
    // @behavior selvedge.startup.server.startup.args.web_binding Startup reserves and starts a web surface when a web binding is supplied.
    pub web_binding: Option<WebBindingConfig>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.startup.server.startup.local_binding Local binding configuration exposes the localhost target used by the process-local server control surface.
pub struct LocalBindingConfig {
    // @behavior selvedge.startup.server.startup.local_binding.target Local binding targets identify the localhost address family and port for local access.
    pub bind_target: LocalhostBindTarget,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.startup.server.web.binding Web binding configuration exposes the localhost target used by the optional web surface.
pub struct WebBindingConfig {
    // @behavior selvedge.startup.server.web.binding.target Web binding targets identify the localhost address family and port for HTTP access.
    pub bind_target: LocalhostBindTarget,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.startup.server.startup.bind_target Localhost bind targets represent IPv4 or IPv6 loopback ports accepted by server startup.
pub enum LocalhostBindTarget {
    Ipv4 { port: u16 },
    Ipv6 { port: u16 },
}

#[derive(Debug)]
// @behavior selvedge.startup.server.startup.handle A started server returns a control handle and join handle to the caller.
pub struct ServerHandle {
    // @behavior selvedge.startup.server.startup.handle.control The server control handle exposes ready, command, attach, and stop operations for the running server.
    pub control: ServerControl,
    // @behavior selvedge.startup.server.startup.handle.join The server join handle resolves to the final externally visible server exit status.
    pub join_handle: JoinHandle<ServerExitStatus>,
}

// @intent selvedge.startup.server.local_protocol.attach.frame_stream_type Server frame streams expose attached local client frames as asynchronous protocol output.
// @behavior selvedge.startup.server.local_protocol.attach.frame_stream Server frame streams yield local protocol frames or attach stream errors for an accepted client.
pub type ServerFrameStream =
    Pin<Box<dyn Stream<Item = Result<LocalClientFrame, ServerRequestError>> + Send>>;

#[derive(Clone)]
// @behavior selvedge.startup.server.local_protocol.control Server control exposes ready, command, attach, state, and stop behavior over the running server instance.
pub struct ServerControl {
    inner: Arc<ServerInner>,
}

impl fmt::Debug for ServerControl {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        // @behavior selvedge.startup.server.local_protocol.control.debug Debug formatting identifies server control values without exposing runtime internals.
        formatter.write_str("ServerControl")
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.startup.server.lifecycle.state Server runtime state reports starting, ready, closing, stopped, or failed status to callers.
pub enum ServerRuntimeState {
    Starting,
    Ready,
    Closing,
    Stopped,
    Failed,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.startup.server.shutdown.exit_status Server exit status reports clean stop, startup failure, router stop, or fatal failure.
pub enum ServerExitStatus {
    Stopped,
    // @behavior selvedge.startup.server.shutdown.exit_status.startup_failed Startup failures are reported through the server exit status when run_server cannot spawn a server.
    StartupFailed(ServerStartupError),
    RouterStopped,
    // @behavior selvedge.startup.server.shutdown.exit_status.fatal Fatal server exits expose the failure message to the caller.
    Fatal(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.startup.server.startup.error Startup errors report singleton, bind, config, logging, database, events, client-sync, router, or localhost binding failures.
pub enum ServerStartupError {
    SingletonAlreadyRunning,
    InvalidBindTarget,
    // @behavior selvedge.startup.server.startup.error.config Config initialization failures expose the config error message to the caller.
    ConfigInitFailed(String),
    // @behavior selvedge.startup.server.startup.error.logging Logging initialization failures expose the logging error message to the caller.
    LoggingInitFailed(String),
    // @behavior selvedge.startup.server.startup.error.db Database open failures expose the database error message to the caller.
    DbOpenFailed(String),
    // @behavior selvedge.startup.server.startup.error.events Events startup failures expose the events error message to the caller.
    EventsStartFailed(String),
    // @behavior selvedge.startup.server.startup.error.client_sync Client-sync startup failures expose the client-sync error message to the caller.
    ClientSyncStartFailed(String),
    // @behavior selvedge.startup.server.startup.error.router Router startup failures expose the router error message to the caller.
    RouterStartFailed(String),
    // @behavior selvedge.startup.server.startup.error.localhost_bind Localhost bind failures expose the bind error message to the caller.
    LocalhostBindFailed(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.startup.server.local_protocol.error Server request errors classify not-ready, validation, unsupported command, router mailbox, attach channel, and internal failures.
pub enum ServerRequestError {
    NotReady,
    ProtocolValidationFailed,
    UnsupportedCommand,
    RouterMailboxClosed,
    AttachChannelFailed,
    // @behavior selvedge.startup.server.local_protocol.error.internal Internal request failures expose an error message to the bridge layer.
    InternalFailure(String),
}

// @behavior selvedge.startup.server.local_protocol.command.mapper_trait Local command mappers return router envelopes or typed request errors for local command requests.
// @intent selvedge.startup.server.local_protocol.command.mapper The command mapper abstraction owns the local protocol to router envelope boundary for submitted commands.
pub trait LocalCommandMapper: Send + Sync {
    /// @behavior selvedge.startup.server.local_protocol.command.map Local command mapping converts validated local protocol commands into router command envelopes or typed request errors.
    fn map_command(
        &self,
        request: CommandRequest,
    ) -> Result<RouterCommandEnvelope, ServerRequestError>;
}

// @behavior selvedge.startup.server.local_operation.executor Local operation executors run server-owned commands and report progress through the supplied sender.
// @intent selvedge.startup.server.local_operation.executor_trait LocalOperationExecutor isolates server-owned command execution from router command execution.
pub trait LocalOperationExecutor: Send + Sync {
    /// @behavior selvedge.startup.server.local_operation.executor.execute Executor calls return a local operation success or local operation failure while sending progress through the supplied sender.
    fn execute(
        &self,
        command: LocalOperationCommand,
        progress_tx: LocalOperationProgressSender,
    ) -> LocalOperationFuture;
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.startup.server.local_operation.command Local operation commands identify server-owned commands accepted through the local protocol.
pub enum LocalOperationCommand {
    LoginChatgpt,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.startup.server.local_operation.progress Local operation progress reports user-code prompts or diagnostic text.
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
// @behavior selvedge.startup.server.local_operation.success Local operation success carries the terminal success message for the attached client.
pub struct LocalOperationSuccess {
    // @behavior selvedge.startup.server.local_operation.success.message The local operation success message is delivered as terminal client notice text.
    pub message_text: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.startup.server.local_operation.failure Local operation failure carries the terminal failure message for the attached client.
pub struct LocalOperationFailure {
    // @behavior selvedge.startup.server.local_operation.failure.message The local operation failure message is delivered as terminal client notice text.
    pub message_text: String,
}

// @behavior selvedge.startup.server.startup.run run_server returns the spawned server final status or a startup-failed status.
pub async fn run_server(args: ServerStartArgs) -> ServerExitStatus {
    match spawn_server(args) {
        Ok(handle) => handle
            .join_handle
            .await
            .unwrap_or_else(|error| ServerExitStatus::Fatal(error.to_string())),
        // @behavior selvedge.startup.server.startup.run.spawn_error run_server reports spawn errors as StartupFailed exit status.
        Err(error) => ServerExitStatus::StartupFailed(error),
    }
}

// @behavior selvedge.startup.server.startup.spawn spawn_server validates bindings, initializes home config, acquires the singleton lock, reserves web binding, and returns a started server handle.
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
        // @behavior selvedge.startup.server.web.reserve.failure Web bind reservation failure removes the startup lock before returning the startup error.
        Err(error) => {
            cleanup_startup_lock(&home);
            // @behavior selvedge.startup.server.web.reserve.error Web bind reservation errors are returned to the startup caller.
            return Err(error);
        }
    };

    let startup_result = start_server_after_lock(args, home, singleton_lock, web_bind);
    // @behavior selvedge.startup.server.startup.failure_cleanup Startup failures after lock acquisition are returned without a running server handle.
    if let Err(error) = &startup_result {
        // @behavior selvedge.startup.server.startup.failure_cleanup.error Startup failure paths return the original startup error.
        return Err(error.clone());
    }

    startup_result.map(ServerContext::into_handle)
}

impl ServerControl {
    // @behavior selvedge.startup.server.lifecycle.state.query Server state queries return the current runtime state.
    pub async fn state(&self) -> ServerRuntimeState {
        self.inner.state.read().await.clone()
    }

    // @behavior selvedge.startup.server.ready.response Ready requests return the current protocol version and Ready only when validation succeeds and the server is ready.
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

    // @behavior selvedge.startup.server.local_protocol.command.response Command submission returns the current protocol version, original client command id, and accepted or rejected outcome.
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

    // @behavior selvedge.startup.server.local_protocol.attach.response Attach requests return accepted metadata and a frame stream or a typed rejection.
    pub async fn attach_client(
        &self,
        request: AttachRequest,
        // @behavior selvedge.startup.server.local_protocol.attach.request Attach handling preserves the request command id when constructing attach responses.
    ) -> Result<(AttachAccepted, ServerFrameStream), AttachRejected> {
        let _request_guard = self.inner.request_gate.lock().await;
        let protocol_version = current_protocol_version();
        let client_command_id = request.client_command_id.clone();

        let reject = |reason| {
            // @behavior selvedge.startup.server.local_protocol.attach.reject Attach rejections include protocol version, client command id, and a typed reject reason.
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
            // @behavior selvedge.startup.server.local_protocol.attach.active_reject Active attach reservation failures are returned as typed attach rejections.
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
            // @behavior selvedge.startup.server.local_protocol.attach.channel_failed Attach channel creation failures reject the attach request before hydration starts.
            Err(reason) => return reject(reason),
        };
        let subscription = local_subscription_to_command(request.subscription);
        let (admission_tx, admission_rx) = tokio::sync::oneshot::channel();
        if self
            .inner
            .router_tx
            // @behavior selvedge.startup.server.local_protocol.attach.router_command Accepted attach setup sends an AttachClient router command with client identity, subscription, outbound channel, and admission reply.
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
            // @behavior selvedge.startup.server.local_protocol.attach.admission_closed Closed events admission starts shutdown and rejects the attach as an internal failure.
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
            // @behavior selvedge.startup.server.client_sync.start_hydration.full A full client-sync mailbox rejects attach as ClientSyncUnavailable after cleaning the events reservation.
            Err(tokio::sync::mpsc::error::TrySendError::Full(_)) => {
                reservation.cleanup_events_reservation_before_reject().await;
                return reject(AttachRejectReason::ClientSyncUnavailable);
            }
            // @behavior selvedge.startup.server.client_sync.start_hydration.closed A closed client-sync mailbox starts shutdown and rejects attach as ClientSyncUnavailable after cleaning the events reservation.
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

    // @behavior selvedge.startup.server.shutdown.stop Server stop requests begin server shutdown.
    pub async fn stop(&self) {
        self.begin_shutdown().await;
    }

    // @intent selvedge.startup.server.local_protocol.command.pipeline The command submission path gates readiness, validates protocol shape, and then maps accepted commands into router outcomes.
    async fn submit_command_outcome(&self, request: CommandRequest) -> CommandOutcome {
        let _request_guard = self.inner.request_gate.lock().await;

        if *self.inner.state.read().await != ServerRuntimeState::Ready {
            return CommandOutcome::Rejected(CommandRejectReason::ServerNotReady);
        }

        // @intent selvedge.startup.server.local_protocol.command.validation The command validation branch separates protocol rejection reasons before router command mapping.
        if validate_command_request(&request).is_err() {
            if request.protocol_version != current_protocol_version() {
                return CommandOutcome::Rejected(CommandRejectReason::ProtocolVersionMismatch);
            }
            return CommandOutcome::Rejected(CommandRejectReason::MalformedRequest);
        }

        if request.command_name == "login-chatgpt" {
            if !request
                .payload
                .as_object()
                .is_some_and(|object| object.is_empty())
            {
                return CommandOutcome::Rejected(CommandRejectReason::MalformedRequest);
            }
            return self.submit_login_chatgpt(request).await;
        }

        let command = match self.inner.command_mapper.map_command(request) {
            Ok(command) => command,
            // @behavior selvedge.startup.server.local_protocol.command.unsupported Unsupported mapped commands are rejected with UnsupportedCommand.
            Err(ServerRequestError::UnsupportedCommand) => {
                return CommandOutcome::Rejected(CommandRejectReason::UnsupportedCommand);
            }
            // @behavior selvedge.startup.server.local_protocol.command.router_closed Router mailbox closure starts shutdown and rejects command submission with RouterMailboxClosed.
            Err(ServerRequestError::RouterMailboxClosed) => {
                self.begin_shutdown_locked().await;
                return CommandOutcome::Rejected(CommandRejectReason::RouterMailboxClosed);
            }
            // @behavior selvedge.startup.server.local_protocol.command.not_ready Mapper not-ready errors reject command submission with ServerNotReady.
            Err(ServerRequestError::NotReady) => {
                return CommandOutcome::Rejected(CommandRejectReason::ServerNotReady);
            }
            // @behavior selvedge.startup.server.local_protocol.command.malformed Mapper protocol validation errors reject command submission with MalformedRequest.
            Err(ServerRequestError::ProtocolValidationFailed) => {
                return CommandOutcome::Rejected(CommandRejectReason::MalformedRequest);
            }
            // @behavior selvedge.startup.server.local_protocol.command.internal Mapper attach-channel or internal failures reject command submission with InternalFailure.
            Err(
                ServerRequestError::AttachChannelFailed | ServerRequestError::InternalFailure(_),
            ) => {
                return CommandOutcome::Rejected(CommandRejectReason::InternalFailure);
            }
        };

        if self
            .inner
            .router_tx
            // @behavior selvedge.startup.server.local_protocol.command.router_send Accepted command submission sends the router envelope to the router mailbox.
            .send(RouterIngressMessage::Command(command))
            .is_err()
        {
            self.begin_shutdown_locked().await;
            return CommandOutcome::Rejected(CommandRejectReason::RouterMailboxClosed);
        }

        CommandOutcome::Accepted
    }

    // @behavior selvedge.startup.server.local_operation.login Login command submission requires an active attach stream, enforces single-flight execution, and starts server-owned ChatGPT login outside router command delivery.
    async fn submit_login_chatgpt(&self, request: CommandRequest) -> CommandOutcome {
        let client_id = ClientId(request.client_id.0);
        let submit_command_id = ClientCommandId(request.client_command_id.0);
        let Some(attach_command_id) = self.inner.active_attach_for_client(&client_id) else {
            // @behavior selvedge.startup.server.local_operation.login.attach_required Login command submission is rejected when the requesting client has no active attach stream.
            return CommandOutcome::Rejected(CommandRejectReason::ClientNotAttached);
        };
        let login_permit = match self.inner.login_gate.clone().try_acquire_owned() {
            Ok(permit) => permit,
            Err(_) => {
                // @behavior selvedge.startup.server.local_operation.login.single_flight Login command submission is rejected while another server-owned login operation is running.
                return CommandOutcome::Rejected(CommandRejectReason::LoginAlreadyRunning);
            }
        };
        let Some(events_tx) = self.inner.events_tx.lock().await.as_ref().cloned() else {
            // @behavior selvedge.startup.server.local_operation.login.events_required Login command submission is rejected with internal failure when notice delivery is unavailable.
            return CommandOutcome::Rejected(CommandRejectReason::InternalFailure);
        };
        let executor = Arc::clone(&self.inner.local_operation_executor);
        let (progress_tx, progress_rx) = mpsc::unbounded_channel();
        let command_name = "login-chatgpt".to_owned();
        let operation = executor.execute(LocalOperationCommand::LoginChatgpt, progress_tx);
        let task = tokio::spawn(run_local_operation_task(LocalOperationTask {
            operation,
            progress_rx,
            events_tx,
            client_id,
            attach_command_id,
            submit_command_id,
            command_name,
            _login_permit: login_permit,
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

        // @behavior selvedge.startup.server.shutdown.state_closing Shutdown changes the externally visible runtime state to Closing.
        *self.inner.state.write().await = ServerRuntimeState::Closing;
        // @behavior selvedge.startup.server.shutdown.router_stop Shutdown sends StopRouter to the router mailbox.
        let _ = self.inner.router_tx.send(RouterIngressMessage::StopRouter);
        let client_sync_tx = self.inner.client_sync_tx.lock().await.clone();
        // @behavior selvedge.startup.server.shutdown.client_sync_stop Shutdown sends Shutdown to client-sync.
        let _ = client_sync_tx.send(ClientSyncIngress::Shutdown).await;
        let web_control = self
            .inner
            .web_control
            .lock()
            // @behavior selvedge.startup.server.shutdown.web_stop Shutdown reads stored web control and stops the optional web surface.
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

// @intent selvedge.startup.server.lifecycle.inner_effects ServerInner stores delegated lifecycle boundaries for router, events, client sync, attach channels, command mapping, and web control.
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
    frame_channel_factory: AttachFrameChannelFactoryRef,
    command_mapper: LocalCommandMapperRef,
    local_operation_executor: LocalOperationExecutorRef,
    login_gate: Arc<Semaphore>,
    local_operation_tasks: StdMutex<Vec<JoinHandle<()>>>,
    web_control: StdMutex<Option<selvedge_web::WebControl>>,
}

impl ServerInner {
    // @behavior selvedge.startup.server.local_operation.task.track Accepted local operation tasks are tracked so shutdown can cancel them.
    fn track_local_operation_task(&self, task: JoinHandle<()>) {
        let mut tasks = self
            .local_operation_tasks
            .lock()
            .expect("server local operation task lock");
        tasks.retain(|task| !task.is_finished());
        tasks.push(task);
    }

    // @behavior selvedge.startup.server.local_operation.task.abort Shutdown aborts tracked local operation tasks before closing events ingress.
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

    // @behavior selvedge.startup.server.local_protocol.attach.active_reservation Server attach admission records one active command per client and reports the previous active command.
    fn reserve_active_attach(
        &self,
        client_id: &ClientId,
        client_command_id: &ClientCommandId,
    ) -> Result<Option<ClientCommandId>, AttachRejectReason> {
        let mut active = self
            .active_attaches
            .lock()
            // @behavior selvedge.startup.server.local_protocol.attach.registry_lock Active attach reservation acquires the registry lock before inspecting or updating client attach entries.
            .expect("server active attach registry lock");

        if active.get(client_id) == Some(client_command_id) {
            // @behavior selvedge.startup.server.local_protocol.attach.duplicate The same client command id for an active client is rejected as DuplicateAttach.
            return Err(AttachRejectReason::DuplicateAttach);
        }

        if !active.contains_key(client_id) && active.len() >= DEFAULT_CLIENT_REGISTRY_CAPACITY {
            // @behavior selvedge.startup.server.local_protocol.attach.registry_full A new client attach is rejected as ClientRegistryFull when the active attach registry is at capacity.
            return Err(AttachRejectReason::ClientRegistryFull);
        }

        Ok(active.insert(client_id.clone(), client_command_id.clone()))
    }

    // @behavior selvedge.startup.server.local_operation.login.attach_lookup Active attach lookup returns the attach command id currently registered for the submitting client.
    fn active_attach_for_client(&self, client_id: &ClientId) -> Option<ClientCommandId> {
        self.active_attaches
            .lock()
            .expect("server active attach registry lock")
            .get(client_id)
            .cloned()
    }
}

// @intent selvedge.startup.server.local_operation.task LocalOperationTask carries one accepted local operation and its notice delivery identity.
struct LocalOperationTask {
    operation: LocalOperationFuture,
    progress_rx: mpsc::UnboundedReceiver<LocalOperationProgress>,
    events_tx: EventIngressSender,
    client_id: ClientId,
    attach_command_id: ClientCommandId,
    submit_command_id: ClientCommandId,
    command_name: String,
    _login_permit: OwnedSemaphorePermit,
}

// @behavior selvedge.startup.server.local_operation.task.run Local operation tasks relay progress notices and one terminal success or failure notice to the active attached client.
async fn run_local_operation_task(task: LocalOperationTask) {
    let LocalOperationTask {
        operation,
        mut progress_rx,
        events_tx,
        client_id,
        attach_command_id,
        submit_command_id,
        command_name,
        _login_permit,
    } = task;
    let operation_client_id = client_id.clone();
    let operation_attach_command_id = attach_command_id.clone();
    let operation_submit_command_id = submit_command_id.clone();
    let operation_command_name = command_name.clone();
    let operation_events_tx = events_tx.clone();

    tokio::pin!(operation);
    let mut progress_open = true;
    loop {
        tokio::select! {
            progress = progress_rx.recv(), if progress_open => {
                match progress {
                    Some(progress) => {
                        let notice = local_operation_progress_notice(progress, submit_command_id.clone());
                        if send_local_operation_notice(&events_tx, &client_id, &attach_command_id, notice).await.is_err() {
                            // @behavior selvedge.startup.server.local_operation.task.delivery_closed Local operation tasks stop when the events mailbox cannot accept a progress notice.
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
                            client_command_id: operation_submit_command_id,
                            command_name: operation_command_name,
                        },
                        message_text: success.message_text,
                    },
                    // @behavior selvedge.startup.server.local_operation.task.failure Terminal local operation failure is delivered as a command-failed notice for the submitted command.
                    Err(failure) => ClientNotice {
                        level: ClientNoticeLevel::Error,
                        kind: ClientNoticeKind::CommandFailed {
                            client_command_id: operation_submit_command_id,
                            command_name: operation_command_name,
                        },
                        message_text: failure.message_text,
                    },
                };
                // @behavior selvedge.startup.server.local_operation.task.terminal Local operation tasks attempt one terminal notice after operation completion.
                let _ = send_local_operation_notice(
                    &operation_events_tx,
                    &operation_client_id,
                    &operation_attach_command_id,
                    notice,
                ).await;
                return;
            }
        }
    }
}

// @behavior selvedge.startup.server.local_operation.progress.notice Local operation progress is mapped into typed client notices for the original submitted command.
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

// @behavior selvedge.startup.server.local_operation.notice Local operation notices carry server-owned operation progress and terminal results to attached clients.
// @behavior selvedge.startup.server.local_operation.notice.delivery Local operation notices are delivered through the events control mailbox to the active attach command stream.
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
        // @behavior selvedge.startup.server.local_operation.notice.delivery_closed Notice delivery reports failure when the events control mailbox is closed.
        Err(_) => Err(()),
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
    // @behavior selvedge.startup.server.local_protocol.attach.reservation_rollback Server attach reservation rollback tracks the active attach entry and optional events sender needed for cleanup.
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

// @behavior selvedge.startup.server.start_after_lock Server startup after singleton lock initializes logging, storage, events, client sync, router, and optional web control.
fn start_server_after_lock(
    args: ServerStartArgs,
    home: PathBuf,
    singleton_lock: File,
    web_bind: Option<WebBindReservation>,
) -> Result<ServerContext, ServerStartupError> {
    // @behavior selvedge.startup.server.startup.logging Startup initializes logging after acquiring the singleton lock.
    if let Err(error) = init_logging() {
        cleanup_startup_lock(&home);
        // @behavior selvedge.startup.server.startup.logging.failure Logging initialization failure removes the startup lock and returns the logging error.
        return Err(error);
    }

    let db = match open_db(OpenDbOptions {
        sqlite_path: sqlite_path_for_home(&home).to_string_lossy().to_string(),
    }) {
        Ok(db) => db,
        // @behavior selvedge.startup.server.startup.db_open Startup opens the SQLite database under the selected Selvedge home.
        Err(error) => {
            cleanup_startup_lock(&home);
            // @behavior selvedge.startup.server.startup.db_open.failure Database open failure removes the startup lock and returns DbOpenFailed.
            return Err(ServerStartupError::DbOpenFailed(error.to_string()));
        }
    };

    let events = match spawn_events_task(EventsStartArgs {
        ingress_capacity: DEFAULT_EVENTS_INGRESS_CAPACITY,
        client_registry_capacity: DEFAULT_CLIENT_REGISTRY_CAPACITY,
        hydration_buffer_capacity: DEFAULT_HYDRATION_BUFFER_CAPACITY,
    }) {
        Ok(events) => events,
        // @behavior selvedge.startup.server.startup.events Startup starts the events task with configured ingress, registry, and hydration capacities.
        Err(error) => {
            cleanup_startup_lock(&home);
            // @behavior selvedge.startup.server.startup.events.failure Events startup failure removes the startup lock and returns EventsStartFailed.
            return Err(map_events_start_error(error));
        }
    };

    let client_sync = match spawn_client_sync(ClientSyncStartArgs {
        events_tx: events.ingress_tx.clone(),
        snapshot_builder: args.snapshot_builder,
        ingress_capacity: DEFAULT_CLIENT_SYNC_INGRESS_CAPACITY,
    }) {
        Ok(client_sync) => client_sync,
        // @behavior selvedge.startup.server.startup.client_sync Startup starts client-sync with events ingress, snapshot builder, and configured ingress capacity.
        Err(error) => {
            cleanup_startup_lock(&home);
            // @behavior selvedge.startup.server.startup.client_sync.failure Client-sync startup failure removes the startup lock and returns ClientSyncStartFailed.
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
        // @behavior selvedge.startup.server.startup.router Startup starts the router with database, events ingress, API config, tool executor, and core spawn dependencies.
        Err(error) => {
            cleanup_startup_lock(&home);
            // @behavior selvedge.startup.server.startup.router.failure Router startup failure removes the startup lock and returns RouterStartFailed.
            return Err(map_router_start_error(error));
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
        local_operation_executor: args.local_operation_executor,
        login_gate: Arc::new(Semaphore::new(1)),
        local_operation_tasks: StdMutex::new(Vec::new()),
        web_control: StdMutex::new(None),
    });
    // @behavior selvedge.startup.server.web.start_result Server startup either records optional web control or returns a web startup error after lock cleanup.
    let web = match start_web(
        web_bind,
        ServerControl {
            inner: inner.clone(),
        },
    ) {
        Ok(web) => web,
        // @behavior selvedge.startup.server.web.start.failure Web startup failure removes the startup lock and returns the web startup error.
        Err(error) => {
            cleanup_startup_lock(&home);
            // @behavior selvedge.startup.server.web.start.error Web startup errors are returned to the startup caller.
            return Err(error);
        }
    };
    // @behavior selvedge.startup.server.web.control_store Startup stores optional web control for later shutdown.
    *inner.web_control.lock().expect("server web control lock") =
        web.as_ref().map(|handle| handle.control.clone());
    let join_handle = spawn_server_join_task(inner.clone(), router, events, client_sync, web);

    Ok(ServerContext { inner, join_handle })
}

fn cleanup_startup_lock(home: &Path) {
    // @behavior selvedge.startup.server.lock.cleanup Startup cleanup removes the server lock file for the selected home.
    let _ = std::fs::remove_file(lock_path_for_home(home));
}

// @behavior selvedge.startup.server.shutdown.join_task The server join task resolves to the first worker failure, router stop, fatal join error, or clean stopped status.
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

        // @behavior selvedge.startup.server.lock.shutdown_cleanup Server shutdown removes the server lock file before reporting final state.
        let _ = std::fs::remove_file(&inner.lock_path);
        // @behavior selvedge.startup.server.shutdown.final_state Server shutdown reports Stopped after clean stop and Failed after worker or fatal failure.
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

// @behavior selvedge.startup.server.shutdown.supervised Server shutdown marks the runtime closing, stops router, stops client sync, stops web, closes events ingress, and wakes waiters.
async fn begin_supervised_shutdown(
    inner: &ServerInner,
    router_tx: &RouterIngressSender,
    client_sync_tx: &selvedge_client_sync::ClientSyncSender,
    web_control: Option<&selvedge_web::WebControl>,
) {
    if inner.closing.swap(true, Ordering::SeqCst) {
        return;
    }

    // @behavior selvedge.startup.server.shutdown.supervised.state Supervised shutdown changes the externally visible runtime state to Closing.
    *inner.state.write().await = ServerRuntimeState::Closing;
    // @behavior selvedge.startup.server.shutdown.supervised.router Supervised shutdown sends StopRouter to the router mailbox.
    let _ = router_tx.send(RouterIngressMessage::StopRouter);
    // @behavior selvedge.startup.server.shutdown.supervised.client_sync Supervised shutdown sends Shutdown to client-sync.
    let _ = client_sync_tx.send(ClientSyncIngress::Shutdown).await;
    if let Some(web_control) = web_control {
        web_control.stop().await;
    }
    inner.abort_local_operation_tasks();
    let _ = inner.events_tx.lock().await.take();
    inner.stop_notify.notify_waiters();
}

// @behavior selvedge.startup.server.shutdown.collect_exit Server worker exit collection reports the externally visible server exit status after worker joins and detach cleanup.
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

// @behavior selvedge.startup.server.shutdown.router_status Router join results map to server stopped, router stopped, or fatal server exit statuses.
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
        // @behavior selvedge.startup.server.shutdown.router_status.join_error Router join failures report Fatal server exit status with the join error message.
        Err(error) => ServerExitStatus::Fatal(format!("router task join failed: {error}")),
    }
}

fn events_join_status(result: Result<(), JoinError>, expected_shutdown: bool) -> ServerExitStatus {
    match result {
        Ok(()) if expected_shutdown => ServerExitStatus::Stopped,
        Ok(()) => ServerExitStatus::Fatal("events task exited unexpectedly".to_owned()),
        // @behavior selvedge.startup.server.shutdown.events_status.join_error Events join failures report Fatal server exit status with the join error message.
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
        // @behavior selvedge.startup.server.shutdown.client_sync_status.join_error Client-sync join failures report Fatal server exit status with the join error message.
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
        // @behavior selvedge.startup.server.shutdown.web_status.join_error Web join failures report Fatal server exit status with the join error message.
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
                let client_id = this.client_id.clone();
                let client_command_id = this.client_command_id.clone();
                if let Some(client_sync_tx) = this.client_sync_tx.upgrade() {
                    send_cancel_hydration(
                        &client_sync_tx,
                        client_id.clone(),
                        client_command_id.clone(),
                    );
                }
                if let Some(events_tx) = this.events_tx.upgrade() {
                    send_detach_client_and_clear_active(
                        &events_tx,
                        client_id,
                        client_command_id,
                        DetachReason::ClientDisconnected,
                        Arc::clone(&this.active_attaches),
                    );
                } else {
                    clear_active_attach(&this.active_attaches, &client_id, &client_command_id);
                }
                this.closed_reported = true;
                // @behavior selvedge.startup.server.local_protocol.attach.stream_closed Closed attach frame channels emit AttachChannelFailed before ending the stream.
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

// @behavior selvedge.startup.server.client_sync.cancel_hydration Server attach cleanup sends client-sync cancellation for the affected client command.
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
        // @behavior selvedge.startup.server.client_sync.cancel_hydration.full Full client-sync cancellation mailbox queues cancellation on the runtime or blocks until delivery.
        Err(tokio::sync::mpsc::error::TrySendError::Full(cancel)) => {
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                handle.spawn(async move {
                    // @behavior selvedge.startup.server.client_sync.cancel_hydration.retry Queued client-sync cancellation attempts asynchronous delivery.
                    let _ = retry_client_sync_tx.send(cancel).await;
                });
            } else {
                let _ = retry_client_sync_tx.blocking_send(cancel);
            }
        }
        // @behavior selvedge.startup.server.client_sync.cancel_hydration.closed Closed client-sync cancellation mailboxes drop cancellation because the target is already unavailable.
        Err(tokio::sync::mpsc::error::TrySendError::Closed(_)) => {}
    }
}

// @behavior selvedge.startup.server.event_delivery.detach Server attach cleanup sends an events detach control message for the affected client command.
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
        // @behavior selvedge.startup.server.event_delivery.detach.full Full events detach mailbox queues detach on the runtime or blocks until delivery.
        Err(tokio::sync::mpsc::error::TrySendError::Full(detach)) => {
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                handle.spawn(async move {
                    // @behavior selvedge.startup.server.event_delivery.detach.retry Queued events detach attempts asynchronous delivery.
                    let _ = retry_events_tx.send(detach).await;
                });
            } else {
                let _ = retry_events_tx.blocking_send(detach);
            }
        }
        // @behavior selvedge.startup.server.event_delivery.detach.closed Closed events detach mailboxes drop detach because events are unavailable.
        Err(tokio::sync::mpsc::error::TrySendError::Closed(_)) => {}
    }
}

// @behavior selvedge.startup.server.event_delivery.detach_await Server attach cleanup can await events detach delivery before returning the local attach result.
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
    // @behavior selvedge.startup.server.event_delivery.detach_await.send Awaited detach cleanup waits for the events mailbox send attempt before returning.
    let _ = events_tx.send(detach).await;
}

// @behavior selvedge.startup.server.event_delivery.detach_restore Server attach cleanup sends detach and restores the previous active attach when replacement attach setup fails.
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
        // @behavior selvedge.startup.server.event_delivery.detach_restore.immediate Immediate detach completion or closed events restore the previous active attach state.
        Ok(()) | Err(tokio::sync::mpsc::error::TrySendError::Closed(_)) => {
            restore_active_attach(
                &active_attaches,
                &client_id,
                &client_command_id,
                previous_attach,
            );
        }
        // @behavior selvedge.startup.server.event_delivery.detach_restore.full Full events detach mailbox delays active attach restoration until detach is queued.
        Err(tokio::sync::mpsc::error::TrySendError::Full(detach)) => {
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                handle.spawn(async move {
                    // @behavior selvedge.startup.server.event_delivery.detach_restore.retry Queued detach restoration sends detach and then restores the previous active attach state.
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

// @behavior selvedge.startup.server.event_delivery.detach_clear Server attach cleanup sends detach and clears the active attach when the current attach is closed.
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
        // @behavior selvedge.startup.server.event_delivery.detach_clear.immediate Immediate detach completion or closed events clears the current active attach state.
        Ok(()) | Err(tokio::sync::mpsc::error::TrySendError::Closed(_)) => {
            clear_active_attach(&active_attaches, &client_id, &client_command_id);
        }
        // @behavior selvedge.startup.server.event_delivery.detach_clear.full Full events detach mailbox delays active attach clearing until detach is queued.
        Err(tokio::sync::mpsc::error::TrySendError::Full(detach)) => {
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                handle.spawn(async move {
                    // @behavior selvedge.startup.server.event_delivery.detach_clear.retry Queued detach clearing sends detach and then clears the current active attach state.
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

// @behavior selvedge.startup.server.local_protocol.attach.clear_active Server attach cleanup removes the active client command only when it still matches the closing attach stream.
fn clear_active_attach(
    active_attaches: &ActiveAttachRegistry,
    client_id: &ClientId,
    client_command_id: &ClientCommandId,
) {
    let mut active = active_attaches
        .lock()
        // @behavior selvedge.startup.server.local_protocol.attach.clear_active.lock Active attach clearing acquires the registry lock before removing a matching client command.
        .expect("server active attach registry lock");
    if active.get(client_id) == Some(client_command_id) {
        active.remove(client_id);
    }
}

// @behavior selvedge.startup.server.local_protocol.attach.restore_active Server attach cleanup restores the previous active command or clears the client when no previous command exists.
fn restore_active_attach(
    active_attaches: &ActiveAttachRegistry,
    client_id: &ClientId,
    client_command_id: &ClientCommandId,
    previous_attach: Option<ClientCommandId>,
) {
    let mut active = active_attaches
        .lock()
        // @behavior selvedge.startup.server.local_protocol.attach.restore_active.lock Active attach restoration acquires the registry lock before restoring or clearing a matching client command.
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

// @behavior selvedge.startup.server.local_protocol.attach.subscription_mapping Server attach conversion maps local subscription scope and detail settings into command-model subscription settings.
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

// @behavior selvedge.startup.server.local_protocol.event.tool_phase_mapping Server event conversion maps command-model tool execution phases into local protocol tool execution phases.
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

// @behavior selvedge.startup.server.web.start Server startup converts a reserved web bind into an optional running web surface or startup error.
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
        // @behavior selvedge.startup.server.web.start.error_mapping Web startup failures are mapped into server startup errors.
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
        // @behavior selvedge.startup.server.web.reserve.error_mapping Web bind reservation failures are mapped into server startup errors.
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

    // @behavior selvedge.startup.server.web.command_forward Server web bridge command submission forwards HTTP command requests to server control command handling.
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
                // @behavior selvedge.startup.server.web.attach_forward.reject Web bridge attach forwarding returns server attach rejections as web attach rejections.
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
            // @behavior selvedge.startup.server.web.frame_stream.error_mapping Web frame streams map server request errors into web bridge errors while preserving local frames.
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
        ServerRequestError::UnsupportedCommand => {
            selvedge_web::WebBridgeError::CommandRejected("unsupported command".to_owned())
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
            // @behavior selvedge.startup.server.web.bind_target.zero_port Web startup rejects port zero bind targets as InvalidBindTarget before durable startup side effects.
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
        // @behavior selvedge.startup.server.startup.config.resolve_home Home resolution failures are returned as ConfigInitFailed startup errors.
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
        // @behavior selvedge.startup.server.startup.config.already_initialized Already-initialized config is accepted when the selected home matches the requested home.
        Err(error) if error.to_string().contains("already") => {
            if let Some(home) = explicit_home {
                let selected_home = selvedge_config::selvedge_home()
                    // @behavior selvedge.startup.server.startup.config.selected_home Config mismatch checks read the already-selected Selvedge home.
                    .map_err(|error| ServerStartupError::ConfigInitFailed(error.to_string()))?;
                // @behavior selvedge.startup.server.startup.config.requested_home Config mismatch checks canonicalize the requested explicit home.
                let requested_home = std::fs::canonicalize(home)
                    // @behavior selvedge.startup.server.startup.config.requested_home_error Explicit home canonicalization failures are returned as ConfigInitFailed startup errors.
                    .map_err(|error| ServerStartupError::ConfigInitFailed(error.to_string()))?;
                if selected_home != requested_home {
                    // @behavior selvedge.startup.server.startup.config.home_mismatch Already-initialized config for a different home returns ConfigInitFailed with both paths.
                    return Err(ServerStartupError::ConfigInitFailed(format!(
                        "config service is initialized for {}, requested {}",
                        selected_home.display(),
                        requested_home.display()
                    )));
                }
            }

            Ok(())
        }
        // @behavior selvedge.startup.server.startup.config.init_error Config initialization failures are returned as ConfigInitFailed startup errors.
        Err(error) => Err(ServerStartupError::ConfigInitFailed(error.to_string())),
    }
}

fn init_logging() -> Result<(), ServerStartupError> {
    match selvedge_logging::init() {
        Ok(()) => Ok(()),
        // @behavior selvedge.startup.server.startup.logging.already_initialized Already-initialized logging is accepted during server startup.
        Err(error) if error.to_string().contains("already") => Ok(()),
        // @behavior selvedge.startup.server.startup.logging.init_error Logging initialization failures are returned as LoggingInitFailed startup errors.
        Err(error) => Err(ServerStartupError::LoggingInitFailed(error.to_string())),
    }
}

fn acquire_singleton_lock(home: &Path) -> Result<File, ServerStartupError> {
    // @behavior selvedge.startup.server.lock.home_directory Singleton lock acquisition creates the selected Selvedge home directory before opening the lock file.
    std::fs::create_dir_all(home).map_err(|error| {
        ServerStartupError::ConfigInitFailed(format!("failed to create home directory: {error}"))
    })?;

    match OpenOptions::new()
        .create(true)
        .truncate(false)
        // @behavior selvedge.startup.server.lock.file_open Singleton lock acquisition opens the server lock file for read and write without truncating existing content.
        .write(true)
        .read(true)
        .open(lock_path_for_home(home))
    {
        Ok(file) => match file.try_lock_exclusive() {
            Ok(()) => Ok(file),
            // @behavior selvedge.startup.server.lock.contention A contended server lock returns SingletonAlreadyRunning.
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                // @behavior selvedge.startup.server.lock.contention.error Lock contention is reported as SingletonAlreadyRunning.
                Err(ServerStartupError::SingletonAlreadyRunning)
            }
            // @behavior selvedge.startup.server.lock.error Lock acquisition errors other than contention return ConfigInitFailed.
            Err(error) => Err(ServerStartupError::ConfigInitFailed(error.to_string())),
        },
        // @behavior selvedge.startup.server.lock.open_error Lock file open errors return ConfigInitFailed.
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
    use tokio::sync::oneshot;
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

    struct AcceptingMapper;

    impl LocalCommandMapper for AcceptingMapper {
        fn map_command(
            &self,
            request: CommandRequest,
        ) -> Result<RouterCommandEnvelope, ServerRequestError> {
            Ok(RouterCommandEnvelope {
                client_id: Some(ClientId(request.client_id.0)),
                client_command_id: Some(ClientCommandId(request.client_command_id.0)),
                command: RouterCommand::EnsureMissingTaskRuntimes,
            })
        }
    }

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

    // @verifies selvedge.startup.server
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

        // @verifies selvedge.startup.server.lifecycle
        assert_eq!(rejected.reason, AttachRejectReason::RouterMailboxClosed);
        // @verifies selvedge.startup.server.lifecycle
        assert_eq!(control.state().await, ServerRuntimeState::Closing);
    }

    #[tokio::test]
    async fn login_command_requires_active_attach() {
        let (router_tx, _router_rx) = mpsc::unbounded_channel();
        let (client_sync_tx, _client_sync_rx) = mpsc::channel(1);
        let (events_tx, _events_rx) = mpsc::channel(8);
        let control = test_control(router_tx, client_sync_tx, events_tx);

        let response = control.submit_command(login_command("command-1")).await;

        // @verifies selvedge.startup.server.local_operation.login.attach_required
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

        // @verifies selvedge.startup.server.local_operation
        assert_eq!(response.outcome, CommandOutcome::Accepted);
        // @verifies selvedge.startup.server.local_operation
        assert!(router_rx.try_recv().is_err());
        let notice = timeout(Duration::from_millis(100), events_rx.recv())
            .await
            .expect("terminal notice timeout")
            .expect("terminal notice");
        let EventIngress::Control(EventControlMessage::DeliverNotice(notice)) = notice else {
            panic!("expected terminal notice");
        };
        // @verifies selvedge.startup.server.local_operation.task.terminal
        assert_eq!(
            notice.client_command_id,
            ClientCommandId("attach-1".to_owned())
        );
        // @verifies selvedge.startup.server.local_operation.task.terminal
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
        let control = test_control_with_frame_channel_factory_mapper_and_executor(
            router_tx,
            client_sync_tx,
            events_tx,
            Arc::new(TokioAttachFrameChannelFactory),
            Arc::new(UnusedMapper),
            Arc::new(PendingLocalOperationExecutor),
        );
        activate_attach(&control, "client-1", "attach-1");

        let first = control.submit_command(login_command("command-1")).await;
        let second = control.submit_command(login_command("command-2")).await;

        // @verifies selvedge.startup.server.local_operation.login.single_flight
        assert_eq!(first.outcome, CommandOutcome::Accepted);
        // @verifies selvedge.startup.server.local_operation.login.single_flight
        assert_eq!(
            second.outcome,
            CommandOutcome::Rejected(CommandRejectReason::LoginAlreadyRunning)
        );
    }

    #[tokio::test]
    async fn shutdown_aborts_pending_login_operation() {
        let (router_tx, _router_rx) = mpsc::unbounded_channel();
        let (client_sync_tx, _client_sync_rx) = mpsc::channel(1);
        let (events_tx, _events_rx) = mpsc::channel(8);
        let control = test_control_with_frame_channel_factory_mapper_and_executor(
            router_tx,
            client_sync_tx,
            events_tx,
            Arc::new(TokioAttachFrameChannelFactory),
            Arc::new(UnusedMapper),
            Arc::new(PendingLocalOperationExecutor),
        );
        activate_attach(&control, "client-1", "attach-1");

        let response = control.submit_command(login_command("command-1")).await;
        control.stop().await;

        // @verifies selvedge.startup.server.local_operation.task.abort
        assert_eq!(response.outcome, CommandOutcome::Accepted);
        // @verifies selvedge.startup.server.local_operation.task.abort
        assert!(
            control
                .inner
                .local_operation_tasks
                .lock()
                .expect("local operation tasks")
                .is_empty()
        );
    }

    // @verifies selvedge.startup.server
    #[tokio::test]
    async fn server_web_bridge_forwards_commands_to_server_control() {
        let router_tx = accepting_router_sender();
        let (client_sync_tx, _client_sync_rx) = mpsc::channel(1);
        let (events_tx, _events_rx) = mpsc::channel(1);
        let control = test_control_with_mapper(
            router_tx,
            client_sync_tx,
            events_tx,
            Arc::new(AcceptingMapper),
        );
        let bridge = ServerWebBridge { control };

        let response = bridge
            .submit_command(test_command_request())
            .await
            .expect("web command forwards");

        // @verifies selvedge.startup.server.lifecycle
        assert_eq!(response.outcome, CommandOutcome::Accepted);
    }

    // @verifies selvedge.startup.server
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

        // @verifies selvedge.startup.server.lifecycle
        assert_eq!(
            accepted.client_command_id,
            test_attach_request().client_command_id
        );
        match client_sync_rx.recv().await.expect("start hydration") {
            ClientSyncIngress::StartHydration(begin) => {
                // @verifies selvedge.startup.server.lifecycle
                assert_eq!(begin.client_id, ClientId("client-1".to_owned()));
                // @verifies selvedge.startup.server.lifecycle
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

    // @verifies selvedge.startup.server
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

        // @verifies selvedge.startup.server.lifecycle
        assert_eq!(status, ServerExitStatus::Fatal("router failed".to_owned()));
        // @verifies selvedge.startup.server.lifecycle
        assert_eq!(control.state().await, ServerRuntimeState::Failed);
    }

    // @verifies selvedge.startup.server
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

        // @verifies selvedge.startup.server.lifecycle
        assert_eq!(
            status,
            ServerExitStatus::Fatal("router events mailbox closed".to_owned())
        );
        // @verifies selvedge.startup.server.lifecycle
        assert_eq!(control.state().await, ServerRuntimeState::Failed);
    }

    // @verifies selvedge.startup.server
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

        // @verifies selvedge.startup.server.lifecycle
        assert_eq!(rejected.reason, AttachRejectReason::ClientSyncUnavailable);
        // @verifies selvedge.startup.server.lifecycle
        assert_eq!(control.state().await, ServerRuntimeState::Closing);
    }

    // @verifies selvedge.startup.server
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

        // @verifies selvedge.startup.server.lifecycle
        assert_eq!(rejected.reason, AttachRejectReason::InternalFailure);
        // @verifies selvedge.startup.server.lifecycle
        assert_eq!(control.state().await, ServerRuntimeState::Closing);
    }

    // @verifies selvedge.startup.server
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

        // @verifies selvedge.startup.server.lifecycle
        assert_eq!(rejected.reason, AttachRejectReason::DuplicateAttach);
        // @verifies selvedge.startup.server.lifecycle
        assert!(matches!(
            client_sync_rx.try_recv(),
            Err(tokio::sync::mpsc::error::TryRecvError::Empty)
        ));
    }

    // @verifies selvedge.startup.server
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

        // @verifies selvedge.startup.server.lifecycle
        assert_eq!(rejected.reason, AttachRejectReason::ClientRegistryFull);
        // @verifies selvedge.startup.server.lifecycle
        assert!(matches!(
            client_sync_rx.try_recv(),
            Err(tokio::sync::mpsc::error::TryRecvError::Empty)
        ));
    }

    // @verifies selvedge.startup.server
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

        // @verifies selvedge.startup.server.lifecycle
        assert_eq!(rejected.reason, AttachRejectReason::AttachChannelFailed);
        // @verifies selvedge.startup.server.lifecycle
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

    // @verifies selvedge.startup.server
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

        // @verifies selvedge.startup.server.lifecycle
        assert_eq!(rejected.reason, AttachRejectReason::DuplicateAttach);
    }

    // @verifies selvedge.startup.server
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
        // @verifies selvedge.startup.server.lifecycle
        assert_eq!(error, ServerRequestError::AttachChannelFailed);
        match timeout(Duration::from_millis(100), client_sync_rx.recv())
            .await
            .expect("channel close cancel arrives")
            .expect("channel close cancel")
        {
            ClientSyncIngress::CancelHydration(cancel) => {
                // @verifies selvedge.startup.server.lifecycle
                assert_eq!(cancel.client_id, ClientId("client-1".to_owned()));
                // @verifies selvedge.startup.server.lifecycle
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
                // @verifies selvedge.startup.server.lifecycle
                assert_eq!(detach.client_id, ClientId("client-1".to_owned()));
                // @verifies selvedge.startup.server.lifecycle
                assert_eq!(
                    detach.client_command_id,
                    ClientCommandId("attach-1".to_owned())
                );
                // @verifies selvedge.startup.server.lifecycle
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
        // @verifies selvedge.startup.server.lifecycle
        assert!(matches!(
            client_sync_rx.try_recv(),
            Err(tokio::sync::mpsc::error::TryRecvError::Empty)
        ));
    }

    // @verifies selvedge.startup.server
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
        // @verifies selvedge.startup.server.lifecycle
        assert_eq!(rejected.reason, AttachRejectReason::ClientSyncUnavailable);
        match timeout(Duration::from_millis(100), events_rx.recv())
            .await
            .expect("reservation cleanup detach arrives")
            .expect("reservation cleanup detach")
        {
            EventIngress::Control(EventControlMessage::DetachClient(detach)) => {
                // @verifies selvedge.startup.server.lifecycle
                assert_eq!(detach.client_id, ClientId("client-1".to_owned()));
                // @verifies selvedge.startup.server.lifecycle
                assert_eq!(
                    detach.client_command_id,
                    ClientCommandId("attach-1".to_owned())
                );
                // @verifies selvedge.startup.server.lifecycle
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

    // @verifies selvedge.startup.server
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
        // @verifies selvedge.startup.server.lifecycle
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
                // @verifies selvedge.startup.server.lifecycle
                assert_eq!(detach.client_id, ClientId("client-1".to_owned()));
                // @verifies selvedge.startup.server.lifecycle
                assert_eq!(
                    detach.client_command_id,
                    ClientCommandId("attach-1".to_owned())
                );
                // @verifies selvedge.startup.server.lifecycle
                assert_eq!(detach.reason, DetachReason::ClientDisconnected);
            }
            _ => panic!("unexpected events ingress"),
        }
        let rejected = match attach_task.await.expect("attach task joins") {
            Ok(_) => panic!("backpressured client-sync should reject"),
            Err(rejected) => rejected,
        };
        // @verifies selvedge.startup.server.lifecycle
        assert_eq!(rejected.reason, AttachRejectReason::ClientSyncUnavailable);

        let _ = client_sync_rx.recv().await.expect("drain filled mailbox");
        let (_accepted, _stream) = control
            .attach_client(test_attach_request())
            .await
            .expect("attach accepted after queued cleanup");
    }

    // @verifies selvedge.startup.server
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
            // @verifies selvedge.startup.server.lifecycle
            Err(error) => assert!(error.is_cancelled()),
        }

        match timeout(Duration::from_millis(100), events_rx.recv())
            .await
            .expect("cancelled attach detach arrives")
            .expect("cancelled attach detach")
        {
            EventIngress::Control(EventControlMessage::DetachClient(detach)) => {
                // @verifies selvedge.startup.server.lifecycle
                assert_eq!(detach.client_id, ClientId("client-1".to_owned()));
                // @verifies selvedge.startup.server.lifecycle
                assert_eq!(
                    detach.client_command_id,
                    ClientCommandId("attach-1".to_owned())
                );
                // @verifies selvedge.startup.server.lifecycle
                assert_eq!(detach.reason, DetachReason::ClientDisconnected);
            }
            _ => panic!("unexpected events ingress"),
        }
        // @verifies selvedge.startup.server.lifecycle
        assert!(matches!(
            client_sync_rx.try_recv(),
            Err(tokio::sync::mpsc::error::TryRecvError::Empty)
        ));
    }

    // @verifies selvedge.startup.server
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
                // @verifies selvedge.startup.server.lifecycle
                assert_eq!(begin.client_id, ClientId("client-1".to_owned()));
                // @verifies selvedge.startup.server.lifecycle
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
                // @verifies selvedge.startup.server.lifecycle
                assert_eq!(cancel.client_id, ClientId("client-1".to_owned()));
                // @verifies selvedge.startup.server.lifecycle
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
                // @verifies selvedge.startup.server.lifecycle
                assert_eq!(detach.client_id, ClientId("client-1".to_owned()));
                // @verifies selvedge.startup.server.lifecycle
                assert_eq!(
                    detach.client_command_id,
                    ClientCommandId("attach-1".to_owned())
                );
                // @verifies selvedge.startup.server.lifecycle
                assert_eq!(detach.reason, DetachReason::ClientDisconnected);
            }
            _ => panic!("unexpected events ingress"),
        }
    }

    // @verifies selvedge.startup.server
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
        // @verifies selvedge.startup.server.lifecycle
        assert_eq!(rejected.reason, AttachRejectReason::DuplicateAttach);

        let _ = events_rx.recv().await.expect("drain occupied events slot");
        drop_thread.join().expect("drop thread completes");
        match timeout(Duration::from_millis(100), events_rx.recv())
            .await
            .expect("client detach arrives")
            .expect("client detach")
        {
            EventIngress::Control(EventControlMessage::DetachClient(detach)) => {
                // @verifies selvedge.startup.server.lifecycle
                assert_eq!(detach.client_id, ClientId("client-1".to_owned()));
                // @verifies selvedge.startup.server.lifecycle
                assert_eq!(
                    detach.client_command_id,
                    ClientCommandId("attach-1".to_owned())
                );
                // @verifies selvedge.startup.server.lifecycle
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
        test_control_with_frame_channel_factory_and_mapper(
            router_tx,
            client_sync_tx,
            events_tx,
            frame_channel_factory,
            Arc::new(UnusedMapper),
        )
    }

    fn test_control_with_mapper(
        router_tx: RouterIngressSender,
        client_sync_tx: selvedge_client_sync::ClientSyncSender,
        events_tx: EventIngressSender,
        command_mapper: Arc<dyn LocalCommandMapper>,
    ) -> ServerControl {
        test_control_with_frame_channel_factory_and_mapper(
            router_tx,
            client_sync_tx,
            events_tx,
            Arc::new(TokioAttachFrameChannelFactory),
            command_mapper,
        )
    }

    fn test_control_with_frame_channel_factory_and_mapper(
        router_tx: RouterIngressSender,
        client_sync_tx: selvedge_client_sync::ClientSyncSender,
        events_tx: EventIngressSender,
        frame_channel_factory: Arc<dyn AttachFrameChannelFactory>,
        command_mapper: Arc<dyn LocalCommandMapper>,
    ) -> ServerControl {
        test_control_with_frame_channel_factory_mapper_and_executor(
            router_tx,
            client_sync_tx,
            events_tx,
            frame_channel_factory,
            command_mapper,
            Arc::new(NoopLocalOperationExecutor),
        )
    }

    fn test_control_with_frame_channel_factory_mapper_and_executor(
        router_tx: RouterIngressSender,
        client_sync_tx: selvedge_client_sync::ClientSyncSender,
        events_tx: EventIngressSender,
        frame_channel_factory: Arc<dyn AttachFrameChannelFactory>,
        command_mapper: Arc<dyn LocalCommandMapper>,
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
                active_attaches: Arc::new(StdMutex::new(HashMap::new())),
                frame_channel_factory,
                command_mapper,
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

    fn test_command_request() -> CommandRequest {
        CommandRequest {
            protocol_version: current_protocol_version(),
            client_id: selvedge_local_protocol::LocalClientId::new("client-1")
                .expect("valid client id"),
            client_command_id: LocalClientCommandId::new("command-1").expect("valid command id"),
            command_name: "send-user-input".to_owned(),
            payload: serde_json::json!({"message": "hello"}),
        }
    }

    fn login_command(client_command_id: &str) -> CommandRequest {
        CommandRequest {
            protocol_version: current_protocol_version(),
            client_id: selvedge_local_protocol::LocalClientId::new("client-1")
                .expect("valid client id"),
            client_command_id: LocalClientCommandId::new(client_command_id)
                .expect("valid command id"),
            command_name: "login-chatgpt".to_owned(),
            payload: serde_json::json!({}),
        }
    }

    fn activate_attach(control: &ServerControl, client_id: &str, client_command_id: &str) {
        control
            .inner
            .active_attaches
            .lock()
            .expect("active attaches")
            .insert(
                ClientId(client_id.to_owned()),
                ClientCommandId(client_command_id.to_owned()),
            );
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
                snapshot_mode: selvedge_local_protocol::LocalSnapshotMode::CurrentState,
                include_model_call_status: false,
                include_tool_execution_status: false,
                include_debug_notices: false,
            },
        }
    }
}
