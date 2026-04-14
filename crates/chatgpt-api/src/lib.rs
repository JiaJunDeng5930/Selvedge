#![doc = include_str!("../README.md")]
#![allow(clippy::result_large_err)]

use std::{
    pin::Pin,
    task::{Context, Poll},
    time::Duration,
};

use futures::StreamExt;
use futures_core::Stream;
use http::{HeaderMap, HeaderValue, StatusCode};
use serde_json::Value;
use tokio::{sync::mpsc, task::JoinHandle};

pub type JsonObject = serde_json::Map<String, Value>;

pub async fn stream(
    request: ChatgptResponsesRequest,
) -> Result<ChatgptResponseStream, ChatgptApiError> {
    request
        .validate()
        .map_err(ChatgptApiLowerLayerError::InvalidInput)
        .map_err(ChatgptApiError::LowerLayer)?;

    let api_config = selvedge_config::read(|config| config.llm.providers.chatgpt.api.clone())
        .map_err(ChatgptApiLowerLayerError::Config)
        .map_err(ChatgptApiError::LowerLayer)?;
    let response = open_response_stream(&request, &api_config).await?;
    let effective_turn_state = response
        .headers
        .get("x-codex-turn-state")
        .and_then(|value| value.to_str().ok())
        .map(str::to_owned)
        .or_else(|| request.context.turn_state.clone());

    let (sender, receiver) = mpsc::channel(32);
    let timeout = Duration::from_millis(api_config.stream_completion_timeout_ms);
    let driver_task = tokio::spawn(async move {
        drive_response_stream(response.body, sender, timeout).await;
    });

    Ok(ChatgptResponseStream::empty(
        effective_turn_state,
        receiver,
        Some(driver_task),
    ))
}

async fn open_response_stream(
    request: &ChatgptResponsesRequest,
    api_config: &selvedge_config_model::ChatgptApiConfig,
) -> Result<selvedge_client::HttpStreamResponse, ChatgptApiError> {
    let mut auth = chatgpt_auth::resolve_for_request()
        .await
        .map_err(ChatgptApiLowerLayerError::Auth)
        .map_err(ChatgptApiError::LowerLayer)?;
    let mut retry_count = 0_u8;
    let mut reauth_used = false;

    loop {
        let http_request = build_http_request(request, &auth, api_config)
            .map_err(ChatgptApiLowerLayerError::InvalidInput)
            .map_err(ChatgptApiError::LowerLayer)?;

        match selvedge_client::stream(http_request).await {
            Ok(response) => {
                ensure_event_stream_content_type(&response.headers)?;
                return Ok(response);
            }
            Err(selvedge_client::HttpError::Status(status))
                if status.status == StatusCode::UNAUTHORIZED && !reauth_used =>
            {
                auth = chatgpt_auth::resolve_after_unauthorized()
                    .await
                    .map_err(ChatgptApiLowerLayerError::Auth)
                    .map_err(ChatgptApiError::LowerLayer)?;
                reauth_used = true;
            }
            Err(error) if is_retryable_client_error(&error) && retry_count < 5 => {
                let delay = retry_delay_for_attempt(retry_count, &error);
                retry_count += 1;
                tokio::time::sleep(delay).await;
            }
            Err(error) => {
                return Err(ChatgptApiError::LowerLayer(
                    ChatgptApiLowerLayerError::Client(error),
                ));
            }
        }
    }
}

fn ensure_event_stream_content_type(headers: &HeaderMap) -> Result<(), ChatgptApiError> {
    let content_type = headers
        .get(http::header::CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .map(str::to_owned);

    let is_event_stream = content_type
        .as_deref()
        .is_some_and(|value| value.starts_with("text/event-stream"));

    if !is_event_stream {
        return Err(ChatgptApiError::Endpoint(
            ChatgptApiEndpointError::MalformedResponseHead { content_type },
        ));
    }

    Ok(())
}

fn is_retryable_client_error(error: &selvedge_client::HttpError) -> bool {
    match error {
        selvedge_client::HttpError::Timeout
        | selvedge_client::HttpError::Connect { .. }
        | selvedge_client::HttpError::Io { .. } => true,
        selvedge_client::HttpError::Status(status) => matches!(
            status.status,
            StatusCode::REQUEST_TIMEOUT
                | StatusCode::TOO_EARLY
                | StatusCode::TOO_MANY_REQUESTS
                | StatusCode::INTERNAL_SERVER_ERROR
                | StatusCode::BAD_GATEWAY
                | StatusCode::SERVICE_UNAVAILABLE
                | StatusCode::GATEWAY_TIMEOUT
        ),
        selvedge_client::HttpError::Config(_)
        | selvedge_client::HttpError::Build { .. }
        | selvedge_client::HttpError::Tls { .. } => false,
    }
}

fn retry_delay_for_attempt(retry_count: u8, error: &selvedge_client::HttpError) -> Duration {
    if let selvedge_client::HttpError::Status(status) = error
        && let Some(retry_after) = status
            .headers
            .get("retry-after")
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.parse::<u64>().ok())
    {
        return Duration::from_secs(retry_after.min(30));
    }

    match retry_count {
        0 => Duration::from_millis(200),
        1 => Duration::from_millis(400),
        2 => Duration::from_millis(800),
        3 => Duration::from_millis(1600),
        _ => Duration::from_millis(3200),
    }
}

