use std::collections::VecDeque;
use std::fs;
use std::future;
use std::sync::{Arc, LazyLock, Mutex};
use std::time::Duration;

use futures_util::StreamExt;
use futures_util::stream;
use selvedge_local_client::{
    AttachRejectedOrClientError, LocalClientConfig, LocalClientError, LocalClientState,
    LocalEndpoint, LocalFrameStream, LocalTransport, connect,
};
use selvedge_local_protocol::{
    AttachAccepted, AttachRejected, AttachRequest, CommandOutcome, CommandRejectReason,
    CommandRequest, CommandResponse, LocalClientCommandId, LocalClientFrame, LocalClientId,
    LocalClientSubscription, LocalDetailLevel, LocalNotice, LocalNoticeLevel, LocalTaskScope,
    ReadyRequest, ReadyResponse, ReadyState, current_protocol_version,
};
use tokio::sync::{Mutex as AsyncMutex, oneshot};
use tokio::time::timeout;

static TEST_LOCK: LazyLock<AsyncMutex<()>> = LazyLock::new(|| AsyncMutex::new(()));
static CONNECT_PLAN: LazyLock<Mutex<Option<Result<FakeTransportStateHandle, LocalClientError>>>> =
    LazyLock::new(|| Mutex::new(None));

type FakeTransportStateHandle = Arc<Mutex<FakeTransportState>>;

#[tokio::test]
async fn connect_validates_structured_localhost_endpoint_before_transport_connect() {
    let _guard = TEST_LOCK.lock().await;
    install_connect_plan(Ok(FakeTransportState::new_handle()));

    let invalid = connect::<FakeTransport>(LocalClientConfig {
        endpoint: LocalEndpoint::TcpIpv4 { port: 0 },
        request_timeout: Duration::from_secs(1),
    })
    .await;

    assert!(matches!(
        invalid,
        Err(LocalClientError::ProtocolValidationFailed(_))
    ));
    assert!(connect_plan_is_some());

    let state = FakeTransportState::new_handle();
    install_connect_plan(Ok(state.clone()));
    let client = connect::<FakeTransport>(LocalClientConfig {
        endpoint: LocalEndpoint::TcpIpv6 { port: 17691 },
        request_timeout: Duration::from_secs(1),
    })
    .await
    .expect("connect client");

    assert_eq!(client.state().await, LocalClientState::Ready);
    assert_eq!(
        state.lock().expect("fake state").connected_configs,
        vec![LocalClientConfig {
            endpoint: LocalEndpoint::TcpIpv6 { port: 17691 },
            request_timeout: Duration::from_secs(1),
        }]
    );
}

#[tokio::test]
async fn connect_failure_returns_transport_connect_error() {
    let _guard = TEST_LOCK.lock().await;
    install_connect_plan(Err(LocalClientError::ConnectFailed("refused".to_owned())));

    let error = match connect::<FakeTransport>(valid_config()).await {
        Ok(_) => panic!("connect should fail"),
        Err(error) => error,
    };

    assert_eq!(error, LocalClientError::ConnectFailed("refused".to_owned()));
}

#[tokio::test]
async fn ready_returns_server_state_and_restores_idle_state() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    state
        .lock()
        .expect("fake state")
        .ready_responses
        .push_back(ReadyAction::Response(Ok(ReadyResponse {
            protocol_version: current_protocol_version(),
            state: ReadyState::NotReady,
        })));
    let client = connected_client(state.clone()).await;

    let response = client
        .ready(ReadyRequest {
            protocol_version: current_protocol_version(),
        })
        .await
        .expect("ready response");

    assert_eq!(response.state, ReadyState::NotReady);
    assert_eq!(client.state().await, LocalClientState::Ready);
    assert_eq!(state.lock().expect("fake state").ready_calls, 1);
}

