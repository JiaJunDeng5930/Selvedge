use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use futures_util::StreamExt;
use futures_util::stream;
use selvedge_local_protocol::{
    AttachAccepted, AttachRequest, CommandOutcome, CommandRejectReason, CommandRequest,
    CommandResponse, LocalClientCommandId, LocalClientEvent, LocalClientEventFrame,
    LocalClientFrame, LocalClientId, LocalClientSnapshot, LocalClientSnapshotFrame,
    LocalClientSubscription, LocalDetailLevel, LocalHttpProblem, LocalHttpProblemCode,
    LocalTaskScope, ReadyRequest, ReadyResponse, ReadyState,
};
use selvedge_web::{
    AttachRejectedOrBridgeError, WebAttachFuture, WebBridge, WebBridgeError, WebBridgeFuture,
    WebExitStatus, WebFrameStream, WebLocalhostBind, WebLocalhostHost, WebRuntimeState,
    WebStartArgs, WebStartError, spawn_web_surface,
};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::time::{Duration, timeout};

#[tokio::test]
async fn spawn_web_surface_exposes_control_handle_and_stop_status() {
    let bridge = Arc::new(RecordingBridge::default());
    let handle = spawn_web_surface(WebStartArgs {
        bind: unused_loopback_bind(),
        bridge,
    })
    .expect("valid web start args");

    assert_eq!(handle.control.state().await, WebRuntimeState::Listening);

    handle.control.stop().await;

    assert_eq!(
        handle.join_handle.await.expect("join web task"),
        WebExitStatus::Stopped
    );
}

#[tokio::test]
async fn spawn_web_surface_reserves_an_ephemeral_port() {
    let handle = spawn_web_surface(WebStartArgs {
        bind: unused_loopback_bind(),
        bridge: Arc::new(StaticBridge),
    })
    .expect("bind ephemeral port");
    assert_ne!(handle.control.local_addr().port(), 0);
    handle.control.stop().await;
    handle.join_handle.await.expect("join web task");
}

#[tokio::test]
async fn spawn_web_surface_reports_bind_failure() {
    let listener = std::net::TcpListener::bind(("127.0.0.1", 0)).expect("bind held port");
    let port = listener.local_addr().expect("held addr").port();

    let result = spawn_web_surface(WebStartArgs {
        bind: WebLocalhostBind {
            host: WebLocalhostHost::Ipv4Loopback,
            port,
        },
        bridge: Arc::new(StaticBridge),
    });

    assert!(matches!(result, Err(WebStartError::BindFailed(_))));
}

#[test]
fn web_bridge_trait_exposes_ready_command_and_attach_futures() {
    let bridge = StaticBridge;
    let ready: WebBridgeFuture<ReadyResponse> = bridge.ready(ReadyRequest {});
    let command: WebBridgeFuture<CommandResponse> = bridge.submit_command(valid_command_request());
    let attach: WebAttachFuture = bridge.attach(valid_attach_request());

    drop((ready, command, attach));
}

#[tokio::test]
async fn ready_request_returns_bridge_response() {
    let bridge = Arc::new(RecordingBridge::default());
    bridge.push_ready_response(Ok(ReadyResponse {
        state: ReadyState::Ready,
    }));
    let handle = spawn_web_surface(WebStartArgs {
        bind: unused_loopback_bind(),
        bridge: bridge.clone(),
    })
    .expect("valid web start args");

    let response = handle
        .control
        .ready(ReadyRequest {})
        .await
        .expect("ready response");

    assert_eq!(response.state, ReadyState::Ready);
    assert_eq!(bridge.ready_call_count(), 1);
    handle.control.stop().await;
    assert_eq!(
        handle.join_handle.await.expect("join web task"),
        WebExitStatus::Stopped
    );
}

#[tokio::test]
async fn ready_request_maps_server_not_ready_without_bridge_error() {
    let bridge = Arc::new(RecordingBridge::default());
    bridge.push_ready_response(Err(WebBridgeError::ServerNotReady));
    let handle = spawn_web_surface(WebStartArgs {
        bind: unused_loopback_bind(),
        bridge: bridge.clone(),
    })
    .expect("valid web start args");

    let response = handle
        .control
        .ready(ReadyRequest {})
        .await
        .expect("not ready response");
    assert_eq!(response.state, ReadyState::NotReady);
    assert_eq!(bridge.ready_call_count(), 1);

    handle.control.stop().await;
    assert_eq!(
        handle.join_handle.await.expect("join web task"),
        WebExitStatus::Stopped
    );
}

