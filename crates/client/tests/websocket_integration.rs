use futures_util::{SinkExt, StreamExt};
use http::{HeaderMap, HeaderValue, StatusCode};
use selvedge_client::{HttpError, WebSocketRequest, connect_websocket};
use selvedge_test_support::process::{assert_child_success, child_mode, run_child};
use std::{sync::Arc, time::Duration};
use tokio::{
    net::TcpListener,
    time::{sleep, timeout},
};
use tokio_tungstenite::{
    accept_async, accept_hdr_async,
    tungstenite::{
        Message,
        handshake::server::{Request, Response},
    },
};

fn request(url: String) -> WebSocketRequest {
    WebSocketRequest {
        url,
        headers: HeaderMap::new(),
        timeout: Some(Duration::from_secs(3)),
    }
}
fn init() -> tempfile::TempDir {
    selvedge_test_support::config::init_test_home("")
}

#[tokio::test]
#[allow(clippy::result_large_err)]
async fn websocket_concurrent_send_receive_ping_and_close() {
    const FLAG: &str = "WS_CONCURRENT_CHILD";
    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "websocket_concurrent_send_receive_ping_and_close",
            FLAG,
        ));
        return;
    }
    let _home = init();
    selvedge_config::update_runtime("network.user_agent", "transport-test").expect("config");
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
    let url = format!("ws://{}/responses", listener.local_addr().expect("addr"));
    let server = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.expect("accept");
        let mut ws = accept_hdr_async(socket, |req: &Request, mut response: Response| {
            assert_eq!(req.headers()["authorization"], "Bearer test-secret");
            assert_eq!(req.headers()["user-agent"], "transport-test");
            response
                .headers_mut()
                .insert("x-request-id", HeaderValue::from_static("handshake"));
            Ok(response)
        })
        .await
        .expect("handshake");
        assert_eq!(
            ws.next()
                .await
                .expect("create")
                .expect("message")
                .into_text()
                .expect("text"),
            "create"
        );
        ws.send(Message::Ping(vec![1, 2, 3].into()))
            .await
            .expect("ping");
        assert!(matches!(ws.next().await, Some(Ok(Message::Pong(_)))));
        assert_eq!(
            ws.next()
                .await
                .expect("steer")
                .expect("message")
                .into_text()
                .expect("text"),
            "steer"
        );
        ws.send(Message::Text("done".into()))
            .await
            .expect("response");
        ws.close(None).await.expect("close");
        let _ = ws.next().await;
    });
    let mut req = request(url);
    req.headers.insert(
        "authorization",
        HeaderValue::from_static("Bearer test-secret"),
    );
    let connection = connect_websocket(req).await.expect("connect");
    assert_eq!(connection.headers["x-request-id"], "handshake");
    let (mut sender, mut receiver) = connection.split();
    assert!(matches!(
        sender.send_text("x".repeat(4 * 1024 * 1024 + 1)).await,
        Err(HttpError::ResponseTooLarge { .. })
    ));
    sender.send_text("create".into()).await.expect("create");
    let read = tokio::spawn(async move {
        assert_eq!(
            receiver.next_text().await.expect("read"),
            Some("done".into())
        );
        assert_eq!(receiver.next_text().await.expect("close"), None);
        assert_eq!(receiver.next_text().await.expect("fused close"), None);
    });
    sleep(Duration::from_millis(20)).await;
    sender
        .send_text("steer".into())
        .await
        .expect("steer while read pending");
    timeout(Duration::from_secs(2), read)
        .await
        .expect("read progress")
        .expect("reader");
    server.await.expect("server");
}