#[tokio::test]
async fn command_submit_validates_request_before_transport_and_preserves_server_rejection() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    state
        .lock()
        .expect("fake state")
        .command_responses
        .push_back(CommandAction::Response(Ok(CommandResponse {
            protocol_version: current_protocol_version(),
            client_command_id: LocalClientCommandId::new("command-2").expect("command id"),
            outcome: CommandOutcome::Rejected(CommandRejectReason::ServerNotReady),
        })));
    let client = connected_client(state.clone()).await;

    let invalid = client
        .submit_command(CommandRequest {
            command_name: " ".to_owned(),
            ..valid_command("command-1")
        })
        .await;
    assert!(matches!(
        invalid,
        Err(LocalClientError::ProtocolValidationFailed(_))
    ));
    assert_eq!(state.lock().expect("fake state").command_calls, 0);

    let response = client
        .submit_command(valid_command("command-2"))
        .await
        .expect("command response");
    assert_eq!(
        response.outcome,
        CommandOutcome::Rejected(CommandRejectReason::ServerNotReady)
    );
    assert_eq!(client.state().await, LocalClientState::Ready);
    assert_eq!(state.lock().expect("fake state").command_calls, 1);
}

#[tokio::test]
async fn transport_closed_error_moves_client_to_failed_state() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    state
        .lock()
        .expect("fake state")
        .command_responses
        .push_back(CommandAction::Response(Err(
            LocalClientError::TransportClosed,
        )));
    let client = connected_client(state).await;

    let error = client.submit_command(valid_command("command-1")).await;

    assert_eq!(error, Err(LocalClientError::TransportClosed));
    assert_eq!(client.state().await, LocalClientState::Failed);
    assert_eq!(
        client
            .ready(ReadyRequest {
                protocol_version: current_protocol_version(),
            })
            .await,
        Err(LocalClientError::TransportClosed)
    );
}

#[tokio::test]
async fn cancelling_pending_command_restores_ready_state() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    state
        .lock()
        .expect("fake state")
        .command_responses
        .push_back(CommandAction::Hang);
    let client = connected_client(state).await;

    let mut command = Box::pin(client.submit_command(valid_command("command-1")));
    assert!(
        timeout(Duration::from_millis(5), command.as_mut())
            .await
            .is_err()
    );
    assert_eq!(client.state().await, LocalClientState::CommandPending);
    assert_eq!(
        client
            .ready(ReadyRequest {
                protocol_version: current_protocol_version(),
            })
            .await,
        Err(LocalClientError::Busy)
    );

    drop(command);
    assert_eq!(client.state().await, LocalClientState::Ready);
}

#[tokio::test]
async fn cancelling_pending_attach_restores_ready_state() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    state
        .lock()
        .expect("fake state")
        .attach_responses
        .push_back(AttachAction::Hang);
    let client = connected_client(state).await;

    let mut attach = Box::pin(client.attach(valid_attach("attach-1")));
    assert!(
        timeout(Duration::from_millis(5), attach.as_mut())
            .await
            .is_err()
    );
    assert_eq!(client.state().await, LocalClientState::AttachPending);
    assert!(matches!(
        client.submit_command(valid_command("command-1")).await,
        Err(LocalClientError::Busy)
    ));

    drop(attach);
    assert_eq!(client.state().await, LocalClientState::Ready);
}

#[tokio::test]
async fn request_timeout_sets_failed_state_and_recent_error() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    state
        .lock()
        .expect("fake state")
        .ready_responses
        .push_back(ReadyAction::Hang);
    let client = connected_client_with_timeout(state, Duration::from_millis(5)).await;

    let error = client
        .ready(ReadyRequest {
            protocol_version: current_protocol_version(),
        })
        .await;

    assert_eq!(error, Err(LocalClientError::Timeout));
    assert_eq!(client.state().await, LocalClientState::Failed);
    assert_eq!(
        client
            .submit_command(valid_command("after-timeout"))
            .await
            .expect_err("failed client returns recent error"),
        LocalClientError::Timeout
    );
}

