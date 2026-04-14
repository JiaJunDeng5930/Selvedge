mod support;

use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};

use axum::{
    Json, Router,
    body::Body,
    extract::State,
    http::{HeaderMap, HeaderValue, StatusCode},
    routing::post,
};
use base64::Engine;
use chatgpt_api::{
    ChatgptApiEndpointError, ChatgptApiError, ChatgptModelCapabilities, ChatgptReasoningOptions,
    ChatgptRequestContext, ChatgptResponseEvent, ChatgptResponsesRequest, ChatgptTextOptions,
    ContentItem, MessageItem, ResponseItem, stream,
};
use futures::StreamExt;
use serde_json::json;
use support::{
    assert_child_success, child_mode, init_api_test, run_child, spawn_http_server, write_auth_file,
};
use tokio::time::{Duration, sleep};

fn base_request() -> ChatgptResponsesRequest {
    ChatgptResponsesRequest {
        model: "gpt-5".to_owned(),
        model_capabilities: ChatgptModelCapabilities {
            supports_reasoning_summaries: true,
            supports_text_verbosity: true,
            default_reasoning_effort: Some("medium".to_owned()),
        },
        context: ChatgptRequestContext {
            conversation_id: "conversation-123".to_owned(),
            window_generation: 1,
            installation_id: "install-123".to_owned(),
            turn_state: Some("turn-state".to_owned()),
            turn_metadata: None,
            beta_features: vec![],
            subagent: None,
            parent_thread_id: None,
        },
        instructions: Some("follow instructions".to_owned()),
        input: vec![ResponseItem::Message(MessageItem {
            id: Some("msg-1".to_owned()),
            status: Some("completed".to_owned()),
            phase: Some("commentary".to_owned()),
            role: "user".to_owned(),
            content: vec![ContentItem::InputText {
                text: "hello".to_owned(),
            }],
        })],
        tools: vec![],
        parallel_tool_calls: true,
        reasoning: ChatgptReasoningOptions {
            effort: Some("high".to_owned()),
            summary: Some("detailed".to_owned()),
        },
        text: ChatgptTextOptions::default(),
        service_tier: None,
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn stream_yields_events_and_updates_effective_turn_state() {
    const FLAG: &str = "CHATGPT_API_STREAM_SUCCESS_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "stream_yields_events_and_updates_effective_turn_state",
            FLAG,
        ));
        return;
    }

    let api_server = spawn_http_server(Router::new().route(
        "/responses",
        post(|| async {
            let body = Body::from_stream(async_stream::stream! {
                yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(
                    "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp-1\",\"model\":\"gpt-5\",\"service_tier\":\"default\",\"usage\":{\"input_tokens\":1,\"input_tokens_details\":{\"cached_tokens\":2}}}}\n\n",
                ));
                yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from_static(
                    b"data: {\"type\":\"response.output_text.delta\",\"item_id\":\"item-1\",\"output_index\":0,\"content_index\":0,\"delta\":\"\xE4",
                ));
                yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from_static(
                    b"\xBD\xA0\xE5\xA5\xBD\"}\n\n",
                ));
                yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(
                    "data: {\"type\":\"response.output_text.done\",\"item_id\":\"item-1\",\"output_index\":0,\"content_index\":0,\"text\":\"hello\"}\n\n",
                ));
                yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(
                    "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp-1\",\"model\":\"gpt-5\",\"service_tier\":\"default\",\"usage\":{\"output_tokens\":2,\"output_tokens_details\":{\"reasoning_tokens\":3}}}}\n\n",
                ));
            });

            (
                StatusCode::OK,
                [
                    (
                        http::header::CONTENT_TYPE,
                        HeaderValue::from_static("text/event-stream"),
                    ),
                    (
                        http::header::HeaderName::from_static("x-codex-turn-state"),
                        HeaderValue::from_static("turn-state-next"),
                    ),
                ],
                body,
            )
        }),
    ))
    .await;

    let tempdir = init_api_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "http://127.0.0.1:1"

