use std::fs;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, LazyLock};
use std::time::Duration;

use futures_util::StreamExt;
use futures_util::stream;
use selvedge_local_client::{
    AttachRejectedOrClientError, LocalClientConfig, LocalClientError, LocalClientState,
    LocalEndpoint, connect, connect_http,
};
use selvedge_local_protocol::{
    AttachAccepted, AttachRejectReason, AttachRejected, AttachRequest, CommandOutcome,
    CommandRejectReason, CommandRequest, CommandResponse, LocalClientCommandId, LocalClientId,
    LocalClientSubscription, LocalTaskScope, ReadyRequest, ReadyResponse, ReadyState,
    current_protocol_version,
};
use selvedge_test_support::local_transport::{
    AttachAction, CloseAction, CommandAction, DropNotifyingStream,
    FakeLocalTransport as FakeTransport, FakeTransportState, PollNotifyingStream, ReadyAction,
    connect_plan_is_some, connected_client, connected_client_with_timeout, install_connect_plan,
    next_seq, notice_frame, valid_attach, valid_command, valid_config,
};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{Mutex as AsyncMutex, oneshot};
use tokio::task::JoinHandle;
use tokio::time::timeout;

static TEST_LOCK: LazyLock<AsyncMutex<()>> = LazyLock::new(|| AsyncMutex::new(()));

#[tokio::test]
async fn connect_validates_structured_localhost_endpoint_before_transport_connect() {
    let _guard = TEST_LOCK.lock().await;
    install_connect_plan(Ok(FakeTransportState::new_handle()));

    let invalid = connect::<FakeTransport>(LocalClientConfig {
        endpoint: LocalEndpoint::TcpIpv4 { port: 0 },
        request_timeout: Duration::from_secs(1),
    })
    .await;

    // @verifies selvedge.client.local
    assert!(matches!(
        invalid,
        Err(LocalClientError::ProtocolValidationFailed(_))
    ));
    // @verifies selvedge.client.local
    assert!(connect_plan_is_some());

    let state = FakeTransportState::new_handle();
    install_connect_plan(Ok(state.clone()));
    let client = connect::<FakeTransport>(LocalClientConfig {
        endpoint: LocalEndpoint::TcpIpv6 { port: 17691 },
        request_timeout: Duration::from_secs(1),
    })
    .await
    .expect("connect client");

    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Ready);
    // @verifies selvedge.client.local
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

    // @verifies selvedge.client.local
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

    // @verifies selvedge.client.local
    assert_eq!(response.state, ReadyState::NotReady);
    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Ready);
    // @verifies selvedge.client.local
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
    // @verifies selvedge.client.local
    assert!(matches!(
        invalid,
        Err(LocalClientError::ProtocolValidationFailed(_))
    ));
    // @verifies selvedge.client.local
    assert_eq!(state.lock().expect("fake state").command_calls, 0);

    let response = client
        .submit_command(valid_command("command-2"))
        .await
        .expect("command response");
    // @verifies selvedge.client.local
    assert_eq!(
        response.outcome,
        CommandOutcome::Rejected(CommandRejectReason::ServerNotReady)
    );
    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Ready);
    // @verifies selvedge.client.local
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

    // @verifies selvedge.client.local
    assert_eq!(error, Err(LocalClientError::TransportClosed));
    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Failed);
    // @verifies selvedge.client.local
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
    // @verifies selvedge.client.local
    assert!(
        timeout(Duration::from_millis(5), command.as_mut())
            .await
            .is_err()
    );
    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::CommandPending);
    // @verifies selvedge.client.local
    assert_eq!(
        client
            .ready(ReadyRequest {
                protocol_version: current_protocol_version(),
            })
            .await,
        Err(LocalClientError::Busy)
    );

    drop(command);
    // @verifies selvedge.client.local
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
    // @verifies selvedge.client.local
    assert!(
        timeout(Duration::from_millis(5), attach.as_mut())
            .await
            .is_err()
    );
    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::AttachPending);
    // @verifies selvedge.client.local
    assert!(matches!(
        client.submit_command(valid_command("command-1")).await,
        Err(LocalClientError::Busy)
    ));

    drop(attach);
    // @verifies selvedge.client.local
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

    // @verifies selvedge.client.local
    assert_eq!(error, Err(LocalClientError::Timeout));
    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Failed);
    // @verifies selvedge.client.local
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
    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Attached);
    // @verifies selvedge.client.local
    assert!(matches!(
        client.attach(valid_attach("attach-2")).await,
        Err(AttachRejectedOrClientError::Client(
            LocalClientError::AlreadyAttached
        ))
    ));

    // @verifies selvedge.client.local
    assert_eq!(next_seq(&mut frames).await, Ok(1));
    // @verifies selvedge.client.local
    assert_eq!(next_seq(&mut frames).await, Ok(2));
    // @verifies selvedge.client.local
    assert_eq!(
        frames.next().await,
        Some(Err(LocalClientError::StreamClosed))
    );
    // @verifies selvedge.client.local
    assert_eq!(frames.next().await, None);
    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Ready);
    // @verifies selvedge.client.local
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
    // @verifies selvedge.client.local
    assert!(
        timeout(Duration::from_millis(5), command.as_mut())
            .await
            .is_err()
    );
    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::CommandPending);

    drop(frames);
    drop(command);

    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Ready);
    let (_accepted, _frames) = client
        .attach(valid_attach("attach-2"))
        .await
        .expect("reattach");
    // @verifies selvedge.client.local
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
    // @verifies selvedge.client.local
    assert!(
        timeout(Duration::from_millis(5), command.as_mut())
            .await
            .is_err()
    );
    drop(frames);
    release_tx.send(()).expect("release command");
    command.await.expect("command response");

    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Ready);
    let (_accepted, _frames) = client
        .attach(valid_attach("attach-2"))
        .await
        .expect("reattach");
    // @verifies selvedge.client.local
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
    // @verifies selvedge.client.local
    assert_eq!(
        old_frames.next().await,
        Some(Err(LocalClientError::StreamClosed))
    );
    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Ready);

    let (_accepted, _new_frames) = client
        .attach(valid_attach("attach-2"))
        .await
        .expect("second attach");
    drop(old_frames);

    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Attached);
    // @verifies selvedge.client.local
    assert!(matches!(
        client.attach(valid_attach("attach-3")).await,
        Err(AttachRejectedOrClientError::Client(
            LocalClientError::AlreadyAttached
        ))
    ));
    // @verifies selvedge.client.local
    assert_eq!(state.lock().expect("fake state").attach_calls, 2);
}