async fn drive_response_stream(
    mut body: selvedge_client::ByteStream,
    sender: mpsc::Sender<Result<ChatgptResponseEvent, ChatgptApiError>>,
    timeout: Duration,
) {
    let deadline = tokio::time::Instant::now() + timeout;
    let completed = false;
    let mut buffer = String::new();

    loop {
        let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
        if remaining.is_zero() {
            send_stream_item(
                &sender,
                Err(ChatgptApiError::LowerLayer(
                    ChatgptApiLowerLayerError::StreamCompletionTimeout { timeout },
                )),
            )
            .await;
            return;
        }

        let next_chunk = tokio::time::timeout(remaining, body.next()).await;
        let maybe_chunk = match next_chunk {
            Ok(chunk) => chunk,
            Err(_) => {
                send_stream_item(
                    &sender,
                    Err(ChatgptApiError::LowerLayer(
                        ChatgptApiLowerLayerError::StreamCompletionTimeout { timeout },
                    )),
                )
                .await;
                return;
            }
        };

        let Some(chunk) = maybe_chunk else {
            if completed {
                return;
            }

            let error = if buffer.trim().is_empty() {
                ChatgptApiError::Endpoint(ChatgptApiEndpointError::PrematureClose)
            } else {
                ChatgptApiError::Endpoint(ChatgptApiEndpointError::MalformedEvent {
                    reason: "stream ended before the current SSE frame completed".to_owned(),
                    raw: Some(buffer),
                })
            };
            send_stream_item(&sender, Err(error)).await;
            return;
        };

        let chunk = match chunk {
            Ok(bytes) => bytes,
            Err(error) => {
                send_stream_item(
                    &sender,
                    Err(ChatgptApiError::LowerLayer(
                        ChatgptApiLowerLayerError::Client(error),
                    )),
                )
                .await;
                return;
            }
        };

        let chunk = match std::str::from_utf8(&chunk) {
            Ok(text) => text.replace("\r\n", "\n").replace('\r', "\n"),
            Err(_) => {
                send_stream_item(
                    &sender,
                    Err(ChatgptApiError::Endpoint(
                        ChatgptApiEndpointError::MalformedEvent {
                            reason: "event stream contained non-utf8 bytes".to_owned(),
                            raw: None,
                        },
                    )),
                )
                .await;
                return;
            }
        };
        buffer.push_str(&chunk);

        while let Some(frame) = take_next_sse_frame(&mut buffer) {
            if frame.trim().is_empty() {
                continue;
            }

            let payload = match parse_sse_frame(&frame) {
                Ok(Some(payload)) => payload,
                Ok(None) => continue,
                Err(error) => {
                    send_stream_item(&sender, Err(error)).await;
                    return;
                }
            };

            match map_stream_event(&payload) {
                Ok(MappedEvent::Event(event)) => {
                    send_stream_item(&sender, Ok(event)).await;
                }
                Ok(MappedEvent::Completed(event)) => {
                    send_stream_item(&sender, Ok(event)).await;
                    return;
                }
                Ok(MappedEvent::EndpointError(error)) => {
                    send_stream_item(&sender, Err(error)).await;
                    return;
                }
                Err(error) => {
                    send_stream_item(&sender, Err(error)).await;
                    return;
                }
            }
        }
    }
}

async fn send_stream_item(
    sender: &mpsc::Sender<Result<ChatgptResponseEvent, ChatgptApiError>>,
    item: Result<ChatgptResponseEvent, ChatgptApiError>,
) {
    let _ = sender.send(item).await;
}

fn take_next_sse_frame(buffer: &mut String) -> Option<String> {
    let frame_end = buffer.find("\n\n")?;
    let frame = buffer[..frame_end].to_owned();
    let remainder = buffer[frame_end + 2..].to_owned();
    *buffer = remainder;

    Some(frame)
}

fn parse_sse_frame(frame: &str) -> Result<Option<String>, ChatgptApiError> {
    let mut data_lines = Vec::new();

    for line in frame.lines() {
        if line.is_empty() || line.starts_with(':') {
            continue;
        }

        if let Some(rest) = line.strip_prefix("data:") {
            data_lines.push(rest.trim_start().to_owned());
        }
    }

    if data_lines.is_empty() {
        return Ok(None);
    }

    Ok(Some(data_lines.join("\n")))
}

enum MappedEvent {
    Event(ChatgptResponseEvent),
    Completed(ChatgptResponseEvent),
    EndpointError(ChatgptApiError),
}

fn map_stream_event(payload: &str) -> Result<MappedEvent, ChatgptApiError> {
    let raw_value = serde_json::from_str::<Value>(payload).map_err(|_| {
        ChatgptApiError::Endpoint(ChatgptApiEndpointError::MalformedEvent {
            reason: "event payload was not valid JSON".to_owned(),
            raw: Some(payload.to_owned()),
        })
    })?;
    let Value::Object(raw_object) = raw_value else {
        return Err(ChatgptApiError::Endpoint(
            ChatgptApiEndpointError::MalformedEvent {
                reason: "event payload must be a JSON object".to_owned(),
                raw: Some(payload.to_owned()),
            },
        ));
    };
    let event_type = raw_object
        .get("type")
        .and_then(Value::as_str)
        .ok_or_else(|| {
            ChatgptApiError::Endpoint(ChatgptApiEndpointError::MalformedEvent {
                reason: "event payload must contain a string type".to_owned(),
                raw: Some(payload.to_owned()),
            })
        })?
        .to_owned();

    match event_type.as_str() {
        "response.created" => Ok(MappedEvent::Event(ChatgptResponseEvent::Created(
            response_snapshot_from_field(&raw_object)?,
        ))),
        "response.output_item.added" => {
            Ok(MappedEvent::Event(ChatgptResponseEvent::OutputItemAdded {
                output_index: required_u64(&raw_object, "output_index")?,
                item: response_item_from_field(&raw_object, "item")?,
            }))
        }
        "response.output_item.done" => {
            Ok(MappedEvent::Event(ChatgptResponseEvent::OutputItemDone {
                output_index: required_u64(&raw_object, "output_index")?,
                item: response_item_from_field(&raw_object, "item")?,
            }))
        }
        "response.output_text.delta" => {
            Ok(MappedEvent::Event(ChatgptResponseEvent::OutputTextDelta {
                item_id: required_string(&raw_object, "item_id")?,
                output_index: required_u64(&raw_object, "output_index")?,
                content_index: required_u64(&raw_object, "content_index")?,
                delta: required_string(&raw_object, "delta")?,
            }))
        }
        "response.output_text.done" => {
            Ok(MappedEvent::Event(ChatgptResponseEvent::OutputTextDone {
                item_id: required_string(&raw_object, "item_id")?,
                output_index: required_u64(&raw_object, "output_index")?,
                content_index: required_u64(&raw_object, "content_index")?,
                text: required_string(&raw_object, "text")?,
            }))
        }
        "response.reasoning_summary_text.delta" => Ok(MappedEvent::Event(
            ChatgptResponseEvent::ReasoningSummaryTextDelta {
                item_id: required_string(&raw_object, "item_id")?,
                output_index: required_u64(&raw_object, "output_index")?,
                summary_index: required_u64(&raw_object, "summary_index")?,
                delta: required_string(&raw_object, "delta")?,
            },
        )),
        "response.reasoning_summary_text.done" => Ok(MappedEvent::Event(
            ChatgptResponseEvent::ReasoningSummaryTextDone {
                item_id: required_string(&raw_object, "item_id")?,
                output_index: required_u64(&raw_object, "output_index")?,
                summary_index: required_u64(&raw_object, "summary_index")?,
                text: required_string(&raw_object, "text")?,
            },
        )),
        "response.reasoning_text.delta" => Ok(MappedEvent::Event(
            ChatgptResponseEvent::ReasoningTextDelta {
                item_id: required_string(&raw_object, "item_id")?,
                output_index: required_u64(&raw_object, "output_index")?,
                content_index: required_u64(&raw_object, "content_index")?,
                delta: required_string(&raw_object, "delta")?,
            },
        )),
        "response.reasoning_text.done" => Ok(MappedEvent::Event(
            ChatgptResponseEvent::ReasoningTextDone {
                item_id: required_string(&raw_object, "item_id")?,
                output_index: required_u64(&raw_object, "output_index")?,
                content_index: required_u64(&raw_object, "content_index")?,
                text: required_string(&raw_object, "text")?,
            },
        )),
        "response.completed" => Ok(MappedEvent::Completed(ChatgptResponseEvent::Completed(
            response_snapshot_from_field(&raw_object)?,
        ))),
        "response.failed" => Ok(MappedEvent::EndpointError(failed_endpoint_event(
            &raw_object,
            &event_type,
        ))),
        "response.incomplete" => Ok(MappedEvent::EndpointError(ChatgptApiError::Endpoint(
            ChatgptApiEndpointError::Incomplete(incomplete_endpoint_error(&raw_object)),
        ))),
        _ => Ok(MappedEvent::Event(ChatgptResponseEvent::Other(
            ChatgptRawEvent {
                event_type,
                payload: raw_object,
            },
        ))),
    }
}