[llm.providers.chatgpt.api]
base_url = "{}"
"#,
        api_server.url("")
    ));
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );

    let mut response_stream = stream(base_request()).await.expect("open stream");
    assert_eq!(
        response_stream.effective_turn_state(),
        Some("turn-state-next")
    );

    let mut events = Vec::new();
    while let Some(item) = response_stream.next().await {
        events.push(item.expect("event should be ok"));
    }

    assert!(matches!(
        events.first(),
        Some(ChatgptResponseEvent::Created(_))
    ));
    assert!(matches!(
        events.first(),
        Some(ChatgptResponseEvent::Created(snapshot))
            if snapshot.usage.as_ref().is_some_and(|usage| usage.cached_input_tokens == Some(2))
    ));
    assert!(matches!(
        events.get(1),
        Some(ChatgptResponseEvent::OutputTextDelta { delta, .. }) if delta == "你好"
    ));
    assert!(matches!(
        events.get(2),
        Some(ChatgptResponseEvent::OutputTextDone { text, .. }) if text == "hello"
    ));
    assert!(matches!(
        events.last(),
        Some(ChatgptResponseEvent::Completed(snapshot))
            if snapshot.usage.as_ref().is_some_and(|usage| usage.reasoning_output_tokens == Some(3))
    ));
}

#[tokio::test(flavor = "multi_thread")]
async fn stream_reauthenticates_once_after_unauthorized() {
    const FLAG: &str = "CHATGPT_API_STREAM_REAUTH_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "stream_reauthenticates_once_after_unauthorized",
            FLAG,
        ));
        return;
    }

    let api_hits = Arc::new(AtomicUsize::new(0));
    let api_hits_for_state = Arc::clone(&api_hits);
    let api_server = spawn_http_server(
        Router::new()
            .route(
                "/responses",
                post(
                    |State(hits): State<Arc<AtomicUsize>>, headers: HeaderMap| async move {
                        let hit_number = hits.fetch_add(1, Ordering::SeqCst);
                        let auth_header = headers
                            .get(http::header::AUTHORIZATION)
                            .and_then(|value| value.to_str().ok())
                            .unwrap_or_default()
                            .to_owned();

                        if hit_number == 0 && auth_header == "Bearer stale-access-token" {
                            return (
                                StatusCode::UNAUTHORIZED,
                                [(http::header::CONTENT_TYPE, HeaderValue::from_static("application/json"))],
                                Body::from("{\"error\":\"expired\"}"),
                            );
                        }

                        let body = Body::from_stream(async_stream::stream! {
                            yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(
                                "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp-1\"}}\n\n",
                            ));
                        });

                        (
                            StatusCode::OK,
                            [(http::header::CONTENT_TYPE, HeaderValue::from_static("Text/Event-Stream"))],
                            body,
                        )
                    },
                ),
            )
            .with_state(api_hits_for_state),
    )
    .await;

    let refresh_hits = Arc::new(AtomicUsize::new(0));
    let refresh_hits_for_state = Arc::clone(&refresh_hits);
    let auth_server = spawn_http_server(
        Router::new()
            .route(
                "/oauth/token",
                post(|State(hits): State<Arc<AtomicUsize>>| async move {
                    hits.fetch_add(1, Ordering::SeqCst);
                    Json(json!({
                        "id_token": build_jwt(json!({
                            "sub": "subject",
                            "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
                        })),
                        "access_token": "fresh-access-token"
                    }))
                }),
            )
            .with_state(refresh_hits_for_state),
    )
    .await;

    let tempdir = init_api_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"

[llm.providers.chatgpt.api]
base_url = "{}"
"#,
        auth_server.url(""),
        api_server.url("")
    ));
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            "stale-access-token",
            "refresh-token",
        ),
    );

    let mut response_stream = stream(base_request()).await.expect("open stream");
    let event = response_stream
        .next()
        .await
        .expect("completed item")
        .expect("completed event");

    assert!(matches!(event, ChatgptResponseEvent::Completed(_)));
    assert_eq!(api_hits.load(Ordering::SeqCst), 2);
    assert_eq!(refresh_hits.load(Ordering::SeqCst), 1);
}

#[tokio::test(flavor = "multi_thread")]
async fn stream_rejects_non_sse_response_heads() {
    const FLAG: &str = "CHATGPT_API_BAD_HEAD_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child("stream_rejects_non_sse_response_heads", FLAG));
        return;
    }

    let api_server = spawn_http_server(Router::new().route(
        "/responses",
        post(|| async {
            (
                StatusCode::OK,
                [(http::header::CONTENT_TYPE, "application/json")],
                "{}",
            )
        }),
    ))
    .await;

    let tempdir = init_api_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "http://127.0.0.1:1"

