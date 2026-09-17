#![doc = include_str!("../README.md")]

use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll, Waker};
use std::time::Duration;

use bytes::{Buf, Bytes};
use futures_core::Stream;
use http_body_util::Full;
use hyper::body::{Body, Incoming};
use hyper_util::rt::TokioIo;
use selvedge_local_protocol::{
    AttachAccepted, AttachRejected, AttachRequest, CommandRequest, CommandResponse,
    LocalAttachStreamItem, LocalAttachStreamValidator, LocalClientFrame, LocalHttpProblem,
    LocalStreamError, MAX_LOCAL_FRAME_BYTES, ReadyRequest, ReadyResponse, validate_attach_request,
    validate_attach_stream_item, validate_command_request,
};
use serde::Serialize;
use serde::de::DeserializeOwned;
use std::io;
use tokio::io::{AsyncBufRead, AsyncRead, AsyncReadExt, BufReader, ReadBuf};
use tokio::net::TcpStream;
use tokio_stream::StreamExt;

const READY_PATH: &str = "/selvedge/local/v1/ready";
const COMMAND_PATH: &str = "/selvedge/local/v1/command";
const ATTACH_PATH: &str = "/selvedge/local/v1/attach";
const JSON_CONTENT_TYPE: &str = "application/json";
const NDJSON_CONTENT_TYPE: &str = "application/x-ndjson";
const MAX_HTTP_RESPONSE_HEADER_BYTES: usize = 16 * 1024;
const MAX_HTTP_RESPONSE_BODY_BYTES: usize = 4 * 1024 * 1024;
const MAX_NDJSON_LINE_BYTES: usize = MAX_LOCAL_FRAME_BYTES;

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
    AlreadyAttached,
    Busy,
    Closing,
    Closed,
    ConnectFailed(String),
    Timeout,
    ProtocolValidationFailed(String),
    HttpProblem(LocalHttpProblem),
    StreamError(LocalStreamError),
    StreamClosed,
    TransportClosed,
    TransportFailed(String),
    ResponseTooLarge { limit_bytes: usize },
}

pub trait LocalTransport: Send + Sync + 'static {
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

pub trait LocalConnector {
    type Transport: LocalTransport;
    fn connect(
        self,
        config: LocalClientConfig,
    ) -> impl Future<Output = Result<Self::Transport, LocalClientError>> + Send;
}

pub struct HttpLocalConnector;

pub async fn connect_with<C: LocalConnector>(
    config: LocalClientConfig,
    connector: C,
) -> Result<LocalClient<C::Transport>, LocalClientError> {
    validate_endpoint(&config.endpoint)?;
    let request_timeout = config.request_timeout;
    let transport = tokio::time::timeout(request_timeout, connector.connect(config))
        .await
        .map_err(|_| LocalClientError::Timeout)??;
    Ok(LocalClient {
        transport,
        request_timeout,
        inner: Arc::new(Mutex::new(ClientState::ready())),
    })
}

pub async fn connect_http(
    config: LocalClientConfig,
) -> Result<LocalClient<HttpLocalTransport>, LocalClientError> {
    connect_with(config, HttpLocalConnector).await
}

impl LocalConnector for HttpLocalConnector {
    type Transport = HttpLocalTransport;
    async fn connect(
        self,
        config: LocalClientConfig,
    ) -> Result<HttpLocalTransport, LocalClientError> {
        TcpStream::connect(socket_target(&config.endpoint))
            .await
            .map_err(|error| LocalClientError::ConnectFailed(error.to_string()))?;
        Ok(HttpLocalTransport {
            endpoint: config.endpoint,
        })
    }
}

impl LocalTransport for HttpLocalTransport {
    async fn ready(&self, request: ReadyRequest) -> Result<ReadyResponse, LocalClientError> {
        let response = post_json(&self.endpoint, READY_PATH, &request, JSON_CONTENT_TYPE).await?;
        let ready: ReadyResponse = parse_json_body(response).await?;
        Ok(ready)
    }