fn response_snapshot_from_field(
    object: &JsonObject,
) -> Result<ChatgptResponseSnapshot, ChatgptApiError> {
    let response = object
        .get("response")
        .and_then(Value::as_object)
        .ok_or_else(|| malformed_event("response", "must be an object"))?;

    let usage = response
        .get("usage")
        .map(chatgpt_usage_from_value)
        .transpose()?;

    Ok(ChatgptResponseSnapshot {
        id: optional_string(response, "id")?,
        model: optional_string(response, "model")?,
        usage,
        service_tier: optional_string(response, "service_tier")?,
        raw: response.clone(),
    })
}

fn response_item_from_field(
    object: &JsonObject,
    field: &'static str,
) -> Result<ResponseItem, ChatgptApiError> {
    let item = object
        .get(field)
        .and_then(Value::as_object)
        .ok_or_else(|| malformed_event(field, "must be an object"))?;

    response_item_from_object(item)
}

fn response_item_from_object(item: &JsonObject) -> Result<ResponseItem, ChatgptApiError> {
    let item_type = required_string(item, "type")?;

    match item_type.as_str() {
        "message" => Ok(ResponseItem::Message(MessageItem {
            id: optional_string(item, "id")?,
            status: optional_string(item, "status")?,
            role: required_string(item, "role")?,
            content: required_array(item, "content")?
                .iter()
                .map(content_item_from_value)
                .collect::<Result<Vec<_>, _>>()?,
        })),
        "function_call" => Ok(ResponseItem::FunctionCall(FunctionCallItem {
            id: optional_string(item, "id")?,
            status: optional_string(item, "status")?,
            name: required_string(item, "name")?,
            namespace: optional_string(item, "namespace")?,
            arguments: required_string(item, "arguments")?,
            call_id: required_string(item, "call_id")?,
        })),
        "function_call_output" => Ok(ResponseItem::FunctionCallOutput(FunctionCallOutputItem {
            id: optional_string(item, "id")?,
            status: optional_string(item, "status")?,
            call_id: required_string(item, "call_id")?,
            output: tool_output_from_value(
                item.get("output")
                    .ok_or_else(|| malformed_event("output", "must be present"))?,
            )?,
        })),
        "custom_tool_call_output" => Ok(ResponseItem::CustomToolCallOutput(
            CustomToolCallOutputItem {
                id: optional_string(item, "id")?,
                status: optional_string(item, "status")?,
                call_id: required_string(item, "call_id")?,
                output: tool_output_from_value(
                    item.get("output")
                        .ok_or_else(|| malformed_event("output", "must be present"))?,
                )?,
            },
        )),
        "reasoning" => Ok(ResponseItem::Reasoning(ReasoningItem {
            id: optional_string(item, "id")?,
            status: optional_string(item, "status")?,
            summary: item
                .get("summary")
                .cloned()
                .ok_or_else(|| malformed_event("summary", "must be present"))?,
            content: item
                .get("content")
                .map(|value| match value {
                    Value::Array(values) => values
                        .iter()
                        .map(content_item_from_value)
                        .collect::<Result<Vec<_>, _>>(),
                    _ => Err(malformed_event("content", "must be an array")),
                })
                .transpose()?,
            encrypted_content: optional_string(item, "encrypted_content")?,
        })),
        _ => Ok(ResponseItem::Opaque(OpaqueResponseItem {
            raw: item.clone(),
        })),
    }
}

fn content_item_from_value(value: &Value) -> Result<ContentItem, ChatgptApiError> {
    let object = value
        .as_object()
        .ok_or_else(|| malformed_event("content", "must contain objects"))?;
    let item_type = required_string(object, "type")?;

    match item_type.as_str() {
        "input_text" => Ok(ContentItem::InputText {
            text: required_string(object, "text")?,
        }),
        "input_image" => Ok(ContentItem::InputImage {
            image_url: required_string(object, "image_url")?,
        }),
        "output_text" => Ok(ContentItem::OutputText {
            text: required_string(object, "text")?,
            raw: object.clone(),
        }),
        _ => Ok(ContentItem::Other {
            raw: object.clone(),
        }),
    }
}

fn tool_output_from_value(value: &Value) -> Result<ToolOutput, ChatgptApiError> {
    match value {
        Value::String(text) => Ok(ToolOutput::Text(text.clone())),
        Value::Array(values) => Ok(ToolOutput::Content(
            values
                .iter()
                .map(content_item_from_value)
                .collect::<Result<Vec<_>, _>>()?,
        )),
        _ => Err(malformed_event(
            "output",
            "must be a string or content array",
        )),
    }
}

fn chatgpt_usage_from_value(value: &Value) -> Result<ChatgptUsage, ChatgptApiError> {
    let usage = value
        .as_object()
        .ok_or_else(|| malformed_event("usage", "must be an object"))?;

    Ok(ChatgptUsage {
        input_tokens: optional_u64(usage, "input_tokens")?,
        cached_input_tokens: optional_u64(usage, "cached_input_tokens")?,
        output_tokens: optional_u64(usage, "output_tokens")?,
        reasoning_output_tokens: optional_u64(usage, "reasoning_output_tokens")?,
        total_tokens: optional_u64(usage, "total_tokens")?,
    })
}