#[tokio::test]
async fn ready_request_preserves_bridge_failure() {
    let bridge = Arc::new(RecordingBridge::default());
    bridge.push_ready_response(Err(WebBridgeError::InternalFailure("boom".to_owned())));
    let handle = spawn_web_surface(WebStartArgs {
        bind: unused_loopback_bind(),
        bridge,
    })
    .expect("valid web start args");

    let error = handle
        .control
        .ready(ReadyRequest {})
        .await
        .expect_err("bridge failure should return error");

    assert_eq!(error, WebBridgeError::InternalFailure("boom".to_owned()));
    handle.control.stop().await;
    assert_eq!(
        handle.join_handle.await.expect("join web task"),
        WebExitStatus::Stopped
    );
}

#[tokio::test]
async fn invalid_command_request_returns_rejection_without_bridge_call() {
    let bridge = Arc::new(RecordingBridge::default());
    let handle = spawn_web_surface(WebStartArgs {
        bind: unused_loopback_bind(),
        bridge: bridge.clone(),
    })
    .expect("valid web start args");

    let response = handle
        .control
        .submit_command(CommandRequest {
            command_name: " ".to_owned(),
            ..valid_command_request()
        })
        .await
        .expect("command response");

    assert_eq!(
        response.outcome,
        CommandOutcome::Rejected(CommandRejectReason::MalformedRequest)
    );
    assert_eq!(bridge.command_call_count(), 0);
    handle.control.stop().await;
    assert_eq!(
        handle.join_handle.await.expect("join web task"),
        WebExitStatus::Stopped
    );
}

#[tokio::test]
async fn command_request_returns_bridge_response() {
    let bridge = Arc::new(RecordingBridge::default());
    bridge.push_command_response(Ok(CommandResponse {
        client_command_id: LocalClientCommandId::new("command-1").expect("command id"),
        outcome: CommandOutcome::Rejected(CommandRejectReason::UnsupportedCommand),
    }));
    let handle = spawn_web_surface(WebStartArgs {
        bind: unused_loopback_bind(),
        bridge: bridge.clone(),
    })
    .expect("valid web start args");

    let response = handle
        .control
        .submit_command(valid_command_request())
        .await
        .expect("command response");

    assert_eq!(
        response.outcome,
        CommandOutcome::Rejected(CommandRejectReason::UnsupportedCommand)
    );
    assert_eq!(bridge.command_call_count(), 1);
    handle.control.stop().await;
    assert_eq!(
        handle.join_handle.await.expect("join web task"),
        WebExitStatus::Stopped
    );
}

#[tokio::test]
async fn attach_request_forwards_bridge_frames_in_order() {
    let bridge = Arc::new(RecordingBridge::default());
    bridge.push_attach_response(Ok((
        AttachAccepted {
            client_id: LocalClientId::new("client-1").expect("client id"),
            client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
        },
        Box::pin(stream::iter(vec![
            Ok(LocalClientFrame::Snapshot(LocalClientSnapshotFrame {
                delivery_seq: 1,
                client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
                snapshot: empty_snapshot(),
            })),
            Ok(LocalClientFrame::Event(LocalClientEventFrame {
                delivery_seq: 2,
                event: LocalClientEvent::DebugNotice(
                    selvedge_local_protocol::LocalDebugNoticeEvent {
                        task_id: None,
                        message_text: "ready".to_owned(),
                    },
                ),
            })),
        ])),
    )));
    let handle = spawn_web_surface(WebStartArgs {
        bind: unused_loopback_bind(),
        bridge: bridge.clone(),
    })
    .expect("valid web start args");

    let (_accepted, mut frames) = handle
        .control
        .attach(valid_attach_request())
        .await
        .expect("attach accepted");

    assert!(matches!(
        frames.next().await,
        Some(Ok(LocalClientFrame::Snapshot(_)))
    ));
    assert!(matches!(
        frames.next().await,
        Some(Ok(LocalClientFrame::Event(_)))
    ));
    assert!(frames.next().await.is_none());
    assert_eq!(bridge.attach_call_count(), 1);
    handle.control.stop().await;
    assert_eq!(
        handle.join_handle.await.expect("join web task"),
        WebExitStatus::Stopped
    );
}