    async fn submit_command(
        &self,
        request: CommandRequest,
    ) -> Result<CommandResponse, LocalClientError> {
        let expected_command_id = request.client_command_id.clone();
        let response = post_json(&self.endpoint, COMMAND_PATH, &request, JSON_CONTENT_TYPE).await?;
        let command: CommandResponse = parse_json_body(response).await?;
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
                let stream = Arc::new(Mutex::new(SharedAttachStreamState {
                    inner: Some(stream),
                    waker: None,
                }));
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
        let active_stream = {
            let mut state = self.inner.lock().expect("local client state lock");
            if state.state == guard.pending {
                state.state = LocalClientState::Failed;
                state.attach_open = false;
                state.recent_error = Some(error.clone());
                state.active_attach_stream.take()
            } else {
                None
            }
        };
        if let Some(active_stream) = active_stream {
            drop_shared_attach_stream(&active_stream);
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

struct SharedAttachStreamState {
    inner: Option<LocalFrameStream>,
    waker: Option<Waker>,
}

type SharedAttachStream = Arc<Mutex<SharedAttachStreamState>>;

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
            match inner.inner.as_mut() {
                Some(stream) => {
                    let item = stream.as_mut().poll_next(cx);
                    match &item {
                        Poll::Pending => inner.waker = Some(cx.waker().clone()),
                        Poll::Ready(_) => inner.waker = None,
                    }
                    item
                }
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
    let waker = {
        let mut stream = stream.lock().expect("local attach stream lock");
        let _ = stream.inner.take();
        stream.waker.take()
    };
    if let Some(waker) = waker {
        waker.wake();
    }
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
    reader: BufReader<HttpBodyReader>,
}

struct HttpAttachFrameStream {
    lines: BoundedLines<BufReader<HttpBodyReader>>,
    validator: LocalAttachStreamValidator,
    ended: bool,
}

struct BoundedLines<R> {
    reader: R,
    buffer: Vec<u8>,
    ended: bool,
}

impl<R> BoundedLines<R> {
    fn new(reader: R) -> Self {
        Self {
            reader,
            buffer: Vec::new(),
            ended: false,
        }
    }
}

impl<R: AsyncBufRead + Unpin> Stream for BoundedLines<R> {
    type Item = Result<String, LocalClientError>;

    fn poll_next(self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let this = self.get_mut();
        if this.ended {
            return Poll::Ready(None);
        }

        loop {
            let (consume, has_newline) = {
                let available = match Pin::new(&mut this.reader).poll_fill_buf(context) {
                    Poll::Ready(Ok(available)) => available,
                    Poll::Ready(Err(error)) => {
                        this.ended = true;
                        return Poll::Ready(Some(Err(LocalClientError::TransportFailed(
                            error.to_string(),
                        ))));
                    }
                    Poll::Pending => return Poll::Pending,
                };
                if available.is_empty() {
                    this.ended = true;
                    return if this.buffer.is_empty() {
                        Poll::Ready(None)
                    } else {
                        Poll::Ready(Some(finish_bounded_line(&mut this.buffer)))
                    };
                }

                let newline = available.iter().position(|byte| *byte == b'\n');
                let content_len = newline.unwrap_or(available.len());
                if content_len > MAX_NDJSON_LINE_BYTES.saturating_sub(this.buffer.len()) {
                    this.ended = true;
                    return Poll::Ready(Some(Err(LocalClientError::ResponseTooLarge {
                        limit_bytes: MAX_NDJSON_LINE_BYTES,
                    })));
                }
                this.buffer.extend_from_slice(&available[..content_len]);
                (
                    newline.map_or(available.len(), |index| index + 1),
                    newline.is_some(),
                )
            };

            Pin::new(&mut this.reader).consume(consume);
            if has_newline {
                return Poll::Ready(Some(finish_bounded_line(&mut this.buffer)));
            }
        }
    }
}

fn finish_bounded_line(buffer: &mut Vec<u8>) -> Result<String, LocalClientError> {
    if buffer.last() == Some(&b'\r') {
        buffer.pop();
    }
    String::from_utf8(std::mem::take(buffer))
        .map_err(|error| LocalClientError::ProtocolValidationFailed(error.to_string()))
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
                Poll::Ready(Some(Err(error)))
            }
            Poll::Ready(None) => {
                this.ended = true;
                Poll::Ready(None)
            }
            Poll::Pending => Poll::Pending,
        }
    }
}

struct ConnectionDriver(tokio::task::JoinHandle<()>);

impl Drop for ConnectionDriver {
    fn drop(&mut self) {
        self.0.abort();
    }
}

// The response owns the connection driver, including when a request or attach is cancelled.
struct HttpBodyReader {
    body: Incoming,
    buffered: Bytes,
    _driver: ConnectionDriver,
}