[llm.providers.chatgpt.api]
base_url = "{}"
"#,
        api_server.url("")
    ));
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );

    let error = match stream(base_request()).await {
        Ok(_) => panic!("bad head must fail"),
        Err(error) => error,
    };

    assert!(matches!(
        error,
        ChatgptApiError::Endpoint(ChatgptApiEndpointError::MalformedResponseHead { .. })
    ));
}

#[tokio::test(flavor = "multi_thread")]
async fn stream_reports_malformed_events() {
    const FLAG: &str = "CHATGPT_API_MALFORMED_EVENT_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child("stream_reports_malformed_events", FLAG));
        return;
    }

    let api_server = spawn_http_server(Router::new().route(
        "/responses",
        post(|| async {
            let body = Body::from_stream(async_stream::stream! {
                yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(
                    "data: {\"type\":\"response.output_text.delta\",\"item_id\":\"item-1\"}\n\n",
                ));
            });

            (
                StatusCode::OK,
                [(
                    http::header::CONTENT_TYPE,
                    HeaderValue::from_static("text/event-stream"),
                )],
                body,
            )
        }),
    ))
    .await;

    let tempdir = init_api_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "http://127.0.0.1:1"

[llm.providers.chatgpt.api]
base_url = "{}"
"#,
        api_server.url("")
    ));
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );

    let mut response_stream = stream(base_request()).await.expect("open stream");
    let error = response_stream
        .next()
        .await
        .expect("error item")
        .expect_err("malformed event must fail");

    assert!(matches!(
        error,
        ChatgptApiError::Endpoint(ChatgptApiEndpointError::MalformedEvent { .. })
    ));
}

#[tokio::test(flavor = "multi_thread")]
async fn stream_maps_top_level_error_events_to_endpoint_errors() {
    const FLAG: &str = "CHATGPT_API_TOP_LEVEL_ERROR_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "stream_maps_top_level_error_events_to_endpoint_errors",
            FLAG,
        ));
        return;
    }

    let api_server = spawn_http_server(Router::new().route(
        "/responses",
        post(|| async {
            let body = Body::from_stream(async_stream::stream! {
                yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(
                    "data: {\"type\":\"error\",\"code\":\"server_busy\",\"message\":\"try again in 7 seconds\"}\n\n",
                ));
            });

            (
                StatusCode::OK,
                [(
                    http::header::CONTENT_TYPE,
                    HeaderValue::from_static("text/event-stream"),
                )],
                body,
            )
        }),
    ))
    .await;

    let tempdir = init_api_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "http://127.0.0.1:1"

[llm.providers.chatgpt.api]
base_url = "{}"
"#,
        api_server.url("")
    ));
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );

    let mut response_stream = stream(base_request()).await.expect("open stream");
    let error = response_stream
        .next()
        .await
        .expect("error item")
        .expect_err("top-level error must fail");

    assert!(matches!(
        error,
        ChatgptApiError::Endpoint(ChatgptApiEndpointError::Other(_))
    ));
}

#[tokio::test(flavor = "multi_thread")]
async fn stream_allows_unknown_final_event_at_eof_without_premature_close() {
    const FLAG: &str = "CHATGPT_API_UNKNOWN_EOF_EVENT_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "stream_allows_unknown_final_event_at_eof_without_premature_close",
            FLAG,
        ));
        return;
    }

    let api_server = spawn_http_server(Router::new().route(
        "/responses",
        post(|| async {
            let body = Body::from_stream(async_stream::stream! {
                yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(
                    "data: {\"type\":\"response.future_terminal\",\"response\":{\"id\":\"resp-1\"}}",
                ));
            });

            (
                StatusCode::OK,
                [(
                    http::header::CONTENT_TYPE,
                    HeaderValue::from_static("text/event-stream"),
                )],
                body,
            )
        }),
    ))
    .await;

    let tempdir = init_api_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "http://127.0.0.1:1"

[llm.providers.chatgpt.api]
base_url = "{}"
"#,
        api_server.url("")
    ));
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );

    let mut response_stream = stream(base_request()).await.expect("open stream");
    let event = response_stream
        .next()
        .await
        .expect("other event")
        .expect("other event value");

    assert!(matches!(event, ChatgptResponseEvent::Other(_)));
    assert!(response_stream.next().await.is_none());
}

