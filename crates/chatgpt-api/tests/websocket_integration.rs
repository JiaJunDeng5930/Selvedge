mod support;

use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};

use axum::{
    Json, Router,
    extract::ws::{Message, WebSocket, WebSocketUpgrade},
    http::{HeaderMap, StatusCode},
    routing::get,
};
use chatgpt_api::{
    ChatgptApiEndpointError, ChatgptApiError, ChatgptApiLowerLayerError, ChatgptFailedEndpointKind,
    ChatgptModelCapabilities, ChatgptReasoningOptions, ChatgptRequestContext, ChatgptResponseEvent,
    ChatgptResponsesRequest, ChatgptTextOptions, FunctionCallOutputItem, ResponseItem, ToolOutput,
    websocket::{
        ChatgptSteerInput, ChatgptSteerRequest, ChatgptWebSocketError, ChatgptWebSocketEvent,
        ChatgptWebSocketEvents, connect_websocket,
    },
};
use serde_json::{Value, json};
use support::{
    assert_child_success, child_mode, init_authenticated_api_test, run_child, spawn_http_server,
};
use tokio::time::{Duration, timeout};

fn request() -> ChatgptResponsesRequest {
    ChatgptResponsesRequest {
        model: "gpt-6-astra".into(),
        model_capabilities: ChatgptModelCapabilities {
            supports_reasoning_summaries: true,
            supports_text_verbosity: true,
            default_reasoning_effort: None,
        },
        context: ChatgptRequestContext {
            conversation_id: "conversation-ws".into(),
            window_generation: 2,
            installation_id: "installation-ws".into(),
            turn_state: Some("original-turn".into()),
            turn_metadata: Some("metadata".into()),
            beta_features: vec!["caller-feature".into()],
            subagent: None,
            parent_thread_id: None,
        },
        instructions: Some("Keep scope small".into()),
        input: vec![],
        tools: vec![],
        allowed_tools: None,
        parallel_tool_calls: true,
        reasoning: ChatgptReasoningOptions::default(),
        text: ChatgptTextOptions::default(),
        service_tier: None,
    }
}

async fn receive(socket: &mut WebSocket) -> Value {
    loop {
        match timeout(Duration::from_secs(5), socket.recv())
            .await
            .expect("server receive deadline")
            .expect("socket frame")
            .expect("socket read")
        {
            Message::Text(text) => return serde_json::from_str(&text).expect("JSON request"),
            Message::Ping(_) | Message::Pong(_) => {}
            other => panic!("unexpected frame: {other:?}"),
        }
    }
}

async fn send(socket: &mut WebSocket, value: Value) {
    socket
        .send(Message::Text(value.to_string().into()))
        .await
        .expect("server send");
}

async fn event(events: &mut ChatgptWebSocketEvents) -> ChatgptWebSocketEvent {
    timeout(Duration::from_secs(5), events.next())
        .await
        .expect("event deadline")
        .expect("event available")
        .expect("valid event")
}

