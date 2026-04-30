use std::{collections::BTreeMap, sync::Arc, time::Duration};

use async_trait::async_trait;
use selvedge_api::{
    ApiCallTerminalStatus, ApiExecutorConfig, ModelProviderAdapter, ModelProviderRegistry,
    ProviderCallError, ProviderCallErrorKind, ProviderModelRequest, ProviderModelResponse,
    execute_model_call, spawn_model_call_tokio_task,
};
use selvedge_command_model::{
    ApiCallCorrelation, ApiEffectId, ApiOutputEnvelope, ModelCallDispatchRequest,
    ModelCallErrorKind, ModelRunId, RouterIngressApiMessage, TaskId, validate_api_output_envelope,
};
use selvedge_domain_model::{
    ConversationMessage, ConversationPath, MessageContent, MessageRole, ModelFinishReason,
    ModelProviderProfile, ModelReply, ResponsePreference, StructuredPayload, ToolCallProposal,
};
use tokio::sync::mpsc;

#[tokio::test]
async fn successful_provider_reply_is_sent_once_with_original_correlation() {
    let request = valid_dispatch_request();
    let registry = Arc::new(StaticRegistry::new(Some(Arc::new(StaticAdapter::ok(
        ProviderModelResponse {
            reply: Some(ModelReply {
                content: Some("ok".to_owned()),
                tool_calls: Vec::new(),
                usage: None,
                finish_reason: ModelFinishReason::Stop,
            }),
        },
    )))));
    let (router_tx, mut router_rx) = mpsc::channel(1);

    let status = execute_model_call(
        request.clone(),
        router_tx,
        registry,
        ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
    )
    .await;

    assert_eq!(status, ApiCallTerminalStatus::OutputSent);
    let message = router_rx.recv().await.expect("router message");
    assert!(router_rx.try_recv().is_err());

    match message {
        RouterIngressApiMessage::Api(ApiOutputEnvelope::Success { correlation, reply }) => {
            assert_eq!(correlation.api_effect_id, request.correlation.api_effect_id);
            assert_eq!(correlation.task_id, request.correlation.task_id);
            assert_eq!(correlation.model_run_id, request.correlation.model_run_id);
            assert_eq!(reply.content.as_deref(), Some("ok"));
        }
        _ => panic!("unexpected router message"),
    }
}

