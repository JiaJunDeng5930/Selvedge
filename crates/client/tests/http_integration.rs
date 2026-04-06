mod support;

use std::{
    convert::Infallible,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

use axum::{
    Json, Router,
    body::Body,
    extract::State,
    http::{HeaderMap, HeaderValue, StatusCode},
    response::Redirect,
    routing::{get, post},
};
use bytes::Bytes;
use futures::StreamExt;
use selvedge_client::{
    HttpError, HttpMethod, HttpRequest, HttpRequestBody, RequestCompression, execute, stream,
};
use support::{
    assert_child_success, child_mode, init_client_test, run_child, spawn_http_proxy,
    spawn_http_server, spawn_https_server,
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpListener,
    task::JoinHandle,
    time::sleep,
};

#[tokio::test(flavor = "multi_thread")]
async fn execute_returns_full_response_body() {
    const FLAG: &str = "SELVEDGE_CLIENT_EXECUTE_SUCCESS_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child("execute_returns_full_response_body", FLAG));
        return;
    }

    let _tempdir = init_client_test().await;
    let server =
        spawn_http_server(Router::new().route("/ok", get(|| async { (StatusCode::OK, "ready") })))
            .await;

    let response = execute(HttpRequest {
        method: HttpMethod::Get,
        url: server.url("/ok"),
        headers: HeaderMap::new(),
        body: HttpRequestBody::Empty,
        timeout: None,
        compression: RequestCompression::None,
    })
    .await
    .expect("execute request");

    assert_eq!(response.status, StatusCode::OK);
    assert_eq!(response.body, Bytes::from_static(b"ready"));
}

#[tokio::test(flavor = "multi_thread")]
async fn execute_returns_status_error_after_redirect_without_retrying() {
    const FLAG: &str = "SELVEDGE_CLIENT_REDIRECT_STATUS_CHILD";

    if !child_mode(FLAG) {
        let output = run_child(
            "execute_returns_status_error_after_redirect_without_retrying",
            FLAG,
        );
        assert_child_success(&output);
        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(stderr.contains("http request returned non-success status"));
        return;
    }

    let _tempdir = init_client_test().await;
    let hits = Arc::new(AtomicUsize::new(0));
    let hits_for_state = Arc::clone(&hits);
    let app = Router::new()
        .route("/redirect", get(|| async { Redirect::temporary("/final") }))
        .route(
            "/final",
            get(|State(hits): State<Arc<AtomicUsize>>| async move {
                hits.fetch_add(1, Ordering::SeqCst);
                (StatusCode::IM_A_TEAPOT, "nope")
            }),
        )
        .with_state(hits_for_state);
    let server = spawn_http_server(app).await;

    let error = execute(HttpRequest {
        method: HttpMethod::Get,
        url: server.url("/redirect"),
        headers: HeaderMap::new(),
        body: HttpRequestBody::Empty,
        timeout: None,
        compression: RequestCompression::None,
    })
    .await
    .expect_err("redirect target should return status error");

    match error {
        HttpError::Status(status) => {
            assert_eq!(status.status, StatusCode::IM_A_TEAPOT);
            assert_eq!(status.url, server.url("/final"));
            assert_eq!(status.body, Bytes::from_static(b"nope"));
        }
        other => panic!("expected status error, got {other:?}"),
    }

    assert_eq!(hits.load(Ordering::SeqCst), 1);
}

#[tokio::test(flavor = "multi_thread")]
async fn execute_applies_request_compression() {
    const FLAG: &str = "SELVEDGE_CLIENT_REQUEST_COMPRESSION_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child("execute_applies_request_compression", FLAG));
        return;
    }

    let _tempdir = init_client_test().await;
    let app = Router::new().route(
        "/capture",
        post(|headers: HeaderMap, body: Bytes| async move {
            let encoding = headers
                .get("content-encoding")
                .and_then(|value| value.to_str().ok())
                .unwrap_or_default()
                .to_owned();
            let decoded = tokio::task::spawn_blocking(move || {
                zstd::stream::decode_all(body.as_ref()).expect("decode request body")
            })
            .await
            .expect("join decoder");

            Json(serde_json::json!({
                "encoding": encoding,
                "body": String::from_utf8(decoded).expect("utf8 body"),
            }))
        }),
    );
    let server = spawn_http_server(app).await;

    let response = execute(HttpRequest {
        method: HttpMethod::Post,
        url: server.url("/capture"),
        headers: HeaderMap::new(),
        body: HttpRequestBody::Bytes(Bytes::from_static(b"payload")),
        timeout: None,
        compression: RequestCompression::Zstd,
    })
    .await
    .expect("compressed request");

    let payload: serde_json::Value = serde_json::from_slice(&response.body).expect("json body");
    assert_eq!(payload["encoding"], "zstd");
    assert_eq!(payload["body"], "payload");
}