fn steer(target: &str, input: &str) -> ChatgptSteerRequest {
    ChatgptSteerRequest {
        previous_response_id: target.into(),
        input: ChatgptSteerInput::text(input),
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn websocket_steering_continues_across_responses_and_pending_tools() {
    const FLAG: &str = "CHATGPT_WS_TRANSCRIPT";
    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "websocket_steering_continues_across_responses_and_pending_tools",
            FLAG,
        ));
        return;
    }
    let server = spawn_http_server(Router::new().route("/responses", get(|headers: HeaderMap, upgrade: WebSocketUpgrade| async move {
        assert_eq!(headers["authorization"], "Bearer opaque-access-token");
        assert_eq!(headers["chatgpt-account-id"], "workspace-123");
        assert_eq!(headers["session-id"], "conversation-ws");
        assert_eq!(headers["x-codex-window-id"], "conversation-ws:2");
        assert_eq!(headers["x-codex-turn-state"], "original-turn");
        assert_eq!(headers["x-codex-beta-features"], "caller-feature");
        assert!(!headers.contains_key("openai-beta"));
        assert!(!headers.contains_key("accept"));
        let mut response = upgrade.on_upgrade(|mut socket| async move {
            let create = receive(&mut socket).await;
            assert_eq!(create["type"], "response.create");
            assert_eq!(create["model"], "gpt-6-astra");
            assert_eq!(create["stream"], true);
            assert_eq!(create["parallel_tool_calls"], true);
            send(&mut socket, json!({"type":"response.created","response":{"id":"r1"}})).await;
            let update = receive(&mut socket).await;
            assert_eq!(update, json!({"type":"response.steer","previous_response_id":"r1","input":"Use Rust"}));
            send(&mut socket, json!({"type":"response.steer.accepted","sequence_number":1,"steer":{"id":"s1","previous_response_id":"r1"}})).await;
            send(&mut socket, json!({"type":"response.incomplete","response":{"id":"r1","incomplete_details":{"reason":"steered"}}})).await;
            send(&mut socket, json!({"type":"response.created","response":{"id":"r2"}})).await;
            send(&mut socket, json!({"type":"response.completed","response":{"id":"r2"}})).await;
            let create = receive(&mut socket).await;
            assert_eq!(create["previous_response_id"], "r2");
            send(&mut socket, json!({"type":"response.created","response":{"id":"r3"}})).await;
            assert_eq!(receive(&mut socket).await["input"], "Check status first");
            send(&mut socket, json!({"type":"response.steer.accepted","steer":{"id":"s2","previous_response_id":"r3"}})).await;
            send(&mut socket, json!({"type":"response.completed","response":{"id":"r3","output":[{"type":"function_call","call_id":"call1","name":"status","arguments":"{}","async":true}]}})).await;
            send(&mut socket, json!({"type":"response.steer.pending","steer":{"id":"s2","previous_response_id":"r3"},"reason":"waiting_for_required_input","required_input":[{"type":"function_call_output","call_id":"call1","name":"status"}]})).await;
            let continuation = receive(&mut socket).await;
            assert_eq!(continuation["type"], "response.create");
            assert_eq!(continuation["previous_response_id"], "r3");
            assert_eq!(continuation["input"][0]["call_id"], "call1");
            assert_eq!(continuation["input"][0]["output"], "Ready");
            send(&mut socket, json!({"type":"response.created","response":{"id":"r4"}})).await;
            assert_eq!(receive(&mut socket).await["input"], "Original update");
            send(&mut socket, json!({"type":"response.steer.failed","sequence_number":10,"steer":{"id":"s3","previous_response_id":"r4","input":"Original update"},"error":{"code":"too_many_pending_steers","message":"wait","details":{"limit":4}}})).await;
            send(&mut socket, json!({"type":"response.completed","response":{"id":"r4"}})).await;
            while let Some(Ok(message)) = socket.recv().await {
                if matches!(message, Message::Close(_)) { break; }
            }
        });
        response.headers_mut().insert("x-codex-turn-state", "next-turn".parse().expect("header"));
        response
    }))).await;
    let _home = init_authenticated_api_test(&server.url(""));
    let request = request();
    let session = connect_websocket(&request).await.expect("handshake");
    assert_eq!(session.effective_turn_state(), Some("next-turn"));
    let (mut sender, mut events) = session.split();
    let mut changed = request.clone();
    changed.context.turn_state = Some("next-turn".into());
    assert!(matches!(
        sender.create(&changed, None).await,
        Err(ChatgptWebSocketError::Api(ChatgptApiError::LowerLayer(
            ChatgptApiLowerLayerError::InvalidInput(_)
        )))
    ));
    sender.create(&request, None).await.expect("create");
    assert!(matches!(
        event(&mut events).await,
        ChatgptWebSocketEvent::Response(ChatgptResponseEvent::Created(_))
    ));
    assert!(matches!(
        sender.create(&request, None).await,
        Err(ChatgptWebSocketError::ResponseInProgress)
    ));
    sender
        .steer(&steer("r1", "Use Rust"))
        .await
        .expect("steer while reading");
    match event(&mut events).await {
        ChatgptWebSocketEvent::SteerAccepted(accepted) => {
            assert_eq!(accepted.steer.id, "s1");
            assert_eq!(accepted.sequence_number, Some(1));
        }
        other => panic!("unexpected: {other:?}"),
    }
    assert!(matches!(
        event(&mut events).await,
        ChatgptWebSocketEvent::Steered(_)
    ));
    assert!(matches!(
        event(&mut events).await,
        ChatgptWebSocketEvent::Response(ChatgptResponseEvent::Created(_))
    ));
    assert!(matches!(
        event(&mut events).await,
        ChatgptWebSocketEvent::Response(ChatgptResponseEvent::Completed(_))
    ));
    sender
        .create(&request, Some("r2"))
        .await
        .expect("new response on same socket");
    event(&mut events).await;
    sender
        .steer(&steer("r3", "Check status first"))
        .await
        .expect("second steer");
    event(&mut events).await;
    event(&mut events).await;
    match event(&mut events).await {
        ChatgptWebSocketEvent::SteerPending(pending) => {
            assert_eq!(pending.required_input[0]["call_id"], "call1")
        }
        other => panic!("unexpected: {other:?}"),
    }
    let mut continuation = request.clone();
    continuation.input = vec![ResponseItem::FunctionCallOutput(FunctionCallOutputItem {
        internal_chat_message_metadata_passthrough: None,
        id: None,
        status: None,
        call_id: "call1".into(),
        output: ToolOutput::Text("Ready".into()),
    })];
    sender
        .create(&continuation, Some("r3"))
        .await
        .expect("submit required tool result");
    event(&mut events).await;
    sender
        .steer(&steer("r4", "Original update"))
        .await
        .expect("third steer");
    match event(&mut events).await {
        ChatgptWebSocketEvent::SteerFailed(failed) => {
            assert_eq!(failed.input, "Original update");
            assert_eq!(failed.steer.previous_response_id, "r4");
            assert_eq!(failed.error["details"]["limit"], 4);
        }
        other => panic!("unexpected: {other:?}"),
    }
    assert!(matches!(
        event(&mut events).await,
        ChatgptWebSocketEvent::Response(ChatgptResponseEvent::Completed(_))
    ));
    sender.close().await.expect("close");
    assert!(matches!(
        sender.steer(&steer("r4", "again")).await,
        Err(ChatgptWebSocketError::Closed)
    ));
}

