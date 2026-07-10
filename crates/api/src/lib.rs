#![doc = include_str!("../README.md")]

use std::collections::BTreeMap;
use std::future::Future;
use std::io::Write;
use std::panic::AssertUnwindSafe;
use std::pin::Pin;
use std::sync::Arc;
use std::time::Duration;

use chatgpt_api::{
    ChatgptApiEndpointError, ChatgptApiError, ChatgptApiLowerLayerError,
    ChatgptIncompleteEndpointError, ChatgptModelCapabilities, ChatgptReasoningOptions,
    ChatgptRequestContext, ChatgptResponseEvent, ChatgptResponsesRequest, ChatgptTextOptions,
    ContentItem, FunctionCallItem, FunctionCallOutputItem, MessageItem, ResponseItem,
    ToolDescriptor, ToolOutput, stream,
};
use futures_util::{FutureExt, StreamExt};
use selvedge_command_model::{
    ApiOutputEnvelope, ModelCallDispatchRequest, ModelCallError, ModelCallErrorKind,
    RouterIngressApiMessage, RouterIngressWeakSender, validate_dispatch_request,
};
use selvedge_domain_model::{
    ConversationMessage, MessageContent, MessageRole, ModelFinishReason, ModelReply,
    ResponsePreference, StructuredPayload, TokenUsage, ToolCallProposal, ToolManifest,
    ToolParameterType, validate_model_reply,
};
use selvedge_model_providers::{ProviderRegistryError, default_registry};

type ProviderAdapterFuture<'a> =
    Pin<Box<dyn Future<Output = Result<ModelReply, ModelCallError>> + Send + 'a>>;

trait ProviderAdapter: Send + Sync {
    fn execute<'a>(
        &'a self,
        request: &'a ModelCallDispatchRequest,
        config: &'a ApiExecutorConfig,
    ) -> ProviderAdapterFuture<'a>;
}

struct ProviderAdapterRegistry {
    adapters: BTreeMap<&'static str, Arc<dyn ProviderAdapter>>,
}

impl ProviderAdapterRegistry {
    fn new(adapters: Vec<(&'static str, Arc<dyn ProviderAdapter>)>) -> Self {
        Self {
            adapters: adapters.into_iter().collect(),
        }
    }

    fn adapter(&self, provider_id: &str) -> Option<Arc<dyn ProviderAdapter>> {
        self.adapters.get(provider_id).cloned()
    }
}

struct ChatgptProviderAdapter;

impl ProviderAdapter for ChatgptProviderAdapter {
    fn execute<'a>(
        &'a self,
        request: &'a ModelCallDispatchRequest,
        config: &'a ApiExecutorConfig,
    ) -> ProviderAdapterFuture<'a> {
        Box::pin(async move { call_chatgpt(request, config).await })
    }
}

fn default_provider_adapter_registry() -> ProviderAdapterRegistry {
    ProviderAdapterRegistry::new(vec![("chatgpt", Arc::new(ChatgptProviderAdapter))])
}

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

pub async fn execute_model_call(
    request: ModelCallDispatchRequest,
    router_tx: RouterIngressWeakSender,
    config: ApiExecutorConfig,
) -> ApiCallTerminalStatus {
    let envelope = run_model_call(request, config).await;
    send_output(router_tx, envelope).await
}

pub fn spawn_model_call_tokio_task(
    request: ModelCallDispatchRequest,
    router_tx: RouterIngressWeakSender,
    config: ApiExecutorConfig,
) -> tokio::task::JoinHandle<ApiCallTerminalStatus> {
    let correlation = request.correlation.clone();
    let execution = execute_model_call(request, router_tx.clone(), config);
    tokio::spawn(supervise_model_call(correlation, router_tx, execution))
}

async fn supervise_model_call(
    correlation: selvedge_command_model::ApiCallCorrelation,
    router_tx: RouterIngressWeakSender,
    execution: impl Future<Output = ApiCallTerminalStatus>,
) -> ApiCallTerminalStatus {
    match AssertUnwindSafe(execution).catch_unwind().await {
        Ok(status) => status,
        Err(_) => {
            send_output(
                router_tx,
                ApiOutputEnvelope::Failure {
                    correlation,
                    error: model_call_error(
                        ModelCallErrorKind::ProviderResponse,
                        "model call task panicked",
                    ),
                },
            )
            .await
        }
    }
}

