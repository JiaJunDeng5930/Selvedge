use std::{collections::BTreeMap, time::Duration};

use axum::{
    Json, Router,
    body::Body,
    extract::State,
    http::{HeaderValue, StatusCode},
    routing::post,
};
use selvedge_api::{
    ApiCallTerminalStatus, ApiExecutorConfig, execute_model_call, spawn_model_call_tokio_task,
};
use selvedge_command_model::{
    ApiCallCorrelation, ApiEffectId, ApiOutputEnvelope, ModelCallDispatchRequest,
    ModelCallErrorKind, ModelRunId, RouterIngressApiMessage, TaskId, validate_api_output_envelope,
};
use selvedge_domain_model::{
    ConversationMessage, ConversationPath, MessageContent, MessageRole, ModelFinishReason,
    ModelProviderProfile, ResponsePreference, StructuredPayload, ToolManifest, ToolParameter,
    ToolParameterType, ToolSpec,
};
use selvedge_test_support::{
    chatgpt_auth::{auth_file_json, build_unsigned_jwt as build_jwt, write_auth_file},
    config::init_test_home as init_api_test,
    http::spawn_http_server,
    process::{assert_child_success, child_mode, run_child},
};
use tokio::sync::mpsc;

#[tokio::test(flavor = "multi_thread")]
async fn chatgpt_provider_name_routes_to_chatgpt_api_and_sends_success() {
    const FLAG: &str = "SELVEDGE_API_CHATGPT_DIRECT_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "chatgpt_provider_name_routes_to_chatgpt_api_and_sends_success",
            FLAG,
        ));
        return;
    }

    let captured_body = std::sync::Arc::new(std::sync::Mutex::new(None));
    let captured_body_for_state = std::sync::Arc::clone(&captured_body);
    let api_server = spawn_http_server(
        Router::new()
            .route(
                "/responses",
                post(
                    |State(captured): State<
                        std::sync::Arc<std::sync::Mutex<Option<serde_json::Value>>>,
                    >,
                     Json(body): Json<serde_json::Value>| async move {
                        *captured.lock().expect("captured body lock") = Some(body);
                        let body = Body::from_stream(async_stream::stream! {
                            yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(
                                "data: {\"type\":\"response.output_text.done\",\"item_id\":\"item-1\",\"output_index\":0,\"content_index\":0,\"text\":\"hello \"}\n\n",
                            ));
                            yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(
                                "data: {\"type\":\"response.output_text.done\",\"item_id\":\"item-1\",\"output_index\":0,\"content_index\":1,\"text\":\"from chatgpt\"}\n\n",
                            ));
                            yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(
                                "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp-1\",\"model\":\"gpt-5\",\"usage\":{\"input_tokens\":3,\"output_tokens\":4}}}\n\n",
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
                    },
                ),
            )
            .with_state(captured_body_for_state),
    )
    .await;

    let tempdir = init_api_test(&format!(
        r#"
[llm.providers.chatgpt.settings]
issuer = "http://127.0.0.1:1"

[llm.providers.chatgpt]
base_url = "{}"
"#,
        api_server.url("")
    ));
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(serde_json::json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );

    let mut request = valid_dispatch_request();
    request.provider.max_output_tokens = Some(10);
    let (router_tx, mut router_rx) = mpsc::unbounded_channel();

    let status = execute_model_call(
        request.clone(),
        router_tx.downgrade(),
        ApiExecutorConfig {
            request_timeout: Duration::from_secs(5),
            max_response_bytes: None,
        },
    )
    .await;

    // @verifies selvedge.model.dispatch.success
    assert_eq!(status, ApiCallTerminalStatus::OutputSent);
    let message = router_rx.recv().await.expect("router message");

    match message {
        RouterIngressApiMessage::ApiOutput(ApiOutputEnvelope::Success { correlation, reply }) => {
            // @verifies selvedge.model.dispatch.success
            assert_eq!(correlation, request.correlation);
            assert_eq!(reply.content.as_deref(), Some("hello from chatgpt"));
            assert!(reply.tool_calls.is_empty());
            assert_eq!(reply.usage.expect("usage").input_tokens, 3);
        }
        _ => panic!("unexpected router message"),
    }

    let captured_body = captured_body
        .lock()
        .expect("captured body lock")
        .clone()
        .expect("captured request body");
    // @verifies selvedge.model.chatgpt.build
    assert_eq!(
        captured_body.get("model"),
        Some(&serde_json::json!("gpt-5"))
    );
    // @verifies selvedge.model.chatgpt.message
    assert_eq!(
        captured_body.pointer("/input/0/content/0/text"),
        Some(&serde_json::json!("hello"))
    );
    // @verifies selvedge.model.chatgpt.build
    assert!(
        captured_body
            .pointer("/client_metadata/x-codex-installation-id")
            .is_some_and(|value| value == "550e8400-e29b-41d4-a716-446655440000")
    );
    // @verifies selvedge.model.chatgpt.build
    assert_eq!(
        captured_body.pointer("/reasoning/effort"),
        Some(&serde_json::json!("medium"))
    );
    // @verifies selvedge.model.chatgpt.build
    assert!(captured_body.get("max_output_tokens").is_none());
}