#[tokio::test(flavor = "multi_thread")]
async fn execute_uses_config_user_agent_when_missing() {
    const FLAG: &str = "SELVEDGE_CLIENT_USER_AGENT_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "execute_uses_config_user_agent_when_missing",
            FLAG,
        ));
        return;
    }

    let _tempdir = init_client_test().await;
    selvedge_config::update_runtime("network.user_agent", "selvedge-client/test")
        .expect("set user agent");
    let app = Router::new().route(
        "/agent",
        get(|headers: HeaderMap| async move {
            headers
                .get("user-agent")
                .and_then(|value| value.to_str().ok())
                .unwrap_or_default()
                .to_owned()
        }),
    );
    let server = spawn_http_server(app).await;

    let response = execute(HttpRequest {
        method: HttpMethod::Get,
        url: server.url("/agent"),
        headers: HeaderMap::new(),
        body: HttpRequestBody::Empty,
        timeout: None,
        compression: RequestCompression::None,
    })
    .await
    .expect("execute request");

    assert_eq!(response.body, Bytes::from_static(b"selvedge-client/test"));
}

#[tokio::test(flavor = "multi_thread")]
async fn execute_keeps_raw_zstd_response_bytes() {
    const FLAG: &str = "SELVEDGE_CLIENT_RAW_ZSTD_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child("execute_keeps_raw_zstd_response_bytes", FLAG));
        return;
    }

    let _tempdir = init_client_test().await;
    let compressed = tokio::task::spawn_blocking(|| {
        zstd::stream::encode_all("compressed".as_bytes(), 0).expect("compress response")
    })
    .await
    .expect("join compressor");
    let expected = Bytes::from(compressed);
    let response_body = expected.clone();
    let app = Router::new().route(
        "/compressed",
        get(move || {
            let response_body = response_body.clone();
            async move {
                (
                    [(
                        http::header::CONTENT_ENCODING,
                        HeaderValue::from_static("zstd"),
                    )],
                    response_body,
                )
            }
        }),
    );
    let server = spawn_http_server(app).await;

    let response = execute(HttpRequest {
        method: HttpMethod::Get,
        url: server.url("/compressed"),
        headers: HeaderMap::new(),
        body: HttpRequestBody::Empty,
        timeout: None,
        compression: RequestCompression::None,
    })
    .await
    .expect("execute request");

    assert_eq!(response.body, expected);
}

#[tokio::test(flavor = "multi_thread")]
async fn execute_times_out_entire_request() {
    const FLAG: &str = "SELVEDGE_CLIENT_EXECUTE_TIMEOUT_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child("execute_times_out_entire_request", FLAG));
        return;
    }

    let _tempdir = init_client_test().await;
    let app = Router::new().route(
        "/slow",
        get(|| async move {
            sleep(Duration::from_millis(150)).await;
            (StatusCode::OK, "late")
        }),
    );
    let server = spawn_http_server(app).await;

    let error = execute(HttpRequest {
        method: HttpMethod::Get,
        url: server.url("/slow"),
        headers: HeaderMap::new(),
        body: HttpRequestBody::Empty,
        timeout: Some(Duration::from_millis(50)),
        compression: RequestCompression::None,
    })
    .await
    .expect_err("request should time out");

    assert!(matches!(error, HttpError::Timeout));
}

#[tokio::test(flavor = "multi_thread")]
async fn execute_maps_connect_failure() {
    const FLAG: &str = "SELVEDGE_CLIENT_CONNECT_FAILURE_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child("execute_maps_connect_failure", FLAG));
        return;
    }

    let _tempdir = init_client_test().await;
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind listener");
    let port = listener.local_addr().expect("local addr").port();
    drop(listener);

    let error = execute(HttpRequest {
        method: HttpMethod::Get,
        url: format!("http://127.0.0.1:{port}/missing"),
        headers: HeaderMap::new(),
        body: HttpRequestBody::Empty,
        timeout: Some(Duration::from_millis(200)),
        compression: RequestCompression::None,
    })
    .await
    .expect_err("connect should fail");

    assert!(matches!(error, HttpError::Connect { .. }));
}

#[tokio::test(flavor = "multi_thread")]
async fn execute_maps_tls_failure() {
    const FLAG: &str = "SELVEDGE_CLIENT_TLS_FAILURE_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child("execute_maps_tls_failure", FLAG));
        return;
    }

    let _tempdir = init_client_test().await;
    let server = spawn_https_server(StatusCode::OK, Bytes::from_static(b"secure")).await;

    let error = execute(HttpRequest {
        method: HttpMethod::Get,
        url: server.url.clone(),
        headers: HeaderMap::new(),
        body: HttpRequestBody::Empty,
        timeout: Some(Duration::from_secs(2)),
        compression: RequestCompression::None,
    })
    .await
    .expect_err("tls should fail without custom ca");

    assert!(matches!(error, HttpError::Tls { .. }));
}