#[tokio::test(flavor = "multi_thread")]
async fn stream_reports_completion_timeout() {
    const FLAG: &str = "CHATGPT_API_COMPLETION_TIMEOUT_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child("stream_reports_completion_timeout", FLAG));
        return;
    }

    let api_server = spawn_http_server(Router::new().route(
        "/responses",
        post(|| async {
            let body = Body::from_stream(async_stream::stream! {
                yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(
                    "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp-1\"}}\n\n",
                ));
                sleep(Duration::from_millis(50)).await;
                yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(
                    "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp-1\"}}\n\n",
                ));
            });

            (
                StatusCode::OK,
                [(
                    http::header::CONTENT_TYPE,
                    HeaderValue::from_static("text/event-stream"),
                )],
                body,
            )
        }),
    ))
    .await;

    let tempdir = init_api_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "http://127.0.0.1:1"

[llm.providers.chatgpt.api]
base_url = "{}"
stream_completion_timeout_ms = 10
"#,
        api_server.url("")
    ));
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );

    let mut response_stream = stream(base_request()).await.expect("open stream");
    let _created = response_stream
        .next()
        .await
        .expect("created item")
        .expect("created event");

    let error = response_stream
        .next()
        .await
        .expect("timeout item")
        .expect_err("completion timeout must fail");

    assert!(matches!(
        error,
        ChatgptApiError::LowerLayer(
            chatgpt_api::ChatgptApiLowerLayerError::StreamCompletionTimeout { .. }
        )
    ));
}

#[tokio::test(flavor = "multi_thread")]
async fn stream_accepts_completed_event_at_eof_without_trailing_blank_line() {
    const FLAG: &str = "CHATGPT_API_EOF_COMPLETED_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "stream_accepts_completed_event_at_eof_without_trailing_blank_line",
            FLAG,
        ));
        return;
    }

    let api_server = spawn_http_server(Router::new().route(
        "/responses",
        post(|| async {
            let body = Body::from_stream(async_stream::stream! {
                yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(
                    "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp-1\"}}",
                ));
            });

            (
                StatusCode::OK,
                [(
                    http::header::CONTENT_TYPE,
                    HeaderValue::from_static("text/event-stream"),
                )],
                body,
            )
        }),
    ))
    .await;

    let tempdir = init_api_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "http://127.0.0.1:1"

[llm.providers.chatgpt.api]
base_url = "{}"
"#,
        api_server.url("")
    ));
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );

    let mut response_stream = stream(base_request()).await.expect("open stream");
    let event = response_stream
        .next()
        .await
        .expect("completed item")
        .expect("completed event");

    assert!(matches!(event, ChatgptResponseEvent::Completed(_)));
    assert!(response_stream.next().await.is_none());
}

#[tokio::test(flavor = "multi_thread")]
async fn stream_reports_premature_close_after_non_terminal_final_frame_at_eof() {
    const FLAG: &str = "CHATGPT_API_EOF_NON_TERMINAL_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "stream_reports_premature_close_after_non_terminal_final_frame_at_eof",
            FLAG,
        ));
        return;
    }

    let api_server = spawn_http_server(Router::new().route(
        "/responses",
        post(|| async {
            let body = Body::from_stream(async_stream::stream! {
                yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(
                    "data: {\"type\":\"response.output_text.delta\",\"item_id\":\"item-1\",\"output_index\":0,\"content_index\":0,\"delta\":\"x\"}",
                ));
            });

            (
                StatusCode::OK,
                [(
                    http::header::CONTENT_TYPE,
                    HeaderValue::from_static("text/event-stream"),
                )],
                body,
            )
        }),
    ))
    .await;

    let tempdir = init_api_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "http://127.0.0.1:1"

[llm.providers.chatgpt.api]
base_url = "{}"
"#,
        api_server.url("")
    ));
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );

    let mut response_stream = stream(base_request()).await.expect("open stream");
    let event = response_stream
        .next()
        .await
        .expect("delta item")
        .expect("delta event");
    let error = response_stream
        .next()
        .await
        .expect("premature close item")
        .expect_err("non-terminal EOF must fail");

    assert!(matches!(
        event,
        ChatgptResponseEvent::OutputTextDelta { .. }
    ));
    assert!(matches!(
        error,
        ChatgptApiError::Endpoint(ChatgptApiEndpointError::PrematureClose)
    ));
}