#[test]
fn steering_input_rejects_non_user_and_unsupported_shapes() {
    for invalid in [
        Value::Null,
        json!([]),
        json!([{"role":"assistant","content":"no"}]),
        json!([{"role":"user","content":[]}]),
        json!([{"role":"user","content":[{"type":"output_text","text":"no"}]}]),
        json!([{"role":"user","content":"yes","tools":[]}]),
        json!([{"role":"user","content":[{"type":"input_image","image_url":"url","file_id":"file"}]}]),
    ] {
        assert!(
            ChatgptSteerInput::from_value(invalid.clone()).is_err(),
            "accepted {invalid}"
        );
    }
    let valid = json!([{"type":"message","role":"user","content":[{"type":"input_text","text":"Look"},{"type":"input_image","file_id":"image1","detail":"high"},{"type":"input_file","file_id":"file1"}]}]);
    assert_eq!(
        ChatgptSteerInput::from_value(valid.clone())
            .expect("user messages")
            .as_value(),
        &valid
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn websocket_policy_handshake_is_classified_without_retry() {
    const FLAG: &str = "CHATGPT_WS_POLICY_HANDSHAKE";
    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "websocket_policy_handshake_is_classified_without_retry",
            FLAG,
        ));
        return;
    }
    let calls = Arc::new(AtomicUsize::new(0));
    let counter = Arc::clone(&calls);
    let server = spawn_http_server(Router::new().route("/responses", get(move || {
        counter.fetch_add(1, Ordering::SeqCst);
        async { (StatusCode::FORBIDDEN, Json(json!({"error":{"code":"misalignment_policy_violation","message":"blocked","policy":{"reason":"detail"}}}))) }
    }))).await;
    let _home = init_authenticated_api_test(&server.url(""));
    let error = connect_websocket(&request())
        .await
        .err()
        .expect("policy rejection");
    assert_policy(error);
    assert_eq!(calls.load(Ordering::SeqCst), 1);
}

