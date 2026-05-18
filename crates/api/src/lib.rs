#![doc = include_str!("../README.md")]
//! @behavior selvedge.model Task model requests produce a task-visible model reply or a command-reportable model error.
//! @behavior selvedge.model.dispatch.unknown_provider Unknown provider ids produce task-visible provider-request failures through registry dispatch validation.

use std::collections::BTreeMap;
use std::future::Future;
use std::io::Write;
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
use futures::StreamExt;
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

// @intent selvedge.model.dispatch.adapter.future Provider adapter futures abstract asynchronous provider execution behind the dispatch registry.
type ProviderAdapterFuture<'a> =
    Pin<Box<dyn Future<Output = Result<ModelReply, ModelCallError>> + Send + 'a>>;

// @intent selvedge.model.dispatch.adapter Provider adapters hide provider-specific request execution behind a registry lookup boundary.
trait ProviderAdapter: Send + Sync {
    // @behavior selvedge.model.dispatch.adapter.execute Provider adapters execute validated model dispatch requests and return unified model replies.
    fn execute<'a>(
        &'a self,
        request: &'a ModelCallDispatchRequest,
        config: &'a ApiExecutorConfig,
    ) -> ProviderAdapterFuture<'a>;
}

// @intent selvedge.model.dispatch.adapter.registry.abstraction Provider adapter registries decouple provider id dispatch from provider-specific request execution.
// @constraint selvedge.model.dispatch.adapter.registry The provider adapter registry maps provider ids to executable provider adapters.
struct ProviderAdapterRegistry {
    adapters: BTreeMap<&'static str, Arc<dyn ProviderAdapter>>,
}

impl ProviderAdapterRegistry {
    // @intent selvedge.model.dispatch.adapter.registry.constructor Provider adapter registry construction provides an explicit adapter injection boundary for dispatch tests and defaults.
    // @constraint selvedge.model.dispatch.adapter.registry.new Provider adapter registry construction stores executable adapters by provider id.
    fn new(adapters: Vec<(&'static str, Arc<dyn ProviderAdapter>)>) -> Self {
        Self {
            adapters: adapters.into_iter().collect(),
        }
    }

    // @intent selvedge.model.dispatch.adapter.registry.lookup_boundary Provider adapter lookup keeps provider id dispatch outside provider-specific request code.
    // @behavior selvedge.model.dispatch.adapter.registry.lookup Provider adapter lookup returns the executable adapter registered for a provider id.
    fn adapter(&self, provider_id: &str) -> Option<Arc<dyn ProviderAdapter>> {
        self.adapters.get(provider_id).cloned()
    }
}

// @intent selvedge.model.dispatch.adapter.chatgpt ChatGPT provider adapter binds the ChatGPT request implementation to the executable provider adapter boundary.
struct ChatgptProviderAdapter;

impl ProviderAdapter for ChatgptProviderAdapter {
    // @behavior selvedge.model.dispatch.adapter.chatgpt.execute ChatGPT adapter execution delegates to the ChatGPT provider implementation.
    fn execute<'a>(
        &'a self,
        request: &'a ModelCallDispatchRequest,
        config: &'a ApiExecutorConfig,
    ) -> ProviderAdapterFuture<'a> {
        Box::pin(async move { call_chatgpt(request, config).await })
    }
}

// @behavior selvedge.model.dispatch.adapter.default_registry The default provider adapter registry exposes executable adapters available in the current build.
fn default_provider_adapter_registry() -> ProviderAdapterRegistry {
    ProviderAdapterRegistry::new(vec![("chatgpt", Arc::new(ChatgptProviderAdapter))])
}

/// @behavior selvedge.model.config Model execution uses caller-supplied timeout and response-size policy for each task request.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiExecutorConfig {
    /// @behavior selvedge.model.config.timeout Long-running provider calls surface to the task as timeout failures.
    pub request_timeout: Duration,
    /// @behavior selvedge.model.config.bytes Oversized provider results surface to the task as response-size failures.
    pub max_response_bytes: Option<usize>,
}