async fn run_model_call(
    request: ModelCallDispatchRequest,
    config: ApiExecutorConfig,
) -> ApiOutputEnvelope {
    if let Err(error) = validate_dispatch_request(&request) {
        return failure_envelope(request, error);
    }

    let reply_result = tokio::time::timeout(
        config.request_timeout,
        execute_validated_provider_call(&request, &config),
    )
    .await;

    let reply = match reply_result {
        Ok(Ok(reply)) => reply,
        Ok(Err(error)) => return failure_envelope(request, error),
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

    if let Err(error) = enforce_response_limit(&reply, config.max_response_bytes) {
        return failure_envelope(request, error);
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

    let correlation = request.correlation;
    ApiOutputEnvelope::Success { correlation, reply }
}

async fn execute_validated_provider_call(
    request: &ModelCallDispatchRequest,
    config: &ApiExecutorConfig,
) -> Result<ModelReply, ModelCallError> {
    validate_provider_dispatch_target(request)
        .await
        .map_err(map_provider_registry_error)?;
    let adapter_registry = default_provider_adapter_registry();
    let Some(adapter) = adapter_registry.adapter(&request.provider.provider_name) else {
        return Err(model_call_error(
            ModelCallErrorKind::ProviderRequest,
            "provider adapter is not available",
        ));
    };

    adapter.execute(request, config).await
}

async fn validate_provider_dispatch_target(
    request: &ModelCallDispatchRequest,
) -> Result<(), ProviderRegistryError> {
    let llm_config = selvedge_config::read(|config| config.llm.clone())
        .map_err(|error| ProviderRegistryError::Credential(error.to_string()))?;
    let selvedge_home = selvedge_config::selvedge_home()
        .map_err(|error| ProviderRegistryError::Credential(error.to_string()))?;
    default_registry()
        .validate_dispatch_target_from_home(
            &selvedge_home,
            &llm_config,
            &request.provider.provider_name,
            &request.provider.model_name,
        )
        .await
}

fn map_provider_registry_error(error: ProviderRegistryError) -> ModelCallError {
    match error {
        ProviderRegistryError::UnknownProvider { .. } => model_call_error(
            ModelCallErrorKind::ProviderRequest,
            "provider is not supported",
        ),
        ProviderRegistryError::IncompleteProvider { provider_id } => model_call_error(
            ModelCallErrorKind::ProviderRequest,
            format!("provider {provider_id} is not configured"),
        ),
        ProviderRegistryError::ValidationError {
            provider_id,
            model_name,
        } => model_call_error(
            ModelCallErrorKind::ProviderRequest,
            format!("model {model_name} is not available for provider {provider_id}"),
        ),
        ProviderRegistryError::Credential(error) => model_call_error(
            ModelCallErrorKind::ProviderRequest,
            format!("provider credential lookup failed: {error}"),
        ),
        ProviderRegistryError::DiscoveryError {
            provider_id,
            reason,
        } => model_call_error(
            ModelCallErrorKind::ProviderRequest,
            format!("provider {provider_id} discovery failed: {reason}"),
        ),
        ProviderRegistryError::InvalidProviderDescriptor { provider_id }
        | ProviderRegistryError::DuplicateProviderDescriptor { provider_id } => model_call_error(
            ModelCallErrorKind::ProviderRequest,
            format!("provider registry descriptor {provider_id} is invalid"),
        ),
    }
}

async fn call_chatgpt(
    request: &ModelCallDispatchRequest,
    config: &ApiExecutorConfig,
) -> Result<ModelReply, ModelCallError> {
    let chatgpt_request = chatgpt_request_from_dispatch(request)?;
    let mut response_stream = stream(chatgpt_request).await.map_err(map_chatgpt_error)?;
    let mut byte_counter = config.max_response_bytes.map(BoundedByteCounter::new);
    let mut text_parts = BTreeMap::new();
    let mut fallback_text = String::new();
    let mut tool_calls = Vec::new();
    let mut usage = None;
    let mut finish_reason = ModelFinishReason::Stop;

    while let Some(item) = response_stream.next().await {
        let event = match item {
            Ok(event) => event,
            Err(ChatgptApiError::Endpoint(ChatgptApiEndpointError::Incomplete(error)))
                if is_chatgpt_output_length_incomplete(&error) =>
            {
                finish_reason = ModelFinishReason::Length;
                break;
            }
            Err(error) => return Err(map_chatgpt_error(error)),
        };

        match event {
            ChatgptResponseEvent::OutputTextDelta {
                output_index,
                content_index,
                delta,
                ..
            } => {
                count_stream_bytes(&mut byte_counter, delta.as_bytes())?;
                text_parts
                    .entry((output_index, content_index))
                    .or_insert_with(String::new)
                    .push_str(&delta);
            }
            ChatgptResponseEvent::OutputTextDone {
                output_index,
                content_index,
                text,
                ..
            } => {
                let existing = text_parts
                    .get(&(output_index, content_index))
                    .map(String::as_str)
                    .unwrap_or_default();
                let Some(suffix) = text.strip_prefix(existing) else {
                    return Err(model_call_error(
                        ModelCallErrorKind::ProviderResponse,
                        "chatgpt output text done did not match streamed delta",
                    ));
                };
                count_stream_bytes(&mut byte_counter, suffix.as_bytes())?;
                text_parts.insert((output_index, content_index), text);
            }
            ChatgptResponseEvent::OutputItemDone {
                item: ResponseItem::Message(message),
                ..
            } if text_parts.is_empty() => {
                append_message_content(&mut fallback_text, &message, &mut byte_counter)?;
            }
            ChatgptResponseEvent::OutputItemDone {
                item: ResponseItem::FunctionCall(function_call),
                ..
            } => {
                count_stream_bytes(&mut byte_counter, function_call.arguments.as_bytes())?;
                tool_calls.push(tool_call_from_chatgpt(function_call)?);
            }
            ChatgptResponseEvent::Completed(snapshot) => {
                usage = snapshot.usage.and_then(|usage| {
                    usage.input_tokens.zip(usage.output_tokens).map(
                        |(input_tokens, output_tokens)| TokenUsage {
                            input_tokens,
                            output_tokens,
                        },
                    )
                });
            }
            ChatgptResponseEvent::Created(_)
            | ChatgptResponseEvent::OutputItemAdded { .. }
            | ChatgptResponseEvent::ReasoningSummaryTextDelta { .. }
            | ChatgptResponseEvent::ReasoningSummaryTextDone { .. }
            | ChatgptResponseEvent::ReasoningTextDelta { .. }
            | ChatgptResponseEvent::ReasoningTextDone { .. }
            | ChatgptResponseEvent::Other(_) => {}
            _ => {}
        }
    }

    if request.response_preference == ResponsePreference::PlainTextOnly && !tool_calls.is_empty() {
        return Err(model_call_error(
            ModelCallErrorKind::ProviderResponse,
            "chatgpt returned tool calls for a text-only request",
        ));
    }

    let content = if text_parts.is_empty() {
        fallback_text
    } else {
        text_parts.into_values().collect::<String>()
    };

    if !tool_calls.is_empty() && finish_reason == ModelFinishReason::Stop {
        finish_reason = ModelFinishReason::ToolCalls;
    }

    Ok(ModelReply {
        content: (!content.trim().is_empty()).then_some(content),
        tool_calls,
        usage,
        finish_reason,
    })
}

fn chatgpt_request_from_dispatch(
    request: &ModelCallDispatchRequest,
) -> Result<ChatgptResponsesRequest, ModelCallError> {
    // NOTE: ChatGPT dispatch ignores max_output_tokens because chatgpt-api exposes no request field for this control; max-token incompletes are reported as Length replies.
    Ok(ChatgptResponsesRequest {
        model: request.provider.model_name.clone(),
        // HACK: Pin direct ChatGPT dispatch to the current Selvedge capability decision until a capability source exists.
        model_capabilities: ChatgptModelCapabilities {
            supports_reasoning_summaries: true,
            supports_text_verbosity: true,
            default_reasoning_effort: Some("medium".to_owned()),
        },
        context: ChatgptRequestContext {
            // HACK: Generate a fresh ChatGPT conversation id until task-to-ChatGPT conversation persistence exists.
            conversation_id: uuid::Uuid::new_v4().to_string(),
            // HACK: Keep the initial ChatGPT window generation until replay windows are modeled in Selvedge.
            window_generation: 0,
            // HACK: Use a fixed installation id until Selvedge has installation identity config.
            installation_id: "550e8400-e29b-41d4-a716-446655440000".to_owned(),
            // HACK: Leave turn state empty until Selvedge persists ChatGPT turn state between calls.
            turn_state: None,
            turn_metadata: None,
            beta_features: Vec::new(),
            subagent: None,
            parent_thread_id: None,
        },
        instructions: None,
        input: request
            .conversation
            .messages
            .iter()
            .map(chatgpt_item_from_message)
            .collect::<Result<Vec<_>, _>>()?,
        tools: chatgpt_tools(request.tool_manifest.as_ref(), &request.response_preference),
        parallel_tool_calls: true,
        reasoning: ChatgptReasoningOptions::default(),
        text: ChatgptTextOptions::default(),
        service_tier: None,
    })
}

fn chatgpt_item_from_message(
    message: &ConversationMessage,
) -> Result<ResponseItem, ModelCallError> {
    if let MessageContent::Structured(payload) = &message.content
        && let Some(item) = chatgpt_tool_history_item(&message.role, payload)?
    {
        return Ok(item);
    }

    Ok(ResponseItem::Message(MessageItem {
        id: message
            .source_node_id
            .as_ref()
            .map(|node_id| node_id.0.clone()),
        status: Some("completed".to_owned()),
        role: chatgpt_role(&message.role).to_owned(),
        content: vec![chatgpt_content_item_from_message(message)?],
    }))
}

fn chatgpt_role(role: &MessageRole) -> &'static str {
    match role {
        MessageRole::System => "system",
        MessageRole::Developer => "developer",
        MessageRole::User => "user",
        MessageRole::Assistant => "assistant",
        MessageRole::Tool => "tool",
    }
}

fn chatgpt_content_item_from_message(
    message: &ConversationMessage,
) -> Result<ContentItem, ModelCallError> {
    let text = message_content_text(&message.content)?;
    if message.role == MessageRole::Assistant {
        return Ok(ContentItem::OutputText {
            text,
            raw: serde_json::Map::new(),
        });
    }
    Ok(ContentItem::InputText { text })
}

fn message_content_text(content: &MessageContent) -> Result<String, ModelCallError> {
    match content {
        MessageContent::Text(text) | MessageContent::ToolResultSummary(text) => Ok(text.clone()),
        MessageContent::Structured(payload) => serde_json::to_string(payload).map_err(|error| {
            model_call_error(
                ModelCallErrorKind::ProviderResponse,
                format!("structured message content could not be encoded: {error}"),
            )
        }),
    }
}

fn chatgpt_tool_history_item(
    role: &MessageRole,
    payload: &StructuredPayload,
) -> Result<Option<ResponseItem>, ModelCallError> {
    let StructuredPayload::Object(object) = payload else {
        return Ok(None);
    };

    match role {
        MessageRole::Assistant => {
            let Some(function_call_id) = payload_string_field(object, "function_call_id") else {
                return Ok(None);
            };
            let Some(tool_name) = payload_string_field(object, "tool_name") else {
                return Ok(None);
            };
            let arguments = tool_history_arguments_json(
                object
                    .get("arguments")
                    .ok_or_else(|| missing_tool_history_field("arguments"))?,
            )?;
            Ok(Some(ResponseItem::FunctionCall(FunctionCallItem {
                id: None,
                status: Some("completed".to_owned()),
                name: tool_name.to_owned(),
                namespace: None,
                arguments,
                call_id: function_call_id.to_owned(),
            })))
        }
        MessageRole::Tool => {
            let Some(function_call_id) = payload_string_field(object, "function_call_id") else {
                return Ok(None);
            };
            let output_text = payload_string_field(object, "output_text")
                .ok_or_else(|| missing_tool_history_field("output_text"))?;
            Ok(Some(ResponseItem::FunctionCallOutput(
                FunctionCallOutputItem {
                    id: None,
                    status: Some("completed".to_owned()),
                    call_id: function_call_id.to_owned(),
                    output: ToolOutput::Text(output_text.to_owned()),
                },
            )))
        }
        MessageRole::System | MessageRole::Developer | MessageRole::User => Ok(None),
    }
}

fn payload_string_field<'a>(
    object: &'a BTreeMap<String, StructuredPayload>,
    field: &str,
) -> Option<&'a str> {
    match object.get(field) {
        Some(StructuredPayload::String(value)) => Some(value.as_str()),
        _ => None,
    }
}