fn assert_policy(error: ChatgptWebSocketError) {
    match error {
        ChatgptWebSocketError::Api(ChatgptApiError::Endpoint(ChatgptApiEndpointError::Failed(
            failed,
        ))) => {
            assert_eq!(
                failed.kind,
                ChatgptFailedEndpointKind::MisalignmentPolicyViolation
            );
            assert_eq!(
                failed.code.as_deref(),
                Some("misalignment_policy_violation")
            );
        }
        other => panic!("unexpected: {other:?}"),
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn websocket_policy_event_closes_sender_and_eof_is_terminal() {
    const FLAG: &str = "CHATGPT_WS_POLICY_EVENT";
    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "websocket_policy_event_closes_sender_and_eof_is_terminal",
            FLAG,
        ));
        return;
    }
    let calls = Arc::new(AtomicUsize::new(0));
    let counter = Arc::clone(&calls);
    let server = spawn_http_server(Router::new().route("/responses", get(move |upgrade: WebSocketUpgrade| {
        let call = counter.fetch_add(1, Ordering::SeqCst);
        async move { upgrade.on_upgrade(move |mut socket| async move {
            receive(&mut socket).await;
            if call == 0 {
                send(&mut socket, json!({"type":"error","error":{"code":"misalignment_policy_violation","message":"stop"}})).await;
                while let Some(Ok(message)) = socket.recv().await {
                    assert!(!matches!(message, Message::Text(_)), "must not send after policy rejection");
                }
            } else { socket.send(Message::Close(None)).await.expect("close"); }
        }) }
    }))).await;
    let _home = init_authenticated_api_test(&server.url(""));
    let request = request();
    let (mut sender, mut events) = connect_websocket(&request).await.expect("connect").split();
    sender.create(&request, None).await.expect("create");
    assert_policy(
        timeout(Duration::from_secs(5), events.next())
            .await
            .expect("deadline")
            .expect("terminal")
            .expect_err("policy"),
    );
    assert!(matches!(
        sender.create(&request, None).await,
        Err(ChatgptWebSocketError::Closed)
    ));
    assert!(events.next().await.is_none());
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    let (mut sender, mut events) = connect_websocket(&request)
        .await
        .expect("explicit new connection")
        .split();
    sender.create(&request, None).await.expect("create");
    let error = timeout(Duration::from_secs(5), events.next())
        .await
        .expect("deadline")
        .expect("terminal")
        .expect_err("premature EOF");
    assert!(matches!(
        error,
        ChatgptWebSocketError::Api(ChatgptApiError::Endpoint(
            ChatgptApiEndpointError::PrematureClose
        ))
    ));
    assert!(matches!(
        sender.steer(&steer("r1", "update")).await,
        Err(ChatgptWebSocketError::Closed)
    ));
    assert_eq!(calls.load(Ordering::SeqCst), 2);
}

#[tokio::test(flavor = "multi_thread")]
async fn websocket_refreshes_unauthorized_handshake_exactly_once() {
    use axum::{response::IntoResponse, routing::post};
    use support::{auth_file_json, build_jwt, init_api_test, write_auth_file};
    const FLAG: &str = "CHATGPT_WS_REFRESH";
    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "websocket_refreshes_unauthorized_handshake_exactly_once",
            FLAG,
        ));
        return;
    }
    let calls = Arc::new(AtomicUsize::new(0));
    let counter = Arc::clone(&calls);
    let api = spawn_http_server(Router::new().route(
        "/responses",
        get(move |headers: HeaderMap, upgrade: WebSocketUpgrade| {
            let call = counter.fetch_add(1, Ordering::SeqCst);
            async move {
                if call == 0 {
                    assert_eq!(headers["authorization"], "Bearer stale-token");
                    return StatusCode::UNAUTHORIZED.into_response();
                }
                assert_eq!(headers["authorization"], "Bearer fresh-token");
                upgrade.on_upgrade(|mut socket| async move {
                    receive(&mut socket).await;
                    send(
                        &mut socket,
                        json!({"type":"response.completed","response":{"id":"r1"}}),
                    )
                    .await;
                    let _ = socket.recv().await;
                })
            }
        }),
    ))
    .await;
    let refresh_calls = Arc::new(AtomicUsize::new(0));
    let refresh_counter = Arc::clone(&refresh_calls);
    let issuer = spawn_http_server(Router::new().route("/oauth/token", post(move || {
        refresh_counter.fetch_add(1, Ordering::SeqCst);
        async { Json(json!({"id_token":build_jwt(json!({"sub":"subject","https://api.openai.com/auth.chatgpt_account_id":"workspace-123"})),"access_token":"fresh-token"})) }
    }))).await;
    let home = init_api_test(&format!(
        "[llm.providers.chatgpt]\nbase_url = {:?}\n[llm.providers.chatgpt.settings]\nissuer = {:?}\n",
        api.url(""),
        issuer.url("")
    ));
    write_auth_file(
        &home,
        &auth_file_json(
            &build_jwt(
                json!({"sub":"subject","https://api.openai.com/auth.chatgpt_account_id":"workspace-123"}),
            ),
            "stale-token",
            "refresh-token",
        ),
    );
    let request = request();
    let (mut sender, mut events) = connect_websocket(&request)
        .await
        .expect("refreshed handshake")
        .split();
    sender.create(&request, None).await.expect("create");
    assert!(matches!(
        event(&mut events).await,
        ChatgptWebSocketEvent::Response(ChatgptResponseEvent::Completed(_))
    ));
    assert_eq!(calls.load(Ordering::SeqCst), 2);
    assert_eq!(refresh_calls.load(Ordering::SeqCst), 1);
}