impl AsyncRead for HttpBodyReader {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        output: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        if output.remaining() == 0 {
            return Poll::Ready(Ok(()));
        }
        loop {
            if !this.buffered.is_empty() {
                let size = output.remaining().min(this.buffered.len());
                output.put_slice(&this.buffered[..size]);
                this.buffered.advance(size);
                return Poll::Ready(Ok(()));
            }
            match Pin::new(&mut this.body).poll_frame(cx) {
                Poll::Pending => return Poll::Pending,
                Poll::Ready(None) => return Poll::Ready(Ok(())),
                Poll::Ready(Some(Err(error))) => return Poll::Ready(Err(io::Error::other(error))),
                Poll::Ready(Some(Ok(frame))) => {
                    if let Ok(data) = frame.into_data() {
                        this.buffered = data;
                    }
                }
            }
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
    let authority = socket_target(endpoint);
    let stream = TcpStream::connect(&authority)
        .await
        .map_err(|error| LocalClientError::ConnectFailed(error.to_string()))?;
    let (mut sender, connection) = hyper::client::conn::http1::Builder::new()
        .max_buf_size(MAX_HTTP_RESPONSE_HEADER_BYTES)
        .handshake(TokioIo::new(stream))
        .await
        .map_err(http_error)?;
    let driver = ConnectionDriver(tokio::spawn(async move {
        let _ = connection.await;
    }));
    let request = hyper::Request::post(path)
        .header("host", authority)
        .header("content-type", JSON_CONTENT_TYPE)
        .header("accept", accept)
        .header("connection", "close")
        .body(Full::new(Bytes::from(body)))
        .map_err(|error| LocalClientError::ProtocolValidationFailed(error.to_string()))?;
    let response = sender.send_request(request).await.map_err(http_error)?;
    let header_bytes = response
        .headers()
        .iter()
        .map(|(name, value)| name.as_str().len() + value.as_bytes().len() + 4)
        .sum::<usize>()
        + 16;
    if header_bytes > MAX_HTTP_RESPONSE_HEADER_BYTES {
        return Err(LocalClientError::ResponseTooLarge {
            limit_bytes: MAX_HTTP_RESPONSE_HEADER_BYTES,
        });
    }
    let status_code = response.status().as_u16();
    let content_type = response
        .headers()
        .get("content-type")
        .and_then(|value| value.to_str().ok())
        .map(str::to_ascii_lowercase);
    Ok(HttpResponse {
        status_code,
        content_type,
        reader: BufReader::new(HttpBodyReader {
            body: response.into_body(),
            buffered: Bytes::new(),
            _driver: driver,
        }),
    })
}

fn http_error(error: hyper::Error) -> LocalClientError {
    if error.is_parse_too_large() {
        LocalClientError::ResponseTooLarge {
            limit_bytes: MAX_HTTP_RESPONSE_HEADER_BYTES,
        }
    } else {
        LocalClientError::TransportFailed(error.to_string())
    }
}

async fn parse_json_body<T: DeserializeOwned>(
    mut response: HttpResponse,
) -> Result<T, LocalClientError> {
    require_content_type(&response, JSON_CONTENT_TYPE)?;
    let body = read_bounded_body(&mut response.reader).await?;

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

async fn read_bounded_body(
    reader: &mut BufReader<HttpBodyReader>,
) -> Result<Vec<u8>, LocalClientError> {
    let mut body = Vec::new();
    reader
        .take((MAX_HTTP_RESPONSE_BODY_BYTES + 1) as u64)
        .read_to_end(&mut body)
        .await
        .map_err(|error| LocalClientError::TransportFailed(error.to_string()))?;
    if body.len() > MAX_HTTP_RESPONSE_BODY_BYTES {
        return Err(LocalClientError::ResponseTooLarge {
            limit_bytes: MAX_HTTP_RESPONSE_BODY_BYTES,
        });
    }
    Ok(body)
}

async fn parse_attach_rejected_response(
    mut response: HttpResponse,
    expected_command_id: selvedge_local_protocol::LocalClientCommandId,
) -> Result<(AttachAccepted, LocalFrameStream), AttachRejectedOrClientError> {
    require_content_type(&response, JSON_CONTENT_TYPE)
        .map_err(AttachRejectedOrClientError::Client)?;
    let body = read_bounded_body(&mut response.reader)
        .await
        .map_err(AttachRejectedOrClientError::Client)?;

    match serde_json::from_slice::<AttachRejected>(&body) {
        Ok(rejected) => {
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
    let mut lines = BoundedLines::new(response.reader);
    let Some(first) = lines.next().await else {
        return Err(LocalClientError::TransportClosed);
    };
    let first = first?;
    let item = parse_attach_stream_item(&first)?;
    validate_attach_stream_item(&item)
        .map_err(|error| LocalClientError::ProtocolValidationFailed(format!("{error:?}")))?;
    let mut validator = LocalAttachStreamValidator::new();
    let sequence_result = validator.validate_next(&item);
    sequence_result.map_err(|error| LocalClientError::TransportFailed(format!("{error:?}")))?;

    let LocalAttachStreamItem::Accepted(accepted) = item else {
        return Err(LocalClientError::TransportFailed(
            "attach stream must start with accepted item".to_owned(),
        ));
    };
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
            Err(LocalClientError::StreamError(error))
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
        .map(LocalClientError::HttpProblem)
}

fn socket_target(endpoint: &LocalEndpoint) -> String {
    match endpoint {
        LocalEndpoint::TcpIpv4 { port } => format!("127.0.0.1:{port}"),
        LocalEndpoint::TcpIpv6 { port } => format!("[::1]:{port}"),
    }
}