fn missing_tool_history_field(field: &str) -> ModelCallError {
    model_call_error(
        ModelCallErrorKind::ProviderRequest,
        format!("tool history is missing {field}"),
    )
}

fn tool_history_arguments_json(payload: &StructuredPayload) -> Result<String, ModelCallError> {
    let StructuredPayload::Array(arguments) = payload else {
        return Err(model_call_error(
            ModelCallErrorKind::ProviderRequest,
            "tool history arguments must be an array",
        ));
    };
    let mut object = serde_json::Map::new();
    for argument in arguments {
        let StructuredPayload::Object(argument) = argument else {
            return Err(model_call_error(
                ModelCallErrorKind::ProviderRequest,
                "tool history argument must be an object",
            ));
        };
        let name = payload_string_field(argument, "name")
            .ok_or_else(|| missing_tool_history_field("argument name"))?;
        let value = argument
            .get("value")
            .ok_or_else(|| missing_tool_history_field("argument value"))?;
        object.insert(name.to_owned(), json_value_from_structured_payload(value));
    }
    serde_json::to_string(&object).map_err(|error| {
        model_call_error(
            ModelCallErrorKind::ProviderRequest,
            format!("tool history arguments could not be encoded: {error}"),
        )
    })
}

fn chatgpt_tools(
    tool_manifest: Option<&ToolManifest>,
    response_preference: &ResponsePreference,
) -> Vec<ToolDescriptor> {
    if *response_preference == ResponsePreference::PlainTextOnly {
        return Vec::new();
    }
    let Some(tool_manifest) = tool_manifest else {
        return Vec::new();
    };

    tool_manifest
        .tools
        .iter()
        .map(|tool| {
            let mut properties = serde_json::Map::new();
            let mut required = Vec::new();
            for parameter in &tool.parameters {
                properties.insert(
                    parameter.name.clone(),
                    serde_json::json!({
                        "type": chatgpt_parameter_type(&parameter.parameter_type),
                        "description": parameter.description,
                    }),
                );
                if parameter.required {
                    required.push(serde_json::Value::String(parameter.name.clone()));
                }
            }

            ToolDescriptor(serde_json::Map::from_iter([
                ("type".to_owned(), serde_json::json!("function")),
                ("name".to_owned(), serde_json::json!(tool.name)),
                (
                    "description".to_owned(),
                    serde_json::json!(tool.description),
                ),
                (
                    "parameters".to_owned(),
                    serde_json::Value::Object(serde_json::Map::from_iter([
                        ("type".to_owned(), serde_json::json!("object")),
                        (
                            "properties".to_owned(),
                            serde_json::Value::Object(properties),
                        ),
                        ("required".to_owned(), serde_json::Value::Array(required)),
                    ])),
                ),
            ]))
        })
        .collect()
}