#[tokio::test(flavor = "multi_thread")]
async fn websocket_deadline_survives_repeated_created_and_backpressure() {
    use support::{auth_file_json, build_jwt, init_api_test, write_auth_file};
    const FLAG: &str = "CHATGPT_WS_DEADLINE";
    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "websocket_deadline_survives_repeated_created_and_backpressure",
            FLAG,
        ));
        return;
    }
    let server = spawn_http_server(Router::new().route(
        "/responses",
        get(|upgrade: WebSocketUpgrade| async {
            upgrade.on_upgrade(|mut socket| async move {
                receive(&mut socket).await;
                for _ in 0..50 {
                    if socket
                        .send(Message::Text(
                            json!({"type":"response.created","response":{"id":"r1"}})
                                .to_string()
                                .into(),
                        ))
                        .await
                        .is_err()
                    {
                        break;
                    }
                    tokio::time::sleep(Duration::from_millis(10)).await;
                }
                let _ = socket.recv().await;
            })
        }),
    ))
    .await;
    let home = init_api_test(&format!(
        "[llm.providers.chatgpt]\nbase_url = {:?}\nstream_completion_timeout_ms = 150\n[llm.providers.chatgpt.settings]\nissuer = \"http://127.0.0.1:1\"\n",
        server.url("")
    ));
    write_auth_file(
        &home,
        &auth_file_json(
            &build_jwt(
                json!({"sub":"subject","https://api.openai.com/auth.chatgpt_account_id":"workspace-123"}),
            ),
            "opaque-access-token",
            "refresh-token",
        ),
    );
    let request = request();
    let (mut sender, mut events) = connect_websocket(&request).await.expect("connect").split();
    sender.create(&request, None).await.expect("create");
    tokio::time::sleep(Duration::from_millis(250)).await;
    let mut count = 0;
    loop {
        match timeout(Duration::from_secs(2), events.next())
            .await
            .expect("deadline")
            .expect("terminal available")
        {
            Ok(_) => count += 1,
            Err(ChatgptWebSocketError::Api(ChatgptApiError::LowerLayer(
                ChatgptApiLowerLayerError::StreamCompletionTimeout { .. },
            ))) => break,
            other => panic!("unexpected: {other:?}"),
        }
    }
    assert!(count < 25, "repeated created must not extend timeout");
    assert!(matches!(
        sender.create(&request, None).await,
        Err(ChatgptWebSocketError::Closed)
    ));
}

