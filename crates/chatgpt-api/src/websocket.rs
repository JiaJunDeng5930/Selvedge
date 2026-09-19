//! Caller-owned Responses WebSocket connections and mid-turn steering.

use std::sync::{Arc, Mutex};
use std::time::Duration;

use http::StatusCode;
use serde_json::{Value, json};
use tokio::sync::{Notify, mpsc};
use tokio::task::JoinHandle;
use tokio::time::Instant;

use super::{
    ChatgptApiEndpointError, ChatgptApiError, ChatgptApiLowerLayerError, ChatgptFailedEndpointKind,
    ChatgptIncompleteEndpointError, ChatgptRequestContext, ChatgptResponseEvent,
    ChatgptResponsesRequest, JsonObject, MappedEvent, RequestValidationError, build_http_request,
    build_request_body, chatgpt_api_config_from_app_config, failed_endpoint_event,
    incomplete_endpoint_error, map_stream_event, misalignment_policy_error_from_http_response,
    validate_chatgpt_api_config, validate_non_blank,
};

const MAX_EVENT_BYTES: usize = 1024 * 1024;
const MAX_RESPONSE_BYTES: usize = 4 * 1024 * 1024;
const EVENT_QUEUE_CAPACITY: usize = 32;

#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum ChatgptWebSocketError {
    #[error(transparent)]
    Api(#[from] ChatgptApiError),
    #[error("WebSocket session is closed")]
    Closed,
    #[error("a response is already in progress on this WebSocket session")]
    ResponseInProgress,
}

/// Steering input validated once; serialization cannot introduce non-user messages.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChatgptSteerInput(Value);

impl ChatgptSteerInput {
    pub fn text(text: impl Into<String>) -> Self {
        Self(Value::String(text.into()))
    }

    pub fn from_value(value: Value) -> Result<Self, RequestValidationError> {
        validate_steer_input(&value)?;
        Ok(Self(value))
    }