fn chatgpt_parameter_type(parameter_type: &ToolParameterType) -> &'static str {
    match parameter_type {
        ToolParameterType::String => "string",
        ToolParameterType::Integer => "integer",
        ToolParameterType::Number => "number",
        ToolParameterType::Boolean => "boolean",
    }
}

fn append_message_content(
    content: &mut String,
    message: &MessageItem,
    counter: &mut Option<BoundedByteCounter>,
) -> Result<(), ModelCallError> {
    for item in &message.content {
        match item {
            ContentItem::OutputText { text, .. } | ContentItem::InputText { text } => {
                count_stream_bytes(counter, text.as_bytes())?;
                content.push_str(text);
            }
            ContentItem::InputImage { .. } | ContentItem::Other { .. } => {}
            _ => {}
        }
    }
    Ok(())
}

fn tool_call_from_chatgpt(
    function_call: FunctionCallItem,
) -> Result<ToolCallProposal, ModelCallError> {
    Ok(ToolCallProposal {
        call_id: function_call.call_id,
        tool_name: function_call.name,
        arguments: structured_payload_from_json_string(&function_call.arguments)?,
    })
}

fn structured_payload_from_json_string(raw: &str) -> Result<StructuredPayload, ModelCallError> {
    let value = serde_json::from_str::<serde_json::Value>(raw).map_err(|error| {
        model_call_error(
            ModelCallErrorKind::ProviderResponse,
            format!("chatgpt function-call arguments are invalid JSON: {error}"),
        )
    })?;
    if !value.is_object() {
        return Err(model_call_error(
            ModelCallErrorKind::ProviderResponse,
            "chatgpt function-call arguments must be a JSON object",
        ));
    }
    structured_payload_from_json_value(value)
}

