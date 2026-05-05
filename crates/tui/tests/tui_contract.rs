use std::collections::VecDeque;
use std::future;
use std::sync::{Arc, LazyLock, Mutex};
use std::time::Duration;

use futures_util::stream;
use selvedge_local_client::{
    AttachRejectedOrClientError, LocalClientConfig, LocalClientError, LocalEndpoint,
    LocalFrameStream, LocalTransport,
};
use selvedge_local_protocol::{
    AttachAccepted, AttachRejected, AttachRequest, CommandOutcome, CommandRejectReason,
    CommandRequest, CommandResponse, LocalClientCommandId, LocalClientFrame, LocalClientId,
    LocalClientSnapshot, LocalClientSnapshotFrame, LocalClientSubscription, LocalDetailLevel,
    LocalTaskScope, ReadyRequest, ReadyResponse, ReadyState, current_protocol_version,
};
use selvedge_tui::{TuiExitStatus, TuiInputAction, TuiStartArgs, run_tui};
use tokio::sync::Mutex as AsyncMutex;

static TEST_LOCK: LazyLock<AsyncMutex<()>> = LazyLock::new(|| AsyncMutex::new(()));
static CONNECT_PLAN: LazyLock<Mutex<Option<Result<FakeTransportStateHandle, LocalClientError>>>> =
    LazyLock::new(|| Mutex::new(None));

type FakeTransportStateHandle = Arc<Mutex<FakeTransportState>>;

#[tokio::test]
async fn connect_failure_returns_server_unavailable() {
    let _guard = TEST_LOCK.lock().await;
    install_connect_plan(Err(LocalClientError::ConnectFailed("refused".to_owned())));

    let status = run_tui::<FakeTransport, _>(valid_args(None), NoopMapper).await;

    assert_eq!(status, TuiExitStatus::ServerUnavailable);
}

#[tokio::test]
async fn not_ready_returns_server_not_ready() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    state
        .lock()
        .expect("fake state")
        .ready_responses
        .push_back(ReadyResponse {
            protocol_version: current_protocol_version(),
            state: ReadyState::NotReady,
        });
    install_connect_plan(Ok(state.clone()));

    let status = run_tui::<FakeTransport, _>(valid_args(None), NoopMapper).await;

    assert_eq!(status, TuiExitStatus::ServerNotReady);
    assert_eq!(state.lock().expect("fake state").close_calls, 1);
}

#[tokio::test]
async fn attach_rejection_returns_attach_rejected() {
    let _guard = TEST_LOCK.lock().await;
    let state = ready_state();
    state
        .lock()
        .expect("fake state")
        .attach_responses
        .push_back(AttachAction::Rejected(AttachRejected {
            protocol_version: current_protocol_version(),
            client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
            reason: CommandRejectReason::ServerNotReady,
        }));
    install_connect_plan(Ok(state.clone()));

    let status = run_tui::<FakeTransport, _>(valid_args(None), NoopMapper).await;

    assert_eq!(
        status,
        TuiExitStatus::AttachRejected("ServerNotReady".to_owned())
    );
    assert_eq!(state.lock().expect("fake state").close_calls, 1);
}

#[tokio::test]
async fn waits_for_snapshot_then_submits_initial_command_and_reports_rejection() {
    let _guard = TEST_LOCK.lock().await;
    let state = ready_state();
    {
        let mut state_guard = state.lock().expect("fake state");
        state_guard
            .attach_responses
            .push_back(AttachAction::Accepted(vec![Ok(
                LocalClientFrame::Snapshot(LocalClientSnapshotFrame {
                    delivery_seq: 1,
                    client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
                    snapshot: empty_snapshot(),
                }),
            )]));
        state_guard.command_responses.push_back(CommandResponse {
            protocol_version: current_protocol_version(),
            client_command_id: LocalClientCommandId::new("command-1").expect("command id"),
            outcome: CommandOutcome::Rejected(CommandRejectReason::UnsupportedCommand),
        });
    }
    install_connect_plan(Ok(state.clone()));

    let status =
        run_tui::<FakeTransport, _>(valid_args(Some(valid_command("command-1"))), NoopMapper).await;

    assert_eq!(
        status,
        TuiExitStatus::CommandRejected("UnsupportedCommand".to_owned())
    );
    let state = state.lock().expect("fake state");
    assert_eq!(state.attach_calls, 1);
    assert_eq!(state.command_calls, 1);
    assert_eq!(state.close_calls, 1);
}

#[tokio::test]
async fn accepted_initial_command_exits_successfully() {
    let _guard = TEST_LOCK.lock().await;
    let state = ready_state();
    {
        let mut state_guard = state.lock().expect("fake state");
        state_guard
            .attach_responses
            .push_back(AttachAction::Accepted(vec![Ok(
                LocalClientFrame::Snapshot(LocalClientSnapshotFrame {
                    delivery_seq: 1,
                    client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
                    snapshot: empty_snapshot(),
                }),
            )]));
        state_guard.command_responses.push_back(CommandResponse {
            protocol_version: current_protocol_version(),
            client_command_id: LocalClientCommandId::new("command-1").expect("command id"),
            outcome: CommandOutcome::Accepted,
        });
    }
    install_connect_plan(Ok(state.clone()));

    let status =
        run_tui::<FakeTransport, _>(valid_args(Some(valid_command("command-1"))), NoopMapper).await;

    assert_eq!(status, TuiExitStatus::Exited);
    let state = state.lock().expect("fake state");
    assert_eq!(state.command_calls, 1);
    assert_eq!(state.close_calls, 1);
}

