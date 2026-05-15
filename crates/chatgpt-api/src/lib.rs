#![doc = include_str!("../README.md")]
#![allow(clippy::result_large_err)]

use std::{
    pin::Pin,
    sync::{Arc, Mutex},
    task::{Context, Poll},
    time::Duration,
};

use futures::StreamExt;
use futures_core::Stream;
use http::{HeaderMap, HeaderValue, StatusCode};
use serde_json::Value;
use tokio::{sync::mpsc, task::JoinHandle};

// @behavior selvedge.model.chatgpt.event.verify_surface ChatGPT API callers observe request validation, HTTP stream opening, typed response events, endpoint errors, and public data shapes.
// @behavior selvedge.model.chatgpt.api ChatGPT API callers observe request validation, authenticated `/responses` streaming, typed response events, endpoint errors, and public data shapes.
// @intent selvedge.model.chatgpt.api.json_object Public JSON object aliases expose raw ChatGPT payload objects without tying callers to serde_json map spelling.
pub type JsonObject = serde_json::Map<String, Value>;

// @behavior selvedge.model.chatgpt.api.stream Starting a ChatGPT response stream validates the request, reads current API config, opens the upstream stream, and returns a typed event stream.
pub async fn stream(
    request: ChatgptResponsesRequest,
) -> Result<ChatgptResponseStream, ChatgptApiError> {
    request
        .validate()
        // @behavior selvedge.model.chatgpt.api.stream.invalid_request Invalid response stream requests return lower-layer invalid-input errors before auth or HTTP work.
        .map_err(ChatgptApiLowerLayerError::InvalidInput)
        .map_err(ChatgptApiError::LowerLayer)?;

    let api_config = selvedge_config::read(|config| config.llm.providers.chatgpt.api.clone())
        // @behavior selvedge.model.chatgpt.api.stream.config Stream startup reads the current ChatGPT API config and returns config errors before opening HTTP streams.
        .map_err(ChatgptApiLowerLayerError::Config)
        .map_err(ChatgptApiError::LowerLayer)?;
    let response = open_response_stream(&request, &api_config).await?;
    // @behavior selvedge.model.chatgpt.api.turn_state The effective turn state returned to callers prefers the upstream response header and otherwise preserves the request turn state.
    let effective_turn_state = response
        .headers
        .get("x-codex-turn-state")
        .and_then(|value| value.to_str().ok())
        .map(str::to_owned)
        .or_else(|| request.context.turn_state.clone());

    let (sender, receiver) = mpsc::channel(32);
    let terminal_error = Arc::new(Mutex::new(None));
    let terminal_error_for_driver = Arc::clone(&terminal_error);
    let timeout = Duration::from_millis(api_config.stream_completion_timeout_ms);
    let driver_task = tokio::spawn(async move {
        drive_response_stream(response.body, sender, terminal_error_for_driver, timeout).await;
    });

    Ok(ChatgptResponseStream::empty(
        effective_turn_state,
        receiver,
        terminal_error,
        Some(driver_task),
    ))
}