#[tokio::test(flavor = "multi_thread")]
async fn execute_accepts_custom_ca_bundle() {
    const FLAG: &str = "SELVEDGE_CLIENT_CA_BUNDLE_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child("execute_accepts_custom_ca_bundle", FLAG));
        return;
    }

    let tempdir = init_client_test().await;
    let server = spawn_https_server(StatusCode::OK, Bytes::from_static(b"secure")).await;
    let bundle_path = tempdir.path().join("ca.pem");
    std::fs::write(&bundle_path, server.ca_cert_pem.as_bytes()).expect("write ca bundle");
    selvedge_config::update_runtime(
        "network.ca_bundle_path",
        bundle_path.to_string_lossy().to_string(),
    )
    .expect("set ca bundle");

    let response = execute(HttpRequest {
        method: HttpMethod::Get,
        url: server.url.clone(),
        headers: HeaderMap::new(),
        body: HttpRequestBody::Empty,
        timeout: Some(Duration::from_secs(2)),
        compression: RequestCompression::None,
    })
    .await
    .expect("custom ca should succeed");

    assert_eq!(response.status, StatusCode::OK);
    assert_eq!(response.body, Bytes::from_static(b"secure"));
}

#[tokio::test(flavor = "multi_thread")]
async fn execute_uses_explicit_proxy() {
    const FLAG: &str = "SELVEDGE_CLIENT_PROXY_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child("execute_uses_explicit_proxy", FLAG));
        return;
    }

    let _tempdir = init_client_test().await;
    let origin = spawn_http_server(
        Router::new().route("/proxied", get(|| async { (StatusCode::OK, "proxied") })),
    )
    .await;
    let proxy = spawn_http_proxy().await;
    selvedge_config::update_runtime("network.proxy_url", proxy.url.clone()).expect("set proxy");

    let response = execute(HttpRequest {
        method: HttpMethod::Get,
        url: origin.url("/proxied"),
        headers: HeaderMap::new(),
        body: HttpRequestBody::Empty,
        timeout: Some(Duration::from_secs(2)),
        compression: RequestCompression::None,
    })
    .await
    .expect("request through proxy");

    assert_eq!(response.body, Bytes::from_static(b"proxied"));
    assert_eq!(proxy.hit_count(), 1);
}

#[tokio::test(flavor = "multi_thread")]
async fn execute_preserves_status_when_error_body_is_truncated() {
    const FLAG: &str = "SELVEDGE_CLIENT_TRUNCATED_STATUS_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "execute_preserves_status_when_error_body_is_truncated",
            FLAG,
        ));
        return;
    }

    let _tempdir = init_client_test().await;
    let (url, server_handle) = spawn_truncated_status_server().await;

    let error = execute(HttpRequest {
        method: HttpMethod::Get,
        url,
        headers: HeaderMap::new(),
        body: HttpRequestBody::Empty,
        timeout: Some(Duration::from_secs(1)),
        compression: RequestCompression::None,
    })
    .await
    .expect_err("truncated error body should still return status");

    match error {
        HttpError::Status(status) => {
            assert_eq!(status.status, StatusCode::BAD_GATEWAY);
            assert_eq!(status.body, Bytes::from_static(b"par"));
        }
        other => panic!("expected status error, got {other:?}"),
    }

    server_handle.abort();
}

#[tokio::test(flavor = "multi_thread")]
async fn stream_returns_status_before_entering_body() {
    const FLAG: &str = "SELVEDGE_CLIENT_STREAM_STATUS_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "stream_returns_status_before_entering_body",
            FLAG,
        ));
        return;
    }

    let _tempdir = init_client_test().await;
    let server = spawn_http_server(Router::new().route(
        "/status",
        get(|| async { (StatusCode::BAD_REQUEST, "bad request") }),
    ))
    .await;

    let error = stream(HttpRequest {
        method: HttpMethod::Get,
        url: server.url("/status"),
        headers: HeaderMap::new(),
        body: HttpRequestBody::Empty,
        timeout: Some(Duration::from_secs(1)),
        compression: RequestCompression::None,
    })
    .await
    .expect_err("stream should return status error");

    match error {
        HttpError::Status(status) => {
            assert_eq!(status.status, StatusCode::BAD_REQUEST);
            assert_eq!(status.body, Bytes::from_static(b"bad request"));
        }
        other => panic!("expected status error, got {other:?}"),
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn stream_request_timeout_covers_wait_for_first_chunk() {
    const FLAG: &str = "SELVEDGE_CLIENT_STREAM_FIRST_CHUNK_TIMEOUT_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "stream_request_timeout_covers_wait_for_first_chunk",
            FLAG,
        ));
        return;
    }

    let _tempdir = init_client_test().await;
    let app = Router::new().route(
        "/stream",
        get(|| async {
            let body = Body::from_stream(async_stream::stream! {
                sleep(Duration::from_millis(120)).await;
                yield Ok::<Bytes, Infallible>(Bytes::from_static(b"late"));
            });

            (StatusCode::OK, body)
        }),
    );
    let server = spawn_http_server(app).await;

    let response = stream(HttpRequest {
        method: HttpMethod::Get,
        url: server.url("/stream"),
        headers: HeaderMap::new(),
        body: HttpRequestBody::Empty,
        timeout: Some(Duration::from_millis(50)),
        compression: RequestCompression::None,
    })
    .await
    .expect("response head should arrive");

    let chunks = response.body.collect::<Vec<_>>().await;

    assert_eq!(chunks.len(), 1);
    assert!(matches!(chunks[0], Err(HttpError::Timeout)));
}

