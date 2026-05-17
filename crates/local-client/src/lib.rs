#![doc = include_str!("../README.md")]
//! @behavior selvedge.client.local Local clients connect to a configured localhost endpoint, send ready and command requests, attach to one event stream, and expose typed state and errors.

use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll, Waker};
use std::time::Duration;

use futures_core::Stream;
use selvedge_local_protocol::{
    AttachAccepted, AttachRejected, AttachRequest, CommandRequest, CommandResponse,
    LocalAttachStreamItem, LocalAttachStreamValidator, LocalClientFrame, LocalHttpProblem,
    ReadyRequest, ReadyResponse, validate_attach_request, validate_attach_stream_item,
    validate_command_request, validate_ready_request,
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
// @behavior selvedge.client.local.config Local client config exposes the endpoint and per-request timeout selected by callers.
pub struct LocalClientConfig {
    /// @behavior selvedge.client.local.config.endpoint Local client config exposes the structured loopback endpoint.
    pub endpoint: LocalEndpoint,
    /// @behavior selvedge.client.local.config.timeout Local client config exposes the request timeout applied to ready, command, and attach calls.
    pub request_timeout: Duration,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @constraint selvedge.client.local.endpoint Local endpoints are structured loopback TCP targets with nonzero ports.
pub enum LocalEndpoint {
    TcpIpv4 { port: u16 },
    TcpIpv6 { port: u16 },
}

// @intent selvedge.client.local.http_transport The HTTP local transport maps local protocol requests onto localhost HTTP endpoints.
// @behavior selvedge.client.local.http HTTP local transport exchanges local protocol messages over localhost HTTP request and response bodies.
pub struct HttpLocalTransport {
    endpoint: LocalEndpoint,
}

// @intent selvedge.client.local.client.abstraction LocalClient owns caller-visible state for ready probes, command submission, attach streams, and close requests.
// @behavior selvedge.client.local.client LocalClient exposes a configured transport, timeout, and state machine for caller-visible local protocol operations.
pub struct LocalClient<T: LocalTransport> {
    transport: T,
    request_timeout: Duration,
    inner: Arc<Mutex<ClientState>>,
}

// @intent selvedge.client.local.frame_stream.abstraction Local frame streams abstract asynchronous delivery of local protocol frames to attached clients.
// @behavior selvedge.client.local.frame_stream Attached clients expose local protocol frames as a stream of typed frame or client error results.
pub type LocalFrameStream =
    Pin<Box<dyn Stream<Item = Result<LocalClientFrame, LocalClientError>> + Send>>;

// @behavior selvedge.client.local.state Local client state reports connection, pending request, attached stream, closing, closed, and failed states to callers.
// @intent selvedge.client.local.state_machine The local client state enum defines caller-visible lifecycle states for local protocol operations.
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
// @behavior selvedge.client.local.error Local client errors expose connection, state, timeout, protocol validation, server rejection, stream, and transport failures to callers.
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

// @intent selvedge.client.local.transport.abstraction Local transports provide caller-supplied connection, ready, command, attach, and close operations behind the local client state machine.
// @behavior selvedge.client.local.transport Local transports expose connection, ready, command, attach, and close results to the local client.
pub trait LocalTransport: Send + Sync + 'static {
    // @behavior selvedge.client.local.transport.connect.call Local transport connect receives caller-selected endpoint and timeout config.
    // @behavior selvedge.client.local.transport.connect Local transports connect using the caller-selected config and return a client error on failure.
    fn connect(
        config: LocalClientConfig,
    ) -> impl Future<Output = Result<Self, LocalClientError>> + Send
    where
        Self: Sized;

    // @behavior selvedge.client.local.transport.ready.call Local transport ready receives a protocol ready request.
    // @behavior selvedge.client.local.transport.ready Local transports send ready protocol requests and return ready protocol responses or client errors.
    fn ready(
        &self,
        request: ReadyRequest,
    ) -> impl Future<Output = Result<ReadyResponse, LocalClientError>> + Send;

    // @behavior selvedge.client.local.transport.command.call Local transport command receives a protocol command request.
    // @behavior selvedge.client.local.transport.command Local transports submit command protocol requests and return command protocol responses or client errors.
    fn submit_command(
        &self,
        request: CommandRequest,
    ) -> impl Future<Output = Result<CommandResponse, LocalClientError>> + Send;

    // @behavior selvedge.client.local.transport.attach.call Local transport attach receives a protocol attach request.
    // @behavior selvedge.client.local.transport.attach Local transports submit attach protocol requests and return accepted streams, server rejections, or client errors.
    fn attach(
        &self,
        request: AttachRequest,
    ) -> impl Future<
        Output = Result<(AttachAccepted, LocalFrameStream), AttachRejectedOrClientError>,
    > + Send;

    // @behavior selvedge.client.local.transport.close.call Local transport close completes after releasing connection resources.
    // @behavior selvedge.client.local.transport.close Local transports close their underlying connection resources.
    fn close(&self) -> impl Future<Output = ()> + Send;
}

#[derive(Debug, PartialEq, Eq)]
// @behavior selvedge.client.local.attach_result Attach failures distinguish server rejections from local client or transport errors.
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

// @behavior selvedge.client.local.connect.call Connecting returns a ready local client or a typed endpoint or transport error.
pub async fn connect<T: LocalTransport>(
    config: LocalClientConfig,
) -> Result<LocalClient<T>, LocalClientError> {
    // @behavior selvedge.client.local.connect Connecting validates the structured localhost endpoint before invoking the transport.
    validate_endpoint(&config.endpoint)?;
    let request_timeout = config.request_timeout;
    // @behavior selvedge.client.local.connect.transport Connecting returns the transport connection error when transport connect fails.
    let transport = T::connect(config).await?;

    Ok(LocalClient {
        transport,
        request_timeout,
        inner: Arc::new(Mutex::new(ClientState::ready())),
    })
}

// @behavior selvedge.client.local.connect_http.call HTTP connect returns a local client backed by the localhost HTTP transport.
pub async fn connect_http(
    config: LocalClientConfig,
) -> Result<LocalClient<HttpLocalTransport>, LocalClientError> {
    // @behavior selvedge.client.local.connect_http HTTP connect returns a local client backed by the localhost HTTP transport.
    connect::<HttpLocalTransport>(config).await
}

impl LocalTransport for HttpLocalTransport {
    async fn connect(config: LocalClientConfig) -> Result<Self, LocalClientError>
    where
        Self: Sized,
    {
        // @behavior selvedge.client.local.http.connect HTTP transport connect opens a TCP connection to the configured loopback endpoint and reports connection failures as ConnectFailed.
        TcpStream::connect(socket_target(&config.endpoint))
            .await
            .map_err(|error| LocalClientError::ConnectFailed(error.to_string()))?;

        Ok(Self {
            endpoint: config.endpoint,
        })
    }

    async fn ready(&self, request: ReadyRequest) -> Result<ReadyResponse, LocalClientError> {
        // @behavior selvedge.client.local.http.ready HTTP ready sends a JSON POST to the ready endpoint and returns a validated ready response.
        let response = post_json(&self.endpoint, READY_PATH, &request, JSON_CONTENT_TYPE).await?;
        let ready: ReadyResponse = parse_json_body(response).await?;
        Ok(ready)
    }

    // @behavior selvedge.client.local.http.command.call HTTP command calls return a validated command response or typed client error.
    async fn submit_command(
        &self,
        request: CommandRequest,
    ) -> Result<CommandResponse, LocalClientError> {
        // @behavior selvedge.client.local.http.command HTTP command sends a JSON POST to the command endpoint and rejects response command identity mismatches.
        let expected_command_id = request.client_command_id.clone();
        let response = post_json(&self.endpoint, COMMAND_PATH, &request, JSON_CONTENT_TYPE).await?;
        let command: CommandResponse = parse_json_body(response).await?;
        // @constraint selvedge.client.local.http.command.identity HTTP command responses must carry the requested client command ID.
        if command.client_command_id != expected_command_id {
            return Err(LocalClientError::ProtocolValidationFailed(
                "command response id mismatch".to_owned(),
            ));
        }
        Ok(command)
    }

    // @behavior selvedge.client.local.http.attach.call HTTP attach calls return an accepted frame stream, server rejection, or client error.
    async fn attach(
        &self,
        request: AttachRequest,
    ) -> Result<(AttachAccepted, LocalFrameStream), AttachRejectedOrClientError> {
        // @behavior selvedge.client.local.http.attach HTTP attach sends a JSON POST to the attach endpoint and returns an accepted NDJSON frame stream or typed rejection.
        let expected_client_id = request.client_id.clone();
        let expected_command_id = request.client_command_id.clone();
        let response = post_json(&self.endpoint, ATTACH_PATH, &request, NDJSON_CONTENT_TYPE)
            .await
            .map_err(AttachRejectedOrClientError::Client)?;

        // @behavior selvedge.client.local.http.attach.status HTTP attach status controls whether callers receive an accepted stream or rejection response.
        match response.status_code {
            200 => parse_attach_accepted_stream(response, expected_client_id, expected_command_id)
                .await
                .map_err(AttachRejectedOrClientError::Client),
            _ => {
                // @behavior selvedge.client.local.http.attach.reject_status Non-200 attach responses are parsed as attach rejection or client protocol errors.
                parse_attach_rejected_response(response, expected_command_id).await
            }
        }
    }

    // @behavior selvedge.client.local.http.close Closing the HTTP transport completes without additional protocol output.
    async fn close(&self) {}
}

impl<T: LocalTransport> LocalClient<T> {
    // @behavior selvedge.client.local.state.read Reading state returns the current caller-visible local client state.
    pub async fn state(&self) -> LocalClientState {
        self.inner
            .lock()
            .expect("local client state lock")
            .state
            .clone()
    }

    // @behavior selvedge.client.local.ready Ready validates the ready request, runs one timed transport request, and restores the prior idle state on success.
    pub async fn ready(&self, request: ReadyRequest) -> Result<ReadyResponse, LocalClientError> {
        // @behavior selvedge.client.local.ready.validate Ready returns ProtocolValidationFailed for invalid ready requests before transport execution.
        validate_ready_request(&request)
            .map_err(|error| LocalClientError::ProtocolValidationFailed(format!("{error:?}")))?;
        let guard = self.begin_request(LocalClientState::CommandPending)?;
        let result = tokio::time::timeout(guard.timeout, self.transport.ready(request)).await;
        self.finish_request_result(guard, result)
    }

    // @behavior selvedge.client.local.command Command submission validates the command request, runs one timed transport request, and preserves the server command outcome.
    pub async fn submit_command(
        &self,
        request: CommandRequest,
    ) -> Result<CommandResponse, LocalClientError> {
        // @behavior selvedge.client.local.command.validate Command submission returns ProtocolValidationFailed for invalid command requests before transport execution.
        validate_command_request(&request)
            .map_err(|error| LocalClientError::ProtocolValidationFailed(format!("{error:?}")))?;
        let guard = self.begin_request(LocalClientState::CommandPending)?;
        let result =
            tokio::time::timeout(guard.timeout, self.transport.submit_command(request)).await;
        self.finish_request_result(guard, result)
    }

    // @behavior selvedge.client.local.attach Attach validates the attach request, allows one active attach stream, and returns accepted identity with the frame stream.
    pub async fn attach(
        &self,
        request: AttachRequest,
    ) -> Result<(AttachAccepted, LocalFrameStream), AttachRejectedOrClientError> {
        // @behavior selvedge.client.local.attach.validate Attach returns a client ProtocolValidationFailed error for invalid attach requests before transport execution.
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
                // @behavior selvedge.client.local.attach.success A successful attach moves the client to Attached and makes the returned stream the active attach stream.
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
            // @behavior selvedge.client.local.attach.rejected A server attach rejection is returned without moving the client into Failed state.
            Ok(Err(AttachRejectedOrClientError::Rejected(rejected))) => {
                let return_state = guard.return_state.clone();
                guard.complete_as(return_state);
                Err(AttachRejectedOrClientError::Rejected(rejected))
            }
            Ok(Err(AttachRejectedOrClientError::Client(error))) => {
                // @behavior selvedge.client.local.attach.client_error A client attach error moves the client to Failed and returns the typed client error.
                let error = self.finish_client_error(guard, error);
                Err(AttachRejectedOrClientError::Client(error))
            }
            Err(_) => {
                // @behavior selvedge.client.local.attach.timeout An attach timeout moves the client to Failed and returns Timeout.
                let error = self.finish_client_error(guard, LocalClientError::Timeout);
                Err(AttachRejectedOrClientError::Client(error))
            }
        }
    }

    // @behavior selvedge.client.local.close Closing a client runs the transport close, closes any active attach stream, and reports Closed state on success.
    pub async fn close(&self) -> Result<(), LocalClientError> {
        // @behavior selvedge.client.local.close.call Close transitions the client through Closing before transport close completes.
        let guard = self.begin_close()?;

        self.transport.close().await;
        guard.complete_closed();
        Ok(())
    }

    fn begin_close(&self) -> Result<CloseGuard, LocalClientError> {
        // @constraint selvedge.client.local.close.state Close requests return typed state errors when the client is already closed, closing, or busy.
        let mut state = self.inner.lock().expect("local client state lock");
        match state.state {
            // @constraint selvedge.client.local.close.state.closed Close requests return Closed when the client is already closed.
            LocalClientState::Closed => return Err(LocalClientError::Closed),
            // @constraint selvedge.client.local.close.state.closing Close requests return Closing when a close is already pending.
            LocalClientState::Closing => return Err(LocalClientError::Closing),
            LocalClientState::CommandPending | LocalClientState::AttachPending => {
                // @constraint selvedge.client.local.close.state.busy Close requests return Busy while command or attach requests are pending.
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
        // @constraint selvedge.client.local.request.state Ready and command requests run only from Ready or Attached states and otherwise return typed state errors.
        let mut state = self.inner.lock().expect("local client state lock");
        let return_state = match &state.state {
            LocalClientState::Ready => LocalClientState::Ready,
            LocalClientState::Attached => LocalClientState::Attached,
            LocalClientState::CommandPending | LocalClientState::AttachPending => {
                // @constraint selvedge.client.local.request.state.busy Ready and command requests return Busy while another request is pending.
                return Err(LocalClientError::Busy);
            }
            // @constraint selvedge.client.local.request.state.closing Ready and command requests return Closing while close is pending.
            LocalClientState::Closing => return Err(LocalClientError::Closing),
            // @constraint selvedge.client.local.request.state.closed Ready and command requests return Closed after close completes.
            LocalClientState::Closed => return Err(LocalClientError::Closed),
            LocalClientState::Failed => {
                // @constraint selvedge.client.local.request.state.failed Ready and command requests return the recent client error after failure.
                return Err(state.recent_error.clone().unwrap_or(
                    LocalClientError::TransportFailed("client failed".to_owned()),
                ));
            }
            // @constraint selvedge.client.local.request.state.disconnected Ready and command requests return NotConnected from Disconnected state.
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
        // @constraint selvedge.client.local.attach.state Attach requests run only from Ready state and otherwise return typed state errors.
        let mut state = self.inner.lock().expect("local client state lock");
        let return_state = match &state.state {
            LocalClientState::Ready => LocalClientState::Ready,
            // @constraint selvedge.client.local.attach.state.already_attached Attach returns AlreadyAttached while an attach stream is active.
            LocalClientState::Attached => return Err(LocalClientError::AlreadyAttached),
            LocalClientState::CommandPending | LocalClientState::AttachPending => {
                // @constraint selvedge.client.local.attach.state.busy Attach returns Busy while another request is pending.
                return Err(LocalClientError::Busy);
            }
            // @constraint selvedge.client.local.attach.state.closing Attach returns Closing while close is pending.
            LocalClientState::Closing => return Err(LocalClientError::Closing),
            // @constraint selvedge.client.local.attach.state.closed Attach returns Closed after close completes.
            LocalClientState::Closed => return Err(LocalClientError::Closed),
            LocalClientState::Failed => {
                // @constraint selvedge.client.local.attach.state.failed Attach returns the recent client error after failure.
                return Err(state.recent_error.clone().unwrap_or(
                    LocalClientError::TransportFailed("client failed".to_owned()),
                ));
            }
            // @constraint selvedge.client.local.attach.state.disconnected Attach returns NotConnected from Disconnected state.
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

    // @behavior selvedge.client.local.request.finish.call Timed request completion returns successful responses, typed transport errors, or Timeout.
    fn finish_request_result<R>(
        &self,
        guard: RequestGuard,
        result: Result<Result<R, LocalClientError>, tokio::time::error::Elapsed>,
    ) -> Result<R, LocalClientError> {
        // @behavior selvedge.client.local.request.finish Timed request completion returns successful responses, typed transport errors, or Timeout.
        match result {
            Ok(Ok(response)) => {
                // @behavior selvedge.client.local.request.finish.success Successful ready and command requests return the transport response and restore the prior idle state.
                let return_state = guard.return_state.clone();
                guard.complete_as(return_state);
                Ok(response)
            }
            // @behavior selvedge.client.local.request.finish.error Transport client errors move the client to Failed and return the same error.
            Ok(Err(error)) => Err(self.finish_client_error(guard, error)),
            // @behavior selvedge.client.local.request.finish.timeout Timed out requests move the client to Failed and return Timeout.
            Err(_) => Err(self.finish_client_error(guard, LocalClientError::Timeout)),
        }
    }

    fn finish_client_error(
        &self,
        mut guard: RequestGuard,
        error: LocalClientError,
    ) -> LocalClientError {
        // @behavior selvedge.client.local.failure A client request error moves the client to Failed, stores the recent error, and closes the active attach stream.
        let active_stream = {
            let mut state = self.inner.lock().expect("local client state lock");
            // @behavior selvedge.client.local.failure.pending Client request failure changes state only while the guarded request is still pending.
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

// @behavior selvedge.client.local.request Ready and command requests use one pending state, one timeout, and typed success or error results.
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
        // @behavior selvedge.client.local.close.complete A completed close reports Closed, clears recent errors, and wakes the active attach stream reader.
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
        // @behavior selvedge.client.local.close.cancel A cancelled close restores the previous caller-visible state when close completion has not occurred.
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
        // @behavior selvedge.client.local.request.success A completed request returns to the caller-visible idle state and clears recent errors.
        let mut state = self.state.lock().expect("local client state lock");
        if state.state == self.pending {
            state.state = resolved_state(next_state, state.attach_open);
            state.recent_error = None;
        }
        self.active = false;
    }

    fn complete_attach_success(mut self, stream: SharedAttachStream) -> u64 {
        // @behavior selvedge.client.local.attach.generation A successful attach increments the active attach generation and stores the active frame stream.
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
        // @behavior selvedge.client.local.request.cancel A cancelled pending request restores the prior caller-visible state.
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

// @behavior selvedge.client.local.stream Attach stream ownership exposes one active frame reader and client-driven closure to callers.
impl Stream for ClientFrameStream {
    type Item = Result<LocalClientFrame, LocalClientError>;

    fn poll_next(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        // @behavior selvedge.client.local.stream.poll Polling an attach stream yields validated frames, typed stream errors, StreamClosed once, or end of stream after closure.
        let this = self.get_mut();
        // @behavior selvedge.client.local.stream.poll.after_closed Polling after the stream has reported closure returns end of stream.
        if this.closed_reported {
            return Poll::Ready(None);
        }
        // @behavior selvedge.client.local.stream.poll.client_closed Polling after client-driven closure drops the shared stream and returns end of stream.
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
            Poll::Ready(Some(Ok(frame))) => {
                // @behavior selvedge.client.local.stream.poll.frame Polling an attach stream returns protocol frames unchanged.
                Poll::Ready(Some(Ok(frame)))
            }
            Poll::Ready(Some(Err(error))) => {
                // @behavior selvedge.client.local.stream.poll.error Polling an errored attach stream clears attached state and returns the stream error once.
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
        // @behavior selvedge.client.local.stream.drop Dropping the active attach stream clears the attached state for that stream generation.
        clear_attached_state(&self.state, self.attach_generation);
    }
}

fn clear_attached_state(state: &Arc<Mutex<ClientState>>, attach_generation: u64) {
    // @behavior selvedge.client.local.stream.clear Clearing an active attach stream returns the client to Ready when the cleared generation is current.
    let active_stream = {
        let mut state = state.lock().expect("local client state lock");
        // @behavior selvedge.client.local.stream.clear.stale Clearing a stale attach generation leaves the current attach stream observable.
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

    // @behavior selvedge.client.local.stream.clear.drop Clearing the current attach state drops and wakes the active shared stream.
    if let Some(active_stream) = active_stream {
        drop_shared_attach_stream(&active_stream);
    }
}

fn drop_shared_attach_stream(stream: &SharedAttachStream) {
    // @behavior selvedge.client.local.stream.wake Closing a shared attach stream drops the inner stream and wakes a pending reader.
    let waker = {
        let mut stream = stream.lock().expect("local attach stream lock");
        let _ = stream.inner.take();
        stream.waker.take()
    };
    if let Some(waker) = waker {
        // @behavior selvedge.client.local.stream.wake.reader Closing a shared attach stream wakes a pending stream reader.
        waker.wake();
    }
}

fn stream_is_closed_by_client(state: &Arc<Mutex<ClientState>>, attach_generation: u64) -> bool {
    // @behavior selvedge.client.local.stream.closed_by_client An attach stream observes client-driven closure when the client is closed or its generation is no longer open.
    let state = state.lock().expect("local client state lock");
    state.state == LocalClientState::Closed
        || (state.attach_generation == attach_generation && !state.attach_open)
}

fn resolved_state(next_state: LocalClientState, attach_open: bool) -> LocalClientState {
    // @behavior selvedge.client.local.state.resolve Caller-visible state resolves Attached to Ready when no attach stream remains open.
    if next_state == LocalClientState::Attached && !attach_open {
        LocalClientState::Ready
    } else {
        next_state
    }
}

fn validate_endpoint(endpoint: &LocalEndpoint) -> Result<(), LocalClientError> {
    // @constraint selvedge.client.local.endpoint.valid Endpoint validation rejects port zero before any transport connection.
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

    // @behavior selvedge.client.local.http.stream.poll HTTP attach stream polling returns parsed frames, typed transport errors, or stream completion.
    fn poll_next(self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        // @behavior selvedge.client.local.http.stream HTTP attach streams parse each NDJSON line into a local client frame or typed transport error.
        let this = self.get_mut();
        // @behavior selvedge.client.local.http.stream.ended Polling an ended HTTP attach stream returns end of stream.
        if this.ended {
            return Poll::Ready(None);
        }

        match Pin::new(&mut this.lines).poll_next(context) {
            Poll::Ready(Some(Ok(line))) => Poll::Ready(Some(parse_attach_frame_line(
                line,
                &mut this.validator,
                &mut this.ended,
            ))),
            // @behavior selvedge.client.local.http.stream.io_error HTTP attach stream read errors end the stream and return TransportFailed.
            Poll::Ready(Some(Err(error))) => {
                this.ended = true;
                Poll::Ready(Some(Err(LocalClientError::TransportFailed(
                    error.to_string(),
                ))))
            }
            Poll::Ready(None) => {
                this.ended = true;
                // @behavior selvedge.client.local.http.stream.eof HTTP attach stream EOF marks the stream ended.
                Poll::Ready(None)
            }
            Poll::Pending => Poll::Pending,
        }
    }
}

// @behavior selvedge.client.local.http.post.call HTTP transport sends protocol requests as POST with JSON content type and the caller-requested Accept header.
async fn post_json<T: Serialize>(
    endpoint: &LocalEndpoint,
    path: &str,
    request: &T,
    accept: &str,
) -> Result<HttpResponse, LocalClientError> {
    // @behavior selvedge.client.local.http.post HTTP transport sends protocol requests as POST with JSON content type and the caller-requested Accept header.
    let body = serde_json::to_vec(request)
        .map_err(|error| LocalClientError::ProtocolValidationFailed(error.to_string()))?;
    // @behavior selvedge.client.local.http.post.connect HTTP POST returns ConnectFailed when the loopback TCP connection fails.
    let mut stream = TcpStream::connect(socket_target(endpoint))
        .await
        .map_err(|error| LocalClientError::ConnectFailed(error.to_string()))?;
    let request = format!(
        "POST {path} HTTP/1.1\r\nHost: {}\r\nContent-Type: {JSON_CONTENT_TYPE}\r\nAccept: {accept}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        host_header(endpoint),
        body.len()
    );

    // @behavior selvedge.client.local.http.post.headers HTTP POST returns TransportFailed when request headers cannot be written.
    let header_write = stream.write_all(request.as_bytes()).await;
    header_write.map_err(|error| LocalClientError::TransportFailed(error.to_string()))?;
    let body_write = stream.write_all(&body).await;
    // @behavior selvedge.client.local.http.post.body HTTP POST returns TransportFailed when the JSON body cannot be written.
    body_write.map_err(|error| LocalClientError::TransportFailed(error.to_string()))?;
    let flush_result = stream.flush().await;
    // @behavior selvedge.client.local.http.post.flush HTTP POST returns TransportFailed when the request cannot be flushed.
    flush_result.map_err(|error| LocalClientError::TransportFailed(error.to_string()))?;

    read_response_headers(stream).await
}

async fn read_response_headers(stream: TcpStream) -> Result<HttpResponse, LocalClientError> {
    // @behavior selvedge.client.local.http.headers HTTP transport reads status and content type before exposing the response body reader.
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
            // @behavior selvedge.client.local.transport.content_type Parsed HTTP responses expose a lowercased content type when the server sends a Content-Type header.
            content_type = Some(value.trim().to_ascii_lowercase());
        }
    }

    // @behavior selvedge.client.local.transport.response Parsed HTTP responses expose status, content type, and body reader to local client calls.
    Ok(HttpResponse {
        status_code,
        content_type,
        reader,
    })
}

// @behavior selvedge.client.local.http.header_line.call HTTP header reading reports closed connections as TransportClosed and I/O failures as TransportFailed.
async fn read_header_line(
    reader: &mut BufReader<OwnedReadHalf>,
    line: &mut String,
) -> Result<(), LocalClientError> {
    // @behavior selvedge.client.local.http.header_line HTTP header reading reports closed connections as TransportClosed and I/O failures as TransportFailed.
    let bytes = reader
        .read_line(line)
        .await
        .map_err(|error| LocalClientError::TransportFailed(error.to_string()))?;
    // @behavior selvedge.client.local.http.header_line.closed HTTP header reading returns TransportClosed when the peer closes before a header line is read.
    if bytes == 0 {
        return Err(LocalClientError::TransportClosed);
    }

    Ok(())
}

// @behavior selvedge.client.local.http.status HTTP status parsing returns the numeric status code or a TransportFailed parse error.
fn parse_status_code(status_line: &str) -> Result<u16, LocalClientError> {
    status_line
        .split_whitespace()
        .nth(1)
        .ok_or_else(|| LocalClientError::TransportFailed("missing HTTP status code".to_owned()))?
        .parse()
        .map_err(|error| LocalClientError::TransportFailed(format!("invalid HTTP status: {error}")))
}

// @behavior selvedge.client.local.http.json_body.call JSON body parsing requires application/json and returns validated JSON responses or protocol errors.
async fn parse_json_body<T: DeserializeOwned>(
    mut response: HttpResponse,
) -> Result<T, LocalClientError> {
    // @behavior selvedge.client.local.http.json_body JSON body parsing requires application/json and returns validated JSON responses or protocol errors.
    require_content_type(&response, JSON_CONTENT_TYPE)?;
    let mut body = Vec::new();
    response
        .reader
        .read_to_end(&mut body)
        .await
        .map_err(|error| LocalClientError::TransportFailed(error.to_string()))?;

    // @behavior selvedge.client.local.http.json_body.status Non-200 JSON responses return a parsed problem message or an unexpected status transport error.
    if response.status_code != 200 {
        return Err(parse_problem(&body).unwrap_or_else(|| {
            LocalClientError::TransportFailed(format!(
                "unexpected HTTP status {}",
                response.status_code
            ))
        }));
    }

    // @behavior selvedge.client.local.http.json_body.parse JSON response body parsing returns ProtocolValidationFailed for invalid response JSON.
    serde_json::from_slice(&body)
        .map_err(|error| LocalClientError::ProtocolValidationFailed(error.to_string()))
}

// @behavior selvedge.client.local.http.attach_reject.call Attach rejection parsing returns a typed server rejection or a typed client-side error.
async fn parse_attach_rejected_response(
    mut response: HttpResponse,
    expected_command_id: selvedge_local_protocol::LocalClientCommandId,
) -> Result<(AttachAccepted, LocalFrameStream), AttachRejectedOrClientError> {
    // @behavior selvedge.client.local.http.attach_reject Attach rejection parsing returns a typed server rejection when command identity matches.
    require_content_type(&response, JSON_CONTENT_TYPE)
        .map_err(AttachRejectedOrClientError::Client)?;
    let mut body = Vec::new();
    let body_read = response.reader.read_to_end(&mut body).await;
    // @behavior selvedge.client.local.http.attach_reject.body Attach rejection parsing returns a client transport error when the rejection body cannot be read.
    body_read.map_err(|error| {
        AttachRejectedOrClientError::Client(LocalClientError::TransportFailed(error.to_string()))
    })?;

    match serde_json::from_slice::<AttachRejected>(&body) {
        Ok(rejected) => {
            // @constraint selvedge.client.local.http.attach_reject.identity Attach rejection responses must carry the requested client command ID.
            if rejected.client_command_id != expected_command_id {
                // @constraint selvedge.client.local.http.attach_reject.identity_error Identity mismatches in attach rejection responses return ProtocolValidationFailed.
                return Err(AttachRejectedOrClientError::Client(
                    LocalClientError::ProtocolValidationFailed(
                        "attach rejected identity mismatch".to_owned(),
                    ),
                ));
            }
            // @behavior selvedge.client.local.http.attach_reject.rejected Valid attach rejection bodies return the server rejection to callers.
            Err(AttachRejectedOrClientError::Rejected(rejected))
        }
        Err(_) => {
            // @behavior selvedge.client.local.http.attach_reject.invalid Invalid attach rejection bodies return a parsed problem or ProtocolValidationFailed.
            Err(AttachRejectedOrClientError::Client(
                parse_problem(&body).unwrap_or_else(|| {
                    LocalClientError::ProtocolValidationFailed(
                        "invalid attach reject body".to_owned(),
                    )
                }),
            ))
        }
    }
}

// @behavior selvedge.client.local.http.attach_accept.call Attach acceptance parsing requires an NDJSON stream that starts with a matching accepted item.
async fn parse_attach_accepted_stream(
    response: HttpResponse,
    expected_client_id: selvedge_local_protocol::LocalClientId,
    expected_command_id: selvedge_local_protocol::LocalClientCommandId,
) -> Result<(AttachAccepted, LocalFrameStream), LocalClientError> {
    // @behavior selvedge.client.local.http.attach_accept Attach acceptance parsing requires an NDJSON stream that starts with a matching accepted item.
    require_content_type(&response, NDJSON_CONTENT_TYPE)?;
    let mut lines = LinesStream::new(response.reader.lines());
    // @behavior selvedge.client.local.http.attach_accept.empty Empty attach acceptance streams return TransportClosed.
    let Some(first) = lines.next().await else {
        return Err(LocalClientError::TransportClosed);
    };
    let first = first.map_err(|error| LocalClientError::TransportFailed(error.to_string()))?;
    let item = parse_attach_stream_item(&first)?;
    validate_attach_stream_item(&item)
        .map_err(|error| LocalClientError::ProtocolValidationFailed(format!("{error:?}")))?;
    let mut validator = LocalAttachStreamValidator::new();
    // @constraint selvedge.client.local.http.attach_accept.sequence_errors Attach acceptance stream validation errors are returned as transport failures before frames are exposed.
    let sequence_result = validator.validate_next(&item);
    sequence_result.map_err(|error| LocalClientError::TransportFailed(format!("{error:?}")))?;

    // @constraint selvedge.client.local.http.attach_accept.first_item Attach acceptance streams must begin with an accepted item.
    let LocalAttachStreamItem::Accepted(accepted) = item else {
        return Err(LocalClientError::TransportFailed(
            "attach stream must start with accepted item".to_owned(),
        ));
    };
    // @constraint selvedge.client.local.http.attach_accept.identity Attach accepted responses must carry the requested client and command identity.
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

// @behavior selvedge.client.local.http.frame_line.call Attach frame line parsing returns frames, stream errors, or duplicate-acceptance protocol failures.
fn parse_attach_frame_line(
    line: String,
    validator: &mut LocalAttachStreamValidator,
    ended: &mut bool,
) -> Result<LocalClientFrame, LocalClientError> {
    // @behavior selvedge.client.local.http.frame_line Attach frame line parsing returns frames, stream errors, or duplicate-acceptance protocol failures.
    let item = parse_attach_stream_item(&line)?;
    validate_attach_stream_item(&item)
        .map_err(|error| LocalClientError::ProtocolValidationFailed(format!("{error:?}")))?;
    validator
        .validate_next(&item)
        .map_err(|error| LocalClientError::TransportFailed(format!("{error:?}")))?;

    match item {
        // @behavior selvedge.client.local.http.frame_line.frame Attach frame lines expose frame items as local client frames.
        LocalAttachStreamItem::Frame(frame) => Ok(frame),
        LocalAttachStreamItem::StreamError(error) => {
            *ended = true;
            // @behavior selvedge.client.local.http.frame_line.stream_error Attach stream error items end the stream and return TransportFailed with the message text.
            Err(LocalClientError::TransportFailed(error.message_text))
        }
        // @constraint selvedge.client.local.http.frame_line.accepted_late Attach frame lines return TransportFailed for duplicate accepted items.
        LocalAttachStreamItem::Accepted(_) => Err(LocalClientError::TransportFailed(
            "duplicate attach accepted item".to_owned(),
        )),
    }
}

fn parse_attach_stream_item(line: &str) -> Result<LocalAttachStreamItem, LocalClientError> {
    // @behavior selvedge.client.local.http.stream_item Attach stream item parsing exposes invalid NDJSON lines as protocol validation failures.
    serde_json::from_str(line)
        .map_err(|error| LocalClientError::ProtocolValidationFailed(error.to_string()))
}

fn require_content_type(response: &HttpResponse, expected: &str) -> Result<(), LocalClientError> {
    // @constraint selvedge.client.local.http.content_type HTTP responses must include the expected media type before their bodies are parsed.
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

    // @constraint selvedge.client.local.http.content_type.unexpected HTTP responses with unexpected media types return ProtocolValidationFailed.
    Err(LocalClientError::ProtocolValidationFailed(format!(
        "unexpected content type {content_type}"
    )))
}

fn parse_problem(body: &[u8]) -> Option<LocalClientError> {
    // @behavior selvedge.client.local.http.problem Local HTTP problem bodies map to TransportFailed messages.
    serde_json::from_slice::<LocalHttpProblem>(body)
        .ok()
        .map(|problem| LocalClientError::TransportFailed(problem.message_text))
}

fn socket_target(endpoint: &LocalEndpoint) -> String {
    // @behavior selvedge.client.local.endpoint.socket Endpoint socket targets render as loopback IPv4 or IPv6 addresses with the configured port.
    match endpoint {
        LocalEndpoint::TcpIpv4 { port } => format!("127.0.0.1:{port}"),
        LocalEndpoint::TcpIpv6 { port } => format!("[::1]:{port}"),
    }
}

fn host_header(endpoint: &LocalEndpoint) -> String {
    // @behavior selvedge.client.local.endpoint.host_header Endpoint host headers render as loopback IPv4 or IPv6 hosts with the configured port.
    match endpoint {
        LocalEndpoint::TcpIpv4 { port } => format!("127.0.0.1:{port}"),
        LocalEndpoint::TcpIpv6 { port } => format!("[::1]:{port}"),
    }
}