#[tokio::test]
async fn invalid_dispatch_request_sends_validation_failure_without_provider_call() {
    let mut request = valid_dispatch_request();
    request.conversation.messages.clear();
    let registry = Arc::new(StaticRegistry::new(Some(Arc::new(StaticAdapter::ok(
        ProviderModelResponse {
            reply: Some(ModelReply {
                content: Some("unused".to_owned()),
                tool_calls: Vec::new(),
                usage: None,
                finish_reason: ModelFinishReason::Stop,
            }),
        },
    )))));
    let (router_tx, mut router_rx) = mpsc::channel(1);

    let status = execute_model_call(
        request.clone(),
        router_tx,
        registry,
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
    let registry = Arc::new(StaticRegistry::new(Some(Arc::new(StaticAdapter::ok(
        ProviderModelResponse {
            reply: Some(ModelReply {
                content: Some("unused".to_owned()),
                tool_calls: Vec::new(),
                usage: None,
                finish_reason: ModelFinishReason::Stop,
            }),
        },
    )))));
    let (router_tx, mut router_rx) = mpsc::channel(1);

    let status = execute_model_call(
        request,
        router_tx,
        registry,
        ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
    )
    .await;

    assert_eq!(status, ApiCallTerminalStatus::OutputSent);
    let message = router_rx.recv().await.expect("router message");

    match message {
        RouterIngressApiMessage::Api(envelope) => {
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
async fn missing_provider_sends_provider_request_failure() {
    let request = valid_dispatch_request();
    let registry = Arc::new(StaticRegistry::new(None));
    let (router_tx, mut router_rx) = mpsc::channel(1);

    let status = execute_model_call(
        request.clone(),
        router_tx,
        registry,
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
async fn provider_network_failure_is_classified() {
    let request = valid_dispatch_request();
    let registry = Arc::new(StaticRegistry::new(Some(Arc::new(StaticAdapter::err(
        ProviderCallError {
            kind: ProviderCallErrorKind::Network,
            message: "network".to_owned(),
        },
    )))));
    let (router_tx, mut router_rx) = mpsc::channel(1);

    let status = execute_model_call(
        request.clone(),
        router_tx,
        registry,
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
        ModelCallErrorKind::ProviderNetwork,
    );
}

#[tokio::test]
async fn provider_timeout_is_classified() {
    let request = valid_dispatch_request();
    let registry = Arc::new(StaticRegistry::new(Some(Arc::new(StaticAdapter::err(
        ProviderCallError {
            kind: ProviderCallErrorKind::Timeout,
            message: "timeout".to_owned(),
        },
    )))));
    let (router_tx, mut router_rx) = mpsc::channel(1);

    let status = execute_model_call(
        request.clone(),
        router_tx,
        registry,
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
        ModelCallErrorKind::ProviderTimeout,
    );
}

#[tokio::test]
async fn provider_cancelled_failure_is_classified() {
    let request = valid_dispatch_request();
    let registry = Arc::new(StaticRegistry::new(Some(Arc::new(StaticAdapter::err(
        ProviderCallError {
            kind: ProviderCallErrorKind::Cancelled,
            message: "cancelled".to_owned(),
        },
    )))));
    let (router_tx, mut router_rx) = mpsc::channel(1);

    let status = execute_model_call(
        request.clone(),
        router_tx,
        registry,
        ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
    )
    .await;

    assert_eq!(status, ApiCallTerminalStatus::OutputSent);
    let message = router_rx.recv().await.expect("router message");

    assert_failure(message, request.correlation, ModelCallErrorKind::Cancelled);
}

#[tokio::test]
async fn invalid_provider_response_is_classified() {
    let request = valid_dispatch_request();
    let registry = Arc::new(StaticRegistry::new(Some(Arc::new(StaticAdapter::ok(
        ProviderModelResponse { reply: None },
    )))));
    let (router_tx, mut router_rx) = mpsc::channel(1);

    let status = execute_model_call(
        request.clone(),
        router_tx,
        registry,
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
        ModelCallErrorKind::ProviderResponse,
    );
}

#[tokio::test]
async fn response_byte_limit_applies_to_tool_call_arguments() {
    let request = valid_dispatch_request();
    let registry = Arc::new(StaticRegistry::new(Some(Arc::new(StaticAdapter::ok(
        ProviderModelResponse {
            reply: Some(ModelReply {
                content: None,
                tool_calls: vec![ToolCallProposal {
                    call_id: "call-1".to_owned(),
                    tool_name: "search".to_owned(),
                    arguments: StructuredPayload::Object(BTreeMap::from([(
                        "query".to_owned(),
                        StructuredPayload::String("0123456789".to_owned()),
                    )])),
                }],
                usage: None,
                finish_reason: ModelFinishReason::ToolCalls,
            }),
        },
    )))));
    let (router_tx, mut router_rx) = mpsc::channel(1);

    let status = execute_model_call(
        request.clone(),
        router_tx,
        registry,
        ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: Some(4),
        },
    )
    .await;

    assert_eq!(status, ApiCallTerminalStatus::OutputSent);
    let message = router_rx.recv().await.expect("router message");

    assert_failure(
        message,
        request.correlation,
        ModelCallErrorKind::ProviderResponse,
    );
}

#[tokio::test]
async fn response_byte_limit_includes_structural_payload_bytes() {
    let request = valid_dispatch_request();
    let registry = Arc::new(StaticRegistry::new(Some(Arc::new(StaticAdapter::ok(
        ProviderModelResponse {
            reply: Some(ModelReply {
                content: None,
                tool_calls: vec![ToolCallProposal {
                    call_id: "call-1".to_owned(),
                    tool_name: "search".to_owned(),
                    arguments: StructuredPayload::Array(vec![
                        StructuredPayload::Array(Vec::new(),);
                        100
                    ]),
                }],
                usage: None,
                finish_reason: ModelFinishReason::ToolCalls,
            }),
        },
    )))));
    let (router_tx, mut router_rx) = mpsc::channel(1);

    let status = execute_model_call(
        request.clone(),
        router_tx,
        registry,
        ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: Some(40),
        },
    )
    .await;

    assert_eq!(status, ApiCallTerminalStatus::OutputSent);
    let message = router_rx.recv().await.expect("router message");

    assert_failure(
        message,
        request.correlation,
        ModelCallErrorKind::ProviderResponse,
    );
}

#[tokio::test]
async fn response_byte_limit_counts_escaped_structured_payload_bytes() {
    let request = valid_dispatch_request();
    let registry = Arc::new(StaticRegistry::new(Some(Arc::new(StaticAdapter::ok(
        ProviderModelResponse {
            reply: Some(ModelReply {
                content: None,
                tool_calls: vec![ToolCallProposal {
                    call_id: "call-1".to_owned(),
                    tool_name: "search".to_owned(),
                    arguments: StructuredPayload::Object(BTreeMap::from([(
                        "\"".to_owned(),
                        StructuredPayload::String("\\\n\"".to_owned()),
                    )])),
                }],
                usage: None,
                finish_reason: ModelFinishReason::ToolCalls,
            }),
        },
    )))));
    let (router_tx, mut router_rx) = mpsc::channel(1);

    let status = execute_model_call(
        request.clone(),
        router_tx,
        registry,
        ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: Some(40),
        },
    )
    .await;

    assert_eq!(status, ApiCallTerminalStatus::OutputSent);
    let message = router_rx.recv().await.expect("router message");

    assert_failure(
        message,
        request.correlation,
        ModelCallErrorKind::ProviderResponse,
    );
}

#[tokio::test]
async fn closed_router_mailbox_discards_completion_result() {
    let request = valid_dispatch_request();
    let registry = Arc::new(StaticRegistry::new(Some(Arc::new(StaticAdapter::ok(
        ProviderModelResponse {
            reply: Some(ModelReply {
                content: Some("ok".to_owned()),
                tool_calls: Vec::new(),
                usage: None,
                finish_reason: ModelFinishReason::Stop,
            }),
        },
    )))));
    let (router_tx, router_rx) = mpsc::channel(1);
    drop(router_rx);

    let status = execute_model_call(
        request,
        router_tx,
        registry,
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
    let request = valid_dispatch_request();
    let registry = Arc::new(StaticRegistry::new(Some(Arc::new(StaticAdapter::ok(
        ProviderModelResponse {
            reply: Some(ModelReply {
                content: Some("ok".to_owned()),
                tool_calls: Vec::new(),
                usage: None,
                finish_reason: ModelFinishReason::Stop,
            }),
        },
    )))));
    let (router_tx, mut router_rx) = mpsc::channel(1);

    let handle = spawn_model_call_tokio_task(
        request,
        router_tx,
        registry,
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
        RouterIngressApiMessage::Api(ApiOutputEnvelope::Failure { correlation, error }) => {
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
            provider_name: "provider".to_owned(),
            model_name: "model".to_owned(),
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

struct StaticRegistry {
    adapter: Option<Arc<dyn ModelProviderAdapter>>,
}

impl StaticRegistry {
    fn new(adapter: Option<Arc<dyn ModelProviderAdapter>>) -> Self {
        Self { adapter }
    }
}

impl ModelProviderRegistry for StaticRegistry {
    fn resolve(&self, _provider_name: &str) -> Option<Arc<dyn ModelProviderAdapter>> {
        self.adapter.clone()
    }
}

struct StaticAdapter {
    response: Result<ProviderModelResponse, ProviderCallError>,
}

impl StaticAdapter {
    fn ok(response: ProviderModelResponse) -> Self {
        Self {
            response: Ok(response),
        }
    }

    fn err(error: ProviderCallError) -> Self {
        Self {
            response: Err(error),
        }
    }
}

#[async_trait]
impl ModelProviderAdapter for StaticAdapter {
    async fn call_model(
        &self,
        _request: ProviderModelRequest,
        _timeout: Duration,
    ) -> Result<ProviderModelResponse, ProviderCallError> {
        self.response.clone()
    }
}
