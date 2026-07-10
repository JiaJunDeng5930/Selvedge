use std::sync::LazyLock;
use std::time::Duration;

use selvedge_local_client::{LocalClientConfig, LocalClientError, LocalEndpoint};
use selvedge_local_protocol::{
    AttachRejectReason, AttachRejected, CommandOutcome, CommandRejectReason, CommandRequest,
    CommandResponse, LocalClientCommandId, LocalClientFrame, LocalClientSnapshotFrame,
    LocalClientSubscription, LocalDetailLevel, LocalTaskScope, ReadyResponse, ReadyState,
};
use selvedge_test_support::local_transport::{
    AttachAction, CommandAction, FakeLocalTransport as FakeTransport, FakeTransportState,
    ReadyAction, empty_local_snapshot as empty_snapshot, install_connect_plan,
    noop_command as valid_command, ready_state,
};
use tokio::sync::Mutex as AsyncMutex;

use super::{TuiExitStatus, TuiInputAction, TuiStartArgs, run_tui_with_transport};

static TEST_LOCK: LazyLock<AsyncMutex<()>> = LazyLock::new(|| AsyncMutex::new(()));

#[tokio::test]
async fn connect_failure_returns_server_unavailable() {
    let _guard = TEST_LOCK.lock().await;
    install_connect_plan(Err(LocalClientError::ConnectFailed("refused".to_owned())));

    let status = run_tui_with_transport::<FakeTransport, _>(valid_args(None), NoopMapper).await;

    assert_eq!(status, TuiExitStatus::ServerUnavailable);
}

#[tokio::test]
async fn invalid_identifiers_skip_transport_connection() {
    let _guard = TEST_LOCK.lock().await;
    let mut invalid_client = valid_args(None);
    invalid_client.client_id.clear();
    let mut invalid_attach = valid_args(None);
    invalid_attach.attach_command_id.clear();

    for args in [invalid_client, invalid_attach] {
        let state = FakeTransportState::new_handle();
        install_connect_plan(Ok(state.clone()));
        let status = run_tui_with_transport::<FakeTransport, _>(args, NoopMapper).await;

        assert!(matches!(status, TuiExitStatus::InvalidArgs(_)));
        assert!(
            state
                .lock()
                .expect("fake state")
                .connected_configs
                .is_empty()
        );
    }
}

#[tokio::test]
async fn not_ready_returns_server_not_ready() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    state
        .lock()
        .expect("fake state")
        .ready_responses
        .push_back(ReadyAction::Response(Ok(ReadyResponse {
            state: ReadyState::NotReady,
        })));
    install_connect_plan(Ok(state.clone()));

    let status = run_tui_with_transport::<FakeTransport, _>(valid_args(None), NoopMapper).await;

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
            client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
            reason: AttachRejectReason::ServerNotReady,
        }));
    install_connect_plan(Ok(state.clone()));

    let status = run_tui_with_transport::<FakeTransport, _>(valid_args(None), NoopMapper).await;

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
        state_guard
            .command_responses
            .push_back(CommandAction::Response(Ok(CommandResponse {
                client_command_id: LocalClientCommandId::new("command-1").expect("command id"),
                outcome: CommandOutcome::Rejected(CommandRejectReason::UnsupportedCommand),
            })));
    }
    install_connect_plan(Ok(state.clone()));

    let status = run_tui_with_transport::<FakeTransport, _>(
        valid_args(Some(valid_command("command-1"))),
        NoopMapper,
    )
    .await;

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
        state_guard
            .command_responses
            .push_back(CommandAction::Response(Ok(CommandResponse {
                client_command_id: LocalClientCommandId::new("command-1").expect("command id"),
                outcome: CommandOutcome::Accepted,
            })));
    }
    install_connect_plan(Ok(state.clone()));

    let status = run_tui_with_transport::<FakeTransport, _>(
        valid_args(Some(valid_command("command-1"))),
        NoopMapper,
    )
    .await;

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

    let status = run_tui_with_transport::<FakeTransport, _>(valid_args(None), NoopMapper).await;

    assert_eq!(status, TuiExitStatus::Disconnected);
    assert_eq!(state.lock().expect("fake state").close_calls, 1);
}

#[tokio::test]
async fn snapshot_wait_timeout_returns_snapshot_timeout() {
    let _guard = TEST_LOCK.lock().await;
    let state = ready_state();
    state
        .lock()
        .expect("fake state")
        .attach_responses
        .push_back(AttachAction::Pending);
    install_connect_plan(Ok(state.clone()));

    let mut args = valid_args(None);
    args.client_config.request_timeout = Duration::from_millis(5);
    let status = run_tui_with_transport::<FakeTransport, _>(args, NoopMapper).await;

    assert_eq!(status, TuiExitStatus::SnapshotTimeout);
    assert_eq!(state.lock().expect("fake state").close_calls, 1);
}

struct NoopMapper;

impl super::TuiCommandMapper for NoopMapper {
    fn map_input(&self, _input_text: &str) -> Result<TuiInputAction, String> {
        Ok(TuiInputAction::Noop)
    }
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
            snapshot_mode: selvedge_local_protocol::LocalSnapshotMode::CurrentState,
            include_model_call_status: false,
            include_tool_execution_status: false,
            include_debug_notices: false,
        },
        initial_command,
    }
}