#[tokio::test]
async fn attach_stream_error_clears_attached_state_before_returning_error() {
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
            Box::pin(stream::iter(vec![Err(LocalClientError::TransportClosed)])),
        ))));
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
    let (_accepted, mut frames) = client
        .attach(valid_attach("attach-1"))
        .await
        .expect("attach");

    // @verifies selvedge.client.local
    assert_eq!(
        frames.next().await,
        Some(Err(LocalClientError::TransportClosed))
    );
    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Ready);

    let (_accepted, _frames) = client
        .attach(valid_attach("attach-2"))
        .await
        .expect("reattach");
    // @verifies selvedge.client.local
    assert_eq!(state.lock().expect("fake state").attach_calls, 2);
}

#[tokio::test]
async fn request_failure_drops_active_attach_inner_stream() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    let drops = Arc::new(AtomicUsize::new(0));
    {
        let mut state = state.lock().expect("fake state");
        state.attach_responses.push_back(AttachAction::Response(Ok((
            AttachAccepted {
                protocol_version: current_protocol_version(),
                client_id: LocalClientId::new("client-1").expect("client id"),
                client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
            },
            Box::pin(DropNotifyingStream {
                drops: Arc::clone(&drops),
            }),
        ))));
        state
            .command_responses
            .push_back(CommandAction::Response(Err(
                LocalClientError::TransportClosed,
            )));
    }
    let client = connected_client(state).await;
    let (_accepted, mut frames) = client
        .attach(valid_attach("attach-1"))
        .await
        .expect("attach");

    // @verifies selvedge.client.local
    assert_eq!(
        client.submit_command(valid_command("command-1")).await,
        Err(LocalClientError::TransportClosed)
    );

    // @verifies selvedge.client.local
    assert_eq!(drops.load(Ordering::SeqCst), 1);
    // @verifies selvedge.client.local
    assert_eq!(frames.next().await, None);
    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Failed);
}