// @behavior selvedge.model.chatgpt.api.open ChatGPT stream opening resolves auth, builds `/responses`, retries bounded pre-stream failures, and returns an event-stream response.
async fn open_response_stream(
    request: &ChatgptResponsesRequest,
    api_config: &selvedge_config_model::ChatgptApiConfig,
) -> Result<selvedge_client::HttpStreamResponse, ChatgptApiError> {
    let mut auth = chatgpt_auth::resolve_for_request()
        .await
        // @behavior selvedge.model.chatgpt.api.open.auth Auth resolution failures surface as lower-layer auth errors before the upstream stream is opened.
        .map_err(ChatgptApiLowerLayerError::Auth)
        .map_err(ChatgptApiError::LowerLayer)?;
    let mut retry_count = 0_u8;
    let mut reauth_used = false;

    loop {
        let http_request = build_http_request(request, &auth, api_config)
            // @behavior selvedge.model.chatgpt.api.open.request_error HTTP request construction errors return lower-layer invalid-input errors before transport use.
            .map_err(ChatgptApiLowerLayerError::InvalidInput)
            .map_err(ChatgptApiError::LowerLayer)?;

        match selvedge_client::stream(http_request).await {
            Ok(response) => {
                ensure_event_stream_content_type(&response.headers)?;
                return Ok(response);
            }
            // @behavior selvedge.model.chatgpt.api.open.unauthorized A single upstream unauthorized response forces auth refresh and retries the stream opening once.
            Err(selvedge_client::HttpError::Status(status))
                if status.status == StatusCode::UNAUTHORIZED && !reauth_used =>
            {
                auth = chatgpt_auth::resolve_after_unauthorized()
                    .await
                    // @behavior selvedge.model.chatgpt.api.open.reauth_error Forced auth refresh failures surface as lower-layer auth errors.
                    .map_err(ChatgptApiLowerLayerError::Auth)
                    .map_err(ChatgptApiError::LowerLayer)?;
                reauth_used = true;
            }
            // @behavior selvedge.model.chatgpt.api.open.retry Retryable pre-stream client errors are retried up to five times before the stream is returned to the caller.
            Err(error) if is_retryable_client_error(&error) && retry_count < 5 => {
                let delay = retry_delay_for_attempt(retry_count, &error);
                retry_count += 1;
                tokio::time::sleep(delay).await;
            }
            Err(error) => {
                // @behavior selvedge.model.chatgpt.api.open.client_error Exhausted or unretryable stream-opening failures surface as lower-layer client errors.
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

    let is_event_stream = content_type.as_deref().is_some_and(|value| {
        value
            .split(';')
            .next()
            .is_some_and(|media_type| media_type.trim().eq_ignore_ascii_case("text/event-stream"))
    });

    if !is_event_stream {
        // @constraint selvedge.model.chatgpt.api.open.content_type Successful stream openings must return a `text/event-stream` content type before events are delivered.
        return Err(ChatgptApiError::Endpoint(
            ChatgptApiEndpointError::MalformedResponseHead { content_type },
        ));
    }

    Ok(())
}

fn is_retryable_client_error(error: &selvedge_client::HttpError) -> bool {
    // @behavior selvedge.model.chatgpt.api.retry ChatGPT stream opening applies bounded retries to selected pre-stream failures.
    // @constraint selvedge.model.chatgpt.api.retry.classification Pre-stream retries apply to connection, IO, and retryable HTTP status failures while immediate timeout, config, build, and TLS failures return to callers.
    match error {
        selvedge_client::HttpError::Timeout => false,
        selvedge_client::HttpError::Connect { .. } | selvedge_client::HttpError::Io { .. } => true,
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
    // @behavior selvedge.model.chatgpt.api.retry.delay Retry delay uses an upstream Retry-After value capped at thirty seconds or an exponential millisecond backoff.
    if let selvedge_client::HttpError::Status(status) = error
        && let Some(retry_after) = parse_retry_after_header(
            status
                .headers
                .get("retry-after")
                .and_then(|value| value.to_str().ok()),
        )
    {
        return retry_after.min(Duration::from_secs(30));
    }

    match retry_count {
        0 => Duration::from_millis(200),
        1 => Duration::from_millis(400),
        2 => Duration::from_millis(800),
        3 => Duration::from_millis(1600),
        _ => Duration::from_millis(3200),
    }
}

// @behavior selvedge.model.chatgpt.api.drive ChatGPT stream driving converts body chunks into caller-visible response events or terminal errors.
async fn drive_response_stream(
    mut body: selvedge_client::ByteStream,
    sender: mpsc::Sender<Result<ChatgptResponseEvent, ChatgptApiError>>,
    terminal_error: Arc<Mutex<Option<ChatgptApiError>>>,
    timeout: Duration,
) {
    let deadline = tokio::time::Instant::now() + timeout;
    let mut buffer = Vec::new();

    loop {
        let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
        if remaining.is_zero() {
            send_stream_item(
                &sender,
                &terminal_error,
                // @behavior selvedge.model.chatgpt.api.drive.completion_timeout Stream completion timeout produces a lower-layer timeout error when the stream exceeds its total lifetime.
                Err(ChatgptApiError::LowerLayer(
                    ChatgptApiLowerLayerError::StreamCompletionTimeout { timeout },
                )),
                deadline,
                timeout,
            )
            .await;
            return;
        }

        // @behavior selvedge.model.chatgpt.api.drive.next_chunk ChatGPT stream body reads are bounded by the remaining completion timeout.
        let next_chunk = tokio::time::timeout(remaining, body.next()).await;
        let maybe_chunk = match next_chunk {
            Ok(chunk) => chunk,
            Err(_) => {
                send_stream_item(
                    &sender,
                    &terminal_error,
                    // @behavior selvedge.model.chatgpt.api.drive.chunk_timeout Chunk waits that consume the completion budget produce stream completion timeout errors.
                    Err(ChatgptApiError::LowerLayer(
                        ChatgptApiLowerLayerError::StreamCompletionTimeout { timeout },
                    )),
                    deadline,
                    timeout,
                )
                .await;
                return;
            }
        };

        let Some(chunk) = maybe_chunk else {
            let final_result = if buffer.is_empty() {
                // @behavior selvedge.model.chatgpt.api.drive.empty_close Empty upstream stream closure produces a premature-close endpoint error.
                Err(ChatgptApiError::Endpoint(
                    ChatgptApiEndpointError::PrematureClose,
                ))
            } else {
                parse_final_sse_frame(&buffer).and_then(|maybe_payload| match maybe_payload {
                    // @behavior selvedge.model.chatgpt.api.drive.trailing_frame Upstream closure with buffered non-event data produces a premature-close endpoint error.
                    None => Err(ChatgptApiError::Endpoint(
                        ChatgptApiEndpointError::PrematureClose,
                    )),
                    Some(payload) => match map_stream_event(&payload) {
                        Ok(MappedEvent::Event(event)) => Ok(Some(event)),
                        Ok(MappedEvent::Completed(event)) => Ok(Some(event)),
                        // @behavior selvedge.model.chatgpt.api.drive.final_endpoint_error Final buffered endpoint-error events become terminal endpoint errors.
                        Ok(MappedEvent::EndpointError(error)) => Err(error),
                        // @behavior selvedge.model.chatgpt.api.drive.final_map_error Final buffered malformed events become terminal stream errors.
                        Err(error) => Err(error),
                    },
                })
            };

            match final_result {
                Ok(Some(event)) => {
                    if event_is_completed(&event) {
                        let _ = send_stream_item(
                            &sender,
                            &terminal_error,
                            Ok(event),
                            deadline,
                            timeout,
                        )
                        .await;
                        return;
                    }

                    if !send_stream_item(&sender, &terminal_error, Ok(event), deadline, timeout)
                        .await
                    {
                        return;
                    }
                    send_stream_item(
                        &sender,
                        &terminal_error,
                        // @behavior selvedge.model.chatgpt.api.drive.final_noncompletion A final buffered non-completion event is delivered and followed by a premature-close error.
                        Err(ChatgptApiError::Endpoint(
                            ChatgptApiEndpointError::PrematureClose,
                        )),
                        deadline,
                        timeout,
                    )
                    .await;
                    return;
                }
                Ok(None) => {}
                // @behavior selvedge.model.chatgpt.api.drive.final_error Malformed final buffered SSE data is delivered as the terminal stream error.
                Err(error) => {
                    send_stream_item(&sender, &terminal_error, Err(error), deadline, timeout).await;
                    return;
                }
            }

            if buffer.is_empty() {
                return;
            }

            return;
        };

        let chunk = match chunk {
            Ok(bytes) => bytes,
            // @behavior selvedge.model.chatgpt.api.drive.body_error Upstream body stream errors are delivered as lower-layer client errors.
            Err(error) => {
                send_stream_item(
                    &sender,
                    &terminal_error,
                    Err(ChatgptApiError::LowerLayer(
                        ChatgptApiLowerLayerError::Client(error),
                    )),
                    deadline,
                    timeout,
                )
                .await;
                return;
            }
        };

        buffer.extend_from_slice(&chunk);

        while let Some(frame) = take_next_sse_frame(&mut buffer) {
            let frame = match std::str::from_utf8(&frame) {
                Ok(text) => text.replace("\r\n", "\n").replace('\r', "\n"),
                // @behavior selvedge.model.chatgpt.api.drive.utf8 Non-UTF-8 SSE frame bytes produce malformed-event endpoint errors.
                Err(_) => {
                    send_stream_item(
                        &sender,
                        &terminal_error,
                        Err(ChatgptApiError::Endpoint(
                            ChatgptApiEndpointError::MalformedEvent {
                                reason: "event stream contained non-utf8 bytes".to_owned(),
                                raw: None,
                            },
                        )),
                        deadline,
                        timeout,
                    )
                    .await;
                    return;
                }
            };

            if frame.trim().is_empty() {
                continue;
            }

            let payload = match parse_sse_frame(&frame) {
                Ok(Some(payload)) => payload,
                Ok(None) => continue,
                // @behavior selvedge.model.chatgpt.api.drive.frame_error Malformed SSE frames are delivered as terminal stream errors.
                Err(error) => {
                    send_stream_item(&sender, &terminal_error, Err(error), deadline, timeout).await;
                    return;
                }
            };

            match map_stream_event(&payload) {
                Ok(MappedEvent::Event(event)) => {
                    if !send_stream_item(&sender, &terminal_error, Ok(event), deadline, timeout)
                        .await
                    {
                        return;
                    }
                }
                Ok(MappedEvent::Completed(event)) => {
                    send_stream_item(&sender, &terminal_error, Ok(event), deadline, timeout).await;
                    return;
                }
                Ok(MappedEvent::EndpointError(error)) => {
                    // @behavior selvedge.model.chatgpt.api.drive.endpoint_event Endpoint failure events are delivered as terminal stream errors.
                    send_stream_item(&sender, &terminal_error, Err(error), deadline, timeout).await;
                    return;
                }
                Err(error) => {
                    // @behavior selvedge.model.chatgpt.api.drive.map_error Event mapping errors are delivered as terminal stream errors.
                    send_stream_item(&sender, &terminal_error, Err(error), deadline, timeout).await;
                    return;
                }
            }
        }
    }
}

// @behavior selvedge.model.chatgpt.api.send_item ChatGPT stream item delivery forwards response events and records timeout errors under channel backpressure.
async fn send_stream_item(
    sender: &mpsc::Sender<Result<ChatgptResponseEvent, ChatgptApiError>>,
    terminal_error: &Arc<Mutex<Option<ChatgptApiError>>>,
    item: Result<ChatgptResponseEvent, ChatgptApiError>,
    deadline: tokio::time::Instant,
    timeout: Duration,
) -> bool {
    // @behavior selvedge.model.chatgpt.api.send_item.timeout ChatGPT stream item delivery applies the completion deadline to channel sends.
    match tokio::time::timeout_at(deadline, sender.send(item)).await {
        Ok(Ok(())) => true,
        // @behavior selvedge.model.chatgpt.api.send_item.receiver_closed Closed caller receivers stop background stream delivery.
        Ok(Err(_)) => false,
        Err(_) => {
            // @behavior selvedge.model.chatgpt.api.send_item.backpressure_timeout Channel backpressure that consumes the completion budget records a stream completion timeout for the caller.
            if let Ok(mut slot) = terminal_error.lock() {
                *slot = Some(ChatgptApiError::LowerLayer(
                    ChatgptApiLowerLayerError::StreamCompletionTimeout { timeout },
                ));
            }
            false
        }
    }
}

fn parse_final_sse_frame(buffer: &[u8]) -> Result<Option<String>, ChatgptApiError> {
    // @behavior selvedge.model.chatgpt.api.sse ChatGPT SSE parsing converts event-stream frames into JSON payload strings or malformed-event errors.
    // @behavior selvedge.model.chatgpt.api.sse.final_frame Final buffered SSE bytes decode as UTF-8 and parse as a single optional event payload.
    let frame = std::str::from_utf8(buffer).map_err(|_| {
        ChatgptApiError::Endpoint(ChatgptApiEndpointError::MalformedEvent {
            reason: "event stream contained non-utf8 bytes".to_owned(),
            raw: None,
        })
    })?;

    parse_sse_frame(&frame.replace("\r\n", "\n").replace('\r', "\n"))
}

fn take_next_sse_frame(buffer: &mut Vec<u8>) -> Option<Vec<u8>> {
    let (frame_end, delimiter_len) = find_frame_delimiter(buffer)?;
    let frame = buffer[..frame_end].to_vec();
    buffer.drain(..frame_end + delimiter_len);

    Some(frame)
}

fn find_frame_delimiter(buffer: &[u8]) -> Option<(usize, usize)> {
    let mut index = 0;

    while index + 1 < buffer.len() {
        if buffer[index] == b'\n' && buffer[index + 1] == b'\n' {
            return Some((index, 2));
        }

        if buffer[index] == b'\r' && buffer[index + 1] == b'\r' {
            return Some((index, 2));
        }

        if index + 3 < buffer.len()
            && buffer[index] == b'\r'
            && buffer[index + 1] == b'\n'
            && buffer[index + 2] == b'\r'
            && buffer[index + 3] == b'\n'
        {
            return Some((index, 4));
        }

        index += 1;
    }

    None
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
    // @behavior selvedge.model.chatgpt.api.event.map SSE data payloads decode as JSON objects with string event types before typed event mapping.
    let raw_value = serde_json::from_str::<Value>(payload).map_err(|_| {
        ChatgptApiError::Endpoint(ChatgptApiEndpointError::MalformedEvent {
            reason: "event payload was not valid JSON".to_owned(),
            raw: Some(payload.to_owned()),
        })
    })?;
    let Value::Object(raw_object) = raw_value else {
        // @constraint selvedge.model.chatgpt.api.event.object Event payloads must be JSON objects before they can produce typed events.
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
        // @constraint selvedge.model.chatgpt.api.event.type Event payloads must contain a string type before they can produce typed events.
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
        _ if event_type.starts_with("response.") => Ok(MappedEvent::Event(
            ChatgptResponseEvent::Other(ChatgptRawEvent {
                event_type,
                payload: raw_object,
            }),
        )),
        _ => Ok(MappedEvent::EndpointError(unknown_endpoint_event(
            &raw_object,
            &event_type,
        ))),
    }
}

// @behavior selvedge.model.chatgpt.api.snapshot.decode ChatGPT response snapshots decode caller-visible response id, model, usage, service tier, and raw payload data.
fn response_snapshot_from_field(
    object: &JsonObject,
) -> Result<ChatgptResponseSnapshot, ChatgptApiError> {
    let response = object
        .get("response")
        .and_then(Value::as_object)
        // @constraint selvedge.model.chatgpt.api.snapshot.response_object Snapshot events must contain a response object before caller-visible snapshots are returned.
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

// @behavior selvedge.model.chatgpt.api.item.decode_field ChatGPT response item fields decode typed output items or return malformed event errors.
fn response_item_from_field(
    object: &JsonObject,
    field: &'static str,
) -> Result<ResponseItem, ChatgptApiError> {
    let item = object
        .get(field)
        .and_then(Value::as_object)
        // @constraint selvedge.model.chatgpt.api.item.field_object Response item fields must be JSON objects before item decoding.
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
                    // @constraint selvedge.model.chatgpt.api.item.function_call_output.required Function-call output items require an output field before typed decoding succeeds.
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
                        // @constraint selvedge.model.chatgpt.api.item.custom_tool_call_output.required Custom tool-call output items require an output field before typed decoding succeeds.
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
                // @constraint selvedge.model.chatgpt.api.item.reasoning.summary_required Reasoning items require a summary value before typed decoding succeeds.
                .ok_or_else(|| malformed_event("summary", "must be present"))?,
            content: item
                .get("content")
                .map(|value| match value {
                    Value::Array(values) => values
                        .iter()
                        .map(content_item_from_value)
                        .collect::<Result<Vec<_>, _>>(),
                    // @constraint selvedge.model.chatgpt.api.item.reasoning.content_array Reasoning item content must be an array when present.
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
        // @constraint selvedge.model.chatgpt.api.content.object Content items must be JSON objects before typed content decoding.
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
        // @constraint selvedge.model.chatgpt.api.tool_output.shape Tool outputs must be plain text or content arrays before typed decoding succeeds.
        _ => Err(malformed_event(
            "output",
            "must be a string or content array",
        )),
    }
}

fn chatgpt_usage_from_value(value: &Value) -> Result<ChatgptUsage, ChatgptApiError> {
    let usage = value
        .as_object()
        // @constraint selvedge.model.chatgpt.api.usage.object Usage values must be JSON objects before token counts are returned.
        .ok_or_else(|| malformed_event("usage", "must be an object"))?;

    Ok(ChatgptUsage {
        input_tokens: optional_u64(usage, "input_tokens")?,
        cached_input_tokens: nested_optional_u64_with_fallback(
            usage,
            "input_token_details",
            "input_tokens_details",
            "cached_tokens",
        )?,
        output_tokens: optional_u64(usage, "output_tokens")?,
        reasoning_output_tokens: nested_optional_u64_with_fallback(
            usage,
            "output_token_details",
            "output_tokens_details",
            "reasoning_tokens",
        )?,
        total_tokens: optional_u64(usage, "total_tokens")?,
    })
}

fn failed_endpoint_event(object: &JsonObject, event_type: &str) -> ChatgptApiError {
    let response = object.get("response").and_then(Value::as_object).cloned();
    let error = response
        .as_ref()
        .and_then(|response| response.get("error"))
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
        .as_ref()
        .and_then(|response| response.get("id"))
        .and_then(Value::as_str)
        .map(str::to_owned);
    let raw = response.unwrap_or_else(|| object.clone());

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

fn unknown_endpoint_event(object: &JsonObject, event_type: &str) -> ChatgptApiError {
    let code = object
        .get("code")
        .and_then(Value::as_str)
        .map(str::to_owned)
        .or_else(|| {
            object
                .get("error")
                .and_then(Value::as_object)
                .and_then(|error| error.get("code"))
                .and_then(Value::as_str)
                .map(str::to_owned)
        });
    let message = object
        .get("message")
        .and_then(Value::as_str)
        .map(str::to_owned)
        .or_else(|| {
            object
                .get("error")
                .and_then(Value::as_object)
                .and_then(|error| error.get("message"))
                .and_then(Value::as_str)
                .map(str::to_owned)
        });

    ChatgptApiError::Endpoint(ChatgptApiEndpointError::Other(ChatgptOtherEndpointError {
        event_type: Some(event_type.to_owned()),
        code,
        message: message.clone(),
        retry_after: message.as_deref().and_then(parse_retry_after),
        raw: object.clone(),
    }))
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

fn parse_retry_after_header(value: Option<&str>) -> Option<Duration> {
    let value = value?;

    if let Ok(seconds) = value.parse::<u64>() {
        return Some(Duration::from_secs(seconds));
    }

    let http_date = httpdate::parse_http_date(value).ok()?;
    let now = std::time::SystemTime::now();

    http_date.duration_since(now).ok()
}

fn malformed_event(field: &'static str, reason: &'static str) -> ChatgptApiError {
    ChatgptApiError::Endpoint(ChatgptApiEndpointError::MalformedEvent {
        reason: format!("{field} {reason}"),
        raw: None,
    })
}

// @constraint selvedge.model.chatgpt.api.decode ChatGPT event decoding rejects fields whose JSON shapes differ from the public typed event contract.
fn required_string(object: &JsonObject, field: &'static str) -> Result<String, ChatgptApiError> {
    object
        .get(field)
        .and_then(Value::as_str)
        .map(str::to_owned)
        // @constraint selvedge.model.chatgpt.api.decode.required_string Required string fields must contain JSON strings before typed decoding succeeds.
        .ok_or_else(|| malformed_event(field, "must be a string"))
}

fn optional_string(
    object: &JsonObject,
    field: &'static str,
) -> Result<Option<String>, ChatgptApiError> {
    match object.get(field) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(value)) => Ok(Some(value.clone())),
        // @constraint selvedge.model.chatgpt.api.decode.optional_string Optional string fields must be JSON strings when present.
        Some(_) => Err(malformed_event(field, "must be a string")),
    }
}

fn required_u64(object: &JsonObject, field: &'static str) -> Result<u64, ChatgptApiError> {
    object
        .get(field)
        .and_then(Value::as_u64)
        // @constraint selvedge.model.chatgpt.api.decode.required_u64 Required integer fields must contain unsigned JSON integers before typed decoding succeeds.
        .ok_or_else(|| malformed_event(field, "must be an unsigned integer"))
}

fn optional_u64(object: &JsonObject, field: &'static str) -> Result<Option<u64>, ChatgptApiError> {
    match object.get(field) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Number(number)) => number
            .as_u64()
            .map(Some)
            // @constraint selvedge.model.chatgpt.api.decode.optional_u64_numeric Optional integer fields must be unsigned when numeric.
            .ok_or_else(|| malformed_event(field, "must be an unsigned integer")),
        // @constraint selvedge.model.chatgpt.api.decode.optional_u64_type Optional integer fields must be JSON numbers when present.
        Some(_) => Err(malformed_event(field, "must be an unsigned integer")),
    }
}

fn nested_optional_u64(
    object: &JsonObject,
    parent_field: &'static str,
    child_field: &'static str,
) -> Result<Option<u64>, ChatgptApiError> {
    let Some(parent) = object.get(parent_field) else {
        return Ok(None);
    };
    let Value::Object(child) = parent else {
        // @constraint selvedge.model.chatgpt.api.decode.nested_u64_parent Nested token detail parents must be JSON objects when present.
        return Err(malformed_event(parent_field, "must be an object"));
    };

    optional_u64(child, child_field)
}

// @behavior selvedge.model.chatgpt.api.usage.nested_fallback ChatGPT usage parsing reads primary and alternate nested token detail field names.
fn nested_optional_u64_with_fallback(
    object: &JsonObject,
    primary_parent_field: &'static str,
    fallback_parent_field: &'static str,
    child_field: &'static str,
) -> Result<Option<u64>, ChatgptApiError> {
    nested_optional_u64(object, primary_parent_field, child_field)?.map_or_else(
        || nested_optional_u64(object, fallback_parent_field, child_field),
        |value| Ok(Some(value)),
    )
}

// @constraint selvedge.model.chatgpt.api.decode.required_array ChatGPT response fields required as arrays must contain JSON arrays.
fn required_array<'a>(
    object: &'a JsonObject,
    field: &'static str,
) -> Result<&'a Vec<Value>, ChatgptApiError> {
    object
        .get(field)
        .and_then(Value::as_array)
        // @constraint selvedge.model.chatgpt.api.decode.required_array_type Required array fields must contain JSON arrays before typed decoding succeeds.
        .ok_or_else(|| malformed_event(field, "must be an array"))
}

// @behavior selvedge.model.chatgpt.api.http_request ChatGPT HTTP requests post to the configured `/responses` endpoint with auth, correlation, replay, beta, and streaming fields.
fn build_http_request(
    request: &ChatgptResponsesRequest,
    auth: &chatgpt_auth::ResolvedChatgptAuth,
    api_config: &selvedge_config_model::ChatgptApiConfig,
) -> Result<selvedge_client::HttpRequest, RequestValidationError> {
    request.validate()?;
    validate_non_blank("auth.access_token", &auth.access_token)?;
    validate_header_value("auth.access_token", &auth.access_token)?;
    if let Some(account_id) = &auth.account_id {
        validate_non_blank("auth.account_id", account_id)?;
        validate_header_value("auth.account_id", account_id)?;
    }

    let mut headers = HeaderMap::new();
    insert_header(
        &mut headers,
        "authorization",
        &format!("Bearer {}", auth.access_token),
    )?;
    if let Some(account_id) = &auth.account_id {
        insert_header(&mut headers, "chatgpt-account-id", account_id)?;
    }
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

fn event_is_completed(event: &ChatgptResponseEvent) -> bool {
    matches!(event, ChatgptResponseEvent::Completed(_))
}

// @constraint selvedge.model.chatgpt.api.http_request.header ChatGPT request header values must parse as valid HTTP header values.
fn insert_header(
    headers: &mut HeaderMap,
    name: &'static str,
    value: &str,
) -> Result<(), RequestValidationError> {
    let header_value = HeaderValue::from_str(value)
        // @constraint selvedge.model.chatgpt.api.http_request.header_error Invalid request header values become request validation errors.
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

    body.insert(
        "reasoning".to_owned(),
        if request.model_capabilities.supports_reasoning_summaries {
            Value::Object(build_reasoning_body(request))
        } else {
            Value::Null
        },
    );
    body.insert(
        "include".to_owned(),
        if request.model_capabilities.supports_reasoning_summaries {
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
        ResponseItem::Message(message) => {
            let mut value = JsonObject::from_iter([
                ("type".to_owned(), Value::String("message".to_owned())),
                ("role".to_owned(), Value::String(message.role.clone())),
                (
                    "content".to_owned(),
                    Value::Array(message.content.iter().map(content_item_to_json).collect()),
                ),
            ]);
            insert_optional_string(&mut value, "id", message.id.as_deref());
            insert_optional_string(&mut value, "status", message.status.as_deref());
            Value::Object(value)
        }
        ResponseItem::FunctionCall(call) => {
            let mut value = JsonObject::from_iter([
                ("type".to_owned(), Value::String("function_call".to_owned())),
                ("name".to_owned(), Value::String(call.name.clone())),
                (
                    "arguments".to_owned(),
                    Value::String(call.arguments.clone()),
                ),
                ("call_id".to_owned(), Value::String(call.call_id.clone())),
            ]);
            insert_optional_string(&mut value, "id", call.id.as_deref());
            insert_optional_string(&mut value, "status", call.status.as_deref());
            insert_optional_string(&mut value, "namespace", call.namespace.as_deref());
            Value::Object(value)
        }
        ResponseItem::FunctionCallOutput(output) => {
            let mut value = JsonObject::from_iter([
                (
                    "type".to_owned(),
                    Value::String("function_call_output".to_owned()),
                ),
                ("call_id".to_owned(), Value::String(output.call_id.clone())),
                ("output".to_owned(), tool_output_to_json(&output.output)),
            ]);
            insert_optional_string(&mut value, "id", output.id.as_deref());
            insert_optional_string(&mut value, "status", output.status.as_deref());
            Value::Object(value)
        }
        ResponseItem::CustomToolCallOutput(output) => {
            let mut value = JsonObject::from_iter([
                (
                    "type".to_owned(),
                    Value::String("custom_tool_call_output".to_owned()),
                ),
                ("call_id".to_owned(), Value::String(output.call_id.clone())),
                ("output".to_owned(), tool_output_to_json(&output.output)),
            ]);
            insert_optional_string(&mut value, "id", output.id.as_deref());
            insert_optional_string(&mut value, "status", output.status.as_deref());
            Value::Object(value)
        }
        ResponseItem::Reasoning(reasoning) => {
            let mut value =
                JsonObject::from_iter([("type".to_owned(), Value::String("reasoning".to_owned()))]);
            insert_optional_string(&mut value, "id", reasoning.id.as_deref());
            insert_optional_string(&mut value, "status", reasoning.status.as_deref());

            value.insert("summary".to_owned(), reasoning.summary.clone());

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

fn insert_optional_string(object: &mut JsonObject, key: &str, value: Option<&str>) {
    if let Some(value) = value {
        object.insert(key.to_owned(), Value::String(value.to_owned()));
    }
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

// @behavior selvedge.model.chatgpt.api.response_stream ChatGPT response streams expose the effective turn state and yield typed response events or terminal errors.
pub struct ChatgptResponseStream {
    effective_turn_state: Option<String>,
    receiver: mpsc::Receiver<Result<ChatgptResponseEvent, ChatgptApiError>>,
    terminal_error: Arc<Mutex<Option<ChatgptApiError>>>,
    driver_task: Option<JoinHandle<()>>,
}

impl ChatgptResponseStream {
    // @behavior selvedge.model.chatgpt.api.response_stream.turn_state Callers can read the effective turn state that should be replayed on the next ChatGPT request.
    pub fn effective_turn_state(&self) -> Option<&str> {
        self.effective_turn_state.as_deref()
    }

    // @behavior selvedge.model.chatgpt.api.response_stream.construct Constructed ChatGPT response streams retain effective turn state, receiver, terminal error storage, and driver task ownership.
    fn empty(
        effective_turn_state: Option<String>,
        receiver: mpsc::Receiver<Result<ChatgptResponseEvent, ChatgptApiError>>,
        terminal_error: Arc<Mutex<Option<ChatgptApiError>>>,
        driver_task: Option<JoinHandle<()>>,
    ) -> Self {
        Self {
            effective_turn_state,
            receiver,
            terminal_error,
            driver_task,
        }
    }
}

impl Drop for ChatgptResponseStream {
    fn drop(&mut self) {
        // @behavior selvedge.model.chatgpt.api.response_stream.drop Dropping a ChatGPT response stream aborts its background stream driver.
        if let Some(driver_task) = self.driver_task.take() {
            driver_task.abort();
        }
    }
}

impl Stream for ChatgptResponseStream {
    type Item = Result<ChatgptResponseEvent, ChatgptApiError>;

    fn poll_next(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let stream = self.get_mut();

        // @behavior selvedge.model.chatgpt.api.response_stream.poll Polling a ChatGPT response stream returns queued events first and then one recorded terminal error after the channel closes.
        match stream.receiver.poll_recv(cx) {
            Poll::Ready(Some(item)) => Poll::Ready(Some(item)),
            Poll::Ready(None) => Poll::Ready(stream.take_terminal_error().map(Err)),
            Poll::Pending => Poll::Pending,
        }
    }
}

impl ChatgptResponseStream {
    fn take_terminal_error(&self) -> Option<ChatgptApiError> {
        self.terminal_error.lock().ok()?.take()
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
// @behavior selvedge.model.chatgpt.api.request A ChatGPT responses request carries the upstream model, replay history, context headers, tools, reasoning options, text options, and service tier.
pub struct ChatgptResponsesRequest {
    // @behavior selvedge.model.chatgpt.api.request.model The request model field becomes the upstream `/responses` model.
    pub model: String,
    // @behavior selvedge.model.chatgpt.api.request.capabilities Model capabilities decide which optional reasoning and text controls may be sent upstream.
    pub model_capabilities: ChatgptModelCapabilities,
    // @behavior selvedge.model.chatgpt.api.request.context Request context supplies upstream correlation, replay, beta, subagent, and parent-thread headers.
    pub context: ChatgptRequestContext,
    // @behavior selvedge.model.chatgpt.api.request.instructions Nonempty instructions are sent as the upstream instructions field.
    pub instructions: Option<String>,
    // @behavior selvedge.model.chatgpt.api.request.input Request input is serialized as the upstream conversation and tool history.
    pub input: Vec<ResponseItem>,
    // @behavior selvedge.model.chatgpt.api.request.tools Request tools are sent as upstream tool descriptors with automatic tool choice.
    pub tools: Vec<ToolDescriptor>,
    // @behavior selvedge.model.chatgpt.api.request.parallel_tool_calls The parallel tool-call flag is forwarded to the upstream request body.
    pub parallel_tool_calls: bool,
    // @behavior selvedge.model.chatgpt.api.request.reasoning Reasoning options control upstream effort and summary fields when model capabilities allow them.
    pub reasoning: ChatgptReasoningOptions,
    // @behavior selvedge.model.chatgpt.api.request.text Text options control upstream verbosity and strict JSON-schema response formatting.
    pub text: ChatgptTextOptions,
    // @behavior selvedge.model.chatgpt.api.request.service_tier Optional service tier selects the upstream latency or default tier.
    pub service_tier: Option<ChatgptServiceTier>,
}

impl ChatgptResponsesRequest {
    // @constraint selvedge.model.chatgpt.api.request.validation Requests must have nonblank header-safe identity fields, capability-supported options, and valid tool descriptor JSON before streaming.
    pub fn validate(&self) -> Result<(), RequestValidationError> {
        validate_non_blank("model", &self.model)?;
        validate_non_blank("context.conversation_id", &self.context.conversation_id)?;
        validate_non_blank("context.installation_id", &self.context.installation_id)?;

        if self.context.conversation_id.contains(':') {
            // @constraint selvedge.model.chatgpt.api.request.conversation_id Conversation IDs exclude colons so generated window IDs keep an unambiguous delimiter.
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
                // @constraint selvedge.model.chatgpt.api.request.beta_features Beta feature values exclude commas because the upstream header serializes them as a comma-separated list.
                return Err(RequestValidationError::new(
                    "context.beta_features",
                    "must not contain ','",
                ));
            }
        }

        if self.reasoning.summary.is_some() && !self.model_capabilities.supports_reasoning_summaries
        {
            // @constraint selvedge.model.chatgpt.api.request.reasoning_support Reasoning summaries require a model capability that supports summary fields.
            return Err(RequestValidationError::new(
                "reasoning.summary",
                "is not supported by this model",
            ));
        }

        if self.text.verbosity.is_some() && !self.model_capabilities.supports_text_verbosity {
            // @constraint selvedge.model.chatgpt.api.request.verbosity_support Text verbosity requires a model capability that supports verbosity fields.
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
        // @constraint selvedge.model.chatgpt.api.request.nonblank Required request string fields must contain non-whitespace text before streaming.
        return Err(RequestValidationError::new(field, "must not be blank"));
    }

    Ok(())
}

fn validate_header_value(field: &'static str, value: &str) -> Result<(), RequestValidationError> {
    HeaderValue::from_str(value)
        // @constraint selvedge.model.chatgpt.api.request.header_value Request values that become headers must parse as valid HTTP header values.
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

// @constraint selvedge.model.chatgpt.api.request.tool_json ChatGPT tool descriptors must serialize as JSON objects.
fn validate_json_objects(
    field: &'static str,
    tools: &[ToolDescriptor],
) -> Result<(), RequestValidationError> {
    if tools
        .iter()
        .any(|descriptor| serde_json::to_value(&descriptor.0).ok().is_none())
    {
        // @constraint selvedge.model.chatgpt.api.request.tool_json_error Invalid tool descriptor JSON returns a request validation error before streaming.
        return Err(RequestValidationError::new(
            field,
            "must be valid JSON objects",
        ));
    }

    Ok(())
}

#[derive(Clone, Debug, Eq, PartialEq)]
// @constraint selvedge.model.chatgpt.api.capabilities Model capabilities define which optional request controls can reach upstream ChatGPT.
pub struct ChatgptModelCapabilities {
    // @constraint selvedge.model.chatgpt.api.capabilities.reasoning_summaries Reasoning summaries are sent only for models marked as supporting reasoning summaries.
    pub supports_reasoning_summaries: bool,
    // @constraint selvedge.model.chatgpt.api.capabilities.text_verbosity Text verbosity is sent only for models marked as supporting text verbosity.
    pub supports_text_verbosity: bool,
    // @behavior selvedge.model.chatgpt.api.capabilities.default_reasoning_effort Default reasoning effort fills the upstream effort field when the request omits an explicit effort.
    pub default_reasoning_effort: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
// @behavior selvedge.model.chatgpt.api.context Request context carries upstream correlation and replay headers for one ChatGPT turn.
pub struct ChatgptRequestContext {
    // @behavior selvedge.model.chatgpt.api.context.conversation_id Conversation ID becomes session, client request, window, and prompt-cache identity in the upstream request.
    pub conversation_id: String,
    // @behavior selvedge.model.chatgpt.api.context.window_generation Window generation is combined with conversation ID for the upstream Codex window ID.
    pub window_generation: u64,
    // @behavior selvedge.model.chatgpt.api.context.installation_id Installation ID is sent as upstream client metadata.
    pub installation_id: String,
    // @behavior selvedge.model.chatgpt.api.context.turn_state Turn state is sent as a replay header and can be superseded by the response turn-state header.
    pub turn_state: Option<String>,
    // @behavior selvedge.model.chatgpt.api.context.turn_metadata Turn metadata is sent as an optional upstream replay header.
    pub turn_metadata: Option<String>,
    // @behavior selvedge.model.chatgpt.api.context.beta_features Beta features are sent as a comma-separated upstream header.
    pub beta_features: Vec<String>,
    // @behavior selvedge.model.chatgpt.api.context.subagent Subagent identity is sent as an optional upstream subagent header.
    pub subagent: Option<String>,
    // @behavior selvedge.model.chatgpt.api.context.parent_thread_id Parent thread ID is sent as an optional upstream parent-thread header.
    pub parent_thread_id: Option<String>,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
// @behavior selvedge.model.chatgpt.api.reasoning Reasoning options control upstream reasoning effort and summary generation.
pub struct ChatgptReasoningOptions {
    // @behavior selvedge.model.chatgpt.api.reasoning.effort Explicit reasoning effort takes precedence over the model default in the upstream request body.
    pub effort: Option<String>,
    // @behavior selvedge.model.chatgpt.api.reasoning.summary Reasoning summary requests add the upstream summary field and encrypted-content include when supported.
    pub summary: Option<String>,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
// @behavior selvedge.model.chatgpt.api.text Text options control upstream text verbosity and structured output formatting.
pub struct ChatgptTextOptions {
    // @behavior selvedge.model.chatgpt.api.text.verbosity Text verbosity maps to the upstream verbosity field when supported.
    pub verbosity: Option<TextVerbosity>,
    // @behavior selvedge.model.chatgpt.api.text.json_schema JSON schema options request strict upstream `codex_output_schema` formatted output.
    pub json_schema: Option<JsonObject>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
// @behavior selvedge.model.chatgpt.api.text.verbosity_values Text verbosity values map to upstream low, medium, and high strings.
pub enum TextVerbosity {
    Low,
    Medium,
    High,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
// @behavior selvedge.model.chatgpt.api.service_tier Service tiers map caller choices to upstream default, flex, and priority service tiers.
pub enum ChatgptServiceTier {
    Default,
    Flex,
    Fast,
}

#[derive(Clone, Debug, Eq, PartialEq)]
// @behavior selvedge.model.chatgpt.api.tool_descriptor Tool descriptors pass caller-provided JSON objects through to the upstream tools array.
pub struct ToolDescriptor(pub JsonObject);

#[derive(Clone, Debug, PartialEq)]
#[non_exhaustive]
// @behavior selvedge.model.chatgpt.api.event Response events expose created snapshots, output items, text deltas, reasoning deltas, completion snapshots, and unknown response events.
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
// @behavior selvedge.model.chatgpt.api.snapshot Response snapshots expose upstream response identity, model, usage, service tier, and raw response payload.
pub struct ChatgptResponseSnapshot {
    // @behavior selvedge.model.chatgpt.api.snapshot.id Snapshot ID carries the upstream response ID when present.
    pub id: Option<String>,
    // @behavior selvedge.model.chatgpt.api.snapshot.model Snapshot model carries the upstream model name when present.
    pub model: Option<String>,
    // @behavior selvedge.model.chatgpt.api.snapshot.usage Snapshot usage carries upstream token accounting when present and well-formed.
    pub usage: Option<ChatgptUsage>,
    // @behavior selvedge.model.chatgpt.api.snapshot.service_tier Snapshot service tier carries the upstream service tier when present.
    pub service_tier: Option<String>,
    // @behavior selvedge.model.chatgpt.api.snapshot.raw Snapshot raw payload preserves the upstream response object for callers.
    pub raw: JsonObject,
}

#[derive(Clone, Debug, Eq, PartialEq)]
// @behavior selvedge.model.chatgpt.api.raw_event Unknown response events preserve their upstream event type and payload.
pub struct ChatgptRawEvent {
    // @behavior selvedge.model.chatgpt.api.raw_event.event_type Raw events expose the upstream event type string.
    pub event_type: String,
    // @behavior selvedge.model.chatgpt.api.raw_event.payload Raw events expose the upstream event JSON object.
    pub payload: JsonObject,
}

#[derive(Clone, Debug, Eq, PartialEq)]
// @behavior selvedge.model.chatgpt.api.usage Usage exposes upstream input, cached input, output, reasoning output, and total token counts when present.
pub struct ChatgptUsage {
    // @behavior selvedge.model.chatgpt.api.usage.input Input token count carries upstream input token accounting when present.
    pub input_tokens: Option<u64>,
    // @behavior selvedge.model.chatgpt.api.usage.cached_input Cached input token count reads either upstream input token detail spelling.
    pub cached_input_tokens: Option<u64>,
    // @behavior selvedge.model.chatgpt.api.usage.output Output token count carries upstream output token accounting when present.
    pub output_tokens: Option<u64>,
    // @behavior selvedge.model.chatgpt.api.usage.reasoning_output Reasoning output token count reads either upstream output token detail spelling.
    pub reasoning_output_tokens: Option<u64>,
    // @behavior selvedge.model.chatgpt.api.usage.total Total token count carries upstream total token accounting when present.
    pub total_tokens: Option<u64>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
#[non_exhaustive]
// @behavior selvedge.model.chatgpt.api.item Response items represent messages, tool calls, tool outputs, reasoning blocks, and opaque upstream items.
pub enum ResponseItem {
    Message(MessageItem),
    FunctionCall(FunctionCallItem),
    FunctionCallOutput(FunctionCallOutputItem),
    CustomToolCallOutput(CustomToolCallOutputItem),
    Reasoning(ReasoningItem),
    Opaque(OpaqueResponseItem),
}

#[derive(Clone, Debug, Eq, PartialEq)]
// @behavior selvedge.model.chatgpt.api.item.message Message items carry role-tagged content between Selvedge and ChatGPT.
pub struct MessageItem {
    // @behavior selvedge.model.chatgpt.api.item.message.id Message item ID carries the upstream item ID when present.
    pub id: Option<String>,
    // @behavior selvedge.model.chatgpt.api.item.message.status Message item status carries the upstream item status when present.
    pub status: Option<String>,
    // @behavior selvedge.model.chatgpt.api.item.message.role Message item role carries the upstream message role.
    pub role: String,
    // @behavior selvedge.model.chatgpt.api.item.message.content Message item content carries text, images, output text, and opaque content blocks.
    pub content: Vec<ContentItem>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
// @behavior selvedge.model.chatgpt.api.item.function_call Function-call items carry upstream tool-call requests with name, arguments, and call ID.
pub struct FunctionCallItem {
    // @behavior selvedge.model.chatgpt.api.item.function_call.id Function-call item ID carries the upstream item ID when present.
    pub id: Option<String>,
    // @behavior selvedge.model.chatgpt.api.item.function_call.status Function-call status carries the upstream item status when present.
    pub status: Option<String>,
    // @behavior selvedge.model.chatgpt.api.item.function_call.name Function-call name carries the upstream tool name.
    pub name: String,
    // @behavior selvedge.model.chatgpt.api.item.function_call.namespace Function-call namespace carries upstream namespace data when present.
    pub namespace: Option<String>,
    // @behavior selvedge.model.chatgpt.api.item.function_call.arguments Function-call arguments carry the upstream JSON argument string.
    pub arguments: String,
    // @behavior selvedge.model.chatgpt.api.item.function_call.call_id Function-call call ID correlates tool-call requests with tool outputs.
    pub call_id: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
// @behavior selvedge.model.chatgpt.api.item.function_call_output Function-call output items carry a function tool result for a prior call ID.
pub struct FunctionCallOutputItem {
    // @behavior selvedge.model.chatgpt.api.item.function_call_output.id Function-call output ID carries the upstream item ID when present.
    pub id: Option<String>,
    // @behavior selvedge.model.chatgpt.api.item.function_call_output.status Function-call output status carries the upstream item status when present.
    pub status: Option<String>,
    // @behavior selvedge.model.chatgpt.api.item.function_call_output.call_id Function-call output call ID targets the matching function call.
    pub call_id: String,
    // @behavior selvedge.model.chatgpt.api.item.function_call_output.output Function-call output carries text or structured content returned by the tool.
    pub output: ToolOutput,
}

#[derive(Clone, Debug, Eq, PartialEq)]
// @behavior selvedge.model.chatgpt.api.item.custom_tool_call_output Custom tool-call output items carry a custom tool result for a prior call ID.
pub struct CustomToolCallOutputItem {
    // @behavior selvedge.model.chatgpt.api.item.custom_tool_call_output.id Custom tool-call output ID carries the upstream item ID when present.
    pub id: Option<String>,
    // @behavior selvedge.model.chatgpt.api.item.custom_tool_call_output.status Custom tool-call output status carries the upstream item status when present.
    pub status: Option<String>,
    // @behavior selvedge.model.chatgpt.api.item.custom_tool_call_output.call_id Custom tool-call output call ID targets the matching custom tool call.
    pub call_id: String,
    // @behavior selvedge.model.chatgpt.api.item.custom_tool_call_output.output Custom tool-call output carries text or structured content returned by the tool.
    pub output: ToolOutput,
}

#[derive(Clone, Debug, Eq, PartialEq)]
// @behavior selvedge.model.chatgpt.api.item.reasoning Reasoning items carry upstream reasoning summaries, optional content, and encrypted replay content.
pub struct ReasoningItem {
    // @behavior selvedge.model.chatgpt.api.item.reasoning.id Reasoning item ID carries the upstream item ID when present.
    pub id: Option<String>,
    // @behavior selvedge.model.chatgpt.api.item.reasoning.status Reasoning item status carries the upstream item status when present.
    pub status: Option<String>,
    // @behavior selvedge.model.chatgpt.api.item.reasoning.summary Reasoning item summary preserves the upstream summary JSON value.
    pub summary: Value,
    // @behavior selvedge.model.chatgpt.api.item.reasoning.content Reasoning item content carries optional upstream content blocks.
    pub content: Option<Vec<ContentItem>>,
    // @behavior selvedge.model.chatgpt.api.item.reasoning.encrypted_content Reasoning item encrypted content carries replay state when the upstream response includes it.
    pub encrypted_content: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
// @behavior selvedge.model.chatgpt.api.item.opaque Opaque response items preserve upstream item objects with unsupported item types.
pub struct OpaqueResponseItem {
    // @behavior selvedge.model.chatgpt.api.item.opaque.raw Opaque response items expose the raw upstream item object.
    pub raw: JsonObject,
}

#[derive(Clone, Debug, Eq, PartialEq)]
#[non_exhaustive]
// @behavior selvedge.model.chatgpt.api.content Content items represent input text, input images, output text, and opaque content blocks.
pub enum ContentItem {
    InputText { text: String },
    InputImage { image_url: String },
    OutputText { text: String, raw: JsonObject },
    Other { raw: JsonObject },
}

#[derive(Clone, Debug, Eq, PartialEq)]
// @behavior selvedge.model.chatgpt.api.tool_output Tool outputs carry either plain text or structured content blocks for upstream tool-result items.
pub enum ToolOutput {
    Text(String),
    Content(Vec<ContentItem>),
}

#[derive(Clone, Debug, Eq, PartialEq)]
// @behavior selvedge.model.chatgpt.api.request.validation_error Request validation errors expose the invalid field name and caller-visible reason.
pub struct RequestValidationError {
    // @behavior selvedge.model.chatgpt.api.request.validation_error.field Request validation error field identifies the rejected request field.
    pub field: &'static str,
    // @behavior selvedge.model.chatgpt.api.request.validation_error.reason Request validation error reason describes the rejected field constraint.
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
// @behavior selvedge.model.chatgpt.api.error ChatGPT API errors separate lower-layer startup and transport failures from endpoint stream failures.
pub enum ChatgptApiError {
    #[error(transparent)]
    LowerLayer(#[from] ChatgptApiLowerLayerError),
    #[error(transparent)]
    Endpoint(#[from] ChatgptApiEndpointError),
}

#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
// @behavior selvedge.model.chatgpt.api.error.lower Lower-layer errors expose invalid input, config, auth, client, and stream completion timeout failures.
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
// @behavior selvedge.model.chatgpt.api.error.endpoint Endpoint errors expose failed, incomplete, malformed, prematurely closed, and unexpected ChatGPT response streams.
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
// @behavior selvedge.model.chatgpt.api.error.failed_kind Failed endpoint kinds classify known upstream response failure codes.
pub enum ChatgptFailedEndpointKind {
    ContextLengthExceeded,
    InsufficientQuota,
    UsageNotIncluded,
    InvalidPrompt,
    ServerOverloaded,
}

#[derive(Clone, Debug, Eq, PartialEq)]
// @behavior selvedge.model.chatgpt.api.error.failed Failed endpoint errors expose the known failure kind, provider diagnostics, and raw response payload.
pub struct ChatgptFailedEndpointError {
    // @behavior selvedge.model.chatgpt.api.error.failed.kind Failed endpoint errors expose the classified provider failure kind.
    pub kind: ChatgptFailedEndpointKind,
    // @behavior selvedge.model.chatgpt.api.error.failed.response_id Failed endpoint errors expose the upstream response ID when present.
    pub response_id: Option<String>,
    // @behavior selvedge.model.chatgpt.api.error.failed.code Failed endpoint errors expose the provider failure code when present.
    pub code: Option<String>,
    // @behavior selvedge.model.chatgpt.api.error.failed.message Failed endpoint errors expose the provider failure message when present.
    pub message: Option<String>,
    // @behavior selvedge.model.chatgpt.api.error.failed.raw Failed endpoint errors preserve the raw upstream response object.
    pub raw: JsonObject,
}

#[derive(Clone, Debug, Eq, PartialEq)]
// @behavior selvedge.model.chatgpt.api.error.incomplete Incomplete endpoint errors expose response ID, incomplete reason, and raw response payload.
pub struct ChatgptIncompleteEndpointError {
    // @behavior selvedge.model.chatgpt.api.error.incomplete.response_id Incomplete endpoint errors expose the upstream response ID when present.
    pub response_id: Option<String>,
    // @behavior selvedge.model.chatgpt.api.error.incomplete.reason Incomplete endpoint errors expose the upstream incomplete reason when present.
    pub reason: Option<String>,
    // @behavior selvedge.model.chatgpt.api.error.incomplete.raw Incomplete endpoint errors preserve the raw upstream response object.
    pub raw: JsonObject,
}

#[derive(Clone, Debug, Eq, PartialEq)]
// @behavior selvedge.model.chatgpt.api.error.other Unexpected endpoint errors expose event type, diagnostics, retry hint, and raw payload.
pub struct ChatgptOtherEndpointError {
    // @behavior selvedge.model.chatgpt.api.error.other.event_type Unexpected endpoint errors expose the upstream event type when present.
    pub event_type: Option<String>,
    // @behavior selvedge.model.chatgpt.api.error.other.code Unexpected endpoint errors expose the provider code when present.
    pub code: Option<String>,
    // @behavior selvedge.model.chatgpt.api.error.other.message Unexpected endpoint errors expose the provider message when present.
    pub message: Option<String>,
    // @behavior selvedge.model.chatgpt.api.error.other.retry_after Unexpected endpoint errors expose retry hints parsed from provider messages.
    pub retry_after: Option<Duration>,
    // @behavior selvedge.model.chatgpt.api.error.other.raw Unexpected endpoint errors preserve the raw upstream event or response object.
    pub raw: JsonObject,
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use chatgpt_auth::ResolvedChatgptAuth;
    use http::{HeaderMap, HeaderValue, StatusCode};
    use selvedge_client::{HttpMethod, HttpRequestBody, RequestCompression};
    use selvedge_config_model::ChatgptApiConfig;

    use super::{
        ChatgptApiEndpointError, ChatgptApiError, ChatgptModelCapabilities,
        ChatgptOtherEndpointError, ChatgptReasoningOptions, ChatgptRequestContext,
        ChatgptResponseEvent, ChatgptResponsesRequest, ChatgptServiceTier, ChatgptTextOptions,
        ContentItem, JsonObject, MessageItem, ReasoningItem, ResponseItem, TextVerbosity,
        ToolDescriptor, build_http_request, chatgpt_usage_from_value, content_item_from_value,
        failed_endpoint_event, is_retryable_client_error, map_stream_event,
        response_item_from_object, retry_delay_for_attempt, take_next_sse_frame,
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
            account_id: Some("account-123".to_owned()),
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

        // @verifies selvedge.model.chatgpt.event.verify_surface
        let http_request = build_http_request(&request, &auth, &api_config).expect("http request");

        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(http_request.method, HttpMethod::Post);
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(
            http_request.url,
            "https://chatgpt.com/backend-api/codex/responses"
        );
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(http_request.compression, RequestCompression::None);
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(http_request.timeout, None);
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(
            http_request
                .headers
                .get("authorization")
                .and_then(|value: &HeaderValue| value.to_str().ok()),
            Some("Bearer access-token")
        );
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(
            http_request
                .headers
                .get("chatgpt-account-id")
                .and_then(|value: &HeaderValue| value.to_str().ok()),
            Some("account-123")
        );
        // @verifies selvedge.model.chatgpt.event.verify_surface
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

        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(body.get("model"), Some(&serde_json::json!("gpt-5")));
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(body.get("tool_choice"), Some(&serde_json::json!("auto")));
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(
            body.get("parallel_tool_calls"),
            Some(&serde_json::json!(true))
        );
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(body.get("store"), Some(&serde_json::json!(false)));
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(body.get("stream"), Some(&serde_json::json!(true)));
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(
            body.get("prompt_cache_key"),
            Some(&serde_json::json!("conversation-123"))
        );
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(
            body.get("include"),
            Some(&serde_json::json!(["reasoning.encrypted_content"]))
        );
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(
            body.get("service_tier"),
            Some(&serde_json::json!("priority"))
        );
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(
            body.pointer("/client_metadata/x-codex-installation-id"),
            Some(&serde_json::json!("install-123"))
        );
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(
            body.pointer("/reasoning/effort"),
            Some(&serde_json::json!("high"))
        );
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(
            body.pointer("/reasoning/summary"),
            Some(&serde_json::json!("detailed"))
        );
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(
            body.pointer("/text/verbosity"),
            Some(&serde_json::json!("high"))
        );
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(
            body.pointer("/text/format/type"),
            Some(&serde_json::json!("json_schema"))
        );
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(
            body.pointer("/text/format/strict"),
            Some(&serde_json::json!(true))
        );
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(
            body.pointer("/text/format/name"),
            Some(&serde_json::json!("codex_output_schema"))
        );
    }

    #[test]
    fn build_http_request_omits_chatgpt_account_header_when_account_id_is_missing() {
        let request = base_request();
        let mut auth = base_auth();
        auth.account_id = None;
        let api_config = base_api_config();

        // @verifies selvedge.model.chatgpt.api.http_request
        let http_request = build_http_request(&request, &auth, &api_config).expect("http request");

        // @verifies selvedge.model.chatgpt.api.http_request
        assert!(!http_request.headers.contains_key("chatgpt-account-id"));
        // @verifies selvedge.model.chatgpt.api.http_request
        assert_eq!(
            http_request
                .headers
                .get("authorization")
                .and_then(|value: &HeaderValue| value.to_str().ok()),
            Some("Bearer access-token")
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
            // @verifies selvedge.model.chatgpt.event.verify_surface
            build_http_request(&request, &base_auth(), &base_api_config()).expect("http request");

        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert!(http_request.headers.get("x-codex-turn-state").is_none());
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert!(http_request.headers.get("x-codex-turn-metadata").is_none());
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert!(http_request.headers.get("x-codex-beta-features").is_none());

        let HttpRequestBody::Json(body) = http_request.body else {
            panic!("expected json body");
        };

        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(body.get("reasoning"), Some(&serde_json::Value::Null));
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(body.get("include"), Some(&serde_json::json!([])));
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert!(body.get("instructions").is_none());
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert!(body.get("service_tier").is_none());
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert!(body.get("text").is_none());
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(body.get("tools"), Some(&serde_json::json!([])));
    }

    #[test]
    fn build_http_request_omits_missing_optional_request_item_fields() {
        let mut request = base_request();
        request.input = vec![ResponseItem::Message(MessageItem {
            id: None,
            status: None,
            role: "user".to_owned(),
            content: vec![ContentItem::InputText {
                text: "hello".to_owned(),
            }],
        })];

        let http_request =
            // @verifies selvedge.model.chatgpt.event.verify_surface
            build_http_request(&request, &base_auth(), &base_api_config()).expect("http request");
        let selvedge_client::HttpRequestBody::Json(body) = http_request.body else {
            panic!("expected json body");
        };
        let input_item = body
            .get("input")
            .and_then(serde_json::Value::as_array)
            .and_then(|items| items.first())
            .and_then(serde_json::Value::as_object)
            // @verifies selvedge.model.chatgpt.event.verify_surface
            .expect("first input item");

        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert!(!input_item.contains_key("id"));
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert!(!input_item.contains_key("status"));
    }

    #[test]
    fn retry_delay_honors_http_date_retry_after_values() {
        let mut headers = HeaderMap::new();
        headers.insert(
            "retry-after",
            HeaderValue::from_static("Wed, 21 Oct 2099 07:28:00 GMT"),
        );
        let error = selvedge_client::HttpError::Status(selvedge_client::HttpStatusError {
            url: "https://chatgpt.com/backend-api/codex/responses".to_owned(),
            status: StatusCode::TOO_MANY_REQUESTS,
            headers,
            body: bytes::Bytes::new(),
        });

        let delay = retry_delay_for_attempt(0, &error);

        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert!(delay > Duration::from_secs(30) || delay == Duration::from_secs(30));
    }

    #[test]
    fn request_timeouts_are_not_retryable() {
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert!(!is_retryable_client_error(
            &selvedge_client::HttpError::Timeout
        ));
    }

    #[test]
    fn build_http_request_uses_null_reasoning_and_empty_include_without_summary_support() {
        let mut request = base_request();
        request.reasoning.summary = None;
        request.model_capabilities.supports_reasoning_summaries = false;
        request.model_capabilities.default_reasoning_effort = Some("high".to_owned());

        let http_request =
            // @verifies selvedge.model.chatgpt.event.verify_surface
            build_http_request(&request, &base_auth(), &base_api_config()).expect("http request");
        let selvedge_client::HttpRequestBody::Json(body) = http_request.body else {
            panic!("expected json body");
        };

        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(body.get("reasoning"), Some(&serde_json::Value::Null));
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(body.get("include"), Some(&serde_json::json!([])));
    }

    #[test]
    fn build_http_request_does_not_change_reasoning_contract_for_replay() {
        let mut request = base_request();
        request.reasoning = ChatgptReasoningOptions::default();
        request.model_capabilities.default_reasoning_effort = None;
        request.model_capabilities.supports_reasoning_summaries = false;
        request.input.push(ResponseItem::Reasoning(ReasoningItem {
            id: Some("reasoning-1".to_owned()),
            status: Some("completed".to_owned()),
            summary: serde_json::json!([{ "type": "summary_text", "text": "thinking" }]),
            content: None,
            encrypted_content: Some("encrypted".to_owned()),
        }));

        let http_request =
            // @verifies selvedge.model.chatgpt.event.verify_surface
            build_http_request(&request, &base_auth(), &base_api_config()).expect("http request");
        let selvedge_client::HttpRequestBody::Json(body) = http_request.body else {
            panic!("expected json body");
        };

        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(body.get("reasoning"), Some(&serde_json::Value::Null));
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(body.get("include"), Some(&serde_json::json!([])));
    }

    #[test]
    fn chatgpt_usage_reads_nested_cache_and_reasoning_counts() {
        let usage = chatgpt_usage_from_value(&serde_json::json!({
            "input_tokens": 10,
            "input_token_details": {
                "cached_tokens": 4
            },
            "output_tokens": 7,
            "output_token_details": {
                "reasoning_tokens": 3
            },
            "total_tokens": 17
        }))
        // @verifies selvedge.model.chatgpt.event.verify_surface
        .expect("usage");

        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(usage.input_tokens, Some(10));
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(usage.cached_input_tokens, Some(4));
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(usage.output_tokens, Some(7));
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(usage.reasoning_output_tokens, Some(3));
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(usage.total_tokens, Some(17));
    }

    #[test]
    fn chatgpt_usage_rejects_malformed_nested_detail_objects() {
        let error = chatgpt_usage_from_value(&serde_json::json!({
            "input_tokens": 10,
            "input_tokens_details": "not-an-object"
        }))
        .expect_err("malformed nested usage object must fail");

        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert!(matches!(
            error,
            ChatgptApiError::Endpoint(ChatgptApiEndpointError::MalformedEvent { .. })
        ));
    }

    #[test]
    fn response_item_parser_routes_custom_tool_calls_to_opaque() {
        let item = response_item_from_object(&JsonObject::from_iter([
            ("type".to_owned(), serde_json::json!("custom_tool_call")),
            ("id".to_owned(), serde_json::json!("custom-1")),
            ("status".to_owned(), serde_json::json!("in_progress")),
            ("call_id".to_owned(), serde_json::json!("call-1")),
            ("name".to_owned(), serde_json::json!("apply_patch")),
            ("input".to_owned(), serde_json::json!("*** Begin Patch")),
        ]))
        // @verifies selvedge.model.chatgpt.event.verify_surface
        .expect("custom tool call");

        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert!(matches!(item, ResponseItem::Opaque(_)));
    }

    #[test]
    fn response_item_parser_ignores_non_contract_message_fields() {
        let item = response_item_from_object(&JsonObject::from_iter([
            ("type".to_owned(), serde_json::json!("message")),
            ("role".to_owned(), serde_json::json!("assistant")),
            ("phase".to_owned(), serde_json::json!("final_answer")),
            ("content".to_owned(), serde_json::json!([])),
        ]))
        // @verifies selvedge.model.chatgpt.event.verify_surface
        .expect("message item");

        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert!(matches!(
            item,
            ResponseItem::Message(MessageItem {
                role,
                ..
            }) if role == "assistant"
        ));
    }

    #[test]
    fn content_item_parser_rejects_input_images_without_image_url() {
        let error = content_item_from_value(&serde_json::json!({
            "type": "input_image",
            "file_id": "file-123",
            "detail": "high"
        }))
        .expect_err("input images without image_url must fail");

        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert!(matches!(
            error,
            ChatgptApiError::Endpoint(ChatgptApiEndpointError::MalformedEvent { .. })
        ));
    }

    #[test]
    fn response_item_parser_rejects_reasoning_items_without_summary() {
        let item = response_item_from_object(&JsonObject::from_iter([
            ("type".to_owned(), serde_json::json!("reasoning")),
            ("id".to_owned(), serde_json::json!("reasoning-1")),
            ("encrypted_content".to_owned(), serde_json::json!("cipher")),
        ]))
        .expect_err("reasoning item without summary must fail");

        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert!(matches!(
            item,
            ChatgptApiError::Endpoint(ChatgptApiEndpointError::MalformedEvent { .. })
        ));
    }

    #[test]
    fn failed_endpoint_event_keeps_top_level_error_payload_as_raw() {
        let payload = JsonObject::from_iter([
            ("type".to_owned(), serde_json::json!("error")),
            ("code".to_owned(), serde_json::json!("server_busy")),
            (
                "message".to_owned(),
                serde_json::json!("try again in 3 seconds"),
            ),
        ]);

        let error = failed_endpoint_event(&payload, "error");

        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert!(matches!(
            error,
            ChatgptApiError::Endpoint(ChatgptApiEndpointError::Other(ChatgptOtherEndpointError { raw, .. }))
                if raw.get("code") == Some(&serde_json::json!("server_busy"))
        ));
    }

    #[test]
    fn response_done_maps_to_other_nonterminal_event() {
        let event = map_stream_event(
            r#"{"type":"response.done","response":{"id":"resp-1","model":"gpt-5"}}"#,
        )
        // @verifies selvedge.model.chatgpt.event.verify_surface
        .expect("mapped event");

        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert!(matches!(
            event,
            super::MappedEvent::Event(ChatgptResponseEvent::Other(raw))
                if raw.event_type == "response.done"
        ));
    }

    #[test]
    fn unknown_non_response_event_maps_to_endpoint_other_error() {
        let event = map_stream_event(
            r#"{"type":"server.notice","code":"server_busy","message":"retry later"}"#,
        )
        // @verifies selvedge.model.chatgpt.event.verify_surface
        .expect("mapped event");

        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert!(matches!(
            event,
            super::MappedEvent::EndpointError(ChatgptApiError::Endpoint(
                ChatgptApiEndpointError::Other(ChatgptOtherEndpointError { event_type, .. })
            )) if event_type.as_deref() == Some("server.notice")
        ));
    }

    #[test]
    fn take_next_sse_frame_keeps_buffer_allocation_for_remainder() {
        let mut buffer = b"data: first\n\ndata: second\n\n".to_vec();
        buffer.reserve(1024);
        let original_capacity = buffer.capacity();

        // @verifies selvedge.model.chatgpt.event.verify_surface
        let frame = take_next_sse_frame(&mut buffer).expect("first frame");

        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(frame, b"data: first".to_vec());
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(buffer, b"data: second\n\n".to_vec());
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(buffer.capacity(), original_capacity);
    }

    #[test]
    fn take_next_sse_frame_accepts_cr_only_delimiters() {
        let mut buffer = b"data: first\r\rdata: second\r\r".to_vec();

        // @verifies selvedge.model.chatgpt.event.verify_surface
        let frame = take_next_sse_frame(&mut buffer).expect("first frame");

        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(frame, b"data: first".to_vec());
        // @verifies selvedge.model.chatgpt.event.verify_surface
        assert_eq!(buffer, b"data: second\r\r".to_vec());
    }
}