#[tokio::test]
async fn stop_closes_active_attach_stream() {
    let bridge = Arc::new(RecordingBridge::default());
    bridge.push_attach_response(Ok((
        AttachAccepted {
            client_id: LocalClientId::new("client-1").expect("client id"),
            client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
        },
        Box::pin(stream::pending()),
    )));
    let handle = spawn_web_surface(WebStartArgs {
        bind: unused_loopback_bind(),
        bridge,
    })
    .expect("valid web start args");
    let (_accepted, mut frames) = handle
        .control
        .attach(valid_attach_request())
        .await
        .expect("attach accepted");

    let next_frame = tokio::spawn(async move {
        timeout(Duration::from_secs(1), frames.next())
            .await
            .expect("stream close timeout")
    });
    tokio::time::sleep(Duration::from_millis(10)).await;

    handle.control.stop().await;

    assert!(next_frame.await.expect("join next frame").is_none());
    assert_eq!(
        handle.join_handle.await.expect("join web task"),
        WebExitStatus::Stopped
    );
}

#[tokio::test]
async fn http_route_returns_body_too_large_before_allocating_body() {
    let bind = unused_loopback_bind();
    let handle = spawn_web_surface(WebStartArgs {
        bind,
        bridge: Arc::new(StaticBridge),
    })
    .expect("valid web start args");

    let response = send_raw_http_request(
        handle.control.local_addr().port(),
        "POST /selvedge/local/v1/ready HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: 4194305\r\nConnection: close\r\n\r\n",
    )
    .await;

    assert!(response.starts_with("HTTP/1.1 413"));
    assert_eq!(
        extract_problem(&response).code,
        LocalHttpProblemCode::BodyTooLarge
    );
    handle.control.stop().await;
    assert_eq!(
        handle.join_handle.await.expect("join web task"),
        WebExitStatus::Stopped
    );
}

#[tokio::test]
async fn root_page_route_is_not_exposed() {
    let bind = unused_loopback_bind();
    let handle = spawn_web_surface(WebStartArgs {
        bind,
        bridge: Arc::new(StaticBridge),
    })
    .expect("valid web start args");

    let response = send_raw_http_request(
        handle.control.local_addr().port(),
        "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n",
    )
    .await;

    assert!(response.starts_with("HTTP/1.1 404"));
    assert_eq!(
        extract_problem(&response).code,
        LocalHttpProblemCode::RouteNotFound
    );
    handle.control.stop().await;
    assert_eq!(
        handle.join_handle.await.expect("join web task"),
        WebExitStatus::Stopped
    );
}

#[tokio::test]
async fn http_route_rejects_non_loopback_host() {
    let bind = unused_loopback_bind();
    let handle = spawn_web_surface(WebStartArgs {
        bind,
        bridge: Arc::new(StaticBridge),
    })
    .expect("valid web start args");

    let response = send_raw_http_request(
        handle.control.local_addr().port(),
        "POST /selvedge/local/v1/ready HTTP/1.1\r\nHost: attacker.example\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}",
    )
    .await;

    assert!(response.starts_with("HTTP/1.1 403"));
    handle.control.stop().await;
    assert_eq!(
        handle.join_handle.await.expect("join web task"),
        WebExitStatus::Stopped
    );
}

#[tokio::test]
async fn http_route_rejects_non_loopback_origin() {
    let bind = unused_loopback_bind();
    let handle = spawn_web_surface(WebStartArgs {
        bind,
        bridge: Arc::new(StaticBridge),
    })
    .expect("valid web start args");

    let response = send_raw_http_request(
        handle.control.local_addr().port(),
        "POST /selvedge/local/v1/ready HTTP/1.1\r\nHost: 127.0.0.1\r\nOrigin: https://attacker.example\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}",
    )
    .await;

    assert!(response.starts_with("HTTP/1.1 403"));
    handle.control.stop().await;
    assert_eq!(
        handle.join_handle.await.expect("join web task"),
        WebExitStatus::Stopped
    );
}