#[tokio::test]
async fn close_returns_busy_while_request_is_pending() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    state
        .lock()
        .expect("fake state")
        .command_responses
        .push_back(CommandAction::Hang);
    let client = connected_client(state).await;
    let mut command = Box::pin(client.submit_command(valid_command("command-1")));
    // @verifies selvedge.client.local
    assert!(
        timeout(Duration::from_millis(5), command.as_mut())
            .await
            .is_err()
    );

    // @verifies selvedge.client.local
    assert_eq!(client.close().await, Err(LocalClientError::Busy));
    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::CommandPending);

    drop(command);
    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Ready);
}

#[tokio::test]
async fn cancelling_close_after_stream_drop_restores_ready_state() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    {
        let mut state = state.lock().expect("fake state");
        state.close_action = CloseAction::Hang;
        state.attach_responses.push_back(AttachAction::Response(Ok((
            AttachAccepted {
                protocol_version: current_protocol_version(),
                client_id: LocalClientId::new("client-1").expect("client id"),
                client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
            },
            Box::pin(stream::pending()),
        ))));
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
    let mut close = Box::pin(client.close());
    // @verifies selvedge.client.local
    assert!(
        timeout(Duration::from_millis(5), close.as_mut())
            .await
            .is_err()
    );

    drop(frames);
    drop(close);

    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Ready);
    let (_accepted, _frames) = client
        .attach(valid_attach("attach-2"))
        .await
        .expect("reattach after close cancellation");
    // @verifies selvedge.client.local
    assert_eq!(state.lock().expect("fake state").attach_calls, 2);
}

#[tokio::test]
async fn cancelling_close_with_live_stream_restores_attached_state() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    {
        let mut state = state.lock().expect("fake state");
        state.close_action = CloseAction::Hang;
        state.attach_responses.push_back(AttachAction::Response(Ok((
            AttachAccepted {
                protocol_version: current_protocol_version(),
                client_id: LocalClientId::new("client-1").expect("client id"),
                client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
            },
            Box::pin(stream::pending()),
        ))));
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
    let (_accepted, _frames) = client
        .attach(valid_attach("attach-1"))
        .await
        .expect("attach");
    let mut close = Box::pin(client.close());
    // @verifies selvedge.client.local
    assert!(
        timeout(Duration::from_millis(5), close.as_mut())
            .await
            .is_err()
    );

    drop(close);

    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Attached);
    // @verifies selvedge.client.local
    assert!(matches!(
        client.attach(valid_attach("attach-2")).await,
        Err(AttachRejectedOrClientError::Client(
            LocalClientError::AlreadyAttached
        ))
    ));
    // @verifies selvedge.client.local
    assert_eq!(state.lock().expect("fake state").attach_calls, 1);
}

#[tokio::test]
async fn attach_stream_error_terminates_old_stream() {
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
            Box::pin(stream::iter(vec![
                Err(LocalClientError::TransportClosed),
                Ok(notice_frame(1)),
            ])),
        ))));
        state.attach_responses.push_back(AttachAction::Response(Ok((
            AttachAccepted {
                protocol_version: current_protocol_version(),
                client_id: LocalClientId::new("client-1").expect("client id"),
                client_command_id: LocalClientCommandId::new("attach-2").expect("command id"),
            },
            Box::pin(stream::pending()),
        ))));
    }
    let client = connected_client(state).await;
    let (_accepted, mut old_frames) = client
        .attach(valid_attach("attach-1"))
        .await
        .expect("attach");
    // @verifies selvedge.client.local
    assert_eq!(
        old_frames.next().await,
        Some(Err(LocalClientError::TransportClosed))
    );
    let (_accepted, _new_frames) = client
        .attach(valid_attach("attach-2"))
        .await
        .expect("reattach");

    // @verifies selvedge.client.local
    assert_eq!(old_frames.next().await, None);
    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Attached);
}