fn structured_payload_from_json_value(
    value: serde_json::Value,
) -> Result<StructuredPayload, ModelCallError> {
    match value {
        serde_json::Value::Object(object) => Ok(StructuredPayload::Object(
            object
                .into_iter()
                .map(|(key, value)| Ok((key, structured_payload_from_json_value(value)?)))
                .collect::<Result<BTreeMap<_, _>, ModelCallError>>()?,
        )),
        serde_json::Value::Array(values) => Ok(StructuredPayload::Array(
            values
                .into_iter()
                .map(structured_payload_from_json_value)
                .collect::<Result<Vec<_>, _>>()?,
        )),
        serde_json::Value::String(value) => Ok(StructuredPayload::String(value)),
        serde_json::Value::Number(value) => {
            Ok(StructuredPayload::Number(f64_from_json_number(&value)?))
        }
        serde_json::Value::Bool(value) => Ok(StructuredPayload::Boolean(value)),
        serde_json::Value::Null => Ok(StructuredPayload::Null),
    }
}

fn f64_from_json_number(value: &serde_json::Number) -> Result<f64, ModelCallError> {
    const MAX_EXACT_INTEGER: u64 = 9_007_199_254_740_992;

    if let Some(unsigned) = value.as_u64() {
        if unsigned > MAX_EXACT_INTEGER {
            return Err(imprecise_chatgpt_number_error());
        }
    } else if let Some(signed) = value.as_i64()
        && signed.unsigned_abs() > MAX_EXACT_INTEGER
    {
        return Err(imprecise_chatgpt_number_error());
    }

    value.as_f64().ok_or_else(imprecise_chatgpt_number_error)
}