fn failed_endpoint_event(object: &JsonObject, event_type: &str) -> ChatgptApiError {
    let response = object
        .get("response")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let error = response
        .get("error")
        .and_then(Value::as_object)
        .cloned()
        .or_else(|| object.get("error").and_then(Value::as_object).cloned())
        .unwrap_or_default();
    let code = error
        .get("code")
        .and_then(Value::as_str)
        .map(str::to_owned)
        .or_else(|| {
            object
                .get("code")
                .and_then(Value::as_str)
                .map(str::to_owned)
        });
    let message = error
        .get("message")
        .and_then(Value::as_str)
        .map(str::to_owned)
        .or_else(|| {
            object
                .get("message")
                .and_then(Value::as_str)
                .map(str::to_owned)
        });

    let response_id = response
        .get("id")
        .and_then(Value::as_str)
        .map(str::to_owned);
    let raw = response;

    match failed_endpoint_kind(code.as_deref()) {
        Some(kind) => ChatgptApiError::Endpoint(ChatgptApiEndpointError::Failed(
            ChatgptFailedEndpointError {
                kind,
                response_id,
                code,
                message,
                raw,
            },
        )),
        None => {
            ChatgptApiError::Endpoint(ChatgptApiEndpointError::Other(ChatgptOtherEndpointError {
                event_type: Some(event_type.to_owned()),
                code,
                message: message.clone(),
                retry_after: message.as_deref().and_then(parse_retry_after),
                raw,
            }))
        }
    }
}

fn incomplete_endpoint_error(object: &JsonObject) -> ChatgptIncompleteEndpointError {
    let response = object
        .get("response")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let reason = response
        .get("reason")
        .and_then(Value::as_str)
        .map(str::to_owned)
        .or_else(|| {
            response
                .get("incomplete_details")
                .and_then(Value::as_object)
                .and_then(|details| details.get("reason"))
                .and_then(Value::as_str)
                .map(str::to_owned)
        })
        .or_else(|| {
            object
                .get("reason")
                .and_then(Value::as_str)
                .map(str::to_owned)
        });

    ChatgptIncompleteEndpointError {
        response_id: response
            .get("id")
            .and_then(Value::as_str)
            .map(str::to_owned),
        reason,
        raw: response,
    }
}

fn failed_endpoint_kind(code: Option<&str>) -> Option<ChatgptFailedEndpointKind> {
    match code {
        Some("context_length_exceeded") => Some(ChatgptFailedEndpointKind::ContextLengthExceeded),
        Some("insufficient_quota") => Some(ChatgptFailedEndpointKind::InsufficientQuota),
        Some("usage_not_included") => Some(ChatgptFailedEndpointKind::UsageNotIncluded),
        Some("invalid_prompt") => Some(ChatgptFailedEndpointKind::InvalidPrompt),
        Some("server_overloaded") => Some(ChatgptFailedEndpointKind::ServerOverloaded),
        _ => None,
    }
}

fn parse_retry_after(message: &str) -> Option<Duration> {
    let marker = "try again in ";
    let start = message.find(marker)? + marker.len();
    let seconds = message[start..]
        .chars()
        .take_while(|character| character.is_ascii_digit())
        .collect::<String>();

    seconds.parse::<u64>().ok().map(Duration::from_secs)
}

fn malformed_event(field: &'static str, reason: &'static str) -> ChatgptApiError {
    ChatgptApiError::Endpoint(ChatgptApiEndpointError::MalformedEvent {
        reason: format!("{field} {reason}"),
        raw: None,
    })
}

fn required_string(object: &JsonObject, field: &'static str) -> Result<String, ChatgptApiError> {
    object
        .get(field)
        .and_then(Value::as_str)
        .map(str::to_owned)
        .ok_or_else(|| malformed_event(field, "must be a string"))
}

fn optional_string(
    object: &JsonObject,
    field: &'static str,
) -> Result<Option<String>, ChatgptApiError> {
    match object.get(field) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(value)) => Ok(Some(value.clone())),
        Some(_) => Err(malformed_event(field, "must be a string")),
    }
}

fn required_u64(object: &JsonObject, field: &'static str) -> Result<u64, ChatgptApiError> {
    object
        .get(field)
        .and_then(Value::as_u64)
        .ok_or_else(|| malformed_event(field, "must be an unsigned integer"))
}

fn optional_u64(object: &JsonObject, field: &'static str) -> Result<Option<u64>, ChatgptApiError> {
    match object.get(field) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Number(number)) => number
            .as_u64()
            .map(Some)
            .ok_or_else(|| malformed_event(field, "must be an unsigned integer")),
        Some(_) => Err(malformed_event(field, "must be an unsigned integer")),
    }
}

fn required_array<'a>(
    object: &'a JsonObject,
    field: &'static str,
) -> Result<&'a Vec<Value>, ChatgptApiError> {
    object
        .get(field)
        .and_then(Value::as_array)
        .ok_or_else(|| malformed_event(field, "must be an array"))
}

fn build_http_request(
    request: &ChatgptResponsesRequest,
    auth: &chatgpt_auth::ResolvedChatgptAuth,
    api_config: &selvedge_config_model::ChatgptApiConfig,
) -> Result<selvedge_client::HttpRequest, RequestValidationError> {
    request.validate()?;
    validate_non_blank("auth.access_token", &auth.access_token)?;
    validate_non_blank("auth.account_id", &auth.account_id)?;
    validate_header_value("auth.access_token", &auth.access_token)?;
    validate_header_value("auth.account_id", &auth.account_id)?;

    let mut headers = HeaderMap::new();
    insert_header(
        &mut headers,
        "authorization",
        &format!("Bearer {}", auth.access_token),
    )?;
    insert_header(&mut headers, "chatgpt-account-id", &auth.account_id)?;
    insert_header(&mut headers, "session_id", &request.context.conversation_id)?;
    insert_header(
        &mut headers,
        "x-client-request-id",
        &request.context.conversation_id,
    )?;
    insert_header(
        &mut headers,
        "x-codex-window-id",
        &format!(
            "{}:{}",
            request.context.conversation_id, request.context.window_generation
        ),
    )?;
    insert_header(&mut headers, "accept", "text/event-stream")?;

    if let Some(turn_state) = request.context.turn_state.as_deref() {
        insert_header(&mut headers, "x-codex-turn-state", turn_state)?;
    }

    if let Some(turn_metadata) = request.context.turn_metadata.as_deref() {
        insert_header(&mut headers, "x-codex-turn-metadata", turn_metadata)?;
    }

    if !request.context.beta_features.is_empty() {
        insert_header(
            &mut headers,
            "x-codex-beta-features",
            &request.context.beta_features.join(","),
        )?;
    }

    if let Some(subagent) = request.context.subagent.as_deref() {
        insert_header(&mut headers, "x-openai-subagent", subagent)?;
    }

    if let Some(parent_thread_id) = request.context.parent_thread_id.as_deref() {
        insert_header(&mut headers, "x-codex-parent-thread-id", parent_thread_id)?;
    }

    let url = format!("{}/responses", api_config.base_url.trim_end_matches('/'));
    let body = build_request_body(request);

    Ok(selvedge_client::HttpRequest {
        method: selvedge_client::HttpMethod::Post,
        url,
        headers,
        body: selvedge_client::HttpRequestBody::Json(body),
        timeout: None,
        compression: selvedge_client::RequestCompression::None,
    })
}