#[tokio::test]
async fn attach_allows_one_active_stream_and_reports_stream_closed_after_ordered_frames() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    state
        .lock()
        .expect("fake state")
        .attach_responses
        .push_back(AttachAction::Response(Ok((
            AttachAccepted {
                protocol_version: current_protocol_version(),
                client_id: LocalClientId::new("client-1").expect("client id"),
                client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
            },
            Box::pin(stream::iter(vec![Ok(notice_frame(1)), Ok(notice_frame(2))])),
        ))));
    let client = connected_client(state.clone()).await;

    let (_accepted, mut frames) = client
        .attach(valid_attach("attach-1"))
        .await
        .expect("attach");
    assert_eq!(client.state().await, LocalClientState::Attached);
    assert!(matches!(
        client.attach(valid_attach("attach-2")).await,
        Err(AttachRejectedOrClientError::Client(
            LocalClientError::AlreadyAttached
        ))
    ));

    assert_eq!(next_seq(&mut frames).await, Ok(1));
    assert_eq!(next_seq(&mut frames).await, Ok(2));
    assert_eq!(
        frames.next().await,
        Some(Err(LocalClientError::StreamClosed))
    );
    assert_eq!(frames.next().await, None);
    assert_eq!(client.state().await, LocalClientState::Ready);
    assert_eq!(state.lock().expect("fake state").attach_calls, 1);
}

#[tokio::test]
async fn attach_closure_during_pending_command_restores_ready_after_command_cancel() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    {
        let mut state = state.lock().expect("fake state");
        state.attach_responses.push_back(AttachAction::Response(Ok((
            AttachAccepted {
                protocol_version: current_protocol_version(),
                client_id: LocalClientId::new("client-1").expect("client id"),
                client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
            },
            Box::pin(stream::pending()),
        ))));
        state.command_responses.push_back(CommandAction::Hang);
        state.attach_responses.push_back(AttachAction::Response(Ok((
            AttachAccepted {
                protocol_version: current_protocol_version(),
                client_id: LocalClientId::new("client-1").expect("client id"),
                client_command_id: LocalClientCommandId::new("attach-2").expect("command id"),
            },
            Box::pin(stream::empty()),
        ))));
    }
    let client = connected_client(state.clone()).await;
    let (_accepted, frames) = client
        .attach(valid_attach("attach-1"))
        .await
        .expect("attach");

    let mut command = Box::pin(client.submit_command(valid_command("command-1")));
    assert!(
        timeout(Duration::from_millis(5), command.as_mut())
            .await
            .is_err()
    );
    assert_eq!(client.state().await, LocalClientState::CommandPending);

    drop(frames);
    drop(command);

    assert_eq!(client.state().await, LocalClientState::Ready);
    let (_accepted, _frames) = client
        .attach(valid_attach("attach-2"))
        .await
        .expect("reattach");
    assert_eq!(state.lock().expect("fake state").attach_calls, 2);
}

#[tokio::test]
async fn attach_closure_during_pending_command_restores_ready_after_command_success() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    let (release_tx, release_rx) = oneshot::channel();
    {
        let mut state = state.lock().expect("fake state");
        state.attach_responses.push_back(AttachAction::Response(Ok((
            AttachAccepted {
                protocol_version: current_protocol_version(),
                client_id: LocalClientId::new("client-1").expect("client id"),
                client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
            },
            Box::pin(stream::pending()),
        ))));
        state
            .command_responses
            .push_back(CommandAction::WaitForRelease {
                release_rx,
                response: Ok(CommandResponse {
                    protocol_version: current_protocol_version(),
                    client_command_id: LocalClientCommandId::new("command-1").expect("command id"),
                    outcome: CommandOutcome::Accepted,
                }),
            });
        state.attach_responses.push_back(AttachAction::Response(Ok((
            AttachAccepted {
                protocol_version: current_protocol_version(),
                client_id: LocalClientId::new("client-1").expect("client id"),
                client_command_id: LocalClientCommandId::new("attach-2").expect("command id"),
            },
            Box::pin(stream::empty()),
        ))));
    }
    let client = connected_client(state.clone()).await;
    let (_accepted, frames) = client
        .attach(valid_attach("attach-1"))
        .await
        .expect("attach");

    let mut command = Box::pin(client.submit_command(valid_command("command-1")));
    assert!(
        timeout(Duration::from_millis(5), command.as_mut())
            .await
            .is_err()
    );
    drop(frames);
    release_tx.send(()).expect("release command");
    command.await.expect("command response");

    assert_eq!(client.state().await, LocalClientState::Ready);
    let (_accepted, _frames) = client
        .attach(valid_attach("attach-2"))
        .await
        .expect("reattach");
    assert_eq!(state.lock().expect("fake state").attach_calls, 2);
}