fn imprecise_chatgpt_number_error() -> ModelCallError {
    model_call_error(
        ModelCallErrorKind::ProviderResponse,
        "chatgpt function-call arguments contain a number that cannot be represented without precision loss",
    )
}

fn json_value_from_structured_payload(payload: &StructuredPayload) -> serde_json::Value {
    match payload {
        StructuredPayload::Object(object) => serde_json::Value::Object(
            object
                .iter()
                .map(|(key, value)| (key.clone(), json_value_from_structured_payload(value)))
                .collect(),
        ),
        StructuredPayload::Array(values) => serde_json::Value::Array(
            values
                .iter()
                .map(json_value_from_structured_payload)
                .collect(),
        ),
        StructuredPayload::String(value) => serde_json::Value::String(value.clone()),
        StructuredPayload::Number(value) => serde_json::json!(value),
        StructuredPayload::Boolean(value) => serde_json::Value::Bool(*value),
        StructuredPayload::Null => serde_json::Value::Null,
    }
}

fn is_chatgpt_output_length_incomplete(error: &ChatgptIncompleteEndpointError) -> bool {
    error.reason.as_deref() == Some("max_output_tokens")
}

fn map_chatgpt_error(error: ChatgptApiError) -> ModelCallError {
    match error {
        ChatgptApiError::LowerLayer(ChatgptApiLowerLayerError::InvalidInput(error)) => {
            model_call_error(
                ModelCallErrorKind::ProviderRequest,
                format!(
                    "chatgpt request is invalid: {} {}",
                    error.field, error.reason
                ),
            )
        }
        ChatgptApiError::LowerLayer(ChatgptApiLowerLayerError::Config(error)) => model_call_error(
            ModelCallErrorKind::ProviderRequest,
            format!("chatgpt config failed: {error}"),
        ),
        ChatgptApiError::LowerLayer(ChatgptApiLowerLayerError::Auth(error)) => model_call_error(
            ModelCallErrorKind::ProviderRequest,
            format!("chatgpt auth failed: {error:?}"),
        ),
        ChatgptApiError::LowerLayer(ChatgptApiLowerLayerError::StreamCompletionTimeout {
            ..
        })
        | ChatgptApiError::LowerLayer(ChatgptApiLowerLayerError::Client(
            selvedge_client::HttpError::Timeout,
        )) => model_call_error(
            ModelCallErrorKind::ProviderTimeout,
            "chatgpt request timed out",
        ),
        ChatgptApiError::LowerLayer(ChatgptApiLowerLayerError::Client(error)) => model_call_error(
            ModelCallErrorKind::ProviderNetwork,
            format!("chatgpt transport failed: {error}"),
        ),
        ChatgptApiError::Endpoint(ChatgptApiEndpointError::Incomplete(error)) => model_call_error(
            ModelCallErrorKind::ProviderResponse,
            format!("chatgpt response was incomplete: {:?}", error.reason),
        ),
        ChatgptApiError::Endpoint(error) => model_call_error(
            ModelCallErrorKind::ProviderResponse,
            format!("chatgpt endpoint failed: {error}"),
        ),
        _ => model_call_error(
            ModelCallErrorKind::ProviderResponse,
            "chatgpt provider failed with an unknown error",
        ),
    }
}