fn insert_header(
    headers: &mut HeaderMap,
    name: &'static str,
    value: &str,
) -> Result<(), RequestValidationError> {
    let header_value = HeaderValue::from_str(value)
        .map_err(|_| RequestValidationError::new(name, "must be a valid HTTP header value"))?;
    headers.insert(name, header_value);

    Ok(())
}

fn build_request_body(request: &ChatgptResponsesRequest) -> Value {
    let mut body = JsonObject::new();

    body.insert("model".to_owned(), Value::String(request.model.clone()));
    body.insert(
        "input".to_owned(),
        Value::Array(
            request
                .input
                .iter()
                .map(response_item_to_json)
                .collect::<Vec<_>>(),
        ),
    );
    body.insert(
        "tools".to_owned(),
        Value::Array(
            request
                .tools
                .iter()
                .map(|tool| Value::Object(tool.0.clone()))
                .collect::<Vec<_>>(),
        ),
    );
    body.insert("tool_choice".to_owned(), Value::String("auto".to_owned()));
    body.insert(
        "parallel_tool_calls".to_owned(),
        Value::Bool(request.parallel_tool_calls),
    );
    body.insert("store".to_owned(), Value::Bool(false));
    body.insert("stream".to_owned(), Value::Bool(true));
    body.insert(
        "prompt_cache_key".to_owned(),
        Value::String(request.context.conversation_id.clone()),
    );
    body.insert(
        "client_metadata".to_owned(),
        Value::Object(JsonObject::from_iter([(
            "x-codex-installation-id".to_owned(),
            Value::String(request.context.installation_id.clone()),
        )])),
    );

    if let Some(instructions) = request
        .instructions
        .as_ref()
        .filter(|value| !value.is_empty())
    {
        body.insert(
            "instructions".to_owned(),
            Value::String(instructions.clone()),
        );
    }

    let reasoning_support = request.model_capabilities.supports_reasoning_summaries;
    body.insert(
        "reasoning".to_owned(),
        if reasoning_support {
            Value::Object(build_reasoning_body(request))
        } else {
            Value::Null
        },
    );
    body.insert(
        "include".to_owned(),
        if reasoning_support {
            serde_json::json!(["reasoning.encrypted_content"])
        } else {
            serde_json::json!([])
        },
    );

    if let Some(service_tier) = request.service_tier {
        body.insert(
            "service_tier".to_owned(),
            Value::String(service_tier_to_wire(service_tier).to_owned()),
        );
    }

    if let Some(text) = build_text_body(&request.text) {
        body.insert("text".to_owned(), Value::Object(text));
    }

    Value::Object(body)
}

fn build_reasoning_body(request: &ChatgptResponsesRequest) -> JsonObject {
    let mut reasoning = JsonObject::new();

    if let Some(effort) = request
        .reasoning
        .effort
        .clone()
        .or_else(|| request.model_capabilities.default_reasoning_effort.clone())
    {
        reasoning.insert("effort".to_owned(), Value::String(effort));
    }

    if let Some(summary) = request.reasoning.summary.clone() {
        reasoning.insert("summary".to_owned(), Value::String(summary));
    }

    reasoning
}

fn build_text_body(text: &ChatgptTextOptions) -> Option<JsonObject> {
    let mut body = JsonObject::new();

    if let Some(verbosity) = text.verbosity {
        body.insert(
            "verbosity".to_owned(),
            Value::String(text_verbosity_to_wire(verbosity).to_owned()),
        );
    }

    if let Some(schema) = &text.json_schema {
        body.insert(
            "format".to_owned(),
            Value::Object(JsonObject::from_iter([
                ("type".to_owned(), Value::String("json_schema".to_owned())),
                ("strict".to_owned(), Value::Bool(true)),
                (
                    "name".to_owned(),
                    Value::String("codex_output_schema".to_owned()),
                ),
                ("schema".to_owned(), Value::Object(schema.clone())),
            ])),
        );
    }

    (!body.is_empty()).then_some(body)
}

fn response_item_to_json(item: &ResponseItem) -> Value {
    match item {
        ResponseItem::Message(message) => Value::Object(JsonObject::from_iter([
            ("type".to_owned(), Value::String("message".to_owned())),
            (
                "id".to_owned(),
                optional_string_value(message.id.as_deref()),
            ),
            (
                "status".to_owned(),
                optional_string_value(message.status.as_deref()),
            ),
            ("role".to_owned(), Value::String(message.role.clone())),
            (
                "content".to_owned(),
                Value::Array(message.content.iter().map(content_item_to_json).collect()),
            ),
        ])),
        ResponseItem::FunctionCall(call) => Value::Object(JsonObject::from_iter([
            ("type".to_owned(), Value::String("function_call".to_owned())),
            ("id".to_owned(), optional_string_value(call.id.as_deref())),
            (
                "status".to_owned(),
                optional_string_value(call.status.as_deref()),
            ),
            ("name".to_owned(), Value::String(call.name.clone())),
            (
                "namespace".to_owned(),
                optional_string_value(call.namespace.as_deref()),
            ),
            (
                "arguments".to_owned(),
                Value::String(call.arguments.clone()),
            ),
            ("call_id".to_owned(), Value::String(call.call_id.clone())),
        ])),
        ResponseItem::FunctionCallOutput(output) => Value::Object(JsonObject::from_iter([
            (
                "type".to_owned(),
                Value::String("function_call_output".to_owned()),
            ),
            ("id".to_owned(), optional_string_value(output.id.as_deref())),
            (
                "status".to_owned(),
                optional_string_value(output.status.as_deref()),
            ),
            ("call_id".to_owned(), Value::String(output.call_id.clone())),
            ("output".to_owned(), tool_output_to_json(&output.output)),
        ])),
        ResponseItem::CustomToolCallOutput(output) => Value::Object(JsonObject::from_iter([
            (
                "type".to_owned(),
                Value::String("custom_tool_call_output".to_owned()),
            ),
            ("id".to_owned(), optional_string_value(output.id.as_deref())),
            (
                "status".to_owned(),
                optional_string_value(output.status.as_deref()),
            ),
            ("call_id".to_owned(), Value::String(output.call_id.clone())),
            ("output".to_owned(), tool_output_to_json(&output.output)),
        ])),
        ResponseItem::Reasoning(reasoning) => {
            let mut value = JsonObject::from_iter([
                ("type".to_owned(), Value::String("reasoning".to_owned())),
                (
                    "id".to_owned(),
                    optional_string_value(reasoning.id.as_deref()),
                ),
                (
                    "status".to_owned(),
                    optional_string_value(reasoning.status.as_deref()),
                ),
                ("summary".to_owned(), reasoning.summary.clone()),
            ]);

            if let Some(content) = &reasoning.content {
                value.insert(
                    "content".to_owned(),
                    Value::Array(content.iter().map(content_item_to_json).collect()),
                );
            }

            if let Some(encrypted_content) = reasoning.encrypted_content.as_ref() {
                value.insert(
                    "encrypted_content".to_owned(),
                    Value::String(encrypted_content.clone()),
                );
            }

            Value::Object(value)
        }
        ResponseItem::Opaque(opaque) => Value::Object(opaque.raw.clone()),
    }
}