#[tokio::test]
async fn dropping_exhausted_old_stream_does_not_clear_newer_attach_stream() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    {
        let mut state = state.lock().expect("fake state");
        state.attach_responses.push_back(AttachAction::Response(Ok((
            AttachAccepted {
                protocol_version: current_protocol_version(),
                client_id: LocalClientId::new("client-1").expect("client id"),
                client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
            },
            Box::pin(stream::empty()),
        ))));
        state.attach_responses.push_back(AttachAction::Response(Ok((
            AttachAccepted {
                protocol_version: current_protocol_version(),
                client_id: LocalClientId::new("client-1").expect("client id"),
                client_command_id: LocalClientCommandId::new("attach-2").expect("command id"),
            },
            Box::pin(stream::pending()),
        ))));
        state.attach_responses.push_back(AttachAction::Response(Ok((
            AttachAccepted {
                protocol_version: current_protocol_version(),
                client_id: LocalClientId::new("client-1").expect("client id"),
                client_command_id: LocalClientCommandId::new("attach-3").expect("command id"),
            },
            Box::pin(stream::empty()),
        ))));
    }
    let client = connected_client(state.clone()).await;
    let (_accepted, mut old_frames) = client
        .attach(valid_attach("attach-1"))
        .await
        .expect("attach");
    assert_eq!(
        old_frames.next().await,
        Some(Err(LocalClientError::StreamClosed))
    );
    assert_eq!(client.state().await, LocalClientState::Ready);

    let (_accepted, _new_frames) = client
        .attach(valid_attach("attach-2"))
        .await
        .expect("second attach");
    drop(old_frames);

    assert_eq!(client.state().await, LocalClientState::Attached);
    assert!(matches!(
        client.attach(valid_attach("attach-3")).await,
        Err(AttachRejectedOrClientError::Client(
            LocalClientError::AlreadyAttached
        ))
    ));
    assert_eq!(state.lock().expect("fake state").attach_calls, 2);
}

#[tokio::test]
async fn attach_validates_request_before_transport() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    let client = connected_client(state.clone()).await;

    let error = client
        .attach(AttachRequest {
            subscription: LocalClientSubscription {
                task_scope: LocalTaskScope::TaskIds(vec![" ".to_owned()]),
                ..valid_attach("attach-1").subscription
            },
            ..valid_attach("attach-1")
        })
        .await;

    assert!(matches!(
        error,
        Err(AttachRejectedOrClientError::Client(
            LocalClientError::ProtocolValidationFailed(_)
        ))
    ));
    assert_eq!(state.lock().expect("fake state").attach_calls, 0);
    assert_eq!(client.state().await, LocalClientState::Ready);
}

#[tokio::test]
async fn attach_rejection_restores_idle_state() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    state
        .lock()
        .expect("fake state")
        .attach_responses
        .push_back(AttachAction::Response(Err(
            AttachRejectedOrClientError::Rejected(AttachRejected {
                protocol_version: current_protocol_version(),
                client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
                reason: CommandRejectReason::ServerNotReady,
            }),
        )));
    let client = connected_client(state).await;

    let rejected = match client.attach(valid_attach("attach-1")).await {
        Ok(_) => panic!("attach should be rejected"),
        Err(rejected) => rejected,
    };

    assert!(matches!(
        rejected,
        AttachRejectedOrClientError::Rejected(AttachRejected {
            reason: CommandRejectReason::ServerNotReady,
            ..
        })
    ));
    assert_eq!(client.state().await, LocalClientState::Ready);
}

#[tokio::test]
async fn close_closes_transport_and_later_methods_return_closed() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    let client = connected_client(state.clone()).await;

    client.close().await.expect("close client");

    assert_eq!(client.state().await, LocalClientState::Closed);
    assert_eq!(state.lock().expect("fake state").close_calls, 1);
    assert_eq!(
        client
            .ready(ReadyRequest {
                protocol_version: current_protocol_version(),
            })
            .await,
        Err(LocalClientError::Closed)
    );
}