#[tokio::test(flavor = "multi_thread")]
async fn chatgpt_dispatch_preserves_tool_history_items_and_text_preference() {
    const FLAG: &str = "SELVEDGE_API_CHATGPT_TOOL_HISTORY_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "chatgpt_dispatch_preserves_tool_history_items_and_text_preference",
            FLAG,
        ));
        return;
    }

    let captured_body = std::sync::Arc::new(std::sync::Mutex::new(None));
    let captured_body_for_state = std::sync::Arc::clone(&captured_body);
    let api_server = spawn_http_server(
        Router::new()
            .route(
                "/responses",
                post(
                    |State(captured): State<
                        std::sync::Arc<std::sync::Mutex<Option<serde_json::Value>>>,
                    >,
                     Json(body): Json<serde_json::Value>| async move {
                        *captured.lock().expect("captured body lock") = Some(body);
                        let body = Body::from_stream(async_stream::stream! {
                            yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(
                                "data: {\"type\":\"response.output_text.done\",\"item_id\":\"item-1\",\"output_index\":0,\"content_index\":0,\"text\":\"done\"}\n\n",
                            ));
                            yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(
                                "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp-1\",\"model\":\"gpt-5\"}}\n\n",
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
                    },
                ),
            )
            .with_state(captured_body_for_state),
    )
    .await;

    let tempdir = init_api_test(&format!(
        r#"
[llm.providers.chatgpt.settings]
issuer = "http://127.0.0.1:1"

[llm.providers.chatgpt]
base_url = "{}"
"#,
        api_server.url("")
    ));
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(serde_json::json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );

    let mut request = valid_dispatch_request();
    request.conversation.messages.push(ConversationMessage {
        role: MessageRole::Assistant,
        content: MessageContent::Structured(StructuredPayload::Object(BTreeMap::from([
            (
                "function_call_id".to_owned(),
                StructuredPayload::String("call-1".to_owned()),
            ),
            (
                "tool_name".to_owned(),
                StructuredPayload::String("search".to_owned()),
            ),
            (
                "arguments".to_owned(),
                StructuredPayload::Array(vec![StructuredPayload::Object(BTreeMap::from([
                    (
                        "name".to_owned(),
                        StructuredPayload::String("query".to_owned()),
                    ),
                    (
                        "value".to_owned(),
                        StructuredPayload::String("rust".to_owned()),
                    ),
                ]))]),
            ),
        ]))),
        source_node_id: None,
    });
    request.conversation.messages.push(ConversationMessage {
        role: MessageRole::Tool,
        content: MessageContent::Structured(StructuredPayload::Object(BTreeMap::from([
            (
                "function_call_id".to_owned(),
                StructuredPayload::String("call-1".to_owned()),
            ),
            (
                "tool_name".to_owned(),
                StructuredPayload::String("search".to_owned()),
            ),
            (
                "output_text".to_owned(),
                StructuredPayload::String("result".to_owned()),
            ),
        ]))),
        source_node_id: None,
    });
    request.conversation.messages.push(ConversationMessage {
        role: MessageRole::Assistant,
        content: MessageContent::Text("previous answer".to_owned()),
        source_node_id: None,
    });
    request.tool_manifest = Some(ToolManifest {
        tools: vec![ToolSpec {
            name: "search".to_owned(),
            description: "search".to_owned(),
            parameters: vec![ToolParameter {
                name: "query".to_owned(),
                parameter_type: ToolParameterType::String,
                description: "query".to_owned(),
                required: true,
            }],
        }],
    });
    let (router_tx, mut router_rx) = mpsc::unbounded_channel();

    let status = execute_model_call(
        request,
        router_tx.downgrade(),
        ApiExecutorConfig {
            request_timeout: Duration::from_secs(5),
            max_response_bytes: None,
        },
    )
    .await;

    // @verifies selvedge.model.dispatch.success
    assert_eq!(status, ApiCallTerminalStatus::OutputSent);
    // @verifies selvedge.model.dispatch.success
    assert!(matches!(
        router_rx.recv().await.expect("router message"),
        RouterIngressApiMessage::ApiOutput(ApiOutputEnvelope::Success { .. })
    ));

    let captured_body = captured_body
        .lock()
        .expect("captured body lock")
        .clone()
        .expect("captured request body");
    // @verifies selvedge.model.chatgpt.tool_history
    assert_eq!(
        captured_body.pointer("/input/1/type"),
        Some(&serde_json::json!("function_call"))
    );
    // @verifies selvedge.model.chatgpt.tool_args
    assert_eq!(
        captured_body.pointer("/input/1/arguments"),
        Some(&serde_json::json!("{\"query\":\"rust\"}"))
    );
    // @verifies selvedge.model.chatgpt.tool_history
    assert_eq!(
        captured_body.pointer("/input/2/type"),
        Some(&serde_json::json!("function_call_output"))
    );
    // @verifies selvedge.model.chatgpt.content
    assert_eq!(
        captured_body.pointer("/input/3/content/0/type"),
        Some(&serde_json::json!("output_text"))
    );
    // @verifies selvedge.model.chatgpt.tool_schema
    assert_eq!(
        captured_body.pointer("/tools/0/name"),
        Some(&serde_json::json!("search"))
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn chatgpt_max_output_tokens_incomplete_returns_length_reply() {
    const FLAG: &str = "SELVEDGE_API_CHATGPT_LENGTH_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "chatgpt_max_output_tokens_incomplete_returns_length_reply",
            FLAG,
        ));
        return;
    }

    let api_server = spawn_http_server(Router::new().route(
        "/responses",
        post(|| async move {
            let body = Body::from_stream(async_stream::stream! {
                yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(
                    "data: {\"type\":\"response.output_text.done\",\"item_id\":\"item-1\",\"output_index\":0,\"content_index\":0,\"text\":\"truncated\"}\n\n",
                ));
                yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(
                    "data: {\"type\":\"response.incomplete\",\"response\":{\"id\":\"resp-1\",\"reason\":\"max_output_tokens\"}}\n\n",
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
[llm.providers.chatgpt.settings]
issuer = "http://127.0.0.1:1"

[llm.providers.chatgpt]
base_url = "{}"
"#,
        api_server.url("")
    ));
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(serde_json::json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );

    let request = valid_dispatch_request();
    let (router_tx, mut router_rx) = mpsc::unbounded_channel();

    let status = execute_model_call(
        request,
        router_tx.downgrade(),
        ApiExecutorConfig {
            request_timeout: Duration::from_secs(5),
            max_response_bytes: None,
        },
    )
    .await;

    // @verifies selvedge.model.dispatch.success
    assert_eq!(status, ApiCallTerminalStatus::OutputSent);
    let message = router_rx.recv().await.expect("router message");

    match message {
        RouterIngressApiMessage::ApiOutput(ApiOutputEnvelope::Success { reply, .. }) => {
            // @verifies selvedge.model.chatgpt.event
            assert_eq!(reply.content.as_deref(), Some("truncated"));
            assert_eq!(reply.finish_reason, ModelFinishReason::Length);
        }
        _ => panic!("unexpected router message"),
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn chatgpt_imprecise_integer_tool_argument_sends_provider_response_failure() {
    const FLAG: &str = "SELVEDGE_API_CHATGPT_IMPRECISE_INTEGER_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "chatgpt_imprecise_integer_tool_argument_sends_provider_response_failure",
            FLAG,
        ));
        return;
    }

    let api_server = spawn_http_server(Router::new().route(
        "/responses",
        post(|| async move {
            let body = Body::from_stream(async_stream::stream! {
                yield Ok::<_, std::convert::Infallible>(bytes::Bytes::from(
                    "data: {\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"item-1\",\"status\":\"completed\",\"name\":\"lookup\",\"arguments\":\"{\\\"id\\\":9007199254740993}\",\"call_id\":\"call-1\"}}\n\n",
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
[llm.providers.chatgpt.settings]
issuer = "http://127.0.0.1:1"

[llm.providers.chatgpt]
base_url = "{}"
"#,
        api_server.url("")
    ));
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(serde_json::json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );

    let request = valid_dispatch_request();
    let (router_tx, mut router_rx) = mpsc::unbounded_channel();

    let status = execute_model_call(
        request.clone(),
        router_tx.downgrade(),
        ApiExecutorConfig {
            request_timeout: Duration::from_secs(5),
            max_response_bytes: None,
        },
    )
    .await;

    // @verifies selvedge.model.chatgpt.number
    assert_eq!(status, ApiCallTerminalStatus::OutputSent);
    let message = router_rx.recv().await.expect("router message");
    assert_failure(
        message,
        request.correlation,
        ModelCallErrorKind::ProviderResponse,
    );
}

#[tokio::test]
async fn unsupported_provider_name_sends_provider_request_failure_without_external_registry() {
    let mut request = valid_dispatch_request();
    request.provider.provider_name = "unknown".to_owned();
    let (router_tx, mut router_rx) = mpsc::unbounded_channel();

    let status = execute_model_call(
        request.clone(),
        router_tx.downgrade(),
        ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
    )
    .await;

    // @verifies selvedge.model.dispatch.unknown_provider
    assert_eq!(status, ApiCallTerminalStatus::OutputSent);
    let message = router_rx.recv().await.expect("router message");

    assert_failure(
        message,
        request.correlation,
        ModelCallErrorKind::ProviderRequest,
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn provider_credential_validation_obeys_request_timeout() {
    const FLAG: &str = "SELVEDGE_API_PROVIDER_VALIDATION_TIMEOUT_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "provider_credential_validation_obeys_request_timeout",
            FLAG,
        ));
        return;
    }

    let tempdir = init_api_test(
        r#"
[llm.providers.chatgpt.settings]
issuer = "http://127.0.0.1:1"
"#,
    );
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(serde_json::json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );
    let _credential_lock = selvedge_model_credentials::lock_credential_from_home(
        &tempdir.path().join(".selvedge"),
        "chatgpt",
    )
    .await
    .expect("lock provider credential");
    let request = valid_dispatch_request();
    let (router_tx, mut router_rx) = mpsc::unbounded_channel();

    let status = execute_model_call(
        request.clone(),
        router_tx.downgrade(),
        ApiExecutorConfig {
            request_timeout: Duration::from_millis(20),
            max_response_bytes: None,
        },
    )
    .await;

    // @verifies selvedge.model.dispatch.timeout
    assert_eq!(status, ApiCallTerminalStatus::OutputSent);
    let message = router_rx.recv().await.expect("router message");
    assert_failure(
        message,
        request.correlation,
        ModelCallErrorKind::ProviderTimeout,
    );
}

#[tokio::test]
async fn invalid_dispatch_request_sends_validation_failure_before_provider_dispatch() {
    let mut request = valid_dispatch_request();
    request.conversation.messages.clear();
    let (router_tx, mut router_rx) = mpsc::unbounded_channel();

    let status = execute_model_call(
        request.clone(),
        router_tx.downgrade(),
        ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
    )
    .await;

    // @verifies selvedge.model.dispatch.input
    assert_eq!(status, ApiCallTerminalStatus::OutputSent);
    let message = router_rx.recv().await.expect("router message");

    assert_failure(message, request.correlation, ModelCallErrorKind::Validation);
}

#[tokio::test]
async fn invalid_correlation_sends_validation_failure_that_satisfies_output_validation() {
    let mut request = valid_dispatch_request();
    request.correlation.api_effect_id = ApiEffectId(String::new());
    let (router_tx, mut router_rx) = mpsc::unbounded_channel();

    let status = execute_model_call(
        request,
        router_tx.downgrade(),
        ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
    )
    .await;

    // @verifies selvedge.model.dispatch.input
    assert_eq!(status, ApiCallTerminalStatus::OutputSent);
    let message = router_rx.recv().await.expect("router message");

    match message {
        RouterIngressApiMessage::ApiOutput(envelope) => {
            validate_api_output_envelope(&envelope).expect("valid output envelope");
            match envelope {
                ApiOutputEnvelope::Failure { error, .. } => {
                    // @verifies selvedge.model.dispatch.input
                    assert_eq!(error.kind, ModelCallErrorKind::Validation);
                }
                ApiOutputEnvelope::Success { .. } => panic!("unexpected success"),
            }
        }
        _ => panic!("unexpected router message"),
    }
}

#[tokio::test]
async fn closed_router_mailbox_discards_completion_result() {
    let mut request = valid_dispatch_request();
    request.conversation.messages.clear();
    let (router_tx, router_rx) = mpsc::unbounded_channel();
    drop(router_rx);

    let status = execute_model_call(
        request,
        router_tx.downgrade(),
        ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
    )
    .await;

    // @verifies selvedge.model.router
    assert_eq!(status, ApiCallTerminalStatus::RouterClosed);
}

#[tokio::test]
async fn spawn_model_call_tokio_task_returns_terminal_status() {
    let mut request = valid_dispatch_request();
    request.conversation.messages.clear();
    let (router_tx, mut router_rx) = mpsc::unbounded_channel();

    let handle = spawn_model_call_tokio_task(
        request,
        router_tx.downgrade(),
        ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
    );

    // @verifies selvedge.model.dispatch.spawn
    assert_eq!(
        handle.await.expect("join handle"),
        ApiCallTerminalStatus::OutputSent
    );
    // @verifies selvedge.model.dispatch.spawn
    assert!(router_rx.recv().await.is_some());
}

fn assert_failure(
    message: RouterIngressApiMessage,
    expected_correlation: ApiCallCorrelation,
    expected_kind: ModelCallErrorKind,
) {
    match message {
        RouterIngressApiMessage::ApiOutput(ApiOutputEnvelope::Failure { correlation, error }) => {
            // @verifies selvedge.model.failure
            assert_eq!(
                correlation.api_effect_id,
                expected_correlation.api_effect_id
            );
            assert_eq!(correlation.task_id, expected_correlation.task_id);
            assert_eq!(correlation.model_run_id, expected_correlation.model_run_id);
            // @verifies selvedge.model.failure
            assert_eq!(error.kind, expected_kind);
        }
        _ => panic!("unexpected router message"),
    }
}

fn valid_dispatch_request() -> ModelCallDispatchRequest {
    ModelCallDispatchRequest {
        correlation: ApiCallCorrelation {
            api_effect_id: ApiEffectId("api-1".to_owned()),
            task_id: TaskId("task-1".to_owned()),
            model_run_id: ModelRunId("run-1".to_owned()),
        },
        provider: ModelProviderProfile {
            provider_name: "chatgpt".to_owned(),
            model_name: "gpt-5".to_owned(),
            temperature: None,
            max_output_tokens: None,
        },
        conversation: ConversationPath {
            messages: vec![ConversationMessage {
                role: MessageRole::User,
                content: MessageContent::Text("hello".to_owned()),
                source_node_id: None,
            }],
        },
        tool_manifest: None,
        response_preference: ResponsePreference::PlainTextOrToolCalls,
    }
}