#[tokio::test(flavor = "multi_thread")]
async fn stream_times_out_on_idle_gap() {
    const FLAG: &str = "SELVEDGE_CLIENT_STREAM_IDLE_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child("stream_times_out_on_idle_gap", FLAG));
        return;
    }

    let _tempdir = init_client_test().await;
    selvedge_config::update_runtime("network.stream_idle_timeout_ms", 50_u64)
        .expect("set idle timeout");
    let app = Router::new().route(
        "/stream",
        get(|| async {
            let body = Body::from_stream(async_stream::stream! {
                yield Ok::<Bytes, Infallible>(Bytes::from_static(b"first"));
                sleep(Duration::from_millis(120)).await;
                yield Ok::<Bytes, Infallible>(Bytes::from_static(b"second"));
            });

            (StatusCode::OK, body)
        }),
    );
    let server = spawn_http_server(app).await;

    let response = stream(HttpRequest {
        method: HttpMethod::Get,
        url: server.url("/stream"),
        headers: HeaderMap::new(),
        body: HttpRequestBody::Empty,
        timeout: Some(Duration::from_secs(1)),
        compression: RequestCompression::None,
    })
    .await
    .expect("start stream");

    let chunks = response.body.collect::<Vec<_>>().await;

    assert_eq!(chunks.len(), 2);
    assert_eq!(
        chunks[0].as_ref().expect("first chunk"),
        &Bytes::from_static(b"first")
    );
    assert!(matches!(chunks[1], Err(HttpError::Timeout)));
}

#[tokio::test(flavor = "multi_thread")]
async fn stream_returns_transport_error_once_after_body_starts() {
    const FLAG: &str = "SELVEDGE_CLIENT_STREAM_TRANSPORT_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "stream_returns_transport_error_once_after_body_starts",
            FLAG,
        ));
        return;
    }

    let _tempdir = init_client_test().await;
    let (url, server_handle) = spawn_broken_chunked_server().await;

    let response = stream(HttpRequest {
        method: HttpMethod::Get,
        url,
        headers: HeaderMap::new(),
        body: HttpRequestBody::Empty,
        timeout: Some(Duration::from_secs(1)),
        compression: RequestCompression::None,
    })
    .await
    .expect("start stream");

    let chunks = response.body.collect::<Vec<_>>().await;

    assert_eq!(chunks.len(), 2);
    assert_eq!(
        chunks[0].as_ref().expect("first chunk"),
        &Bytes::from_static(b"first")
    );
    assert!(matches!(chunks[1], Err(HttpError::Io { .. })));
    server_handle.abort();
}

async fn spawn_broken_chunked_server() -> (String, JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind broken chunked server");
    let addr = listener.local_addr().expect("local addr");
    let handle = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.expect("accept socket");
        let mut buffer = [0_u8; 2048];
        let _ = socket.read(&mut buffer).await.expect("read request");
        socket
            .write_all(b"HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n\r\n5\r\nfirst\r\n")
            .await
            .expect("write partial chunked response");
        socket.shutdown().await.expect("shutdown socket");
    });

    (format!("http://{addr}/stream"), handle)
}

async fn spawn_truncated_status_server() -> (String, JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind truncated status server");
    let addr = listener.local_addr().expect("local addr");
    let handle = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.expect("accept socket");
        let mut buffer = [0_u8; 2048];
        let _ = socket.read(&mut buffer).await.expect("read request");
        socket
            .write_all(b"HTTP/1.1 502 Bad Gateway\r\ncontent-length: 7\r\n\r\npar")
            .await
            .expect("write partial error response");
        socket.shutdown().await.expect("shutdown socket");
    });

    (format!("http://{addr}/status"), handle)
}