#[tokio::test(flavor = "multi_thread")]
async fn websocket_fast_events_apply_backpressure_without_closing() {
    const FLAG: &str = "CHATGPT_WS_BACKPRESSURE";
    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "websocket_fast_events_apply_backpressure_without_closing",
            FLAG,
        ));
        return;
    }
    let server = spawn_http_server(Router::new().route("/responses", get(|upgrade: WebSocketUpgrade| async {
        upgrade.on_upgrade(|mut socket| async move {
            receive(&mut socket).await;
            send(&mut socket, json!({"type":"response.created","response":{"id":"r1"}})).await;
            for index in 0..96 {
                send(&mut socket, json!({"type":"response.output_text.delta","item_id":"m1","output_index":0,"content_index":0,"delta":index.to_string()})).await;
            }
            send(&mut socket, json!({"type":"response.completed","response":{"id":"r1"}})).await;
            let _ = socket.recv().await;
        })
    }))).await;
    let _home = init_authenticated_api_test(&server.url(""));
    let request = request();
    let (mut sender, mut events) = connect_websocket(&request).await.expect("connect").split();
    sender.create(&request, None).await.expect("create");
    tokio::time::sleep(Duration::from_millis(50)).await;
    event(&mut events).await;
    for index in 0..96 {
        match event(&mut events).await {
            ChatgptWebSocketEvent::Response(ChatgptResponseEvent::OutputTextDelta {
                delta,
                ..
            }) => assert_eq!(delta, index.to_string()),
            other => panic!("unexpected: {other:?}"),
        }
    }
    assert!(matches!(
        event(&mut events).await,
        ChatgptWebSocketEvent::Response(ChatgptResponseEvent::Completed(_))
    ));
    drop(events);
    assert!(matches!(
        sender.create(&request, None).await,
        Err(ChatgptWebSocketError::Closed)
    ));
}

#[tokio::test(flavor = "multi_thread")]
async fn websocket_response_limits_reset_and_ordinary_failure_keeps_session() {
    const FLAG: &str = "CHATGPT_WS_LIMITS";
    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "websocket_response_limits_reset_and_ordinary_failure_keeps_session",
            FLAG,
        ));
        return;
    }
    let server = spawn_http_server(Router::new().route("/responses", get(|upgrade: WebSocketUpgrade| async {
        upgrade.on_upgrade(|mut socket| async move {
            receive(&mut socket).await;
            send(&mut socket, json!({"type":"response.failed","response":{"id":"failed","error":{"code":"server_overloaded","message":"busy"}}})).await;
            for id in ["large1", "large2"] {
                receive(&mut socket).await;
                send(&mut socket, json!({"type":"response.created","response":{"id":id}})).await;
                for _ in 0..4 {
                    send(&mut socket, json!({"type":"response.output_text.delta","item_id":"m","output_index":0,"content_index":0,"delta":"x".repeat(600_000)})).await;
                }
                send(&mut socket, json!({"type":"response.completed","response":{"id":id}})).await;
            }
            receive(&mut socket).await;
            send(&mut socket, json!({"type":"response.output_text.delta","item_id":"m","output_index":0,"content_index":0,"delta":"x".repeat(1_048_576)})).await;
            let _ = socket.recv().await;
        })
    }))).await;
    let _home = init_authenticated_api_test(&server.url(""));
    let request = request();
    let (mut sender, mut events) = connect_websocket(&request).await.expect("connect").split();
    sender.create(&request, None).await.expect("create");
    assert!(matches!(
        event(&mut events).await,
        ChatgptWebSocketEvent::ResponseError(_)
    ));
    for _ in 0..2 {
        sender
            .create(&request, None)
            .await
            .expect("continue socket after terminal");
        event(&mut events).await;
        for _ in 0..4 {
            event(&mut events).await;
        }
        assert!(matches!(
            event(&mut events).await,
            ChatgptWebSocketEvent::Response(ChatgptResponseEvent::Completed(_))
        ));
    }
    sender
        .create(&request, None)
        .await
        .expect("create oversized");
    let error = timeout(Duration::from_secs(5), events.next())
        .await
        .expect("deadline")
        .expect("terminal")
        .expect_err("size limit");
    assert!(matches!(
        error,
        ChatgptWebSocketError::Api(ChatgptApiError::Endpoint(
            ChatgptApiEndpointError::ResponseTooLarge {
                limit_bytes: 1_048_576
            }
        ))
    ));
    assert!(matches!(
        sender.create(&request, None).await,
        Err(ChatgptWebSocketError::Closed)
    ));
    sender
        .close()
        .await
        .expect("close remains allowed after session error");
}