#[tokio::test]
async fn cancelling_pending_close_restores_previous_state() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    state.lock().expect("fake state").close_action = CloseAction::Hang;
    let client = connected_client(state).await;

    let mut close = Box::pin(client.close());
    assert!(
        timeout(Duration::from_millis(5), close.as_mut())
            .await
            .is_err()
    );
    assert_eq!(client.state().await, LocalClientState::Closing);

    drop(close);

    assert_eq!(client.state().await, LocalClientState::Ready);
    assert_eq!(
        client
            .ready(ReadyRequest {
                protocol_version: current_protocol_version(),
            })
            .await
            .expect("ready after close cancellation")
            .state,
        ReadyState::Ready
    );
}

#[test]
fn crate_has_no_systemd_dependency() {
    let manifest = fs::read_to_string(format!("{}/Cargo.toml", env!("CARGO_MANIFEST_DIR")))
        .expect("read manifest");

    assert!(!manifest.contains("systemd"));
}

#[derive(Clone)]
struct FakeTransport {
    state: FakeTransportStateHandle,
}

struct FakeTransportState {
    connected_configs: Vec<LocalClientConfig>,
    ready_calls: usize,
    command_calls: usize,
    attach_calls: usize,
    close_calls: usize,
    close_action: CloseAction,
    ready_responses: VecDeque<ReadyAction>,
    command_responses: VecDeque<CommandAction>,
    attach_responses: VecDeque<AttachAction>,
}

#[derive(Clone, Copy)]
enum CloseAction {
    Complete,
    Hang,
}

enum ReadyAction {
    Response(Result<ReadyResponse, LocalClientError>),
    Hang,
}

enum CommandAction {
    Response(Result<CommandResponse, LocalClientError>),
    WaitForRelease {
        release_rx: oneshot::Receiver<()>,
        response: Result<CommandResponse, LocalClientError>,
    },
    Hang,
}

enum AttachAction {
    Response(Result<(AttachAccepted, LocalFrameStream), AttachRejectedOrClientError>),
    Hang,
}

impl FakeTransportState {
    fn new_handle() -> FakeTransportStateHandle {
        Arc::new(Mutex::new(Self {
            connected_configs: Vec::new(),
            ready_calls: 0,
            command_calls: 0,
            attach_calls: 0,
            close_calls: 0,
            close_action: CloseAction::Complete,
            ready_responses: VecDeque::new(),
            command_responses: VecDeque::new(),
            attach_responses: VecDeque::new(),
        }))
    }
}

impl LocalTransport for FakeTransport {
    async fn connect(config: LocalClientConfig) -> Result<Self, LocalClientError> {
        let state = CONNECT_PLAN
            .lock()
            .expect("connect plan lock")
            .take()
            .expect("connect plan installed")?;
        state
            .lock()
            .expect("fake state")
            .connected_configs
            .push(config);
        Ok(Self { state })
    }

    async fn ready(&self, _request: ReadyRequest) -> Result<ReadyResponse, LocalClientError> {
        let action = {
            let mut state = self.state.lock().expect("fake state");
            state.ready_calls += 1;
            state
                .ready_responses
                .pop_front()
                .unwrap_or(ReadyAction::Response(Ok(ReadyResponse {
                    protocol_version: current_protocol_version(),
                    state: ReadyState::Ready,
                })))
        };

        match action {
            ReadyAction::Response(response) => response,
            ReadyAction::Hang => future::pending().await,
        }
    }

    async fn submit_command(
        &self,
        _request: CommandRequest,
    ) -> Result<CommandResponse, LocalClientError> {
        let action = {
            let mut state = self.state.lock().expect("fake state");
            state.command_calls += 1;
            state.command_responses.pop_front().unwrap_or_else(|| {
                CommandAction::Response(Ok(CommandResponse {
                    protocol_version: current_protocol_version(),
                    client_command_id: LocalClientCommandId::new("command-1").expect("command id"),
                    outcome: CommandOutcome::Accepted,
                }))
            })
        };

        match action {
            CommandAction::Response(response) => response,
            CommandAction::WaitForRelease {
                release_rx,
                response,
            } => {
                let _ = release_rx.await;
                response
            }
            CommandAction::Hang => future::pending().await,
        }
    }