fn count_stream_bytes(
    counter: &mut Option<BoundedByteCounter>,
    bytes: &[u8],
) -> Result<(), ModelCallError> {
    let Some(counter) = counter else {
        return Ok(());
    };
    counter.write_all(bytes).map_err(|_| {
        model_call_error(
            ModelCallErrorKind::ProviderResponse,
            "provider response exceeded configured byte limit",
        )
    })
}

async fn send_output(
    router_tx: RouterIngressWeakSender,
    envelope: ApiOutputEnvelope,
) -> ApiCallTerminalStatus {
    let Some(router_tx) = router_tx.upgrade() else {
        return ApiCallTerminalStatus::RouterClosed;
    };
    match router_tx.send(RouterIngressApiMessage::ApiOutput(envelope)) {
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

fn model_call_error(kind: ModelCallErrorKind, message: impl Into<String>) -> ModelCallError {
    ModelCallError {
        kind,
        message: message.into(),
    }
}

fn enforce_response_limit(
    reply: &ModelReply,
    max_response_bytes: Option<usize>,
) -> Result<(), ModelCallError> {
    let Some(max_response_bytes) = max_response_bytes else {
        return Ok(());
    };

    if encoded_model_reply_exceeds_limit(reply, max_response_bytes)? {
        return Err(model_call_error(
            ModelCallErrorKind::ProviderResponse,
            "provider response exceeded configured byte limit",
        ));
    }

    Ok(())
}

fn encoded_model_reply_exceeds_limit(
    reply: &ModelReply,
    max_response_bytes: usize,
) -> Result<bool, ModelCallError> {
    let mut counter = BoundedByteCounter::new(max_response_bytes);

    match serde_json::to_writer(&mut counter, reply) {
        Ok(()) => Ok(false),
        Err(_) if counter.limit_exceeded() => Ok(true),
        Err(error) => Err(model_call_error(
            ModelCallErrorKind::ProviderResponse,
            format!("provider response could not be encoded: {error}"),
        )),
    }
}

struct BoundedByteCounter {
    max_bytes: usize,
    bytes_written: usize,
    limit_exceeded: bool,
}

impl BoundedByteCounter {
    fn new(max_bytes: usize) -> Self {
        Self {
            max_bytes,
            bytes_written: 0,
            limit_exceeded: false,
        }
    }

    fn limit_exceeded(&self) -> bool {
        self.limit_exceeded
    }
}

impl std::io::Write for BoundedByteCounter {
    fn write(&mut self, buffer: &[u8]) -> std::io::Result<usize> {
        let Some(next_bytes_written) = self.bytes_written.checked_add(buffer.len()) else {
            self.limit_exceeded = true;
            return Err(std::io::Error::other("response byte limit exceeded"));
        };

        if next_bytes_written > self.max_bytes {
            self.limit_exceeded = true;
            return Err(std::io::Error::other("response byte limit exceeded"));
        }

        self.bytes_written = next_bytes_written;

        Ok(buffer.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use std::io::Write;
    use std::sync::Arc;

    use selvedge_command_model::{
        ApiCallCorrelation, ApiEffectId, ApiOutputEnvelope, ModelCallErrorKind, ModelRunId,
        RouterIngressApiMessage, TaskId,
    };
    use tokio::sync::mpsc;

    use super::{
        ApiCallTerminalStatus, BoundedByteCounter, ProviderAdapterRegistry, supervise_model_call,
    };

    struct TestProviderAdapter;

    impl super::ProviderAdapter for TestProviderAdapter {
        fn execute<'a>(
            &'a self,
            _request: &'a selvedge_command_model::ModelCallDispatchRequest,
            _config: &'a super::ApiExecutorConfig,
        ) -> super::ProviderAdapterFuture<'a> {
            Box::pin(async {
                Ok(selvedge_domain_model::ModelReply {
                    content: Some("ok".to_owned()),
                    tool_calls: Vec::new(),
                    usage: None,
                    finish_reason: selvedge_domain_model::ModelFinishReason::Stop,
                })
            })
        }
    }

    #[test]
    fn bounded_byte_counter_errors_when_limit_is_exceeded() {
        let mut counter = BoundedByteCounter::new(4);

        counter.write_all(b"1234").expect("within limit");
        let error = counter.write_all(b"5").expect_err("over limit");

        assert!(counter.limit_exceeded());
        assert_eq!(error.kind(), std::io::ErrorKind::Other);
    }

    #[test]
    fn provider_adapter_registry_resolves_registered_provider_id() {
        let registry =
            ProviderAdapterRegistry::new(vec![("test-provider", Arc::new(TestProviderAdapter))]);

        assert!(registry.adapter("test-provider").is_some());
        assert!(registry.adapter("missing-provider").is_none());
    }

    #[tokio::test]
    async fn model_call_supervisor_sends_failure_when_execution_panics() {
        let correlation = ApiCallCorrelation {
            api_effect_id: ApiEffectId("api-1".to_owned()),
            task_id: TaskId("task-1".to_owned()),
            model_run_id: ModelRunId("run-1".to_owned()),
        };
        let (router_tx, mut router_rx) = mpsc::unbounded_channel();

        let status = supervise_model_call(correlation.clone(), router_tx.downgrade(), async {
            panic!("provider task panic")
        })
        .await;

        assert_eq!(status, ApiCallTerminalStatus::OutputSent);
        match router_rx.recv().await.expect("terminal output") {
            RouterIngressApiMessage::ApiOutput(ApiOutputEnvelope::Failure {
                correlation: actual,
                error,
            }) => {
                assert_eq!(actual, correlation);
                assert_eq!(error.kind, ModelCallErrorKind::ProviderResponse);
                assert_eq!(error.message, "model call task panicked");
            }
            other => panic!("expected failure output, got {other:?}"),
        }
    }
}