#[tokio::test]
async fn attach_stream_error_fuses_even_when_inner_stream_stays_pending() {
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
            Box::pin(
                stream::iter(vec![Err(LocalClientError::TransportClosed)]).chain(stream::pending()),
            ),
        ))));
    let client = connected_client(state).await;
    let (_accepted, mut frames) = client
        .attach(valid_attach("attach-1"))
        .await
        .expect("attach");

    // @verifies selvedge.client.local
    assert_eq!(
        frames.next().await,
        Some(Err(LocalClientError::TransportClosed))
    );
    // @verifies selvedge.client.local
    assert_eq!(
        timeout(Duration::from_millis(5), frames.next()).await,
        Ok(None)
    );
}

#[tokio::test]
async fn cancelled_close_from_failed_state_preserves_recent_error() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    {
        let mut state = state.lock().expect("fake state");
        state.close_action = CloseAction::Hang;
        state.ready_responses.push_back(ReadyAction::Hang);
    }
    let client = connected_client_with_timeout(state, Duration::from_millis(5)).await;
    // @verifies selvedge.client.local
    assert_eq!(
        client
            .ready(ReadyRequest {
                protocol_version: current_protocol_version(),
            })
            .await,
        Err(LocalClientError::Timeout)
    );
    let mut close = Box::pin(client.close());
    // @verifies selvedge.client.local
    assert!(
        timeout(Duration::from_millis(5), close.as_mut())
            .await
            .is_err()
    );

    drop(close);

    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Failed);
    // @verifies selvedge.client.local
    assert_eq!(
        client
            .submit_command(valid_command("after-failed-close"))
            .await,
        Err(LocalClientError::Timeout)
    );
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

    // @verifies selvedge.client.local
    assert!(matches!(
        error,
        Err(AttachRejectedOrClientError::Client(
            LocalClientError::ProtocolValidationFailed(_)
        ))
    ));
    // @verifies selvedge.client.local
    assert_eq!(state.lock().expect("fake state").attach_calls, 0);
    // @verifies selvedge.client.local
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
                reason: AttachRejectReason::ServerNotReady,
            }),
        )));
    let client = connected_client(state).await;

    let rejected = match client.attach(valid_attach("attach-1")).await {
        Ok(_) => panic!("attach should be rejected"),
        Err(rejected) => rejected,
    };

    // @verifies selvedge.client.local
    assert!(matches!(
        rejected,
        AttachRejectedOrClientError::Rejected(AttachRejected {
            reason: AttachRejectReason::ServerNotReady,
            ..
        })
    ));
    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Ready);
}

#[tokio::test]
async fn close_closes_transport_and_later_methods_return_closed() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    let client = connected_client(state.clone()).await;

    client.close().await.expect("close client");

    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Closed);
    // @verifies selvedge.client.local
    assert_eq!(state.lock().expect("fake state").close_calls, 1);
    // @verifies selvedge.client.local
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
async fn close_fuses_existing_attach_stream() {
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
            Box::pin(stream::iter(vec![Ok(notice_frame(1))])),
        ))));
    let client = connected_client(state).await;
    let (_accepted, mut frames) = client
        .attach(valid_attach("attach-1"))
        .await
        .expect("attach");

    client.close().await.expect("close client");

    // @verifies selvedge.client.local
    assert_eq!(frames.next().await, None);
    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Closed);
}

#[tokio::test]
async fn close_drops_active_attach_inner_stream() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    let drops = Arc::new(AtomicUsize::new(0));
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
            Box::pin(DropNotifyingStream {
                drops: Arc::clone(&drops),
            }),
        ))));
    let client = connected_client(state).await;
    let (_accepted, mut frames) = client
        .attach(valid_attach("attach-1"))
        .await
        .expect("attach");

    // @verifies selvedge.client.local
    assert_eq!(drops.load(Ordering::SeqCst), 0);

    client.close().await.expect("close client");

    // @verifies selvedge.client.local
    assert_eq!(drops.load(Ordering::SeqCst), 1);
    // @verifies selvedge.client.local
    assert_eq!(frames.next().await, None);
    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Closed);
}