#[tokio::test]
#[allow(clippy::result_large_err)]
async fn websocket_rejects_redirect_without_forwarding_credentials() {
    const FLAG: &str = "WS_REDIRECT_CHILD";
    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "websocket_rejects_redirect_without_forwarding_credentials",
            FLAG,
        ));
        return;
    }
    let _home = init();
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
    let url = format!("ws://{}/", listener.local_addr().expect("addr"));
    let server = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.expect("accept");
        let result = accept_hdr_async(socket, |_req: &Request, _response: Response| {
            Err(http::Response::builder()
                .status(StatusCode::TEMPORARY_REDIRECT)
                .header("location", "ws://127.0.0.1:1/credentials")
                .body(Some("redirect".into()))
                .expect("response"))
        })
        .await;
        assert!(result.is_err());
    });
    let error = connect_websocket(request(url)).await.err().expect("reject");
    assert!(
        matches!(error, HttpError::Status(error) if error.status == StatusCode::TEMPORARY_REDIRECT && error.headers.contains_key("location"))
    );
    server.await.expect("server");
}

#[tokio::test]
async fn websocket_config_timeout_and_cancel_safe_read() {
    const FLAG: &str = "WS_TIMEOUT_CHILD";
    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "websocket_config_timeout_and_cancel_safe_read",
            FLAG,
        ));
        return;
    }
    let _home = init();
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
    let url = format!("ws://{}/", listener.local_addr().expect("addr"));
    let server = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.expect("accept");
        let mut ws = accept_async(socket).await.expect("handshake");
        use tokio_tungstenite::tungstenite::protocol::frame::{
            Frame,
            coding::{Data, OpCode},
        };
        ws.send(Message::Frame(Frame::message(
            b"la".to_vec(),
            OpCode::Data(Data::Text),
            false,
        )))
        .await
        .expect("first fragment");
        sleep(Duration::from_millis(70)).await;
        ws.send(Message::Frame(Frame::message(
            b"t".to_vec(),
            OpCode::Data(Data::Continue),
            false,
        )))
        .await
        .expect("middle fragment");
        sleep(Duration::from_millis(70)).await;
        ws.send(Message::Frame(Frame::message(
            b"e".to_vec(),
            OpCode::Data(Data::Continue),
            true,
        )))
        .await
        .expect("late event");
        sleep(Duration::from_secs(1)).await;
    });
    selvedge_config::update_runtime("network.stream_idle_timeout_ms", 100_u64).expect("config");
    let (_, mut receiver) = connect_websocket(request(url))
        .await
        .expect("connect")
        .split();
    assert!(
        timeout(Duration::from_millis(20), receiver.next_text())
            .await
            .is_err()
    );
    assert_eq!(
        receiver.next_text().await.expect("read after cancellation"),
        Some("late".into())
    );
    assert!(matches!(
        receiver.next_text().await,
        Err(HttpError::Timeout)
    ));
    server.abort();
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
    let stalled_url = format!("ws://{}/", listener.local_addr().expect("addr"));
    selvedge_config::update_runtime("network.connect_timeout_ms", 30_u64).expect("connect config");
    assert!(matches!(
        connect_websocket(request(stalled_url.clone())).await,
        Err(HttpError::Timeout)
    ));
    selvedge_config::update_runtime("network.connect_timeout_ms", 1000_u64)
        .expect("connect config");
    let mut req = request(stalled_url);
    req.timeout = Some(Duration::from_millis(30));
    assert!(matches!(
        connect_websocket(req).await,
        Err(HttpError::Timeout)
    ));
}