#[tokio::test]
async fn http_route_rejects_oversized_headers() {
    let bind = unused_loopback_bind();
    let handle = spawn_web_surface(WebStartArgs {
        bind,
        bridge: Arc::new(StaticBridge),
    })
    .expect("valid web start args");
    let request = format!(
        "POST /selvedge/local/v1/ready HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Large: {}\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{{}}",
        "a".repeat(16 * 1024)
    );

    let response = send_raw_http_request(handle.control.local_addr().port(), &request).await;

    assert!(response.starts_with("HTTP/1.1 431"), "{response}");
    handle.control.stop().await;
    assert_eq!(
        handle.join_handle.await.expect("join web task"),
        WebExitStatus::Stopped
    );
}

#[tokio::test]
async fn http_route_returns_unsupported_media_type_for_non_json_body() {
    let bind = unused_loopback_bind();
    let handle = spawn_web_surface(WebStartArgs {
        bind,
        bridge: Arc::new(StaticBridge),
    })
    .expect("valid web start args");

    let response = send_raw_http_request(
        handle.control.local_addr().port(),
        "POST /selvedge/local/v1/ready HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}",
    )
    .await;

    assert!(response.starts_with("HTTP/1.1 415"));
    assert_eq!(
        extract_problem(&response).code,
        LocalHttpProblemCode::UnsupportedContentType
    );
    handle.control.stop().await;
    assert_eq!(
        handle.join_handle.await.expect("join web task"),
        WebExitStatus::Stopped
    );
}

struct StaticBridge;

impl WebBridge for StaticBridge {
    fn ready(&self, _request: ReadyRequest) -> WebBridgeFuture<ReadyResponse> {
        Box::pin(async {
            Ok(ReadyResponse {
                state: ReadyState::Ready,
            })
        })
    }

    fn submit_command(&self, request: CommandRequest) -> WebBridgeFuture<CommandResponse> {
        Box::pin(async move {
            Ok(CommandResponse {
                client_command_id: request.client_command_id,
                outcome: CommandOutcome::Accepted,
            })
        })
    }

    fn attach(&self, _request: AttachRequest) -> WebAttachFuture {
        Box::pin(async {
            Err(AttachRejectedOrBridgeError::Bridge(
                selvedge_web::WebBridgeError::ServerNotReady,
            ))
        })
    }
}

#[derive(Default)]
struct RecordingBridge {
    ready_responses: std::sync::Mutex<Vec<Result<ReadyResponse, WebBridgeError>>>,
    command_responses: std::sync::Mutex<Vec<Result<CommandResponse, WebBridgeError>>>,
    attach_responses: std::sync::Mutex<
        Vec<Result<(AttachAccepted, WebFrameStream), AttachRejectedOrBridgeError>>,
    >,
    ready_calls: AtomicUsize,
    command_calls: AtomicUsize,
    attach_calls: AtomicUsize,
}

impl RecordingBridge {
    fn push_ready_response(&self, response: Result<ReadyResponse, WebBridgeError>) {
        self.ready_responses
            .lock()
            .expect("ready responses")
            .push(response);
    }

    fn push_command_response(&self, response: Result<CommandResponse, WebBridgeError>) {
        self.command_responses
            .lock()
            .expect("command responses")
            .push(response);
    }

    fn push_attach_response(
        &self,
        response: Result<(AttachAccepted, WebFrameStream), AttachRejectedOrBridgeError>,
    ) {
        self.attach_responses
            .lock()
            .expect("attach responses")
            .push(response);
    }

    fn ready_call_count(&self) -> usize {
        self.ready_calls.load(Ordering::SeqCst)
    }

    fn command_call_count(&self) -> usize {
        self.command_calls.load(Ordering::SeqCst)
    }

    fn attach_call_count(&self) -> usize {
        self.attach_calls.load(Ordering::SeqCst)
    }
}

impl WebBridge for RecordingBridge {
    fn ready(&self, _request: ReadyRequest) -> WebBridgeFuture<ReadyResponse> {
        self.ready_calls.fetch_add(1, Ordering::SeqCst);
        let response = self.ready_responses.lock().expect("ready responses").pop();
        Box::pin(async move {
            match response {
                Some(response) => response,
                None => Ok(ReadyResponse {
                    state: ReadyState::Ready,
                }),
            }
        })
    }