#[tokio::test]
async fn close_wakes_pending_attach_reader() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    let (polled_tx, polled_rx) = oneshot::channel();
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
            Box::pin(PollNotifyingStream {
                polled: Some(polled_tx),
            }),
        ))));
    let client = connected_client(state).await;
    let (_accepted, mut frames) = client
        .attach(valid_attach("attach-1"))
        .await
        .expect("attach");
    let reader = tokio::spawn(async move { frames.next().await });

    polled_rx.await.expect("reader polls attach stream");
    client.close().await.expect("close client");

    let next = timeout(Duration::from_secs(1), reader)
        .await
        .expect("reader wakes after close")
        .expect("reader task joins");
    // @verifies selvedge.client.local
    assert_eq!(next, None);
}

#[tokio::test]
async fn cancelling_pending_close_restores_previous_state() {
    let _guard = TEST_LOCK.lock().await;
    let state = FakeTransportState::new_handle();
    state.lock().expect("fake state").close_action = CloseAction::Hang;
    let client = connected_client(state).await;

    let mut close = Box::pin(client.close());
    // @verifies selvedge.client.local
    assert!(
        timeout(Duration::from_millis(5), close.as_mut())
            .await
            .is_err()
    );
    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Closing);

    drop(close);

    // @verifies selvedge.client.local
    assert_eq!(client.state().await, LocalClientState::Ready);
    // @verifies selvedge.client.local
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

#[tokio::test]
async fn http_transport_posts_ready_to_local_protocol_route() {
    let _guard = TEST_LOCK.lock().await;
    let body = serde_json::to_vec(&ReadyResponse {
        protocol_version: current_protocol_version(),
        state: ReadyState::Ready,
    })
    .expect("ready response json");
    let (port, server) =
        spawn_http_contract_server(vec![None, Some(HttpContractResponse::json(200, body))]).await;
    let client = connect_http(http_config(port))
        .await
        .expect("connect http client");

    let response = client
        .ready(ReadyRequest {
            protocol_version: current_protocol_version(),
        })
        .await
        .expect("ready over http");

    // @verifies selvedge.client.local
    assert_eq!(response.state, ReadyState::Ready);
    let captures = server.await.expect("join http contract server");
    let ready = captures
        .iter()
        .find(|capture| capture.path == "/selvedge/local/v1/ready")
        .expect("ready request captured");
    // @verifies selvedge.client.local
    assert_eq!(ready.method, "POST");
    // @verifies selvedge.client.local
    assert_eq!(ready.content_type.as_deref(), Some("application/json"));
    // @verifies selvedge.client.local
    assert_eq!(
        serde_json::from_slice::<ReadyRequest>(&ready.body).expect("ready request body"),
        ReadyRequest {
            protocol_version: current_protocol_version()
        }
    );
}

#[tokio::test]
async fn http_transport_posts_command_to_local_protocol_route() {
    let _guard = TEST_LOCK.lock().await;
    let body = serde_json::to_vec(&CommandResponse {
        protocol_version: current_protocol_version(),
        client_command_id: LocalClientCommandId::new("command-1").expect("command id"),
        outcome: CommandOutcome::Accepted,
    })
    .expect("command response json");
    let (port, server) =
        spawn_http_contract_server(vec![None, Some(HttpContractResponse::json(200, body))]).await;
    let client = connect_http(http_config(port))
        .await
        .expect("connect http client");

    let response = client
        .submit_command(valid_command("command-1"))
        .await
        .expect("command over http");

    // @verifies selvedge.client.local
    assert_eq!(response.outcome, CommandOutcome::Accepted);
    let captures = server.await.expect("join http contract server");
    let command = captures
        .iter()
        .find(|capture| capture.path == "/selvedge/local/v1/command")
        .expect("command request captured");
    // @verifies selvedge.client.local
    assert_eq!(command.method, "POST");
    // @verifies selvedge.client.local
    assert_eq!(command.content_type.as_deref(), Some("application/json"));
    // @verifies selvedge.client.local
    assert_eq!(
        serde_json::from_slice::<CommandRequest>(&command.body).expect("command request body"),
        valid_command("command-1")
    );
}

