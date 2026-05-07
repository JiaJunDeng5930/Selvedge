#![doc = include_str!("../README.md")]

use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll};
use std::time::Duration;

use futures_core::Stream;
use selvedge_local_protocol::{
    AttachAccepted, AttachRejected, AttachRequest, CommandRequest, CommandResponse,
    LocalAttachStreamItem, LocalAttachStreamValidator, LocalClientFrame, LocalHttpProblem,
    ReadyRequest, ReadyResponse, current_protocol_version, validate_attach_request,
    validate_attach_stream_item, validate_command_request, validate_ready_request,
};
use serde::Serialize;
use serde::de::DeserializeOwned;
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::net::TcpStream;
use tokio::net::tcp::OwnedReadHalf;
use tokio_stream::StreamExt;
use tokio_stream::wrappers::LinesStream;

const READY_PATH: &str = "/selvedge/local/v1/ready";
const COMMAND_PATH: &str = "/selvedge/local/v1/command";
const ATTACH_PATH: &str = "/selvedge/local/v1/attach";
const JSON_CONTENT_TYPE: &str = "application/json";
const NDJSON_CONTENT_TYPE: &str = "application/x-ndjson";

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LocalClientConfig {
    pub endpoint: LocalEndpoint,
    pub request_timeout: Duration,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LocalEndpoint {
    TcpIpv4 { port: u16 },
    TcpIpv6 { port: u16 },
}

pub struct HttpLocalTransport {
    endpoint: LocalEndpoint,
}

pub struct LocalClient<T: LocalTransport> {
    transport: T,
    request_timeout: Duration,
    inner: Arc<Mutex<ClientState>>,
}

pub type LocalFrameStream =
    Pin<Box<dyn Stream<Item = Result<LocalClientFrame, LocalClientError>> + Send>>;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LocalClientState {
    Disconnected,
    Ready,
    CommandPending,
    AttachPending,
    Attached,
    Closing,
    Closed,
    Failed,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LocalClientError {
    NotConnected,
    AlreadyConnected,
    AlreadyAttached,
    Busy,
    Closing,
    Closed,
    ConnectFailed(String),
    Timeout,
    ProtocolValidationFailed(String),
    ServerRejected(String),
    StreamClosed,
    TransportClosed,
    TransportFailed(String),
}

pub trait LocalTransport: Send + Sync + 'static {
    fn connect(
        config: LocalClientConfig,
    ) -> impl Future<Output = Result<Self, LocalClientError>> + Send
    where
        Self: Sized;

    fn ready(
        &self,
        request: ReadyRequest,
    ) -> impl Future<Output = Result<ReadyResponse, LocalClientError>> + Send;

    fn submit_command(
        &self,
        request: CommandRequest,
    ) -> impl Future<Output = Result<CommandResponse, LocalClientError>> + Send;

    fn attach(
        &self,
        request: AttachRequest,
    ) -> impl Future<
        Output = Result<(AttachAccepted, LocalFrameStream), AttachRejectedOrClientError>,
    > + Send;

    fn close(&self) -> impl Future<Output = ()> + Send;
}

#[derive(Debug, PartialEq, Eq)]
pub enum AttachRejectedOrClientError {
    Rejected(AttachRejected),
    Client(LocalClientError),
}

struct ClientState {
    state: LocalClientState,
    attach_open: bool,
    attach_generation: u64,
    active_attach_stream: Option<SharedAttachStream>,
    recent_error: Option<LocalClientError>,
}

impl ClientState {
    fn ready() -> Self {
        Self {
            state: LocalClientState::Ready,
            attach_open: false,
            attach_generation: 0,
            active_attach_stream: None,
            recent_error: None,
        }
    }
}

pub async fn connect<T: LocalTransport>(
    config: LocalClientConfig,
) -> Result<LocalClient<T>, LocalClientError> {
    validate_endpoint(&config.endpoint)?;
    let request_timeout = config.request_timeout;
    let transport = T::connect(config).await?;

    Ok(LocalClient {
        transport,
        request_timeout,
        inner: Arc::new(Mutex::new(ClientState::ready())),
    })
}

pub async fn connect_http(
    config: LocalClientConfig,
) -> Result<LocalClient<HttpLocalTransport>, LocalClientError> {
    connect::<HttpLocalTransport>(config).await
}

impl LocalTransport for HttpLocalTransport {
    async fn connect(config: LocalClientConfig) -> Result<Self, LocalClientError>
    where
        Self: Sized,
    {
        TcpStream::connect(socket_target(&config.endpoint))
            .await
            .map_err(|error| LocalClientError::ConnectFailed(error.to_string()))?;

        Ok(Self {
            endpoint: config.endpoint,
        })
    }

    async fn ready(&self, request: ReadyRequest) -> Result<ReadyResponse, LocalClientError> {
        let response = post_json(&self.endpoint, READY_PATH, &request, JSON_CONTENT_TYPE).await?;
        let ready: ReadyResponse = parse_json_body(response).await?;
        validate_response_protocol_version(ready.protocol_version)?;
        Ok(ready)
    }

    async fn submit_command(
        &self,
        request: CommandRequest,
    ) -> Result<CommandResponse, LocalClientError> {
        let expected_command_id = request.client_command_id.clone();
        let response = post_json(&self.endpoint, COMMAND_PATH, &request, JSON_CONTENT_TYPE).await?;
        let command: CommandResponse = parse_json_body(response).await?;
        validate_response_protocol_version(command.protocol_version)?;
        if command.client_command_id != expected_command_id {
            return Err(LocalClientError::ProtocolValidationFailed(
                "command response id mismatch".to_owned(),
            ));
        }
        Ok(command)
    }

    async fn attach(
        &self,
        request: AttachRequest,
    ) -> Result<(AttachAccepted, LocalFrameStream), AttachRejectedOrClientError> {
        let expected_client_id = request.client_id.clone();
        let expected_command_id = request.client_command_id.clone();
        let response = post_json(&self.endpoint, ATTACH_PATH, &request, NDJSON_CONTENT_TYPE)
            .await
            .map_err(AttachRejectedOrClientError::Client)?;

        match response.status_code {
            200 => parse_attach_accepted_stream(response, expected_client_id, expected_command_id)
                .await
                .map_err(AttachRejectedOrClientError::Client),
            _ => parse_attach_rejected_response(response, expected_command_id).await,
        }
    }

    async fn close(&self) {}
}

impl<T: LocalTransport> LocalClient<T> {
    pub async fn state(&self) -> LocalClientState {
        self.inner
            .lock()
            .expect("local client state lock")
            .state
            .clone()
    }

    pub async fn ready(&self, request: ReadyRequest) -> Result<ReadyResponse, LocalClientError> {
        validate_ready_request(&request)
            .map_err(|error| LocalClientError::ProtocolValidationFailed(format!("{error:?}")))?;
        let guard = self.begin_request(LocalClientState::CommandPending)?;
        let result = tokio::time::timeout(guard.timeout, self.transport.ready(request)).await;
        self.finish_request_result(guard, result)
    }

    pub async fn submit_command(
        &self,
        request: CommandRequest,
    ) -> Result<CommandResponse, LocalClientError> {
        validate_command_request(&request)
            .map_err(|error| LocalClientError::ProtocolValidationFailed(format!("{error:?}")))?;
        let guard = self.begin_request(LocalClientState::CommandPending)?;
        let result =
            tokio::time::timeout(guard.timeout, self.transport.submit_command(request)).await;
        self.finish_request_result(guard, result)
    }

    pub async fn attach(
        &self,
        request: AttachRequest,
    ) -> Result<(AttachAccepted, LocalFrameStream), AttachRejectedOrClientError> {
        validate_attach_request(&request).map_err(|error| {
            AttachRejectedOrClientError::Client(LocalClientError::ProtocolValidationFailed(
                format!("{error:?}"),
            ))
        })?;
        let guard = self
            .begin_attach()
            .map_err(AttachRejectedOrClientError::Client)?;
        let result = tokio::time::timeout(guard.timeout, self.transport.attach(request)).await;

        match result {
            Ok(Ok((accepted, stream))) => {
                let stream = Arc::new(Mutex::new(Some(stream)));
                let attach_generation = guard.complete_attach_success(Arc::clone(&stream));
                let stream = Box::pin(ClientFrameStream {
                    inner: stream,
                    state: Arc::clone(&self.inner),
                    attach_generation,
                    closed_reported: false,
                });
                Ok((accepted, stream))
            }
            Ok(Err(AttachRejectedOrClientError::Rejected(rejected))) => {
                let return_state = guard.return_state.clone();
                guard.complete_as(return_state);
                Err(AttachRejectedOrClientError::Rejected(rejected))
            }
            Ok(Err(AttachRejectedOrClientError::Client(error))) => {
                let error = self.finish_client_error(guard, error);
                Err(AttachRejectedOrClientError::Client(error))
            }
            Err(_) => {
                let error = self.finish_client_error(guard, LocalClientError::Timeout);
                Err(AttachRejectedOrClientError::Client(error))
            }
        }
    }

    pub async fn close(&self) -> Result<(), LocalClientError> {
        let guard = self.begin_close()?;

        self.transport.close().await;
        guard.complete_closed();
        Ok(())
    }

    fn begin_close(&self) -> Result<CloseGuard, LocalClientError> {
        let mut state = self.inner.lock().expect("local client state lock");
        match state.state {
            LocalClientState::Closed => return Err(LocalClientError::Closed),
            LocalClientState::Closing => return Err(LocalClientError::Closing),
            LocalClientState::CommandPending | LocalClientState::AttachPending => {
                return Err(LocalClientError::Busy);
            }
            _ => {}
        }

        let previous_state = state.state.clone();
        let previous_attach_open = state.attach_open;
        let previous_recent_error = state.recent_error.clone();
        state.state = LocalClientState::Closing;
        state.recent_error = None;

        Ok(CloseGuard {
            state: Arc::clone(&self.inner),
            previous_state,
            previous_attach_open,
            previous_attach_generation: state.attach_generation,
            previous_recent_error,
            active: true,
        })
    }

    fn begin_request(&self, pending: LocalClientState) -> Result<RequestGuard, LocalClientError> {
        let mut state = self.inner.lock().expect("local client state lock");
        let return_state = match &state.state {
            LocalClientState::Ready => LocalClientState::Ready,
            LocalClientState::Attached => LocalClientState::Attached,
            LocalClientState::CommandPending | LocalClientState::AttachPending => {
                return Err(LocalClientError::Busy);
            }
            LocalClientState::Closing => return Err(LocalClientError::Closing),
            LocalClientState::Closed => return Err(LocalClientError::Closed),
            LocalClientState::Failed => {
                return Err(state.recent_error.clone().unwrap_or(
                    LocalClientError::TransportFailed("client failed".to_owned()),
                ));
            }
            LocalClientState::Disconnected => return Err(LocalClientError::NotConnected),
        };

        state.state = pending.clone();
        Ok(RequestGuard {
            state: Arc::clone(&self.inner),
            pending,
            return_state,
            timeout: self.request_timeout,
            active: true,
        })
    }

    fn begin_attach(&self) -> Result<RequestGuard, LocalClientError> {
        let mut state = self.inner.lock().expect("local client state lock");
        let return_state = match &state.state {
            LocalClientState::Ready => LocalClientState::Ready,
            LocalClientState::Attached => return Err(LocalClientError::AlreadyAttached),
            LocalClientState::CommandPending | LocalClientState::AttachPending => {
                return Err(LocalClientError::Busy);
            }
            LocalClientState::Closing => return Err(LocalClientError::Closing),
            LocalClientState::Closed => return Err(LocalClientError::Closed),
            LocalClientState::Failed => {
                return Err(state.recent_error.clone().unwrap_or(
                    LocalClientError::TransportFailed("client failed".to_owned()),
                ));
            }
            LocalClientState::Disconnected => return Err(LocalClientError::NotConnected),
        };

        state.state = LocalClientState::AttachPending;
        Ok(RequestGuard {
            state: Arc::clone(&self.inner),
            pending: LocalClientState::AttachPending,
            return_state,
            timeout: self.request_timeout,
            active: true,
        })
    }

    fn finish_request_result<R>(
        &self,
        guard: RequestGuard,
        result: Result<Result<R, LocalClientError>, tokio::time::error::Elapsed>,
    ) -> Result<R, LocalClientError> {
        match result {
            Ok(Ok(response)) => {
                let return_state = guard.return_state.clone();
                guard.complete_as(return_state);
                Ok(response)
            }
            Ok(Err(error)) => Err(self.finish_client_error(guard, error)),
            Err(_) => Err(self.finish_client_error(guard, LocalClientError::Timeout)),
        }
    }

    fn finish_client_error(
        &self,
        mut guard: RequestGuard,
        error: LocalClientError,
    ) -> LocalClientError {
        let mut state = self.inner.lock().expect("local client state lock");
        if state.state == guard.pending {
            state.state = LocalClientState::Failed;
            state.attach_open = false;
            state.active_attach_stream = None;
            state.recent_error = Some(error.clone());
        }
        guard.active = false;
        error
    }
}

struct RequestGuard {
    state: Arc<Mutex<ClientState>>,
    pending: LocalClientState,
    return_state: LocalClientState,
    timeout: Duration,
    active: bool,
}

struct CloseGuard {
    state: Arc<Mutex<ClientState>>,
    previous_state: LocalClientState,
    previous_attach_open: bool,
    previous_attach_generation: u64,
    previous_recent_error: Option<LocalClientError>,
    active: bool,
}

impl CloseGuard {
    fn complete_closed(mut self) {
        let active_stream = {
            let mut state = self.state.lock().expect("local client state lock");
            if state.state == LocalClientState::Closing {
                state.state = LocalClientState::Closed;
                state.attach_open = false;
                state.recent_error = None;
                state.active_attach_stream.take()
            } else {
                None
            }
        };
        if let Some(active_stream) = active_stream {
            drop_shared_attach_stream(&active_stream);
        }
        self.active = false;
    }
}

impl Drop for CloseGuard {
    fn drop(&mut self) {
        if !self.active {
            return;
        }

        let mut state = self.state.lock().expect("local client state lock");
        if state.state == LocalClientState::Closing {
            let attach_still_open = self.previous_attach_open
                && state.attach_open
                && state.attach_generation == self.previous_attach_generation;
            state.attach_open = attach_still_open;
            state.state = resolved_state(self.previous_state.clone(), attach_still_open);
            state.recent_error = self.previous_recent_error.clone();
        }
    }
}

impl RequestGuard {
    fn complete_as(mut self, next_state: LocalClientState) {
        let mut state = self.state.lock().expect("local client state lock");
        if state.state == self.pending {
            state.state = resolved_state(next_state, state.attach_open);
            state.recent_error = None;
        }
        self.active = false;
    }

    fn complete_attach_success(mut self, stream: SharedAttachStream) -> u64 {
        let mut state = self.state.lock().expect("local client state lock");
        if state.state == self.pending {
            state.attach_generation = state.attach_generation.wrapping_add(1);
            state.attach_open = true;
            state.active_attach_stream = Some(stream);
            state.state = LocalClientState::Attached;
            state.recent_error = None;
        }
        let attach_generation = state.attach_generation;
        self.active = false;
        attach_generation
    }
}

impl Drop for RequestGuard {
    fn drop(&mut self) {
        if !self.active {
            return;
        }

        let mut state = self.state.lock().expect("local client state lock");
        if state.state == self.pending {
            state.state = resolved_state(self.return_state.clone(), state.attach_open);
        }
    }
}

struct ClientFrameStream {
    inner: SharedAttachStream,
    state: Arc<Mutex<ClientState>>,
    attach_generation: u64,
    closed_reported: bool,
}

type SharedAttachStream = Arc<Mutex<Option<LocalFrameStream>>>;

impl Stream for ClientFrameStream {
    type Item = Result<LocalClientFrame, LocalClientError>;

    fn poll_next(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let this = self.get_mut();
        if this.closed_reported {
            return Poll::Ready(None);
        }
        if stream_is_closed_by_client(&this.state, this.attach_generation) {
            this.closed_reported = true;
            drop_shared_attach_stream(&this.inner);
            return Poll::Ready(None);
        }

        let item = {
            let mut inner = this.inner.lock().expect("local attach stream lock");
            match inner.as_mut() {
                Some(inner) => inner.as_mut().poll_next(cx),
                None => Poll::Ready(None),
            }
        };

        match item {
            Poll::Ready(Some(Ok(frame))) => Poll::Ready(Some(Ok(frame))),
            Poll::Ready(Some(Err(error))) => {
                clear_attached_state(&this.state, this.attach_generation);
                this.closed_reported = true;
                Poll::Ready(Some(Err(error)))
            }
            Poll::Ready(None) if !this.closed_reported => {
                this.closed_reported = true;
                clear_attached_state(&this.state, this.attach_generation);
                Poll::Ready(Some(Err(LocalClientError::StreamClosed)))
            }
            Poll::Ready(None) => Poll::Ready(None),
            Poll::Pending => Poll::Pending,
        }
    }
}

impl Drop for ClientFrameStream {
    fn drop(&mut self) {
        clear_attached_state(&self.state, self.attach_generation);
    }
}

fn clear_attached_state(state: &Arc<Mutex<ClientState>>, attach_generation: u64) {
    let active_stream = {
        let mut state = state.lock().expect("local client state lock");
        if state.attach_generation != attach_generation {
            return;
        }
        state.attach_open = false;
        let active_stream = state.active_attach_stream.take();
        if state.state == LocalClientState::Attached {
            state.state = LocalClientState::Ready;
        }
        active_stream
    };

    if let Some(active_stream) = active_stream {
        drop_shared_attach_stream(&active_stream);
    }
}

fn drop_shared_attach_stream(stream: &SharedAttachStream) {
    let mut stream = stream.lock().expect("local attach stream lock");
    let _ = stream.take();
}

fn stream_is_closed_by_client(state: &Arc<Mutex<ClientState>>, attach_generation: u64) -> bool {
    let state = state.lock().expect("local client state lock");
    state.state == LocalClientState::Closed
        || (state.attach_generation == attach_generation && !state.attach_open)
}

fn resolved_state(next_state: LocalClientState, attach_open: bool) -> LocalClientState {
    if next_state == LocalClientState::Attached && !attach_open {
        LocalClientState::Ready
    } else {
        next_state
    }
}

fn validate_endpoint(endpoint: &LocalEndpoint) -> Result<(), LocalClientError> {
    match endpoint {
        LocalEndpoint::TcpIpv4 { port } | LocalEndpoint::TcpIpv6 { port } if *port == 0 => Err(
            LocalClientError::ProtocolValidationFailed("endpoint port must be nonzero".to_owned()),
        ),
        LocalEndpoint::TcpIpv4 { .. } | LocalEndpoint::TcpIpv6 { .. } => Ok(()),
    }
}

struct HttpResponse {
    status_code: u16,
    content_type: Option<String>,
    reader: BufReader<OwnedReadHalf>,
}

struct HttpAttachFrameStream {
    lines: LinesStream<BufReader<OwnedReadHalf>>,
    validator: LocalAttachStreamValidator,
    ended: bool,
}

impl Stream for HttpAttachFrameStream {
    type Item = Result<LocalClientFrame, LocalClientError>;

    fn poll_next(self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let this = self.get_mut();
        if this.ended {
            return Poll::Ready(None);
        }

        match Pin::new(&mut this.lines).poll_next(context) {
            Poll::Ready(Some(Ok(line))) => Poll::Ready(Some(parse_attach_frame_line(
                line,
                &mut this.validator,
                &mut this.ended,
            ))),
            Poll::Ready(Some(Err(error))) => {
                this.ended = true;
                Poll::Ready(Some(Err(LocalClientError::TransportFailed(
                    error.to_string(),
                ))))
            }
            Poll::Ready(None) => {
                this.ended = true;
                Poll::Ready(None)
            }
            Poll::Pending => Poll::Pending,
        }
    }
}

async fn post_json<T: Serialize>(
    endpoint: &LocalEndpoint,
    path: &str,
    request: &T,
    accept: &str,
) -> Result<HttpResponse, LocalClientError> {
    let body = serde_json::to_vec(request)
        .map_err(|error| LocalClientError::ProtocolValidationFailed(error.to_string()))?;
    let mut stream = TcpStream::connect(socket_target(endpoint))
        .await
        .map_err(|error| LocalClientError::ConnectFailed(error.to_string()))?;
    let request = format!(
        "POST {path} HTTP/1.1\r\nHost: {}\r\nContent-Type: {JSON_CONTENT_TYPE}\r\nAccept: {accept}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        host_header(endpoint),
        body.len()
    );

    stream
        .write_all(request.as_bytes())
        .await
        .map_err(|error| LocalClientError::TransportFailed(error.to_string()))?;
    stream
        .write_all(&body)
        .await
        .map_err(|error| LocalClientError::TransportFailed(error.to_string()))?;
    stream
        .flush()
        .await
        .map_err(|error| LocalClientError::TransportFailed(error.to_string()))?;

    read_response_headers(stream).await
}

async fn read_response_headers(stream: TcpStream) -> Result<HttpResponse, LocalClientError> {
    let (read_half, _write_half) = stream.into_split();
    let mut reader = BufReader::new(read_half);
    let mut status_line = String::new();
    read_header_line(&mut reader, &mut status_line).await?;
    let status_code = parse_status_code(&status_line)?;
    let mut content_type = None;

    loop {
        let mut line = String::new();
        read_header_line(&mut reader, &mut line).await?;
        let trimmed = line.trim_end_matches(['\r', '\n']);
        if trimmed.is_empty() {
            break;
        }

        if let Some((name, value)) = trimmed.split_once(':')
            && name.eq_ignore_ascii_case("content-type")
        {
            content_type = Some(value.trim().to_ascii_lowercase());
        }
    }

    Ok(HttpResponse {
        status_code,
        content_type,
        reader,
    })
}

async fn read_header_line(
    reader: &mut BufReader<OwnedReadHalf>,
    line: &mut String,
) -> Result<(), LocalClientError> {
    let bytes = reader
        .read_line(line)
        .await
        .map_err(|error| LocalClientError::TransportFailed(error.to_string()))?;
    if bytes == 0 {
        return Err(LocalClientError::TransportClosed);
    }

    Ok(())
}

fn parse_status_code(status_line: &str) -> Result<u16, LocalClientError> {
    status_line
        .split_whitespace()
        .nth(1)
        .ok_or_else(|| LocalClientError::TransportFailed("missing HTTP status code".to_owned()))?
        .parse()
        .map_err(|error| LocalClientError::TransportFailed(format!("invalid HTTP status: {error}")))
}

async fn parse_json_body<T: DeserializeOwned>(
    mut response: HttpResponse,
) -> Result<T, LocalClientError> {
    require_content_type(&response, JSON_CONTENT_TYPE)?;
    let mut body = Vec::new();
    response
        .reader
        .read_to_end(&mut body)
        .await
        .map_err(|error| LocalClientError::TransportFailed(error.to_string()))?;

    if response.status_code != 200 {
        return Err(parse_problem(&body).unwrap_or_else(|| {
            LocalClientError::TransportFailed(format!(
                "unexpected HTTP status {}",
                response.status_code
            ))
        }));
    }

    serde_json::from_slice(&body)
        .map_err(|error| LocalClientError::ProtocolValidationFailed(error.to_string()))
}

async fn parse_attach_rejected_response(
    mut response: HttpResponse,
    expected_command_id: selvedge_local_protocol::LocalClientCommandId,
) -> Result<(AttachAccepted, LocalFrameStream), AttachRejectedOrClientError> {
    require_content_type(&response, JSON_CONTENT_TYPE)
        .map_err(AttachRejectedOrClientError::Client)?;
    let mut body = Vec::new();
    response
        .reader
        .read_to_end(&mut body)
        .await
        .map_err(|error| {
            AttachRejectedOrClientError::Client(LocalClientError::TransportFailed(
                error.to_string(),
            ))
        })?;

    match serde_json::from_slice::<AttachRejected>(&body) {
        Ok(rejected) => {
            validate_response_protocol_version(rejected.protocol_version)
                .map_err(AttachRejectedOrClientError::Client)?;
            if rejected.client_command_id != expected_command_id {
                return Err(AttachRejectedOrClientError::Client(
                    LocalClientError::ProtocolValidationFailed(
                        "attach rejected identity mismatch".to_owned(),
                    ),
                ));
            }
            Err(AttachRejectedOrClientError::Rejected(rejected))
        }
        Err(_) => Err(AttachRejectedOrClientError::Client(
            parse_problem(&body).unwrap_or_else(|| {
                LocalClientError::ProtocolValidationFailed("invalid attach reject body".to_owned())
            }),
        )),
    }
}

async fn parse_attach_accepted_stream(
    response: HttpResponse,
    expected_client_id: selvedge_local_protocol::LocalClientId,
    expected_command_id: selvedge_local_protocol::LocalClientCommandId,
) -> Result<(AttachAccepted, LocalFrameStream), LocalClientError> {
    require_content_type(&response, NDJSON_CONTENT_TYPE)?;
    let mut lines = LinesStream::new(response.reader.lines());
    let Some(first) = lines.next().await else {
        return Err(LocalClientError::TransportClosed);
    };
    let first = first.map_err(|error| LocalClientError::TransportFailed(error.to_string()))?;
    let item = parse_attach_stream_item(&first)?;
    validate_attach_stream_item(&item)
        .map_err(|error| LocalClientError::ProtocolValidationFailed(format!("{error:?}")))?;
    let mut validator = LocalAttachStreamValidator::new();
    validator
        .validate_next(&item)
        .map_err(|error| LocalClientError::TransportFailed(format!("{error:?}")))?;

    let LocalAttachStreamItem::Accepted(accepted) = item else {
        return Err(LocalClientError::TransportFailed(
            "attach stream must start with accepted item".to_owned(),
        ));
    };
    validate_response_protocol_version(accepted.protocol_version)?;
    if accepted.client_id != expected_client_id || accepted.client_command_id != expected_command_id
    {
        return Err(LocalClientError::ProtocolValidationFailed(
            "attach accepted identity mismatch".to_owned(),
        ));
    }

    Ok((
        accepted,
        Box::pin(HttpAttachFrameStream {
            lines,
            validator,
            ended: false,
        }),
    ))
}

fn parse_attach_frame_line(
    line: String,
    validator: &mut LocalAttachStreamValidator,
    ended: &mut bool,
) -> Result<LocalClientFrame, LocalClientError> {
    let item = parse_attach_stream_item(&line)?;
    validate_attach_stream_item(&item)
        .map_err(|error| LocalClientError::ProtocolValidationFailed(format!("{error:?}")))?;
    validator
        .validate_next(&item)
        .map_err(|error| LocalClientError::TransportFailed(format!("{error:?}")))?;

    match item {
        LocalAttachStreamItem::Frame(frame) => Ok(frame),
        LocalAttachStreamItem::StreamError(error) => {
            *ended = true;
            Err(LocalClientError::TransportFailed(error.message_text))
        }
        LocalAttachStreamItem::Accepted(_) => Err(LocalClientError::TransportFailed(
            "duplicate attach accepted item".to_owned(),
        )),
    }
}

fn parse_attach_stream_item(line: &str) -> Result<LocalAttachStreamItem, LocalClientError> {
    serde_json::from_str(line)
        .map_err(|error| LocalClientError::ProtocolValidationFailed(error.to_string()))
}

fn require_content_type(response: &HttpResponse, expected: &str) -> Result<(), LocalClientError> {
    let Some(content_type) = &response.content_type else {
        return Err(LocalClientError::ProtocolValidationFailed(
            "missing content type".to_owned(),
        ));
    };

    if content_type
        .split(';')
        .next()
        .is_some_and(|media_type| media_type.trim() == expected)
    {
        return Ok(());
    }

    Err(LocalClientError::ProtocolValidationFailed(format!(
        "unexpected content type {content_type}"
    )))
}

fn parse_problem(body: &[u8]) -> Option<LocalClientError> {
    serde_json::from_slice::<LocalHttpProblem>(body)
        .ok()
        .map(|problem| LocalClientError::TransportFailed(problem.message_text))
}

fn validate_response_protocol_version(
    protocol_version: selvedge_local_protocol::ProtocolVersion,
) -> Result<(), LocalClientError> {
    if protocol_version == current_protocol_version() {
        Ok(())
    } else {
        Err(LocalClientError::ProtocolValidationFailed(
            "protocol version mismatch".to_owned(),
        ))
    }
}

fn socket_target(endpoint: &LocalEndpoint) -> String {
    match endpoint {
        LocalEndpoint::TcpIpv4 { port } => format!("127.0.0.1:{port}"),
        LocalEndpoint::TcpIpv6 { port } => format!("[::1]:{port}"),
    }
}

fn host_header(endpoint: &LocalEndpoint) -> String {
    match endpoint {
        LocalEndpoint::TcpIpv4 { port } => format!("127.0.0.1:{port}"),
        LocalEndpoint::TcpIpv6 { port } => format!("[::1]:{port}"),
    }
}