    fn submit_command(&self, request: CommandRequest) -> WebBridgeFuture<CommandResponse> {
        self.command_calls.fetch_add(1, Ordering::SeqCst);
        let response = self
            .command_responses
            .lock()
            .expect("command responses")
            .pop();
        Box::pin(async move {
            match response {
                Some(response) => response,
                None => Ok(CommandResponse {
                    client_command_id: request.client_command_id,
                    outcome: CommandOutcome::Accepted,
                }),
            }
        })
    }

    fn attach(&self, request: AttachRequest) -> WebAttachFuture {
        self.attach_calls.fetch_add(1, Ordering::SeqCst);
        let response = self
            .attach_responses
            .lock()
            .expect("attach responses")
            .pop();
        Box::pin(async move {
            match response {
                Some(response) => response,
                None => Ok((
                    AttachAccepted {
                        client_id: request.client_id,
                        client_command_id: request.client_command_id,
                    },
                    Box::pin(stream::empty()) as WebFrameStream,
                )),
            }
        })
    }
}

fn unused_loopback_bind() -> WebLocalhostBind {
    WebLocalhostBind {
        host: WebLocalhostHost::Ipv4Loopback,
        port: 0,
    }
}

async fn send_raw_http_request(port: u16, request: &str) -> String {
    let mut stream = TcpStream::connect(("127.0.0.1", port))
        .await
        .expect("connect web surface");
    stream
        .write_all(request.as_bytes())
        .await
        .expect("write request");
    stream.shutdown().await.expect("shutdown request writer");
    let mut bytes = Vec::new();
    let mut chunk = [0_u8; 1024];
    loop {
        match stream.read(&mut chunk).await {
            Ok(0) => break,
            Ok(read) => bytes.extend_from_slice(&chunk[..read]),
            Err(error) if error.kind() == std::io::ErrorKind::ConnectionReset => break,
            Err(error) => panic!("read response: {error}"),
        }
    }
    String::from_utf8(bytes).expect("utf8 response")
}

fn extract_problem(response: &str) -> LocalHttpProblem {
    let body = response.split("\r\n\r\n").nth(1).expect("response body");
    serde_json::from_str(body).expect("problem body")
}