/// @behavior selvedge.model.terminal Model-call completion exposes result-delivery status to the caller.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ApiCallTerminalStatus {
    OutputSent,
    RouterClosed,
}

/// @behavior selvedge.model.dispatch A task model request sends one final model-call result to the waiting task and reports delivery status to the caller.
pub async fn execute_model_call(
    request: ModelCallDispatchRequest,
    router_tx: RouterIngressWeakSender,
    config: ApiExecutorConfig,
) -> ApiCallTerminalStatus {
    let envelope = run_model_call(request, config).await;
    send_output(router_tx, envelope).await
}

/// @behavior selvedge.model.dispatch.spawn A spawned task model request returns whether the result reached the task or the waiting task flow closed.
pub fn spawn_model_call_tokio_task(
    request: ModelCallDispatchRequest,
    router_tx: RouterIngressWeakSender,
    config: ApiExecutorConfig,
) -> tokio::task::JoinHandle<ApiCallTerminalStatus> {
    tokio::spawn(execute_model_call(request, router_tx, config))
}

/// @behavior selvedge.model.dispatch.run Dispatched model requests finish as one task-visible reply or failure.
async fn run_model_call(
    request: ModelCallDispatchRequest,
    config: ApiExecutorConfig,
) -> ApiOutputEnvelope {
    // @behavior selvedge.model.dispatch.input Invalid task model input produces a validation failure before any external provider receives a request.
    if let Err(error) = validate_dispatch_request(&request) {
        return failure_envelope(request, error);
    }

    // @behavior selvedge.model.dispatch.timeout Provider validation and provider calls that exceed the configured duration produce task-visible timeout failures.
    let reply_result = tokio::time::timeout(
        config.request_timeout,
        execute_validated_provider_call(&request, &config),
    )
    .await;

    // @behavior selvedge.model.dispatch.outcome Provider success, provider failure, and timeout each complete the task model run once.
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

    // @behavior selvedge.model.dispatch.bytes Provider replies that exceed the configured response-size limit produce task-visible provider-response failures.
    if let Err(error) = enforce_response_limit(&reply, config.max_response_bytes) {
        return failure_envelope(request, error);
    }

    // @behavior selvedge.model.dispatch.reply Provider replies that violate the command model produce task-visible provider-response failures.
    if let Err(error) = validate_model_reply(&reply) {
        return failure_envelope(
            request,
            model_call_error(
                ModelCallErrorKind::ProviderResponse,
                format!("provider response is invalid: {error:?}"),
            ),
        );
    }

    // @behavior selvedge.model.dispatch.success Accepted provider replies return to the task that requested them.
    let correlation = request.correlation;
    ApiOutputEnvelope::Success { correlation, reply }
}

// @behavior selvedge.model.dispatch.provider The provider named by the task request is resolved through provider and adapter registries before execution.
async fn execute_validated_provider_call(
    request: &ModelCallDispatchRequest,
    config: &ApiExecutorConfig,
) -> Result<ModelReply, ModelCallError> {
    validate_provider_dispatch_target(request)
        .await
        .map_err(map_provider_registry_error)?;
    let adapter_registry = default_provider_adapter_registry();
    // @behavior selvedge.model.dispatch.provider.adapter_unavailable Requests whose provider id has no executable adapter return a task-visible provider request failure.
    let Some(adapter) = adapter_registry.adapter(&request.provider.provider_name) else {
        return Err(model_call_error(
            ModelCallErrorKind::ProviderRequest,
            "provider adapter is not available",
        ));
    };

    adapter.execute(request, config).await
}