fn content_item_to_json(item: &ContentItem) -> Value {
    match item {
        ContentItem::InputText { text } => Value::Object(JsonObject::from_iter([
            ("type".to_owned(), Value::String("input_text".to_owned())),
            ("text".to_owned(), Value::String(text.clone())),
        ])),
        ContentItem::InputImage { image_url } => Value::Object(JsonObject::from_iter([
            ("type".to_owned(), Value::String("input_image".to_owned())),
            ("image_url".to_owned(), Value::String(image_url.clone())),
        ])),
        ContentItem::OutputText { text, raw } => {
            let mut value = raw.clone();
            value.insert("type".to_owned(), Value::String("output_text".to_owned()));
            value.insert("text".to_owned(), Value::String(text.clone()));
            Value::Object(value)
        }
        ContentItem::Other { raw } => Value::Object(raw.clone()),
    }
}

fn tool_output_to_json(output: &ToolOutput) -> Value {
    match output {
        ToolOutput::Text(text) => Value::String(text.clone()),
        ToolOutput::Content(content) => {
            Value::Array(content.iter().map(content_item_to_json).collect())
        }
    }
}

fn optional_string_value(value: Option<&str>) -> Value {
    value
        .map(|value| Value::String(value.to_owned()))
        .unwrap_or(Value::Null)
}

fn service_tier_to_wire(service_tier: ChatgptServiceTier) -> &'static str {
    match service_tier {
        ChatgptServiceTier::Default => "default",
        ChatgptServiceTier::Flex => "flex",
        ChatgptServiceTier::Fast => "priority",
    }
}

fn text_verbosity_to_wire(verbosity: TextVerbosity) -> &'static str {
    match verbosity {
        TextVerbosity::Low => "low",
        TextVerbosity::Medium => "medium",
        TextVerbosity::High => "high",
    }
}

pub struct ChatgptResponseStream {
    effective_turn_state: Option<String>,
    receiver: mpsc::Receiver<Result<ChatgptResponseEvent, ChatgptApiError>>,
    driver_task: Option<JoinHandle<()>>,
}

impl ChatgptResponseStream {
    pub fn effective_turn_state(&self) -> Option<&str> {
        self.effective_turn_state.as_deref()
    }

    fn empty(
        effective_turn_state: Option<String>,
        receiver: mpsc::Receiver<Result<ChatgptResponseEvent, ChatgptApiError>>,
        driver_task: Option<JoinHandle<()>>,
    ) -> Self {
        Self {
            effective_turn_state,
            receiver,
            driver_task,
        }
    }
}

impl Drop for ChatgptResponseStream {
    fn drop(&mut self) {
        if let Some(driver_task) = self.driver_task.take() {
            driver_task.abort();
        }
    }
}

impl Stream for ChatgptResponseStream {
    type Item = Result<ChatgptResponseEvent, ChatgptApiError>;

