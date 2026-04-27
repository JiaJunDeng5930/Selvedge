#![doc = include_str!("../README.md")]

use std::{sync::Arc, time::Duration};

use async_trait::async_trait;
use selvedge_command_model_api_slice::{
    ApiOutputEnvelope, ModelCallDispatchRequest, ModelCallError, ModelCallErrorKind,
    RouterIngressApiMessage, RouterIngressSender, validate_dispatch_request,
};
use selvedge_domain_model_api_slice::{
    ConversationPath, ModelProviderProfile, ModelReply, ResponsePreference, ToolManifest,
    validate_model_reply,
};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiExecutorConfig {
    pub request_timeout: Duration,
    pub max_response_bytes: Option<usize>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ApiCallTerminalStatus {
    OutputSent,
    RouterClosed,
}

pub trait ModelProviderRegistry: Send + Sync {
    fn resolve(&self, provider_name: &str) -> Option<Arc<dyn ModelProviderAdapter>>;
}

#[async_trait]
pub trait ModelProviderAdapter: Send + Sync {
    async fn call_model(
        &self,
        request: ProviderModelRequest,
        timeout: Duration,
    ) -> Result<ProviderModelResponse, ProviderCallError>;
}

#[derive(Clone, Debug, PartialEq)]
pub struct ProviderModelRequest {
    pub provider: ModelProviderProfile,
    pub conversation: ConversationPath,
    pub tool_manifest: Option<ToolManifest>,
    pub response_preference: ResponsePreference,
    pub max_response_bytes: Option<usize>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ProviderModelResponse {
    pub reply: Option<ModelReply>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProviderCallError {
    pub kind: ProviderCallErrorKind,
    pub message: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ProviderCallErrorKind {
    Request,
    Network,
    Timeout,
    Cancelled,
    Response,
}

pub async fn execute_model_call(
    request: ModelCallDispatchRequest,
    router_tx: RouterIngressSender,
    provider_registry: Arc<dyn ModelProviderRegistry>,
    config: ApiExecutorConfig,
) -> ApiCallTerminalStatus {
    let envelope = run_model_call(request, provider_registry, config).await;
    send_output(router_tx, envelope).await
}

pub fn spawn_model_call_tokio_task(
    request: ModelCallDispatchRequest,
    router_tx: RouterIngressSender,
    provider_registry: Arc<dyn ModelProviderRegistry>,
    config: ApiExecutorConfig,
) -> tokio::task::JoinHandle<ApiCallTerminalStatus> {
    tokio::spawn(execute_model_call(
        request,
        router_tx,
        provider_registry,
        config,
    ))
}

async fn run_model_call(
    request: ModelCallDispatchRequest,
    provider_registry: Arc<dyn ModelProviderRegistry>,
    config: ApiExecutorConfig,
) -> ApiOutputEnvelope {
    if let Err(error) = validate_dispatch_request(&request) {
        return failure_envelope(request, error);
    }

    let Some(adapter) = provider_registry.resolve(&request.provider.provider_name) else {
        return failure_envelope(
            request,
            model_call_error(
                ModelCallErrorKind::ProviderRequest,
                "provider adapter is not registered",
            ),
        );
    };

    let provider_request = ProviderModelRequest {
        provider: request.provider.clone(),
        conversation: request.conversation.clone(),
        tool_manifest: request.tool_manifest.clone(),
        response_preference: request.response_preference.clone(),
        max_response_bytes: config.max_response_bytes,
    };

    let response_result = tokio::time::timeout(
        config.request_timeout,
        adapter.call_model(provider_request, config.request_timeout),
    )
    .await;

    let response = match response_result {
        Ok(Ok(response)) => response,
        Ok(Err(error)) => return failure_envelope(request, map_provider_error(error)),
        Err(_) => {
            return failure_envelope(
                request,
                model_call_error(
                    ModelCallErrorKind::ProviderTimeout,
                    "provider call exceeded request timeout",
                ),
            );
        }
    };

    let Some(reply) = response.reply else {
        return failure_envelope(
            request,
            model_call_error(
                ModelCallErrorKind::ProviderResponse,
                "provider response did not contain a model reply",
            ),
        );
    };

    let exceeds_response_limit = match exceeds_response_limit(&reply, config.max_response_bytes) {
        Ok(exceeds_response_limit) => exceeds_response_limit,
        Err(error) => return failure_envelope(request, error),
    };

    if exceeds_response_limit {
        return failure_envelope(
            request,
            model_call_error(
                ModelCallErrorKind::ProviderResponse,
                "provider response exceeded configured byte limit",
            ),
        );
    }

    if let Err(error) = validate_model_reply(&reply) {
        return failure_envelope(
            request,
            model_call_error(
                ModelCallErrorKind::ProviderResponse,
                format!("provider response is invalid: {error:?}"),
            ),
        );
    }

    ApiOutputEnvelope::Success {
        correlation: request.correlation,
        reply,
    }
}

async fn send_output(
    router_tx: RouterIngressSender,
    envelope: ApiOutputEnvelope,
) -> ApiCallTerminalStatus {
    match router_tx
        .send(RouterIngressApiMessage::ApiOutput(envelope))
        .await
    {
        Ok(()) => ApiCallTerminalStatus::OutputSent,
        Err(_) => ApiCallTerminalStatus::RouterClosed,
    }
}

fn failure_envelope(request: ModelCallDispatchRequest, error: ModelCallError) -> ApiOutputEnvelope {
    ApiOutputEnvelope::Failure {
        correlation: request.correlation,
        error,
    }
}

fn map_provider_error(error: ProviderCallError) -> ModelCallError {
    let kind = match error.kind {
        ProviderCallErrorKind::Request => ModelCallErrorKind::ProviderRequest,
        ProviderCallErrorKind::Network => ModelCallErrorKind::ProviderNetwork,
        ProviderCallErrorKind::Timeout => ModelCallErrorKind::ProviderTimeout,
        ProviderCallErrorKind::Cancelled => ModelCallErrorKind::Cancelled,
        ProviderCallErrorKind::Response => ModelCallErrorKind::ProviderResponse,
    };

    model_call_error(kind, error.message)
}

fn model_call_error(kind: ModelCallErrorKind, message: impl Into<String>) -> ModelCallError {
    ModelCallError {
        kind,
        message: message.into(),
    }
}

fn exceeds_response_limit(
    reply: &ModelReply,
    max_response_bytes: Option<usize>,
) -> Result<bool, ModelCallError> {
    let Some(max_response_bytes) = max_response_bytes else {
        return Ok(false);
    };

    Ok(model_reply_payload_bytes(reply)? > max_response_bytes)
}

fn model_reply_payload_bytes(reply: &ModelReply) -> Result<usize, ModelCallError> {
    serde_json::to_vec(reply)
        .map(|bytes| bytes.len())
        .map_err(|error| {
            model_call_error(
                ModelCallErrorKind::ProviderResponse,
                format!("provider response could not be encoded: {error}"),
            )
        })
}