#[tokio::test(flavor = "multi_thread")]
async fn stream_reports_timeout_after_channel_backpressure() {
    const FLAG: &str = "CHATGPT_API_BACKPRESSURE_TIMEOUT_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "stream_reports_timeout_after_channel_backpressure",
            FLAG,
        ));
        return;
    }

    let api_server = spawn_http_server(Router::new().route(
        "/responses",
        post(|| async {
            let body = Body::from_stream(async_stream::stream! {
                for index in 0..40_u64 {
                    yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(format!(
                        "data: {{\"type\":\"response.output_text.delta\",\"item_id\":\"item-1\",\"output_index\":0,\"content_index\":{},\"delta\":\"x\"}}\n\n",
                        index
                    )));
                }
                sleep(Duration::from_millis(50)).await;
            });

            (
                StatusCode::OK,
                [(
                    http::header::CONTENT_TYPE,
                    HeaderValue::from_static("text/event-stream"),
                )],
                body,
            )
        }),
    ))
    .await;

    let tempdir = init_api_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "http://127.0.0.1:1"

[llm.providers.chatgpt.api]
base_url = "{}"
stream_completion_timeout_ms = 10
"#,
        api_server.url("")
    ));
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );

    let mut response_stream = stream(base_request()).await.expect("open stream");
    sleep(Duration::from_millis(30)).await;

    let mut received = 0_u64;
    let mut timeout_seen = false;
    while let Some(item) = response_stream.next().await {
        match item {
            Ok(ChatgptResponseEvent::OutputTextDelta { .. }) => {
                received += 1;
            }
            Err(ChatgptApiError::LowerLayer(
                chatgpt_api::ChatgptApiLowerLayerError::StreamCompletionTimeout { .. },
            )) => {
                timeout_seen = true;
                break;
            }
            other => panic!("unexpected stream item: {other:?}"),
        }
    }

    assert!(received >= 32);
    assert!(timeout_seen);
}

#[tokio::test(flavor = "multi_thread")]
async fn stream_overrides_short_global_request_timeout() {
    const FLAG: &str = "CHATGPT_API_OVERRIDE_GLOBAL_TIMEOUT_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "stream_overrides_short_global_request_timeout",
            FLAG,
        ));
        return;
    }

    let api_server = spawn_http_server(Router::new().route(
        "/responses",
        post(|| async {
            let body = Body::from_stream(async_stream::stream! {
                yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(
                    "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp-1\"}}\n\n",
                ));
                sleep(Duration::from_millis(25)).await;
                yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(
                    "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp-1\"}}\n\n",
                ));
            });

            (
                StatusCode::OK,
                [(
                    http::header::CONTENT_TYPE,
                    HeaderValue::from_static("text/event-stream"),
                )],
                body,
            )
        }),
    ))
    .await;

    let tempdir = init_api_test(&format!(
        r#"
[logging]
level = "debug"

[network]
request_timeout_ms = 5

[llm.providers.chatgpt.auth]
issuer = "http://127.0.0.1:1"

[llm.providers.chatgpt.api]
base_url = "{}"
stream_completion_timeout_ms = 100
"#,
        api_server.url("")
    ));
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );

    let mut response_stream = stream(base_request()).await.expect("open stream");
    let first = response_stream
        .next()
        .await
        .expect("created item")
        .expect("created event");
    let second = response_stream
        .next()
        .await
        .expect("completed item")
        .expect("completed event");

    assert!(matches!(first, ChatgptResponseEvent::Created(_)));
    assert!(matches!(second, ChatgptResponseEvent::Completed(_)));
}

fn auth_file_json(id_token: &str, access_token: &str, refresh_token: &str) -> String {
    json!({
        "schema_version": 1,
        "provider": "chatgpt",
        "login_method": "device_code",
        "tokens": {
            "id_token": id_token,
            "access_token": access_token,
            "refresh_token": refresh_token
        }
    })
    .to_string()
}

fn build_jwt(payload: serde_json::Value) -> String {
    let engine = base64::engine::general_purpose::URL_SAFE_NO_PAD;
    let header = engine.encode(r#"{"alg":"none","typ":"JWT"}"#);
    let payload = engine.encode(payload.to_string());

    format!("{header}.{payload}.signature")
}