    pub fn as_value(&self) -> &Value {
        &self.0
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChatgptSteerRequest {
    pub previous_response_id: String,
    pub input: ChatgptSteerInput,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChatgptSteerIdentity {
    pub id: String,
    pub previous_response_id: String,
}

/// Accepted steering is queued, not necessarily applied to a response yet.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChatgptSteerAccepted {
    pub steer: ChatgptSteerIdentity,
    pub sequence_number: Option<u64>,
    pub raw: JsonObject,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChatgptSteerPending {
    pub steer: ChatgptSteerIdentity,
    pub sequence_number: Option<u64>,
    pub reason: String,
    pub required_input: Vec<Value>,
    pub raw: JsonObject,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChatgptSteerFailed {
    pub steer: ChatgptSteerIdentity,
    pub sequence_number: Option<u64>,
    pub input: Value,
    pub error: JsonObject,
    pub raw: JsonObject,
}

#[derive(Debug)]
#[non_exhaustive]
pub enum ChatgptWebSocketEvent {
    Response(ChatgptResponseEvent),
    SteerAccepted(ChatgptSteerAccepted),
    SteerPending(ChatgptSteerPending),
    SteerFailed(ChatgptSteerFailed),
    /// The response ended to let the server create the steering continuation.
    Steered(ChatgptIncompleteEndpointError),
    /// An individual response or command failed; the connection remains available.
    ResponseError(ChatgptApiError),
}

pub struct ChatgptWebSocketSession {
    sender: ChatgptWebSocketSender,
    events: ChatgptWebSocketEvents,
    effective_turn_state: Option<String>,
}

impl ChatgptWebSocketSession {
    /// This header belongs to future connections/HTTP requests. The current
    /// connection continues to require its original handshake context.
    pub fn effective_turn_state(&self) -> Option<&str> {
        self.effective_turn_state.as_deref()
    }

    pub fn split(self) -> (ChatgptWebSocketSender, ChatgptWebSocketEvents) {
        (self.sender, self.events)
    }
}

pub struct ChatgptWebSocketSender {
    transport: selvedge_client::WebSocketSender,
    context: ChatgptRequestContext,
    shared: Arc<Shared>,
    timeout: Duration,
}

pub struct ChatgptWebSocketEvents {
    receiver: mpsc::Receiver<ChatgptWebSocketEvent>,
    shared: Arc<Shared>,
    driver: JoinHandle<()>,
}

impl ChatgptWebSocketEvents {
    /// Drain already queued events before yielding a fatal session error once.
    pub async fn next(&mut self) -> Option<Result<ChatgptWebSocketEvent, ChatgptWebSocketError>> {
        match self.receiver.recv().await {
            Some(event) => Some(Ok(event)),
            None => self
                .shared
                .terminal
                .lock()
                .expect("terminal lock")
                .take()
                .map(Err),
        }
    }
}

impl Drop for ChatgptWebSocketEvents {
    fn drop(&mut self) {
        self.shared.close();
        self.driver.abort();
    }
}

impl Drop for ChatgptWebSocketSender {
    fn drop(&mut self) {
        self.shared.close();
    }
}

impl ChatgptWebSocketSender {
    pub async fn create(
        &mut self,
        request: &ChatgptResponsesRequest,
        previous_response_id: Option<&str>,
    ) -> Result<(), ChatgptWebSocketError> {
        request.validate().map_err(invalid_input)?;
        if request.context != self.context {
            return Err(invalid_input(RequestValidationError::new(
                "context",
                "must equal the WebSocket handshake context; open a new connection to change headers",
            )));
        }
        if let Some(id) = previous_response_id {
            validate_non_blank("previous_response_id", id).map_err(invalid_input)?;
        }
        let mut body = build_request_body(request);
        let object = body.as_object_mut().expect("request body object");
        object.insert("type".into(), Value::String("response.create".into()));
        if let Some(id) = previous_response_id {
            object.insert("previous_response_id".into(), Value::String(id.into()));
        }
        let text = body.to_string();
        validate_outbound_size(&text)?;
        {
            let mut state = self.shared.state.lock().expect("session state lock");
            match &*state {
                ConnectionState::Closed => return Err(ChatgptWebSocketError::Closed),
                ConnectionState::Open(ResponseState::Idle) => {
                    *state = ConnectionState::Open(ResponseState::Creating {
                        deadline: Instant::now() + self.timeout,
                    });
                }
                ConnectionState::Open(_) => return Err(ChatgptWebSocketError::ResponseInProgress),
            }
        }
        self.shared.changed.notify_one();
        self.send(text).await
    }

    pub async fn steer(
        &mut self,
        request: &ChatgptSteerRequest,
    ) -> Result<(), ChatgptWebSocketError> {
        validate_non_blank("previous_response_id", &request.previous_response_id)
            .map_err(invalid_input)?;
        let text = json!({
            "type": "response.steer",
            "previous_response_id": request.previous_response_id,
            "input": request.input.as_value(),
        })
        .to_string();
        validate_outbound_size(&text)?;
        self.send(text).await
    }

    pub async fn close(&mut self) -> Result<(), ChatgptWebSocketError> {
        self.shared.close();
        self.transport.close().await.map_err(client_error)
    }

    async fn send(&mut self, text: String) -> Result<(), ChatgptWebSocketError> {
        let closed = self.shared.closed.notified();
        tokio::pin!(closed);
        closed.as_mut().enable();
        if matches!(
            *self.shared.state.lock().expect("session state lock"),
            ConnectionState::Closed
        ) {
            return Err(ChatgptWebSocketError::Closed);
        }
        // NOTE: Cancellation leaves delivery uncertain; never reuse that connection.
        let mut guard = SendGuard(Some(Arc::clone(&self.shared)));
        tokio::select! {
            biased;
            _ = &mut closed => Err(ChatgptWebSocketError::Closed),
            result = self.transport.send_text(text) => {
                result.map_err(client_error)?;
                guard.0 = None;
                Ok(())
            }
        }
    }
}

struct SendGuard(Option<Arc<Shared>>);

impl Drop for SendGuard {
    fn drop(&mut self) {
        if let Some(shared) = &self.0 {
            shared.close();
        }
    }
}

enum ConnectionState {
    Open(ResponseState),
    Closed,
}

enum ResponseState {
    Idle,
    Creating { deadline: Instant },
    Responding { id: String, deadline: Instant },
}

struct Shared {
    state: Mutex<ConnectionState>,
    changed: Notify,
    closed: Notify,
    terminal: Mutex<Option<ChatgptWebSocketError>>,
}

impl Shared {
    fn close(&self) {
        *self.state.lock().expect("session state lock") = ConnectionState::Closed;
        self.changed.notify_one();
        self.closed.notify_waiters();
    }

    fn fail(&self, error: ChatgptWebSocketError) {
        *self.terminal.lock().expect("terminal lock") = Some(error);
        self.close();
    }
}

/// Opens a caller-owned connection without sending the initial request.
/// Only an unauthorized handshake may refresh credentials and retry once.
pub async fn connect_websocket(
    initial_request: &ChatgptResponsesRequest,
) -> Result<ChatgptWebSocketSession, ChatgptWebSocketError> {
    initial_request.validate().map_err(invalid_input)?;
    let config = selvedge_config::read(chatgpt_api_config_from_app_config)
        .map_err(ChatgptApiLowerLayerError::Config)
        .map_err(ChatgptApiError::LowerLayer)?;
    validate_chatgpt_api_config(&config).map_err(|reason| {
        ChatgptApiError::LowerLayer(ChatgptApiLowerLayerError::Config(
            selvedge_config::ConfigError::ValidationFailed(reason),
        ))
    })?;
    let mut auth = chatgpt_auth::resolve_for_request()
        .await
        .map_err(ChatgptApiLowerLayerError::Auth)
        .map_err(ChatgptApiError::LowerLayer)?;
    let mut refreshed = false;
    let connection = loop {
        let mut request =
            build_http_request(initial_request, &auth, &config).map_err(invalid_input)?;
        request.headers.remove(http::header::ACCEPT);
        let mut url = url::Url::parse(&request.url).map_err(|_| {
            invalid_input(RequestValidationError::new(
                "base_url",
                "must be a valid HTTP(S) URL",
            ))
        })?;
        let scheme = if url.scheme() == "https" { "wss" } else { "ws" };
        url.set_scheme(scheme).map_err(|()| {
            invalid_input(RequestValidationError::new(
                "base_url",
                "cannot convert to WebSocket URL",
            ))
        })?;
        match selvedge_client::connect_websocket(selvedge_client::WebSocketRequest {
            url: url.to_string(),
            headers: request.headers,
            timeout: request.timeout,
        })
        .await
        {
            Ok(connection) => break connection,
            Err(selvedge_client::HttpError::Status(status))
                if status.status == StatusCode::UNAUTHORIZED && !refreshed =>
            {
                auth = chatgpt_auth::resolve_after_unauthorized()
                    .await
                    .map_err(ChatgptApiLowerLayerError::Auth)
                    .map_err(ChatgptApiError::LowerLayer)?;
                refreshed = true;
            }
            Err(error) => return Err(handshake_error(error)),
        }
    };
    let effective_turn_state = connection
        .headers
        .get("x-codex-turn-state")
        .and_then(|value| value.to_str().ok())
        .map(str::to_owned)
        .or_else(|| initial_request.context.turn_state.clone());
    let (transport, receiver) = connection.split();
    let timeout = Duration::from_millis(config.stream_completion_timeout_ms);
    let shared = Arc::new(Shared {
        state: Mutex::new(ConnectionState::Open(ResponseState::Idle)),
        changed: Notify::new(),
        closed: Notify::new(),
        terminal: Mutex::new(None),
    });
    let (events_tx, events_rx) = mpsc::channel(EVENT_QUEUE_CAPACITY);
    let shared_for_driver = Arc::clone(&shared);
    let driver = tokio::spawn(async move {
        drive_events(receiver, events_tx, &shared_for_driver, timeout).await;
    });
    Ok(ChatgptWebSocketSession {
        sender: ChatgptWebSocketSender {
            transport,
            context: initial_request.context.clone(),
            shared: Arc::clone(&shared),
            timeout,
        },
        events: ChatgptWebSocketEvents {
            receiver: events_rx,
            shared,
            driver,
        },
        effective_turn_state,
    })
}

fn invalid_input(error: RequestValidationError) -> ChatgptWebSocketError {
    ChatgptApiError::LowerLayer(ChatgptApiLowerLayerError::InvalidInput(error)).into()
}

fn client_error(error: selvedge_client::HttpError) -> ChatgptWebSocketError {
    ChatgptApiError::LowerLayer(ChatgptApiLowerLayerError::Client(error)).into()
}

fn handshake_error(error: selvedge_client::HttpError) -> ChatgptWebSocketError {
    if let selvedge_client::HttpError::Status(status) = &error
        && let Some(classified) =
            misalignment_policy_error_from_http_response(status.status, &status.body)
    {
        return classified.into();
    }
    client_error(error)
}

fn is_policy_error(error: &ChatgptApiError) -> bool {
    matches!(error, ChatgptApiError::Endpoint(ChatgptApiEndpointError::Failed(error))
        if error.kind == ChatgptFailedEndpointKind::MisalignmentPolicyViolation)
}

fn malformed(reason: &str) -> ChatgptWebSocketError {
    ChatgptApiEndpointError::MalformedEvent {
        reason: reason.into(),
        raw: None,
    }
    .into()
}

impl From<ChatgptApiEndpointError> for ChatgptWebSocketError {
    fn from(error: ChatgptApiEndpointError) -> Self {
        ChatgptApiError::Endpoint(error).into()
    }
}

fn validate_outbound_size(text: &str) -> Result<(), ChatgptWebSocketError> {
    if text.len() > MAX_EVENT_BYTES {
        return Err(invalid_input(RequestValidationError::new(
            "request",
            "WebSocket message exceeds 1 MiB",
        )));
    }
    Ok(())
}

async fn drive_events(
    mut transport: selvedge_client::WebSocketReceiver,
    sender: mpsc::Sender<ChatgptWebSocketEvent>,
    shared: &Shared,
    timeout: Duration,
) {
    let mut response_bytes = 0_usize;
    loop {
        let deadline = match &*shared.state.lock().expect("session state lock") {
            ConnectionState::Closed => return,
            ConnectionState::Open(ResponseState::Idle) => None,
            ConnectionState::Open(
                ResponseState::Creating { deadline } | ResponseState::Responding { deadline, .. },
            ) => Some(*deadline),
        };
        let wait_deadline = async {
            match deadline {
                Some(deadline) => tokio::time::sleep_until(deadline).await,
                None => std::future::pending::<()>().await,
            }
        };
        let text = tokio::select! {
            biased;
            _ = shared.changed.notified() => continue,
            _ = wait_deadline => {
                shared.fail(ChatgptApiError::LowerLayer(ChatgptApiLowerLayerError::StreamCompletionTimeout { timeout }).into());
                return;
            }
            result = transport.next_text() => match result {
                Ok(Some(text)) => text,
                Ok(None) => {
                    shared.fail(ChatgptApiEndpointError::PrematureClose.into());
                    return;
                }
                Err(error) => {
                    shared.fail(client_error(error));
                    return;
                }
            }
        };
        if text.len() > MAX_EVENT_BYTES {
            shared.fail(
                ChatgptApiEndpointError::ResponseTooLarge {
                    limit_bytes: MAX_EVENT_BYTES,
                }
                .into(),
            );
            return;
        }
        let event = match decode_event(&text) {
            Ok(event) => event,
            Err(error) => {
                shared.fail(error);
                return;
            }
        };
        if !matches!(
            event,
            ChatgptWebSocketEvent::SteerAccepted(_)
                | ChatgptWebSocketEvent::SteerPending(_)
                | ChatgptWebSocketEvent::SteerFailed(_)
        ) {
            response_bytes = response_bytes.saturating_add(text.len());
            if response_bytes > MAX_RESPONSE_BYTES {
                shared.fail(
                    ChatgptApiEndpointError::ResponseTooLarge {
                        limit_bytes: MAX_RESPONSE_BYTES,
                    }
                    .into(),
                );
                return;
            }
        }
        if let Err(error) = update_response_state(shared, &event, timeout) {
            shared.fail(error);
            return;
        }
        if is_response_terminal(&event) {
            response_bytes = 0;
        }
        if !deliver_event(&sender, event, shared, timeout).await {
            return;
        }
    }
}

async fn deliver_event(
    sender: &mpsc::Sender<ChatgptWebSocketEvent>,
    event: ChatgptWebSocketEvent,
    shared: &Shared,
    timeout: Duration,
) -> bool {
    loop {
        let deadline = match &*shared.state.lock().expect("session state lock") {
            ConnectionState::Closed => return false,
            ConnectionState::Open(ResponseState::Idle) => None,
            ConnectionState::Open(
                ResponseState::Creating { deadline } | ResponseState::Responding { deadline, .. },
            ) => Some(*deadline),
        };
        let wait_deadline = async {
            match deadline {
                Some(deadline) => tokio::time::sleep_until(deadline).await,
                None => std::future::pending::<()>().await,
            }
        };
        tokio::select! {
            biased;
            _ = shared.changed.notified() => continue,
            _ = wait_deadline => {
                shared.fail(ChatgptApiError::LowerLayer(ChatgptApiLowerLayerError::StreamCompletionTimeout { timeout }).into());
                return false;
            }
            permit = sender.reserve() => {
                match permit {
                    Ok(permit) => { permit.send(event); return true; }
                    Err(_) => { shared.close(); return false; }
                }
            }
        }
    }
}

fn update_response_state(
    shared: &Shared,
    event: &ChatgptWebSocketEvent,
    timeout: Duration,
) -> Result<(), ChatgptWebSocketError> {
    let mut state = shared.state.lock().expect("session state lock");
    if let ChatgptWebSocketEvent::Response(ChatgptResponseEvent::Created(snapshot)) = event {
        let id = snapshot
            .id
            .as_deref()
            .filter(|id| !id.is_empty())
            .ok_or_else(|| malformed("response.created must contain a response id"))?;
        let deadline = match &*state {
            ConnectionState::Closed => return Err(ChatgptWebSocketError::Closed),
            ConnectionState::Open(ResponseState::Idle) => Instant::now() + timeout,
            ConnectionState::Open(ResponseState::Creating { deadline }) => *deadline,
            ConnectionState::Open(ResponseState::Responding {
                id: active_id,
                deadline,
            }) if active_id == id => *deadline,
            ConnectionState::Open(ResponseState::Responding { .. }) => {
                return Err(malformed(
                    "response.created conflicts with the active response",
                ));
            }
        };
        *state = ConnectionState::Open(ResponseState::Responding {
            id: id.into(),
            deadline,
        });
    } else if is_response_terminal(event) && !matches!(*state, ConnectionState::Closed) {
        *state = ConnectionState::Open(ResponseState::Idle);
    }
    Ok(())
}

fn is_response_terminal(event: &ChatgptWebSocketEvent) -> bool {
    matches!(
        event,
        ChatgptWebSocketEvent::Response(ChatgptResponseEvent::Completed(_))
            | ChatgptWebSocketEvent::Steered(_)
            | ChatgptWebSocketEvent::ResponseError(_)
    )
}

fn decode_event(text: &str) -> Result<ChatgptWebSocketEvent, ChatgptWebSocketError> {
    let object = serde_json::from_str::<Value>(text)
        .ok()
        .and_then(|value| value.as_object().cloned())
        .ok_or_else(|| malformed("WebSocket event must be a JSON object"))?;
    let event_type = object
        .get("type")
        .and_then(Value::as_str)
        .ok_or_else(|| malformed("WebSocket event must contain a string type"))?;
    if event_type.starts_with("response.steer.") {
        return decode_steer_event(event_type, &object);
    }
    if event_type == "response.incomplete" {
        let incomplete = incomplete_endpoint_error(&object);
        if incomplete.reason.as_deref() == Some("steered") {
            return Ok(ChatgptWebSocketEvent::Steered(incomplete));
        }
    }
    match map_stream_event(text)? {
        MappedEvent::Event(event) | MappedEvent::Completed(event) => {
            Ok(ChatgptWebSocketEvent::Response(event))
        }
        MappedEvent::EndpointError(error) if is_policy_error(&error) || event_type == "error" => {
            Err(error.into())
        }
        MappedEvent::EndpointError(error) => Ok(ChatgptWebSocketEvent::ResponseError(error)),
    }
}

fn decode_steer_event(
    event_type: &str,
    object: &JsonObject,
) -> Result<ChatgptWebSocketEvent, ChatgptWebSocketError> {
    if !matches!(
        event_type,
        "response.steer.accepted" | "response.steer.pending" | "response.steer.failed"
    ) {
        return Ok(ChatgptWebSocketEvent::Response(
            ChatgptResponseEvent::Other(super::ChatgptRawEvent {
                event_type: event_type.into(),
                payload: object.clone(),
            }),
        ));
    }
    let steer = object
        .get("steer")
        .and_then(Value::as_object)
        .ok_or_else(|| malformed("steering event must contain a steer object"))?;
    let required_string = |object: &JsonObject, field: &str| {
        object
            .get(field)
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .map(str::to_owned)
            .ok_or_else(|| malformed(&format!("steering event requires {field}")))
    };
    let identity = ChatgptSteerIdentity {
        id: required_string(steer, "id")?,
        previous_response_id: required_string(steer, "previous_response_id")?,
    };
    let sequence_number = match object.get("sequence_number") {
        None => None,
        Some(value) => Some(
            value
                .as_u64()
                .ok_or_else(|| malformed("sequence_number must be an unsigned integer"))?,
        ),
    };
    match event_type {
        "response.steer.accepted" => {
            Ok(ChatgptWebSocketEvent::SteerAccepted(ChatgptSteerAccepted {
                steer: identity,
                sequence_number,
                raw: object.clone(),
            }))
        }
        "response.steer.pending" => Ok(ChatgptWebSocketEvent::SteerPending(ChatgptSteerPending {
            steer: identity,
            sequence_number,
            reason: required_string(object, "reason")?,
            required_input: object
                .get("required_input")
                .and_then(Value::as_array)
                .cloned()
                .ok_or_else(|| malformed("pending steering requires required_input array"))?,
            raw: object.clone(),
        })),
        "response.steer.failed" => {
            let error = object
                .get("error")
                .and_then(Value::as_object)
                .cloned()
                .ok_or_else(|| malformed("failed steering requires error object"))?;
            let policy = failed_endpoint_event(object, event_type);
            if is_policy_error(&policy) {
                return Err(policy.into());
            }
            Ok(ChatgptWebSocketEvent::SteerFailed(ChatgptSteerFailed {
                steer: identity,
                sequence_number,
                input: steer
                    .get("input")
                    .cloned()
                    .ok_or_else(|| malformed("failed steering requires original input"))?,
                error,
                raw: object.clone(),
            }))
        }
        _ => unreachable!("known steering event"),
    }
}

fn validate_steer_input(value: &Value) -> Result<(), RequestValidationError> {
    let invalid = || {
        RequestValidationError::new(
            "input",
            "steering requires a string or nonempty array of user messages with supported input content",
        )
    };
    if value.is_string() {
        return Ok(());
    }
    let messages = value
        .as_array()
        .filter(|messages| !messages.is_empty())
        .ok_or_else(invalid)?;
    for message in messages {
        let message = message.as_object().ok_or_else(invalid)?;
        if message
            .keys()
            .any(|key| !matches!(key.as_str(), "type" | "role" | "content"))
            || message.get("role").and_then(Value::as_str) != Some("user")
            || message
                .get("type")
                .is_some_and(|kind| kind.as_str() != Some("message"))
        {
            return Err(invalid());
        }
        match message.get("content") {
            Some(Value::String(_)) => {}
            Some(Value::Array(parts)) if !parts.is_empty() => {
                for part in parts {
                    validate_steer_content(part).map_err(|()| invalid())?;
                }
            }
            _ => return Err(invalid()),
        }
    }
    Ok(())
}

fn validate_steer_content(value: &Value) -> Result<(), ()> {
    let object = value.as_object().ok_or(())?;
    let (allowed, sources): (&[&str], &[&str]) = match object.get("type").and_then(Value::as_str) {
        Some("input_text") => (&["type", "text"], &["text"]),
        Some("input_image") => (
            &["type", "image_url", "file_id", "detail"],
            &["image_url", "file_id"],
        ),
        Some("input_file") => (
            &["type", "file_data", "file_id", "file_url", "filename"],
            &["file_data", "file_id", "file_url"],
        ),
        _ => return Err(()),
    };
    if object.keys().any(|key| !allowed.contains(&key.as_str()))
        || sources
            .iter()
            .filter(|key| object.contains_key(**key))
            .count()
            != 1
        || object.values().any(|value| !value.is_string())
    {
        return Err(());
    }
    if let Some(detail) = object.get("detail").and_then(Value::as_str)
        && !matches!(detail, "auto" | "low" | "high" | "original")
    {
        return Err(());
    }
    Ok(())
}