    fn poll_next(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        self.get_mut().receiver.poll_recv(cx)
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ChatgptResponsesRequest {
    pub model: String,
    pub model_capabilities: ChatgptModelCapabilities,
    pub context: ChatgptRequestContext,
    pub instructions: Option<String>,
    pub input: Vec<ResponseItem>,
    pub tools: Vec<ToolDescriptor>,
    pub parallel_tool_calls: bool,
    pub reasoning: ChatgptReasoningOptions,
    pub text: ChatgptTextOptions,
    pub service_tier: Option<ChatgptServiceTier>,
}

impl ChatgptResponsesRequest {
    pub fn validate(&self) -> Result<(), RequestValidationError> {
        validate_non_blank("model", &self.model)?;
        validate_non_blank("context.conversation_id", &self.context.conversation_id)?;
        validate_non_blank("context.installation_id", &self.context.installation_id)?;

        if self.context.conversation_id.contains(':') {
            return Err(RequestValidationError::new(
                "context.conversation_id",
                "must not contain ':'",
            ));
        }

        validate_header_value("context.conversation_id", &self.context.conversation_id)?;
        validate_header_value("context.installation_id", &self.context.installation_id)?;
        validate_optional_header_value("context.turn_state", self.context.turn_state.as_deref())?;
        validate_optional_header_value(
            "context.turn_metadata",
            self.context.turn_metadata.as_deref(),
        )?;
        validate_optional_header_value("context.subagent", self.context.subagent.as_deref())?;
        validate_optional_header_value(
            "context.parent_thread_id",
            self.context.parent_thread_id.as_deref(),
        )?;

        for beta_feature in &self.context.beta_features {
            validate_non_blank("context.beta_features", beta_feature)?;
            validate_header_value("context.beta_features", beta_feature)?;

            if beta_feature.contains(',') {
                return Err(RequestValidationError::new(
                    "context.beta_features",
                    "must not contain ','",
                ));
            }
        }

        if self.reasoning.summary.is_some() && !self.model_capabilities.supports_reasoning_summaries
        {
            return Err(RequestValidationError::new(
                "reasoning.summary",
                "is not supported by this model",
            ));
        }

        if self.text.verbosity.is_some() && !self.model_capabilities.supports_text_verbosity {
            return Err(RequestValidationError::new(
                "text.verbosity",
                "is not supported by this model",
            ));
        }

        validate_json_objects("tools", &self.tools)?;

        Ok(())
    }
}

fn validate_non_blank(field: &'static str, value: &str) -> Result<(), RequestValidationError> {
    if value.trim().is_empty() {
        return Err(RequestValidationError::new(field, "must not be blank"));
    }

    Ok(())
}

fn validate_header_value(field: &'static str, value: &str) -> Result<(), RequestValidationError> {
    HeaderValue::from_str(value)
        .map_err(|_| RequestValidationError::new(field, "must be a valid HTTP header value"))?;

    Ok(())
}

fn validate_optional_header_value(
    field: &'static str,
    value: Option<&str>,
) -> Result<(), RequestValidationError> {
    if let Some(value) = value {
        validate_non_blank(field, value)?;
        validate_header_value(field, value)?;
    }

    Ok(())
}

fn validate_json_objects(
    field: &'static str,
    tools: &[ToolDescriptor],
) -> Result<(), RequestValidationError> {
    if tools
        .iter()
        .any(|descriptor| serde_json::to_value(&descriptor.0).ok().is_none())
    {
        return Err(RequestValidationError::new(
            field,
            "must be valid JSON objects",
        ));
    }

    Ok(())
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ChatgptModelCapabilities {
    pub supports_reasoning_summaries: bool,
    pub supports_text_verbosity: bool,
    pub default_reasoning_effort: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ChatgptRequestContext {
    pub conversation_id: String,
    pub window_generation: u64,
    pub installation_id: String,
    pub turn_state: Option<String>,
    pub turn_metadata: Option<String>,
    pub beta_features: Vec<String>,
    pub subagent: Option<String>,
    pub parent_thread_id: Option<String>,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct ChatgptReasoningOptions {
    pub effort: Option<String>,
    pub summary: Option<String>,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct ChatgptTextOptions {
    pub verbosity: Option<TextVerbosity>,
    pub json_schema: Option<JsonObject>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TextVerbosity {
    Low,
    Medium,
    High,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ChatgptServiceTier {
    Default,
    Flex,
    Fast,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ToolDescriptor(pub JsonObject);

#[derive(Clone, Debug, PartialEq)]
#[non_exhaustive]
pub enum ChatgptResponseEvent {
    Created(ChatgptResponseSnapshot),
    OutputItemAdded {
        output_index: u64,
        item: ResponseItem,
    },
    OutputItemDone {
        output_index: u64,
        item: ResponseItem,
    },
    OutputTextDelta {
        item_id: String,
        output_index: u64,
        content_index: u64,
        delta: String,
    },
    OutputTextDone {
        item_id: String,
        output_index: u64,
        content_index: u64,
        text: String,
    },
    ReasoningSummaryTextDelta {
        item_id: String,
        output_index: u64,
        summary_index: u64,
        delta: String,
    },
    ReasoningSummaryTextDone {
        item_id: String,
        output_index: u64,
        summary_index: u64,
        text: String,
    },
    ReasoningTextDelta {
        item_id: String,
        output_index: u64,
        content_index: u64,
        delta: String,
    },
    ReasoningTextDone {
        item_id: String,
        output_index: u64,
        content_index: u64,
        text: String,
    },
    Completed(ChatgptResponseSnapshot),
    Other(ChatgptRawEvent),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ChatgptResponseSnapshot {
    pub id: Option<String>,
    pub model: Option<String>,
    pub usage: Option<ChatgptUsage>,
    pub service_tier: Option<String>,
    pub raw: JsonObject,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ChatgptRawEvent {
    pub event_type: String,
    pub payload: JsonObject,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ChatgptUsage {
    pub input_tokens: Option<u64>,
    pub cached_input_tokens: Option<u64>,
    pub output_tokens: Option<u64>,
    pub reasoning_output_tokens: Option<u64>,
    pub total_tokens: Option<u64>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
#[non_exhaustive]
pub enum ResponseItem {
    Message(MessageItem),
    FunctionCall(FunctionCallItem),
    FunctionCallOutput(FunctionCallOutputItem),
    CustomToolCallOutput(CustomToolCallOutputItem),
    Reasoning(ReasoningItem),
    Opaque(OpaqueResponseItem),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MessageItem {
    pub id: Option<String>,
    pub status: Option<String>,
    pub role: String,
    pub content: Vec<ContentItem>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FunctionCallItem {
    pub id: Option<String>,
    pub status: Option<String>,
    pub name: String,
    pub namespace: Option<String>,
    pub arguments: String,
    pub call_id: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FunctionCallOutputItem {
    pub id: Option<String>,
    pub status: Option<String>,
    pub call_id: String,
    pub output: ToolOutput,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CustomToolCallOutputItem {
    pub id: Option<String>,
    pub status: Option<String>,
    pub call_id: String,
    pub output: ToolOutput,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ReasoningItem {
    pub id: Option<String>,
    pub status: Option<String>,
    pub summary: Value,
    pub content: Option<Vec<ContentItem>>,
    pub encrypted_content: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OpaqueResponseItem {
    pub raw: JsonObject,
}

#[derive(Clone, Debug, Eq, PartialEq)]
#[non_exhaustive]
pub enum ContentItem {
    InputText { text: String },
    InputImage { image_url: String },
    OutputText { text: String, raw: JsonObject },
    Other { raw: JsonObject },
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ToolOutput {
    Text(String),
    Content(Vec<ContentItem>),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RequestValidationError {
    pub field: &'static str,
    pub reason: String,
}

impl RequestValidationError {
    fn new(field: &'static str, reason: impl Into<String>) -> Self {
        Self {
            field,
            reason: reason.into(),
        }
    }
}

#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum ChatgptApiError {
    #[error(transparent)]
    LowerLayer(#[from] ChatgptApiLowerLayerError),
    #[error(transparent)]
    Endpoint(#[from] ChatgptApiEndpointError),
}

#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum ChatgptApiLowerLayerError {
    #[error("invalid request field {0:?}")]
    InvalidInput(RequestValidationError),
    #[error(transparent)]
    Config(#[from] selvedge_config::ConfigError),
    #[error("auth error: {0:?}")]
    Auth(chatgpt_auth::ChatgptAuthError),
    #[error(transparent)]
    Client(#[from] selvedge_client::HttpError),
    #[error("response stream exceeded completion timeout of {timeout:?}")]
    StreamCompletionTimeout { timeout: Duration },
}

#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum ChatgptApiEndpointError {
    #[error("response failed")]
    Failed(ChatgptFailedEndpointError),
    #[error("response incomplete")]
    Incomplete(ChatgptIncompleteEndpointError),
    #[error("response head was not a valid event stream")]
    MalformedResponseHead { content_type: Option<String> },
    #[error("malformed event: {reason}")]
    MalformedEvent { reason: String, raw: Option<String> },
    #[error("response stream closed before completion")]
    PrematureClose,
    #[error("unexpected endpoint event")]
    Other(ChatgptOtherEndpointError),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ChatgptFailedEndpointKind {
    ContextLengthExceeded,
    InsufficientQuota,
    UsageNotIncluded,
    InvalidPrompt,
    ServerOverloaded,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ChatgptFailedEndpointError {
    pub kind: ChatgptFailedEndpointKind,
    pub response_id: Option<String>,
    pub code: Option<String>,
    pub message: Option<String>,
    pub raw: JsonObject,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ChatgptIncompleteEndpointError {
    pub response_id: Option<String>,
    pub reason: Option<String>,
    pub raw: JsonObject,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ChatgptOtherEndpointError {
    pub event_type: Option<String>,
    pub code: Option<String>,
    pub message: Option<String>,
    pub retry_after: Option<Duration>,
    pub raw: JsonObject,
}

#[cfg(test)]
mod tests {
    use chatgpt_auth::ResolvedChatgptAuth;
    use http::HeaderValue;
    use selvedge_client::{HttpMethod, HttpRequestBody, RequestCompression};
    use selvedge_config_model::ChatgptApiConfig;

    use super::{
        ChatgptModelCapabilities, ChatgptReasoningOptions, ChatgptRequestContext,
        ChatgptResponsesRequest, ChatgptServiceTier, ChatgptTextOptions, ContentItem, JsonObject,
        MessageItem, ResponseItem, TextVerbosity, ToolDescriptor, build_http_request,
    };

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
                window_generation: 3,
                installation_id: "install-123".to_owned(),
                turn_state: Some("turn-state".to_owned()),
                turn_metadata: Some("{\"k\":\"v\"}".to_owned()),
                beta_features: vec!["beta-a".to_owned(), "beta-b".to_owned()],
                subagent: Some("planner".to_owned()),
                parent_thread_id: Some("thread-123".to_owned()),
            },
            instructions: Some("follow instructions".to_owned()),
            input: vec![ResponseItem::Message(MessageItem {
                id: Some("msg-1".to_owned()),
                status: Some("completed".to_owned()),
                role: "user".to_owned(),
                content: vec![ContentItem::InputText {
                    text: "hello".to_owned(),
                }],
            })],
            tools: vec![ToolDescriptor(JsonObject::new())],
            parallel_tool_calls: true,
            reasoning: ChatgptReasoningOptions {
                effort: Some("high".to_owned()),
                summary: Some("detailed".to_owned()),
            },
            text: ChatgptTextOptions {
                verbosity: Some(TextVerbosity::High),
                json_schema: Some(JsonObject::from_iter([(
                    "type".to_owned(),
                    serde_json::json!("object"),
                )])),
            },
            service_tier: Some(ChatgptServiceTier::Fast),
        }
    }

    fn base_auth() -> ResolvedChatgptAuth {
        ResolvedChatgptAuth {
            access_token: "access-token".to_owned(),
            access_token_expires_at: None,
            account_id: "account-123".to_owned(),
            user_id: Some("user-123".to_owned()),
            email: Some("user@example.com".to_owned()),
            plan_type: Some("plus".to_owned()),
        }
    }

    fn base_api_config() -> ChatgptApiConfig {
        ChatgptApiConfig {
            base_url: "https://chatgpt.com/backend-api/codex".to_owned(),
            stream_completion_timeout_ms: 1_800_000,
        }
    }

    #[test]
    fn build_http_request_derives_headers_and_body_for_supported_models() {
        let request = base_request();
        let auth = base_auth();
        let api_config = base_api_config();

        let http_request = build_http_request(&request, &auth, &api_config).expect("http request");

        assert_eq!(http_request.method, HttpMethod::Post);
        assert_eq!(
            http_request.url,
            "https://chatgpt.com/backend-api/codex/responses"
        );
        assert_eq!(http_request.compression, RequestCompression::None);
        assert_eq!(
            http_request
                .headers
                .get("authorization")
                .and_then(|value: &HeaderValue| value.to_str().ok()),
            Some("Bearer access-token")
        );
        assert_eq!(
            http_request
                .headers
                .get("chatgpt-account-id")
                .and_then(|value: &HeaderValue| value.to_str().ok()),
            Some("account-123")
        );
        assert_eq!(
            http_request
                .headers
                .get("x-codex-window-id")
                .and_then(|value: &HeaderValue| value.to_str().ok()),
            Some("conversation-123:3")
        );

        let HttpRequestBody::Json(body) = http_request.body else {
            panic!("expected json body");
        };

        assert_eq!(body.get("model"), Some(&serde_json::json!("gpt-5")));
        assert_eq!(body.get("tool_choice"), Some(&serde_json::json!("auto")));
        assert_eq!(
            body.get("parallel_tool_calls"),
            Some(&serde_json::json!(true))
        );
        assert_eq!(body.get("store"), Some(&serde_json::json!(false)));
        assert_eq!(body.get("stream"), Some(&serde_json::json!(true)));
        assert_eq!(
            body.get("prompt_cache_key"),
            Some(&serde_json::json!("conversation-123"))
        );
        assert_eq!(
            body.get("include"),
            Some(&serde_json::json!(["reasoning.encrypted_content"]))
        );
        assert_eq!(
            body.get("service_tier"),
            Some(&serde_json::json!("priority"))
        );
        assert_eq!(
            body.pointer("/client_metadata/x-codex-installation-id"),
            Some(&serde_json::json!("install-123"))
        );
        assert_eq!(
            body.pointer("/reasoning/effort"),
            Some(&serde_json::json!("high"))
        );
        assert_eq!(
            body.pointer("/reasoning/summary"),
            Some(&serde_json::json!("detailed"))
        );
        assert_eq!(
            body.pointer("/text/verbosity"),
            Some(&serde_json::json!("high"))
        );
        assert_eq!(
            body.pointer("/text/format/type"),
            Some(&serde_json::json!("json_schema"))
        );
        assert_eq!(
            body.pointer("/text/format/strict"),
            Some(&serde_json::json!(true))
        );
        assert_eq!(
            body.pointer("/text/format/name"),
            Some(&serde_json::json!("codex_output_schema"))
        );
    }

    #[test]
    fn build_http_request_uses_null_reasoning_for_unsupported_models() {
        let mut request = base_request();
        request.instructions = None;
        request.tools.clear();
        request.service_tier = None;
        request.text = ChatgptTextOptions::default();
        request.reasoning = ChatgptReasoningOptions::default();
        request.model_capabilities.supports_reasoning_summaries = false;
        request.model_capabilities.supports_text_verbosity = false;
        request.model_capabilities.default_reasoning_effort = None;
        request.context.turn_state = None;
        request.context.turn_metadata = None;
        request.context.beta_features.clear();
        request.context.subagent = None;
        request.context.parent_thread_id = None;

        let http_request =
            build_http_request(&request, &base_auth(), &base_api_config()).expect("http request");

        assert!(http_request.headers.get("x-codex-turn-state").is_none());
        assert!(http_request.headers.get("x-codex-turn-metadata").is_none());
        assert!(http_request.headers.get("x-codex-beta-features").is_none());

        let HttpRequestBody::Json(body) = http_request.body else {
            panic!("expected json body");
        };

        assert_eq!(body.get("reasoning"), Some(&serde_json::Value::Null));
        assert_eq!(body.get("include"), Some(&serde_json::json!([])));
        assert!(body.get("instructions").is_none());
        assert!(body.get("service_tier").is_none());
        assert!(body.get("text").is_none());
        assert_eq!(body.get("tools"), Some(&serde_json::json!([])));
    }
}