#[tokio::test]
async fn http_transport_rejects_mismatched_command_response_id() {
    let _guard = TEST_LOCK.lock().await;
    let body = serde_json::to_vec(&CommandResponse {
        protocol_version: current_protocol_version(),
        client_command_id: LocalClientCommandId::new("other-command").expect("command id"),
        outcome: CommandOutcome::Accepted,
    })
    .expect("command response json");
    let (port, server) =
        spawn_http_contract_server(vec![None, Some(HttpContractResponse::json(200, body))]).await;
    let client = connect_http(http_config(port))
        .await
        .expect("connect http client");

    let error = client
        .submit_command(valid_command("command-1"))
        .await
        .expect_err("mismatched response id should fail");

    // @verifies selvedge.client.local
    assert!(matches!(
        error,
        LocalClientError::ProtocolValidationFailed(_)
    ));
    let captures = server.await.expect("join http contract server");
    // @verifies selvedge.client.local
    assert!(
        captures
            .iter()
            .any(|capture| capture.path == "/selvedge/local/v1/command")
    );
}

#[tokio::test]
async fn http_transport_reads_attach_accepted_ndjson_stream() {
    let _guard = TEST_LOCK.lock().await;
    let accepted = AttachAccepted {
        protocol_version: current_protocol_version(),
        client_id: LocalClientId::new("client-1").expect("client id"),
        client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
    };
    let ndjson = format!(
        "{}\n{}\n",
        serde_json::to_string(&selvedge_local_protocol::LocalAttachStreamItem::Accepted(
            accepted.clone()
        ))
        .expect("accepted item json"),
        serde_json::to_string(&selvedge_local_protocol::LocalAttachStreamItem::Frame(
            notice_frame(7)
        ))
        .expect("frame item json")
    )
    .into_bytes();
    let (port, server) =
        spawn_http_contract_server(vec![None, Some(HttpContractResponse::ndjson(200, ndjson))])
            .await;
    let client = connect_http(http_config(port))
        .await
        .expect("connect http client");

    let (actual_accepted, mut frames) = client
        .attach(valid_attach("attach-1"))
        .await
        .expect("attach over http");

    // @verifies selvedge.client.local
    assert_eq!(actual_accepted, accepted);
    // @verifies selvedge.client.local
    assert_eq!(next_seq(&mut frames).await, Ok(7));
    let captures = server.await.expect("join http contract server");
    let attach = captures
        .iter()
        .find(|capture| capture.path == "/selvedge/local/v1/attach")
        .expect("attach request captured");
    // @verifies selvedge.client.local
    assert_eq!(attach.method, "POST");
    // @verifies selvedge.client.local
    assert_eq!(attach.content_type.as_deref(), Some("application/json"));
    // @verifies selvedge.client.local
    assert_eq!(attach.accept.as_deref(), Some("application/x-ndjson"));
    // @verifies selvedge.client.local
    assert_eq!(
        serde_json::from_slice::<AttachRequest>(&attach.body).expect("attach request body"),
        valid_attach("attach-1")
    );
}

#[tokio::test]
async fn http_transport_rejects_mismatched_attach_accepted_identity() {
    let _guard = TEST_LOCK.lock().await;
    let accepted = AttachAccepted {
        protocol_version: current_protocol_version(),
        client_id: LocalClientId::new("other-client").expect("client id"),
        client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
    };
    let ndjson = format!(
        "{}\n",
        serde_json::to_string(&selvedge_local_protocol::LocalAttachStreamItem::Accepted(
            accepted
        ))
        .expect("accepted item json")
    )
    .into_bytes();
    let (port, server) =
        spawn_http_contract_server(vec![None, Some(HttpContractResponse::ndjson(200, ndjson))])
            .await;
    let client = connect_http(http_config(port))
        .await
        .expect("connect http client");

    let error = match client.attach(valid_attach("attach-1")).await {
        Ok(_) => panic!("mismatched attach identity should fail"),
        Err(error) => error,
    };

    // @verifies selvedge.client.local
    assert!(matches!(
        error,
        AttachRejectedOrClientError::Client(LocalClientError::ProtocolValidationFailed(_))
    ));
    let captures = server.await.expect("join http contract server");
    // @verifies selvedge.client.local
    assert!(
        captures
            .iter()
            .any(|capture| capture.path == "/selvedge/local/v1/attach")
    );
}