#[tokio::test]
async fn stream_closed_before_snapshot_returns_disconnected() {
    let _guard = TEST_LOCK.lock().await;
    let state = ready_state();
    state
        .lock()
        .expect("fake state")
        .attach_responses
        .push_back(AttachAction::Accepted(Vec::new()));
    install_connect_plan(Ok(state.clone()));

    let status = run_tui::<FakeTransport, _>(valid_args(None), NoopMapper).await;

    assert_eq!(status, TuiExitStatus::Disconnected);
    assert_eq!(state.lock().expect("fake state").close_calls, 1);
}

struct NoopMapper;

impl selvedge_tui::TuiCommandMapper for NoopMapper {
    fn map_input(&self, _input_text: &str) -> Result<TuiInputAction, String> {
        Ok(TuiInputAction::Noop)
    }
}

#[derive(Clone)]
struct FakeTransport {
    state: FakeTransportStateHandle,
}

#[derive(Default)]
struct FakeTransportState {
    ready_responses: VecDeque<ReadyResponse>,
    attach_responses: VecDeque<AttachAction>,
    command_responses: VecDeque<CommandResponse>,
    ready_calls: usize,
    attach_calls: usize,
    command_calls: usize,
    close_calls: usize,
}

enum AttachAction {
    Accepted(Vec<Result<LocalClientFrame, LocalClientError>>),
    Rejected(AttachRejected),
}

impl FakeTransportState {
    fn new_handle() -> FakeTransportStateHandle {
        Arc::new(Mutex::new(Self::default()))
    }
}

impl LocalTransport for FakeTransport {
    async fn connect(config: LocalClientConfig) -> Result<Self, LocalClientError>
    where
        Self: Sized,
    {
        let _ = config;
        match CONNECT_PLAN.lock().expect("connect plan").take() {
            Some(Ok(state)) => Ok(Self { state }),
            Some(Err(error)) => Err(error),
            None => Err(LocalClientError::ConnectFailed(
                "missing connect plan".to_owned(),
            )),
        }
    }

    async fn ready(&self, request: ReadyRequest) -> Result<ReadyResponse, LocalClientError> {
        let _ = request;
        let mut state = self.state.lock().expect("fake state");
        state.ready_calls += 1;
        Ok(state.ready_responses.pop_front().unwrap_or(ReadyResponse {
            protocol_version: current_protocol_version(),
            state: ReadyState::Ready,
        }))
    }

    async fn submit_command(
        &self,
        request: CommandRequest,
    ) -> Result<CommandResponse, LocalClientError> {
        let mut state = self.state.lock().expect("fake state");
        state.command_calls += 1;
        Ok(state
            .command_responses
            .pop_front()
            .unwrap_or(CommandResponse {
                protocol_version: current_protocol_version(),
                client_command_id: request.client_command_id,
                outcome: CommandOutcome::Accepted,
            }))
    }

    async fn attach(
        &self,
        request: AttachRequest,
    ) -> Result<(AttachAccepted, LocalFrameStream), AttachRejectedOrClientError> {
        let mut state = self.state.lock().expect("fake state");
        state.attach_calls += 1;
        match state.attach_responses.pop_front() {
            Some(AttachAction::Accepted(frames)) => Ok((
                AttachAccepted {
                    protocol_version: current_protocol_version(),
                    client_id: request.client_id,
                    client_command_id: request.client_command_id,
                },
                Box::pin(stream::iter(frames)),
            )),
            Some(AttachAction::Rejected(rejected)) => {
                Err(AttachRejectedOrClientError::Rejected(rejected))
            }
            None => Ok((
                AttachAccepted {
                    protocol_version: current_protocol_version(),
                    client_id: request.client_id,
                    client_command_id: request.client_command_id,
                },
                Box::pin(stream::iter(Vec::new())),
            )),
        }
    }

    fn close(&self) -> impl Future<Output = ()> + Send {
        let state = self.state.clone();
        {
            state.lock().expect("fake state").close_calls += 1;
        };
        future::ready(())
    }
}

fn install_connect_plan(plan: Result<FakeTransportStateHandle, LocalClientError>) {
    *CONNECT_PLAN.lock().expect("connect plan") = Some(plan);
}

fn ready_state() -> FakeTransportStateHandle {
    let state = FakeTransportState::new_handle();
    state
        .lock()
        .expect("fake state")
        .ready_responses
        .push_back(ReadyResponse {
            protocol_version: current_protocol_version(),
            state: ReadyState::Ready,
        });
    state
}

fn valid_args(initial_command: Option<CommandRequest>) -> TuiStartArgs {
    TuiStartArgs {
        client_config: LocalClientConfig {
            endpoint: LocalEndpoint::TcpIpv4 { port: 17691 },
            request_timeout: Duration::from_secs(1),
        },
        client_id: "client-1".to_owned(),
        attach_command_id: "attach-1".to_owned(),
        subscription: LocalClientSubscription {
            task_scope: LocalTaskScope::AllTasks,
            detail_level: LocalDetailLevel::Summary,
            include_model_call_status: false,
            include_tool_execution_status: false,
            include_debug_notices: false,
        },
        initial_command,
    }
}

fn valid_command(command_id: &str) -> CommandRequest {
    CommandRequest {
        protocol_version: current_protocol_version(),
        client_id: LocalClientId::new("client-1").expect("client id"),
        client_command_id: LocalClientCommandId::new(command_id).expect("command id"),
        command_name: "noop".to_owned(),
        payload: serde_json::json!({}),
    }
}

fn empty_snapshot() -> LocalClientSnapshot {
    LocalClientSnapshot {
        generated_at: 1,
        tasks: Vec::new(),
        task_parent_edges: Vec::new(),
        history_nodes: Vec::new(),
        task_versions: Vec::new(),
    }
}
