use std::{
    collections::BTreeMap,
    process::{Command, Output},
    time::Duration,
};

use axum::{
    Json, Router,
    body::Body,
    extract::State,
    http::{HeaderValue, StatusCode},
    routing::post,
};
use base64::Engine;
use selvedge_api::{
    ApiCallTerminalStatus, ApiExecutorConfig, execute_model_call, spawn_model_call_tokio_task,
};
use selvedge_command_model::{
    ApiCallCorrelation, ApiEffectId, ApiOutputEnvelope, ModelCallDispatchRequest,
    ModelCallErrorKind, ModelRunId, RouterIngressApiMessage, TaskId, validate_api_output_envelope,
};
use selvedge_domain_model::{
    ConversationMessage, ConversationPath, MessageContent, MessageRole, ModelProviderProfile,
    ResponsePreference, StructuredPayload, ToolManifest, ToolParameter, ToolParameterType,
    ToolSpec,
};
use tempfile::TempDir;
use tokio::{net::TcpListener, sync::mpsc, task::JoinHandle};

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

    assert_eq!(status, ApiCallTerminalStatus::OutputSent);
    let message = router_rx.recv().await.expect("router message");

    match message {
        RouterIngressApiMessage::ApiOutput(ApiOutputEnvelope::Success { correlation, reply }) => {
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
    assert_eq!(
        captured_body.get("model"),
        Some(&serde_json::json!("gpt-5"))
    );
    assert_eq!(
        captured_body.pointer("/input/0/content/0/text"),
        Some(&serde_json::json!("hello"))
    );
    assert!(
        captured_body
            .pointer("/client_metadata/x-codex-installation-id")
            .is_some_and(|value| value == "550e8400-e29b-41d4-a716-446655440000")
    );
    assert_eq!(
        captured_body.pointer("/reasoning/effort"),
        Some(&serde_json::json!("medium"))
    );
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

    assert_eq!(status, ApiCallTerminalStatus::OutputSent);
    assert!(matches!(
        router_rx.recv().await.expect("router message"),
        RouterIngressApiMessage::ApiOutput(ApiOutputEnvelope::Success { .. })
    ));

    let captured_body = captured_body
        .lock()
        .expect("captured body lock")
        .clone()
        .expect("captured request body");
    assert_eq!(
        captured_body.pointer("/input/1/type"),
        Some(&serde_json::json!("function_call"))
    );
    assert_eq!(
        captured_body.pointer("/input/1/arguments"),
        Some(&serde_json::json!("{\"query\":\"rust\"}"))
    );
    assert_eq!(
        captured_body.pointer("/input/2/type"),
        Some(&serde_json::json!("function_call_output"))
    );
    assert_eq!(
        captured_body.pointer("/input/3/content/0/type"),
        Some(&serde_json::json!("output_text"))
    );
    assert_eq!(
        captured_body.pointer("/tools/0/name"),
        Some(&serde_json::json!("search"))
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

    assert_eq!(status, ApiCallTerminalStatus::OutputSent);
    let message = router_rx.recv().await.expect("router message");

    assert_failure(
        message,
        request.correlation,
        ModelCallErrorKind::ProviderRequest,
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

    assert_eq!(status, ApiCallTerminalStatus::OutputSent);
    let message = router_rx.recv().await.expect("router message");

    match message {
        RouterIngressApiMessage::ApiOutput(envelope) => {
            validate_api_output_envelope(&envelope).expect("valid output envelope");
            match envelope {
                ApiOutputEnvelope::Failure { error, .. } => {
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

    assert_eq!(
        handle.await.expect("join handle"),
        ApiCallTerminalStatus::OutputSent
    );
    assert!(router_rx.recv().await.is_some());
}

fn assert_failure(
    message: RouterIngressApiMessage,
    expected_correlation: ApiCallCorrelation,
    expected_kind: ModelCallErrorKind,
) {
    match message {
        RouterIngressApiMessage::ApiOutput(ApiOutputEnvelope::Failure { correlation, error }) => {
            assert_eq!(
                correlation.api_effect_id,
                expected_correlation.api_effect_id
            );
            assert_eq!(correlation.task_id, expected_correlation.task_id);
            assert_eq!(correlation.model_run_id, expected_correlation.model_run_id);
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

fn child_mode(flag: &str) -> bool {
    std::env::var_os(flag).is_some()
}

fn run_child(test_name: &str, flag: &str) -> Output {
    let current_executable = std::env::current_exe().expect("current test executable");

    Command::new(current_executable)
        .arg("--exact")
        .arg(test_name)
        .env(flag, "1")
        .output()
        .expect("run child test")
}

fn assert_child_success(output: &Output) {
    assert!(output.status.success(), "child test failed: {output:?}");
}

fn init_api_test(config_body: &str) -> TempDir {
    let tempdir = TempDir::new().expect("tempdir");
    let config_home = tempdir.path().join(".selvedge");
    let config_path = config_home.join("config.toml");

    std::fs::create_dir_all(&config_home).expect("create config home");
    std::fs::write(&config_path, config_body).expect("write config");

    selvedge_config::init_with_home(&config_home).expect("init config");
    selvedge_logging::init().expect("init logging");

    tempdir
}

fn write_auth_file(tempdir: &TempDir, auth_file_body: &str) -> std::path::PathBuf {
    let auth_file_path = tempdir.path().join(".selvedge/auth/chatgpt-auth.json");
    std::fs::create_dir_all(
        auth_file_path
            .parent()
            .expect("auth file path must have parent"),
    )
    .expect("create auth dir");
    std::fs::write(&auth_file_path, auth_file_body).expect("write auth file");

    auth_file_path
}

struct TestServer {
    addr: std::net::SocketAddr,
    handle: JoinHandle<()>,
}

impl TestServer {
    fn url(&self, path: &str) -> String {
        format!("http://{}{}", self.addr, path)
    }
}

impl Drop for TestServer {
    fn drop(&mut self) {
        self.handle.abort();
    }
}

async fn spawn_http_server(router: Router) -> TestServer {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind test server");
    let addr = listener.local_addr().expect("local addr");
    let handle = tokio::spawn(async move {
        axum::serve(listener, router).await.expect("serve test app");
    });

    TestServer { addr, handle }
}

fn auth_file_json(id_token: &str, access_token: &str, refresh_token: &str) -> String {
    serde_json::json!({
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