#[tokio::test]
async fn http_transport_preserves_attach_rejection_response() {
    let _guard = TEST_LOCK.lock().await;
    let rejected = AttachRejected {
        protocol_version: current_protocol_version(),
        client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
        reason: AttachRejectReason::ServerNotReady,
    };
    let body = serde_json::to_vec(&rejected).expect("attach rejected json");
    let (port, server) =
        spawn_http_contract_server(vec![None, Some(HttpContractResponse::json(409, body))]).await;
    let client = connect_http(http_config(port))
        .await
        .expect("connect http client");

    let error = client.attach(valid_attach("attach-1")).await;

    match error {
        // @verifies selvedge.client.local
        Err(AttachRejectedOrClientError::Rejected(actual)) => assert_eq!(actual, rejected),
        Ok(_) => panic!("attach should be rejected"),
        Err(other) => panic!("unexpected attach error: {other:?}"),
    }
    let captures = server.await.expect("join http contract server");
    // @verifies selvedge.client.local
    assert!(
        captures
            .iter()
            .any(|capture| capture.path == "/selvedge/local/v1/attach")
    );
}

#[tokio::test]
async fn http_transport_rejects_mismatched_attach_rejection_identity() {
    let _guard = TEST_LOCK.lock().await;
    let rejected = AttachRejected {
        protocol_version: current_protocol_version(),
        client_command_id: LocalClientCommandId::new("other-attach").expect("command id"),
        reason: AttachRejectReason::ServerNotReady,
    };
    let body = serde_json::to_vec(&rejected).expect("attach rejected json");
    let (port, server) =
        spawn_http_contract_server(vec![None, Some(HttpContractResponse::json(409, body))]).await;
    let client = connect_http(http_config(port))
        .await
        .expect("connect http client");

    let error = match client.attach(valid_attach("attach-1")).await {
        Ok(_) => panic!("mismatched attach rejection should fail"),
        Err(error) => error,
    };

    // @verifies selvedge.client.local
    assert!(matches!(
        error,
        AttachRejectedOrClientError::Client(LocalClientError::ProtocolValidationFailed(_))
    ));
    let captures = server.await.expect("join http contract server");
    // @verifies selvedge.client.local
    assert!(
        captures
            .iter()
            .any(|capture| capture.path == "/selvedge/local/v1/attach")
    );
}

#[test]
fn crate_has_no_systemd_dependency() {
    let manifest = fs::read_to_string(format!("{}/Cargo.toml", env!("CARGO_MANIFEST_DIR")))
        .expect("read manifest");

    // @verifies selvedge.client.local
    assert!(!manifest.contains("systemd"));
}

struct HttpContractResponse {
    status_code: u16,
    content_type: &'static str,
    body: Vec<u8>,
}

#[derive(Debug)]
struct CapturedHttpRequest {
    method: String,
    path: String,
    content_type: Option<String>,
    accept: Option<String>,
    body: Vec<u8>,
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

struct DropNotifyingStream {
    drops: Arc<AtomicUsize>,
}

struct PollNotifyingStream {
    polled: Option<oneshot::Sender<()>>,
}

impl futures_core::Stream for DropNotifyingStream {
    type Item = Result<LocalClientFrame, LocalClientError>;

    fn poll_next(self: Pin<&mut Self>, _context: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        Poll::Pending
    }
}

impl futures_core::Stream for PollNotifyingStream {
    type Item = Result<LocalClientFrame, LocalClientError>;