#[tokio::test]
async fn websocket_wss_validates_and_reloads_custom_ca() {
    const FLAG: &str = "WS_TLS_CHILD";
    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "websocket_wss_validates_and_reloads_custom_ca",
            FLAG,
        ));
        return;
    }
    let home = init();
    let cert = rcgen::generate_simple_self_signed(vec!["localhost".into()]).expect("cert");
    let key =
        tokio_rustls::rustls::pki_types::PrivatePkcs8KeyDer::from(cert.signing_key.serialize_der());
    let config = tokio_rustls::rustls::ServerConfig::builder_with_provider(Arc::new(
        tokio_rustls::rustls::crypto::ring::default_provider(),
    ))
    .with_safe_default_protocol_versions()
    .expect("versions")
    .with_no_client_auth()
    .with_single_cert(vec![cert.cert.der().clone()], key.into())
    .expect("tls config");
    let acceptor = tokio_rustls::TlsAcceptor::from(Arc::new(config));
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
    let url = format!(
        "wss://localhost:{}/",
        listener.local_addr().expect("addr").port()
    );
    let server = tokio::spawn(async move {
        loop {
            let (socket, _) = listener.accept().await.expect("accept");
            let acceptor = acceptor.clone();
            tokio::spawn(async move {
                if let Ok(tls) = acceptor.accept(socket).await {
                    let mut ws = accept_async(tls).await.expect("handshake");
                    ws.send(Message::Text("trusted".into()))
                        .await
                        .expect("send");
                }
            });
        }
    });
    assert!(matches!(
        connect_websocket(request(url.clone())).await,
        Err(HttpError::Tls { .. })
    ));
    let ca = home.path().join("ca.pem");
    std::fs::write(&ca, cert.cert.pem()).expect("write CA");
    selvedge_config::update_runtime("network.ca_bundle_path", ca.to_str().expect("path"))
        .expect("config");
    let (_, mut receiver) = connect_websocket(request(url.clone()))
        .await
        .expect("trusted connect")
        .split();
    assert_eq!(
        receiver.next_text().await.expect("read"),
        Some("trusted".into())
    );
    std::fs::write(&ca, "invalid cert").expect("replace CA");
    assert!(matches!(
        connect_websocket(request(url)).await,
        Err(HttpError::Build { .. })
    ));
    server.abort();
}

#[tokio::test]
async fn websocket_rejects_binary_and_oversized_messages() {
    const FLAG: &str = "WS_FRAMES_CHILD";
    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "websocket_rejects_binary_and_oversized_messages",
            FLAG,
        ));
        return;
    }
    let _home = init();
    for message in [
        Message::Binary(vec![1].into()),
        Message::Text("x".repeat(4 * 1024 * 1024 + 1).into()),
    ] {
        let oversized = message.len() > 1;
        let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
        let url = format!("ws://{}/", listener.local_addr().expect("addr"));
        let server = tokio::spawn(async move {
            let (socket, _) = listener.accept().await.expect("accept");
            let mut ws = accept_async(socket).await.expect("handshake");
            let _ = ws.send(message).await;
        });
        let (_, mut receiver) = connect_websocket(request(url))
            .await
            .expect("connect")
            .split();
        let error = receiver.next_text().await.expect_err("reject");
        if oversized {
            assert!(matches!(error, HttpError::ResponseTooLarge { .. }));
        } else {
            assert!(matches!(error, HttpError::Io { .. }));
        }
        drop(receiver);
        timeout(Duration::from_secs(2), server)
            .await
            .expect("server stops after rejected frame")
            .expect("server");
    }
}

#[tokio::test]
async fn websocket_sender_closes_connection() {
    const FLAG: &str = "WS_CLOSE_CHILD";
    if !child_mode(FLAG) {
        assert_child_success(&run_child("websocket_sender_closes_connection", FLAG));
        return;
    }
    let _home = init();
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
    let url = format!("ws://{}/", listener.local_addr().expect("addr"));
    let server = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.expect("accept");
        let mut ws = accept_async(socket).await.expect("handshake");
        assert!(matches!(ws.next().await, Some(Ok(Message::Close(_)))));
        ws.flush().await.expect("acknowledge close");
    });
    let (mut sender, mut receiver) = connect_websocket(request(url))
        .await
        .expect("connect")
        .split();
    sender.close().await.expect("close");
    assert_eq!(
        receiver.next_text().await.expect("close acknowledgement"),
        None
    );
    server.await.expect("server");
}