fn valid_command_request() -> CommandRequest {
    CommandRequest {
        client_id: LocalClientId::new("client-1").expect("valid client id"),
        client_command_id: LocalClientCommandId::new("command-1").expect("valid command id"),
        command_name: "send-user-input".to_owned(),
        payload: serde_json::json!({ "message": "hello" }),
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

fn valid_attach_request() -> AttachRequest {
    AttachRequest {
        client_id: LocalClientId::new("client-1").expect("valid client id"),
        client_command_id: LocalClientCommandId::new("attach-1").expect("valid command id"),
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

#[tokio::test]
async fn chunked_requests_and_malformed_lengths_use_http_framing() {
    let handle = spawn_web_surface(WebStartArgs {
        bind: unused_loopback_bind(),
        bridge: Arc::new(StaticBridge),
    })
    .expect("start web");
    let port = handle.control.local_addr().port();
    let chunked = send_raw_http_request(port, "POST /selvedge/local/v1/ready HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n1\r\n{\r\n1\r\n}\r\n0\r\n\r\n").await;
    assert!(chunked.starts_with("HTTP/1.1 200"), "{chunked}");
    for headers in [
        "Content-Length: invalid",
        "Content-Length: 2\r\nContent-Length: 3",
    ] {
        let request = format!(
            "POST /selvedge/local/v1/ready HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\n{headers}\r\n\r\n{{}}"
        );
        let response = send_raw_http_request(port, &request).await;
        assert!(response.starts_with("HTTP/1.1 400"), "{response}");
    }
    handle.control.stop().await;
    handle.join_handle.await.expect("join");
}

#[tokio::test]
async fn attach_snapshot_budget_is_shared_by_real_http_sender_and_receiver() {
    use selvedge_local_client::{LocalClientError, connect_http};
    use selvedge_local_protocol::{
        LocalAttachStreamItem, LocalHistoryNodeProjection, LocalHistoryNodeProjectionBody,
        LocalMessageRole, LocalStreamErrorReason, MAX_LOCAL_FRAME_BYTES,
    };
    for extra in [0, 1] {
        let mut snapshot = empty_snapshot();
        snapshot.history_nodes.push(LocalHistoryNodeProjection {
            node_id: 1,
            parent_node_id: None,
            created_at: 0,
            body: LocalHistoryNodeProjectionBody::Message {
                role: LocalMessageRole::User,
                text: String::new(),
            },
        });
        let mut frame = LocalClientFrame::Snapshot(LocalClientSnapshotFrame {
            delivery_seq: 1,
            client_command_id: valid_attach_request().client_command_id,
            snapshot,
        });
        let overhead = serde_json::to_vec(&LocalAttachStreamItem::Frame(frame.clone()))
            .expect("encode snapshot")
            .len();
        if let LocalClientFrame::Snapshot(frame) = &mut frame
            && let LocalHistoryNodeProjectionBody::Message { text, .. } =
                &mut frame.snapshot.history_nodes[0].body
        {
            *text = "a".repeat(MAX_LOCAL_FRAME_BYTES - overhead + extra);
        }
        let bridge = Arc::new(RecordingBridge::default());
        let request = valid_attach_request();
        bridge.push_attach_response(Ok((
            AttachAccepted {
                client_id: request.client_id.clone(),
                client_command_id: request.client_command_id.clone(),
            },
            Box::pin(stream::iter(vec![Ok(frame.clone())])),
        )));
        let handle = spawn_web_surface(WebStartArgs {
            bind: unused_loopback_bind(),
            bridge,
        })
        .expect("start web");
        let client = connect_http(local_http_config(handle.control.local_addr().port()))
            .await
            .expect("connect HTTP");
        let (_, mut frames) = client.attach(request).await.expect("attach accepted");
        let result = timeout(Duration::from_secs(3), frames.next())
            .await
            .expect("frame within deadline")
            .expect("one item");
        if extra == 0 {
            assert_eq!(result.expect("budget-sized snapshot succeeds"), frame);
        } else {
            assert!(
                matches!(result, Err(LocalClientError::StreamError(error)) if error.reason == LocalStreamErrorReason::FrameTooLarge)
            );
            assert!(frames.next().await.is_none());
        }
        client.close().await.expect("close client");
        handle.control.stop().await;
        handle.join_handle.await.expect("join web");
    }
}

fn local_http_config(port: u16) -> selvedge_local_client::LocalClientConfig {
    selvedge_local_client::LocalClientConfig {
        endpoint: selvedge_local_client::LocalEndpoint::TcpIpv4 { port },
        request_timeout: Duration::from_secs(3),
    }
}

struct DropSignal(Arc<AtomicUsize>);
impl Drop for DropSignal {
    fn drop(&mut self) {
        self.0.fetch_add(1, Ordering::SeqCst);
    }
}

struct BlockedReadyBridge {
    entered: Arc<tokio::sync::Notify>,
    dropped: Arc<AtomicUsize>,
}
impl WebBridge for BlockedReadyBridge {
    fn ready(&self, _: ReadyRequest) -> WebBridgeFuture<ReadyResponse> {
        let entered = self.entered.clone();
        let guard = DropSignal(self.dropped.clone());
        Box::pin(async move {
            let _guard = guard;
            entered.notify_one();
            std::future::pending().await
        })
    }
    fn submit_command(&self, request: CommandRequest) -> WebBridgeFuture<CommandResponse> {
        StaticBridge.submit_command(request)
    }
    fn attach(&self, request: AttachRequest) -> WebAttachFuture {
        StaticBridge.attach(request)
    }
}

#[tokio::test]
async fn stop_joins_http_connection_waiting_in_bridge() {
    let entered = Arc::new(tokio::sync::Notify::new());
    let dropped = Arc::new(AtomicUsize::new(0));
    let handle = spawn_web_surface(WebStartArgs {
        bind: unused_loopback_bind(),
        bridge: Arc::new(BlockedReadyBridge {
            entered: entered.clone(),
            dropped: dropped.clone(),
        }),
    })
    .expect("start web");
    let mut socket = TcpStream::connect(handle.control.local_addr())
        .await
        .expect("connect");
    socket.write_all(b"POST /selvedge/local/v1/ready HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}").await.expect("write request");
    timeout(Duration::from_secs(1), entered.notified())
        .await
        .expect("bridge entered");
    handle.control.stop().await;
    timeout(Duration::from_secs(1), handle.join_handle)
        .await
        .expect("web stops")
        .expect("join");
    assert_eq!(dropped.load(Ordering::SeqCst), 1);
    let mut remaining = Vec::new();
    timeout(Duration::from_secs(1), socket.read_to_end(&mut remaining))
        .await
        .expect("socket closed")
        .expect("read EOF");
}

struct FloodFrames {
    polls: Arc<AtomicUsize>,
    _drop: DropSignal,
}
impl futures_core::Stream for FloodFrames {
    type Item = Result<LocalClientFrame, WebBridgeError>;
    fn poll_next(
        self: std::pin::Pin<&mut Self>,
        _: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Option<Self::Item>> {
        let seq = self.polls.fetch_add(1, Ordering::SeqCst) + 1;
        std::task::Poll::Ready(Some(Ok(LocalClientFrame::Event(LocalClientEventFrame {
            delivery_seq: seq as u64,
            event: LocalClientEvent::DebugNotice(selvedge_local_protocol::LocalDebugNoticeEvent {
                task_id: None,
                message_text: "x".repeat(1024 * 1024),
            }),
        }))))
    }
}

#[tokio::test]
async fn stop_joins_http_connection_blocked_by_nonreading_peer() {
    let polls = Arc::new(AtomicUsize::new(0));
    let dropped = Arc::new(AtomicUsize::new(0));
    let bridge = Arc::new(RecordingBridge::default());
    let request = valid_attach_request();
    bridge.push_attach_response(Ok((
        AttachAccepted {
            client_id: request.client_id.clone(),
            client_command_id: request.client_command_id.clone(),
        },
        Box::pin(FloodFrames {
            polls: polls.clone(),
            _drop: DropSignal(dropped.clone()),
        }),
    )));
    let handle = spawn_web_surface(WebStartArgs {
        bind: unused_loopback_bind(),
        bridge,
    })
    .expect("start web");
    let mut socket = TcpStream::connect(handle.control.local_addr())
        .await
        .expect("connect");
    let body = serde_json::to_string(&request).expect("attach body");
    socket.write_all(format!("POST /selvedge/local/v1/attach HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{body}", body.len()).as_bytes()).await.expect("write request");
    timeout(Duration::from_secs(3), async {
        loop {
            let before = polls.load(Ordering::SeqCst);
            tokio::time::sleep(Duration::from_millis(30)).await;
            if before > 0 && before == polls.load(Ordering::SeqCst) {
                break;
            }
        }
    })
    .await
    .expect("peer stops draining frames");
    handle.control.stop().await;
    timeout(Duration::from_secs(1), handle.join_handle)
        .await
        .expect("web stops despite blocked write")
        .expect("join");
    assert_eq!(dropped.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn http_problem_code_survives_real_client_boundary() {
    let bridge = Arc::new(RecordingBridge::default());
    bridge.push_ready_response(Err(WebBridgeError::InternalFailure(
        "test failure".to_owned(),
    )));
    let handle = spawn_web_surface(WebStartArgs {
        bind: unused_loopback_bind(),
        bridge,
    })
    .expect("start web");
    let client =
        selvedge_local_client::connect_http(local_http_config(handle.control.local_addr().port()))
            .await
            .expect("connect");
    let error = client
        .ready(ReadyRequest {})
        .await
        .expect_err("bridge fails");
    assert!(
        matches!(error, selvedge_local_client::LocalClientError::HttpProblem(problem) if problem.code == LocalHttpProblemCode::InternalFailure)
    );
    handle.control.stop().await;
    handle.join_handle.await.expect("join web");
}

#[tokio::test]
async fn stalled_request_headers_are_closed_after_read_deadline() {
    let handle = spawn_web_surface(WebStartArgs {
        bind: unused_loopback_bind(),
        bridge: Arc::new(StaticBridge),
    })
    .expect("start web");
    let mut socket = TcpStream::connect(handle.control.local_addr())
        .await
        .expect("connect");
    socket.write_all(b"POST /").await.expect("partial headers");
    let mut response = Vec::new();
    timeout(Duration::from_secs(7), socket.read_to_end(&mut response))
        .await
        .expect("header timeout closes socket")
        .expect("read EOF");
    handle.control.stop().await;
    handle.join_handle.await.expect("join web");
}