    async fn attach(
        &self,
        _request: AttachRequest,
    ) -> Result<(AttachAccepted, LocalFrameStream), AttachRejectedOrClientError> {
        let action = {
            let mut state = self.state.lock().expect("fake state");
            state.attach_calls += 1;
            state.attach_responses.pop_front().unwrap_or_else(|| {
                AttachAction::Response(Ok((
                    AttachAccepted {
                        protocol_version: current_protocol_version(),
                        client_id: LocalClientId::new("client-1").expect("client id"),
                        client_command_id: LocalClientCommandId::new("attach-1")
                            .expect("command id"),
                    },
                    Box::pin(stream::empty()),
                )))
            })
        };

        match action {
            AttachAction::Response(response) => response,
            AttachAction::Hang => future::pending().await,
        }
    }

    async fn close(&self) {
        let action = {
            let mut state = self.state.lock().expect("fake state");
            state.close_calls += 1;
            state.close_action
        };

        match action {
            CloseAction::Complete => {}
            CloseAction::Hang => future::pending().await,
        }
    }
}

async fn connected_client(
    state: FakeTransportStateHandle,
) -> selvedge_local_client::LocalClient<FakeTransport> {
    connected_client_with_timeout(state, Duration::from_secs(1)).await
}

async fn connected_client_with_timeout(
    state: FakeTransportStateHandle,
    request_timeout: Duration,
) -> selvedge_local_client::LocalClient<FakeTransport> {
    install_connect_plan(Ok(state));
    connect::<FakeTransport>(LocalClientConfig {
        endpoint: LocalEndpoint::TcpIpv4 { port: 17691 },
        request_timeout,
    })
    .await
    .expect("connect client")
}

fn install_connect_plan(plan: Result<FakeTransportStateHandle, LocalClientError>) {
    *CONNECT_PLAN.lock().expect("connect plan lock") = Some(plan);
}

fn connect_plan_is_some() -> bool {
    CONNECT_PLAN.lock().expect("connect plan lock").is_some()
}

fn valid_config() -> LocalClientConfig {
    LocalClientConfig {
        endpoint: LocalEndpoint::TcpIpv4 { port: 17691 },
        request_timeout: Duration::from_secs(1),
    }
}

fn valid_command(command_id: &str) -> CommandRequest {
    CommandRequest {
        protocol_version: current_protocol_version(),
        client_id: LocalClientId::new("client-1").expect("client id"),
        client_command_id: LocalClientCommandId::new(command_id).expect("command id"),
        command_name: "send-user-input".to_owned(),
        payload: serde_json::json!({"message": "hello"}),
    }
}

fn valid_attach(command_id: &str) -> AttachRequest {
    AttachRequest {
        protocol_version: current_protocol_version(),
        client_id: LocalClientId::new("client-1").expect("client id"),
        client_command_id: LocalClientCommandId::new(command_id).expect("command id"),
        subscription: LocalClientSubscription {
            task_scope: LocalTaskScope::AllTasks,
            detail_level: LocalDetailLevel::Summary,
            include_model_call_status: false,
            include_tool_execution_status: false,
            include_debug_notices: false,
        },
    }
}

fn notice_frame(seq: u64) -> LocalClientFrame {
    LocalClientFrame::Notice(selvedge_local_protocol::LocalClientNoticeFrame {
        delivery_seq: seq,
        client_command_id: LocalClientCommandId::new(format!("notice-{seq}")).expect("command id"),
        notice: LocalNotice {
            level: LocalNoticeLevel::Info,
            message_text: format!("notice {seq}"),
        },
    })
}

async fn next_seq(stream: &mut LocalFrameStream) -> Result<u64, LocalClientError> {
    match stream.next().await {
        Some(Ok(LocalClientFrame::Notice(frame))) => Ok(frame.delivery_seq),
        Some(Ok(_)) => Err(LocalClientError::TransportFailed(
            "unexpected frame kind".to_owned(),
        )),
        Some(Err(error)) => Err(error),
        None => Err(LocalClientError::StreamClosed),
    }
}