    fn poll_next(mut self: Pin<&mut Self>, _context: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        if let Some(polled) = self.polled.take() {
            let _ = polled.send(());
        }
        Poll::Pending
    }
}

impl Drop for DropNotifyingStream {
    fn drop(&mut self) {
        self.drops.fetch_add(1, Ordering::SeqCst);
    }
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
            snapshot_mode: selvedge_local_protocol::LocalSnapshotMode::CurrentState,
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
            kind: selvedge_local_protocol::LocalNoticeKind::Text,
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

impl HttpContractResponse {
    fn json(status_code: u16, body: Vec<u8>) -> Self {
        Self {
            status_code,
            content_type: "application/json",
            body,
        }
    }

    fn ndjson(status_code: u16, body: Vec<u8>) -> Self {
        Self {
            status_code,
            content_type: "application/x-ndjson",
            body,
        }
    }
}

async fn spawn_http_contract_server(
    responses: Vec<Option<HttpContractResponse>>,
) -> (u16, JoinHandle<Vec<CapturedHttpRequest>>) {
    let listener = TcpListener::bind(("127.0.0.1", 0))
        .await
        .expect("bind local http contract server");
    let port = listener.local_addr().expect("local addr").port();
    let handle = tokio::spawn(async move {
        let mut captures = Vec::new();
        for response in responses {
            let (mut stream, _addr) = listener.accept().await.expect("accept http connection");
            let capture = read_captured_http_request(&mut stream)
                .await
                .expect("read captured http request");
            if !capture.method.is_empty() {
                captures.push(capture);
            }
            if let Some(response) = response {
                write_contract_response(&mut stream, response)
                    .await
                    .expect("write contract response");
            }
        }

        captures
    });

    (port, handle)
}

async fn read_captured_http_request(
    stream: &mut TcpStream,
) -> std::io::Result<CapturedHttpRequest> {
    let mut raw = Vec::new();
    let mut byte = [0_u8; 1];
    while !raw.ends_with(b"\r\n\r\n") {
        let read = stream.read(&mut byte).await?;
        if read == 0 {
            return Ok(CapturedHttpRequest {
                method: String::new(),
                path: String::new(),
                content_type: None,
                accept: None,
                body: Vec::new(),
            });
        }
        raw.push(byte[0]);
    }

    let headers = String::from_utf8(raw).expect("request headers are utf8");
    let mut lines = headers.split("\r\n");
    let request_line = lines.next().expect("request line");
    let mut request_parts = request_line.split_whitespace();
    let method = request_parts.next().unwrap_or_default().to_owned();
    let path = request_parts.next().unwrap_or_default().to_owned();
    let mut content_type = None;
    let mut accept = None;
    let mut content_length = 0_usize;

    for line in lines {
        if line.is_empty() {
            continue;
        }
        if let Some((name, value)) = line.split_once(':') {
            let value = value.trim().to_owned();
            if name.eq_ignore_ascii_case("content-type") {
                content_type = Some(value.to_ascii_lowercase());
            } else if name.eq_ignore_ascii_case("accept") {
                accept = Some(value.to_ascii_lowercase());
            } else if name.eq_ignore_ascii_case("content-length") {
                content_length = value.parse().expect("content length");
            }
        }
    }

    let mut body = vec![0_u8; content_length];
    stream.read_exact(&mut body).await?;

    Ok(CapturedHttpRequest {
        method,
        path,
        content_type,
        accept,
        body,
    })
}

async fn write_contract_response(
    stream: &mut TcpStream,
    response: HttpContractResponse,
) -> std::io::Result<()> {
    let status_text = if response.status_code == 200 {
        "OK"
    } else {
        "Rejected"
    };
    let headers = format!(
        "HTTP/1.1 {} {status_text}\r\nContent-Type: {}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        response.status_code,
        response.content_type,
        response.body.len()
    );
    stream.write_all(headers.as_bytes()).await?;
    stream.write_all(&response.body).await?;
    stream.flush().await
}

fn http_config(port: u16) -> LocalClientConfig {
    LocalClientConfig {
        endpoint: LocalEndpoint::TcpIpv4 { port },
        request_timeout: Duration::from_secs(1),
    }
}