// @behavior selvedge.model.dispatch.provider_config Provider dispatch validation reads the current LLM provider map and Selvedge home before registry validation.
async fn validate_provider_dispatch_target(
    request: &ModelCallDispatchRequest,
) -> Result<(), ProviderRegistryError> {
    let llm_config = selvedge_config::read(|config| config.llm.clone())
        // @behavior selvedge.model.dispatch.provider_config.config_error Provider dispatch validation returns provider-request failures when model provider config cannot be read.
        .map_err(|error| ProviderRegistryError::Credential(error.to_string()))?;
    let selvedge_home = selvedge_config::selvedge_home()
        // @behavior selvedge.model.dispatch.provider_config.home_error Provider dispatch validation returns provider-request failures when Selvedge home cannot be resolved.
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

/// @behavior selvedge.model.chatgpt ChatGPT task requests expose ChatGPT text, tool requests, usage, and finish state as Selvedge model output.
async fn call_chatgpt(
    request: &ModelCallDispatchRequest,
    config: &ApiExecutorConfig,
) -> Result<ModelReply, ModelCallError> {
    // @behavior selvedge.model.chatgpt.request ChatGPT receives the task conversation, selected model, and enabled tools for the model run.
    let chatgpt_request = chatgpt_request_from_dispatch(request)?;
    // @behavior selvedge.model.chatgpt.stream ChatGPT stream failures become task-visible model-call failures.
    let mut response_stream = stream(chatgpt_request).await.map_err(map_chatgpt_error)?;
    let mut byte_counter = config.max_response_bytes.map(BoundedByteCounter::new);
    let mut text_parts = BTreeMap::new();
    let mut fallback_text = String::new();
    let mut tool_calls = Vec::new();
    let mut usage = None;
    let mut finish_reason = ModelFinishReason::Stop;

    while let Some(item) = response_stream.next().await {
        // @behavior selvedge.model.chatgpt.event ChatGPT completion, failure, and max-output truncation end the task's wait for provider stream events.
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

        // @behavior selvedge.model.chatgpt.aggregate ChatGPT streaming preserves ordered text, tool requests, usage, and finish reason for the task.
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
                if text.len() > existing.len() {
                    count_stream_bytes(&mut byte_counter, &text.as_bytes()[existing.len()..])?;
                }
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

    // @behavior selvedge.model.chatgpt.preference Plain-text task requests receive provider-response failures when ChatGPT asks to call tools.
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

    // @behavior selvedge.model.chatgpt.finish ChatGPT tool requests make the task-visible model reply finish as tool-calls.
    if !tool_calls.is_empty() && finish_reason == ModelFinishReason::Stop {
        finish_reason = ModelFinishReason::ToolCalls;
    }

    // @behavior selvedge.model.chatgpt.reply Successful ChatGPT task requests produce one Selvedge model reply.
    Ok(ModelReply {
        content: (!content.trim().is_empty()).then_some(content),
        tool_calls,
        usage,
        finish_reason,
    })
}

/// @behavior selvedge.model.chatgpt.request_build ChatGPT provider requests reflect the task's provider profile and conversation.
fn chatgpt_request_from_dispatch(
    request: &ModelCallDispatchRequest,
) -> Result<ChatgptResponsesRequest, ModelCallError> {
    // @behavior selvedge.model.chatgpt.build ChatGPT receives the task-selected model, conversation history, enabled tools, and dispatch defaults.
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

/// @behavior selvedge.model.chatgpt.item ChatGPT receives task conversation messages in their task order.
fn chatgpt_item_from_message(
    message: &ConversationMessage,
) -> Result<ResponseItem, ModelCallError> {
    // @behavior selvedge.model.chatgpt.history ChatGPT receives prior tool activity stored in the task conversation.
    if let MessageContent::Structured(payload) = &message.content
        && let Some(item) = chatgpt_tool_history_item(&message.role, payload)?
    {
        return Ok(item);
    }

    // @behavior selvedge.model.chatgpt.message ChatGPT receives ordinary task messages as completed conversation history.
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

/// @behavior selvedge.model.chatgpt.content_item ChatGPT receives task message text with the role meaning of the original message.
fn chatgpt_content_item_from_message(
    message: &ConversationMessage,
) -> Result<ContentItem, ModelCallError> {
    let text = message_content_text(&message.content)?;
    // @behavior selvedge.model.chatgpt.content Assistant history remains assistant output, and non-assistant history remains input to ChatGPT.
    if message.role == MessageRole::Assistant {
        return Ok(ContentItem::OutputText {
            text,
            raw: serde_json::Map::new(),
        });
    }
    Ok(ContentItem::InputText { text })
}

fn message_content_text(content: &MessageContent) -> Result<String, ModelCallError> {
    // @behavior selvedge.model.chatgpt.content_text Task message content keeps its text meaning when sent to ChatGPT.
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

/// @behavior selvedge.model.chatgpt.tool_history_item ChatGPT receives prior tool activity only from task messages that carry the required tool fields.
fn chatgpt_tool_history_item(
    role: &MessageRole,
    payload: &StructuredPayload,
) -> Result<Option<ResponseItem>, ModelCallError> {
    // @behavior selvedge.model.chatgpt.tool_history Replayed task tool history keeps assistant tool calls paired with tool outputs by call id.
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

/// @behavior selvedge.model.chatgpt.payload_field ChatGPT replay uses a stored task tool-history field only when that field is present as text.
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
    // @behavior selvedge.model.chatgpt.tool_args Replayed task tool arguments reach ChatGPT as named function-call arguments.
    let StructuredPayload::Array(arguments) = payload else {
        return Err(model_call_error(
            ModelCallErrorKind::ProviderRequest,
            "tool history arguments must be an array",
        ));
    };
    let mut object = serde_json::Map::new();
    // @behavior selvedge.model.chatgpt.tool_args.item Tool-history arguments without structured metadata produce provider-request failures for the task.
    for argument in arguments {
        let StructuredPayload::Object(argument) = argument else {
            return Err(model_call_error(
                ModelCallErrorKind::ProviderRequest,
                "tool history argument must be an object",
            ));
        };
        // @behavior selvedge.model.chatgpt.tool_args.name Tool-history arguments without a name or value produce provider-request failures for the task.
        let name = payload_string_field(argument, "name")
            .ok_or_else(|| missing_tool_history_field("argument name"))?;
        let value = argument
            .get("value")
            .ok_or_else(|| missing_tool_history_field("argument value"))?;
        object.insert(name.to_owned(), json_value_from_structured_payload(value));
    }
    // @behavior selvedge.model.chatgpt.tool_args.encode ChatGPT receives replayed tool arguments with the same names and values the tool saw earlier.
    serde_json::to_string(&object).map_err(|error| {
        model_call_error(
            ModelCallErrorKind::ProviderRequest,
            format!("tool history arguments could not be encoded: {error}"),
        )
    })
}

/// @behavior selvedge.model.chatgpt.tools_map Tools enabled for a task appear to ChatGPT as available tool choices.
fn chatgpt_tools(
    tool_manifest: Option<&ToolManifest>,
    response_preference: &ResponsePreference,
) -> Vec<ToolDescriptor> {
    // @behavior selvedge.model.chatgpt.tools Plain-text task requests and requests without tool manifests expose no callable tools to ChatGPT.
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
            // @behavior selvedge.model.chatgpt.tool_schema ChatGPT receives each task tool's name, description, parameter types, and required-field rules.
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

/// @behavior selvedge.model.chatgpt.fallback Completed ChatGPT message text remains visible to the task when streamed text deltas are absent.
fn append_message_content(
    content: &mut String,
    message: &MessageItem,
    counter: &mut Option<BoundedByteCounter>,
) -> Result<(), ModelCallError> {
    // @behavior selvedge.model.chatgpt.fallback_text Fallback ChatGPT message text reaches the task in message item order.
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

/// @behavior selvedge.model.chatgpt.tool_call_map ChatGPT tool requests appear to the task as tool-call proposals.
fn tool_call_from_chatgpt(
    function_call: FunctionCallItem,
) -> Result<ToolCallProposal, ModelCallError> {
    // @behavior selvedge.model.chatgpt.tool_call Task-visible ChatGPT tool requests carry the call id, tool name, and arguments.
    Ok(ToolCallProposal {
        call_id: function_call.call_id,
        tool_name: function_call.name,
        arguments: structured_payload_from_json_string(&function_call.arguments)?,
    })
}

fn structured_payload_from_json_string(raw: &str) -> Result<StructuredPayload, ModelCallError> {
    // @behavior selvedge.model.chatgpt.argument_json ChatGPT tool-call arguments outside JSON object form produce provider-response failures for the task.
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

/// @behavior selvedge.model.chatgpt.json_convert ChatGPT tool-call arguments keep their JSON structure when exposed to the task.
fn structured_payload_from_json_value(
    value: serde_json::Value,
) -> Result<StructuredPayload, ModelCallError> {
    // @behavior selvedge.model.chatgpt.json_value Nested ChatGPT tool-call arguments remain nested in task-visible structured data.
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

    // @behavior selvedge.model.chatgpt.number ChatGPT integer arguments that cannot be represented exactly produce provider-response failures for the task.
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
    // @behavior selvedge.model.chatgpt.payload_json Replayed task tool arguments keep their stored structure when sent back to ChatGPT.
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
    // @behavior selvedge.model.chatgpt.error ChatGPT failures surface to the task as provider request, timeout, network, or response failure categories.
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

/// @behavior selvedge.model.chatgpt.stream_count ChatGPT streamed output contributes to the task response-size limit when that limit is active.
fn count_stream_bytes(
    counter: &mut Option<BoundedByteCounter>,
    bytes: &[u8],
) -> Result<(), ModelCallError> {
    // @behavior selvedge.model.chatgpt.stream_bytes ChatGPT streamed text and tool arguments that cross the response-size limit produce provider-response failures for the task.
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

/// @behavior selvedge.model.router.output Ready model results reach the task flow waiting for that result.
async fn send_output(
    router_tx: RouterIngressWeakSender,
    envelope: ApiOutputEnvelope,
) -> ApiCallTerminalStatus {
    // @behavior selvedge.model.router Closed waiting task flows make delivery failure visible to the caller.
    let Some(router_tx) = router_tx.upgrade() else {
        return ApiCallTerminalStatus::RouterClosed;
    };
    // @behavior selvedge.model.router.send Accepted and rejected task results expose their delivery outcome to the caller.
    match router_tx.send(RouterIngressApiMessage::ApiOutput(envelope)) {
        Ok(()) => ApiCallTerminalStatus::OutputSent,
        Err(_) => ApiCallTerminalStatus::RouterClosed,
    }
}

/// @behavior selvedge.model.failure Model execution failures return one reportable model-call error to the requesting task.
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

/// @behavior selvedge.model.limit.reply Complete model replies that exceed the response-size limit produce size failures before delivery to the task.
fn enforce_response_limit(
    reply: &ModelReply,
    max_response_bytes: Option<usize>,
) -> Result<(), ModelCallError> {
    // @behavior selvedge.model.limit Disabled response-size limiting allows the task to receive complete provider replies of any encoded size.
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

/// @behavior selvedge.model.limit.encoded Active response-size limiting measures the complete model reply against the configured byte ceiling.
fn encoded_model_reply_exceeds_limit(
    reply: &ModelReply,
    max_response_bytes: usize,
) -> Result<bool, ModelCallError> {
    let mut counter = BoundedByteCounter::new(max_response_bytes);

    // @behavior selvedge.model.limit.encode Reply encoding that crosses the size limit produces a size failure, while other encoding failures remain provider-response failures.
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
    // @behavior selvedge.model.limit.counter Response-size accounting starts with zero counted bytes and no limit-exceeded state.
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
    // @behavior selvedge.model.limit.write Response-size accounting fails when counting the task reply would overflow or cross the byte limit.
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

    use super::{BoundedByteCounter, ProviderAdapterRegistry};

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

        // @verifies selvedge.model.limit.write
        assert!(counter.limit_exceeded());
        // @verifies selvedge.model.limit.write
        assert_eq!(error.kind(), std::io::ErrorKind::Other);
    }

    #[test]
    fn provider_adapter_registry_resolves_registered_provider_id() {
        let registry =
            ProviderAdapterRegistry::new(vec![("test-provider", Arc::new(TestProviderAdapter))]);

        // @verifies selvedge.model.dispatch.adapter.registry.lookup
        assert!(registry.adapter("test-provider").is_some());
        // @verifies selvedge.model.dispatch.adapter.registry.lookup
        assert!(registry.adapter("missing-provider").is_none());
    }
}
