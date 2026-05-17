#![doc = include_str!("../README.md")]
//! @behavior selvedge.client.web The web surface exposes localhost readiness, command, attach streaming, lifecycle, and HTTP problem behavior.
//! @behavior selvedge.client.web.spawn The web surface binds localhost HTTP routes for readiness, commands, and attach frame streaming until stopped or failed.
//! @behavior selvedge.client.web.r2 Web processing preserves localhost HTTP readiness, command, attach streaming, lifecycle, and problem response behavior.

use std::future::Future;
use std::io;
use std::net::{Ipv4Addr, Ipv6Addr, TcpListener as StdTcpListener};
use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Poll};
use std::time::Duration;

use futures_core::Stream;
use selvedge_local_protocol::{
    AttachAccepted, AttachRejectReason, AttachRejected, AttachRequest, CommandOutcome,
    CommandRejectReason, CommandRequest, CommandResponse, LocalAttachStreamItem,
    LocalClientCommandId, LocalClientFrame, LocalHttpProblemCode, LocalStreamError,
    LocalStreamErrorReason, ReadyRequest, ReadyResponse, ReadyState, http_problem,
    validate_attach_request, validate_command_request, validate_ready_request,
};
use serde::Serialize;
use serde::de::DeserializeOwned;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::watch;
use tokio::task::JoinHandle;
// @behavior selvedge.client.web.r2.request_timeout Web HTTP request reads apply bounded timeouts to stalled local client connections.
use tokio::time::timeout;
use tokio_stream::StreamExt;
use tokio_stream::wrappers::WatchStream;

const JSON_CONTENT_TYPE: &str = "application/json";
const NDJSON_CONTENT_TYPE: &str = "application/x-ndjson";
const MAX_HTTP_HEADER_BYTES: usize = 16 * 1024;
const MAX_HTTP_BODY_BYTES: usize = 4 * 1024 * 1024;
const HTTP_REQUEST_READ_TIMEOUT: Duration = Duration::from_secs(5);

// @behavior selvedge.client.web.r2.start_args Web startup receives a localhost bind target and server bridge from the caller.
pub struct WebStartArgs {
    // @behavior selvedge.client.web.r2.start_args.bind Web startup binds the supplied localhost host and port for local HTTP routes.
    pub bind: WebLocalhostBind,
    // @behavior selvedge.client.web.r2.start_args.bridge Web startup forwards readiness, command, and attach requests through the supplied server bridge.
    pub bridge: Arc<dyn WebBridge>,
}

// @behavior selvedge.client.web.r2.reserved_start_args Web reserved startup receives an already reserved localhost listener and server bridge from the caller.
pub struct ReservedWebStartArgs {
    // @behavior selvedge.client.web.r2.reserved_start_args.bind Web reserved startup uses the supplied listener reservation as the local HTTP listener.
    pub bind: WebBindReservation,
    // @behavior selvedge.client.web.r2.reserved_start_args.bridge Web reserved startup forwards local HTTP route work through the supplied server bridge.
    pub bridge: Arc<dyn WebBridge>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.client.web.r2.localhost_bind Web bind settings identify the loopback host family and TCP port used by the local HTTP surface.
pub struct WebLocalhostBind {
    // @behavior selvedge.client.web.r2.localhost_bind.host Web bind settings select IPv4 or IPv6 loopback for the local HTTP listener.
    pub host: WebLocalhostHost,
    // @behavior selvedge.client.web.r2.localhost_bind.port Web bind settings select the TCP port used by the local HTTP listener.
    pub port: u16,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.client.web.r2.localhost_host Web localhost host settings restrict HTTP serving to IPv4 or IPv6 loopback addresses.
pub enum WebLocalhostHost {
    Ipv4Loopback,
    Ipv6Loopback,
}

// @behavior selvedge.client.web.r2.bind_reservation Web bind reservations keep a localhost listener reserved until the web surface starts.
pub struct WebBindReservation {
    bind: WebLocalhostBind,
    listener: StdTcpListener,
}

// @behavior selvedge.client.web.r2.handle Web startup returns a control handle and join handle for lifecycle observation and shutdown.
pub struct WebHandle {
    // @behavior selvedge.client.web.r2.handle.control Web startup returns a control handle for readiness, command, attach, state, and stop operations.
    pub control: WebControl,
    // @behavior selvedge.client.web.r2.handle.join Web startup returns a join handle that resolves to the web surface exit status.
    pub join_handle: JoinHandle<WebExitStatus>,
}

#[derive(Clone)]
// @behavior selvedge.client.web.r2.control Web control exposes readiness, command submission, attach streaming, state inspection, and stop operations.
pub struct WebControl {
    inner: Arc<WebControlInner>,
}

// @intent selvedge.client.web.r2.control_inner Web control state stores the runtime state sender and server bridge used by every localhost control operation.
struct WebControlInner {
    state_tx: watch::Sender<WebRuntimeState>,
    bridge: Arc<dyn WebBridge>,
}

// @intent selvedge.client.web.r2.frame_stream_type Web frame streams expose attach frames as an asynchronous localhost response body.
// @behavior selvedge.client.web.r2.frame_stream Web frame streams yield local client frames or bridge errors for attach responses.
pub type WebFrameStream =
    Pin<Box<dyn Stream<Item = Result<LocalClientFrame, WebBridgeError>> + Send>>;
// @behavior selvedge.client.web.r2.bridge_future Web bridge futures resolve readiness and command requests into protocol responses or bridge errors.
pub type WebBridgeFuture<T> = Pin<Box<dyn Future<Output = Result<T, WebBridgeError>> + Send>>;
// @behavior selvedge.client.web.r2.attach_future Web attach futures resolve attach requests into accepted frame streams, attach rejections, or bridge errors.
pub type WebAttachFuture = Pin<
    Box<
        // @intent selvedge.client.web.r2.attach_future.intent The web attach future type carries server-owned attach results across the localhost HTTP boundary.
        dyn Future<Output = Result<(AttachAccepted, WebFrameStream), AttachRejectedOrBridgeError>>
            + Send,
    >,
>;

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.client.web.r2.runtime_state Web runtime states expose binding, listening, closing, stopped, and failed lifecycle phases.
pub enum WebRuntimeState {
    Binding,
    Listening,
    Closing,
    Stopped,
    Failed,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.client.web.r2.exit_status Web exit status reports a clean stop or fatal listener failure to the join handle caller.
pub enum WebExitStatus {
    Stopped,
    // @behavior selvedge.client.web.r2.exit_status.fatal Web exit status reports fatal listener failure text to the join handle caller.
    Fatal(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.client.web.r2.start_error Web startup returns typed errors for invalid bind targets, listener binding failures, and Tokio runtime failures.
pub enum WebStartError {
    InvalidBindTarget,
    // @behavior selvedge.client.web.r2.start_error.bind_failed Web startup reports listener bind failure text as BindFailed.
    BindFailed(String),
    TokioSpawnFailed,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.client.web.r2.bridge_error Web bridge errors report readiness, validation, command, attach, stream, and internal failure outcomes across the web boundary.
pub enum WebBridgeError {
    ServerNotReady,
    ProtocolValidationFailed,
    // @behavior selvedge.client.web.r2.bridge_error.command_rejected Web bridge errors carry command rejection text across the web boundary.
    CommandRejected(String),
    // @behavior selvedge.client.web.r2.bridge_error.attach_rejected Web bridge errors carry attach rejection text across the web boundary.
    AttachRejected(String),
    StreamClosed,
    // @behavior selvedge.client.web.r2.bridge_error.internal_failure Web bridge errors carry internal failure text across the web boundary.
    InternalFailure(String),
}

// @behavior selvedge.client.web.r2.bridge Web bridges answer readiness, command, and attach requests with local protocol results or typed bridge errors.
// @intent selvedge.client.web.r2.bridge.intent The web bridge isolates localhost HTTP handling from server-owned routing and runtime state.
pub trait WebBridge: Send + Sync + 'static {
    /// @behavior selvedge.client.web.r2.bridge_ready Web readiness requests are delegated to the server bridge and return a ready or not-ready protocol response.
    fn ready(&self, request: ReadyRequest) -> WebBridgeFuture<ReadyResponse>;
    /// @behavior selvedge.client.web.r2.bridge_submit_command Web command requests are delegated to the server bridge and return an accepted or rejected command response.
    fn submit_command(&self, request: CommandRequest) -> WebBridgeFuture<CommandResponse>;
    /// @behavior selvedge.client.web.r2.bridge_attach Web attach requests are delegated to the server bridge and return accepted frames or an attach rejection.
    fn attach(&self, request: AttachRequest) -> WebAttachFuture;
}

#[derive(Debug)]
// @behavior selvedge.client.web.r2.attach_result Web attach operations return protocol rejections separately from bridge failures.
pub enum AttachRejectedOrBridgeError {
    // @behavior selvedge.client.web.r2.attach_result.rejected Web attach operations return protocol attach rejections to local clients.
    Rejected(AttachRejected),
    // @behavior selvedge.client.web.r2.attach_result.bridge_error Web attach operations return bridge failures for internal HTTP problem responses.
    Bridge(WebBridgeError),
}

// @behavior selvedge.client.web.r2.spawn_entry Web startup reserves the requested localhost bind target and starts the HTTP surface.
pub fn spawn_web_surface(args: WebStartArgs) -> Result<WebHandle, WebStartError> {
    let bind = reserve_web_bind(args.bind)?;
    spawn_reserved_web_surface(ReservedWebStartArgs {
        bind,
        bridge: args.bridge,
    })
}

// @behavior selvedge.client.web.r2.reserve_bind Web bind reservation opens a nonblocking loopback listener for a nonzero port or returns a typed startup error.
pub fn reserve_web_bind(bind: WebLocalhostBind) -> Result<WebBindReservation, WebStartError> {
    if bind.port == 0 {
        // @behavior selvedge.client.web.r2.reserve_bind.zero_port Web bind reservation rejects port zero with InvalidBindTarget.
        return Err(WebStartError::InvalidBindTarget);
    }
    let listener = bind_localhost(&bind)?;
    Ok(WebBindReservation { bind, listener })
}

// @behavior selvedge.client.web.r2.spawn_reserved Web reserved startup starts accepting local HTTP connections from a reserved listener and returns a lifecycle handle.
pub fn spawn_reserved_web_surface(args: ReservedWebStartArgs) -> Result<WebHandle, WebStartError> {
    if args.bind.bind.port == 0 {
        // @behavior selvedge.client.web.r2.spawn_reserved.zero_port Web reserved startup rejects a zero-port reservation with InvalidBindTarget.
        return Err(WebStartError::InvalidBindTarget);
    }

    let handle =
// @behavior selvedge.client.web.r2.spawn_reserved.runtime Web reserved startup returns TokioSpawnFailed when no Tokio runtime handle is available.
        tokio::runtime::Handle::try_current().map_err(|_| WebStartError::TokioSpawnFailed)?;
    let listener =
// @behavior selvedge.client.web.r2.spawn_reserved.listener Web reserved startup returns TokioSpawnFailed when the reserved listener cannot become a Tokio listener.
        TcpListener::from_std(args.bind.listener).map_err(|_| WebStartError::TokioSpawnFailed)?;
    let (state_tx, mut state_rx) = watch::channel(WebRuntimeState::Listening);
    let control = WebControl {
        inner: Arc::new(WebControlInner {
            state_tx,
            bridge: args.bridge,
        }),
    };
    let task_control = control.clone();
    let join_handle = handle.spawn(async move {
        loop {
            tokio::select! {
                state_change = state_rx.changed() => {
                    if state_change.is_err() || *state_rx.borrow() == WebRuntimeState::Closing {
                        break;
                    }
                }
                accepted = listener.accept() => {
                    match accepted {
                        Ok((stream, _addr)) => {
                            let connection_control = task_control.clone();
                            tokio::spawn(async move {
                                let _ = handle_http_connection(connection_control, stream).await;
                            });
                        }
                        // NOTE: The web surface owns a long-lived localhost listener. The package
                        // state machine classifies listener accept errors as surface failures so
                        // callers observe the failed state and restart through server lifecycle.
// @behavior selvedge.client.web.r2.accept_failure Web serving reports a fatal exit status and failed runtime state when listener accept fails.
                        Err(error) => return fail_web_surface(&task_control, error),
                    }
                }
            }
        }
// @behavior selvedge.client.web.r2.stop_status Web serving reports Stopped after control shutdown ends listener acceptance.
        let _ = task_control.inner.state_tx.send(WebRuntimeState::Stopped);
        WebExitStatus::Stopped
    });

    Ok(WebHandle {
        control,
        join_handle,
    })
}

fn fail_web_surface(control: &WebControl, error: io::Error) -> WebExitStatus {
    // @behavior selvedge.client.web.r2.fail_surface Web serving moves runtime state to Failed and returns Fatal when listener failure occurs.
    let _ = control.inner.state_tx.send(WebRuntimeState::Failed);
    WebExitStatus::Fatal(error.to_string())
}

impl WebControl {
    // @behavior selvedge.client.web.r2.control.state Web control returns the current web runtime state to callers.
    pub async fn state(&self) -> WebRuntimeState {
        self.inner.state_tx.borrow().clone()
    }

    // @behavior selvedge.client.web.r2.control.ready Web control returns bridge readiness responses and maps invalid readiness probes to not-ready responses.
    pub async fn ready(&self, request: ReadyRequest) -> Result<ReadyResponse, WebBridgeError> {
        self.ensure_listening()?;
        if validate_ready_request(&request).is_err() {
            return Ok(not_ready_response());
        }

        match self.inner.bridge.ready(request).await {
            Ok(response) => Ok(response),
            // @behavior selvedge.client.web.r2.control.ready.not_ready Web control maps server-not-ready and protocol-validation bridge errors to not-ready responses.
            Err(WebBridgeError::ServerNotReady) | Err(WebBridgeError::ProtocolValidationFailed) => {
                Ok(not_ready_response())
            }
            // @behavior selvedge.client.web.r2.control.ready.bridge_error Web control returns other readiness bridge errors to callers.
            Err(error) => Err(error),
        }
    }

    // @behavior selvedge.client.web.r2.control.submit_command Web control validates command requests and returns accepted or rejected local protocol command responses.
    pub async fn submit_command(
        &self,
        request: CommandRequest,
    ) -> Result<CommandResponse, WebBridgeError> {
        self.ensure_listening()?;
        let client_command_id = request.client_command_id.clone();
        if validate_command_request(&request).is_err() {
            let reason = CommandRejectReason::MalformedRequest;
            return Ok(rejected_command_response(client_command_id, reason));
        }

        match self.inner.bridge.submit_command(request).await {
            Ok(response) => Ok(response),
            // @behavior selvedge.client.web.r2.control.submit_command.server_not_ready Web control maps server-not-ready command bridge errors to rejected command responses.
            Err(WebBridgeError::ServerNotReady) => Ok(rejected_command_response(
                client_command_id,
                CommandRejectReason::ServerNotReady,
            )),
            // @behavior selvedge.client.web.r2.control.submit_command.validation_failed Web control maps command protocol validation bridge errors to malformed request rejections.
            Err(WebBridgeError::ProtocolValidationFailed) => Ok(rejected_command_response(
                client_command_id,
                CommandRejectReason::MalformedRequest,
            )),
            // @behavior selvedge.client.web.r2.control.submit_command.bridge_error Web control returns other command bridge errors to callers.
            Err(error) => Err(error),
        }
    }

    // @behavior selvedge.client.web.r2.control.attach Web control validates attach requests and returns accepted wrapped frame streams or attach rejections.
    pub async fn attach(
        &self,
        request: AttachRequest,
        // @behavior selvedge.client.web.r2.control.attach.request Web control uses the supplied attach request as the local protocol attach input.
    ) -> Result<(AttachAccepted, WebFrameStream), AttachRejectedOrBridgeError> {
        self.ensure_listening()
            // @behavior selvedge.client.web.r2.control.attach.closing Web control returns a bridge error when attach is requested after the surface begins closing.
            .map_err(AttachRejectedOrBridgeError::Bridge)?;
        let client_command_id = request.client_command_id.clone();
        if validate_attach_request(&request).is_err() {
            let reason = AttachRejectReason::MalformedRequest;
            // @behavior selvedge.client.web.r2.control.attach.invalid_request Web control returns an attach rejection when local protocol attach validation fails.
            return Err(AttachRejectedOrBridgeError::Rejected(AttachRejected {
                client_command_id,
                reason,
            }));
        }

        match self.inner.bridge.attach(request).await {
            Ok((accepted, stream)) => Ok((accepted, self.wrap_frame_stream(stream))),
            // @behavior selvedge.client.web.r2.control.attach.server_not_ready Web control maps server-not-ready attach bridge errors to attach rejections.
            Err(AttachRejectedOrBridgeError::Bridge(WebBridgeError::ServerNotReady)) => {
                // @behavior selvedge.client.web.r2.control.attach.server_not_ready_response Web control returns ServerNotReady as the attach rejection reason.
                Err(AttachRejectedOrBridgeError::Rejected(AttachRejected {
                    client_command_id,
                    reason: AttachRejectReason::ServerNotReady,
                }))
            }
            // @behavior selvedge.client.web.r2.control.attach.validation_failed Web control maps attach protocol validation bridge errors to attach rejections.
            Err(AttachRejectedOrBridgeError::Bridge(WebBridgeError::ProtocolValidationFailed)) => {
                // @behavior selvedge.client.web.r2.control.attach.validation_failed_response Web control returns MalformedRequest as the attach rejection reason.
                Err(AttachRejectedOrBridgeError::Rejected(AttachRejected {
                    client_command_id,
                    reason: AttachRejectReason::MalformedRequest,
                }))
            }
            // @behavior selvedge.client.web.r2.control.attach.bridge_error Web control returns other attach bridge errors to callers.
            Err(error) => Err(error),
        }
    }

    // @behavior selvedge.client.web.r2.control.stop Web control stop moves the runtime toward closing so listener acceptance and wrapped attach streams end.
    pub async fn stop(&self) {
        // @behavior selvedge.client.web.r2.control.stop.signal Web control stop sends the Closing runtime state to listener and stream observers.
        let _ = self.inner.state_tx.send(WebRuntimeState::Closing);
    }

    fn ensure_listening(&self) -> Result<(), WebBridgeError> {
        if *self.inner.state_tx.borrow() == WebRuntimeState::Listening {
            Ok(())
        } else {
            // @behavior selvedge.client.web.r2.control.closed_operation Web control operations return InternalFailure after the surface leaves Listening.
            Err(WebBridgeError::InternalFailure(
                "web surface is closing".to_owned(),
            ))
        }
    }

    fn wrap_frame_stream(&self, inner: WebFrameStream) -> WebFrameStream {
        Box::pin(WebBrowserFrameStream {
            inner,
            state_stream: WatchStream::new(self.inner.state_tx.subscribe()),
            closed_after_error: false,
        })
    }
}

struct WebBrowserFrameStream {
    inner: WebFrameStream,
    state_stream: WatchStream<WebRuntimeState>,
    closed_after_error: bool,
}

impl Stream for WebBrowserFrameStream {
    type Item = Result<LocalClientFrame, WebBridgeError>;

    fn poll_next(self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let this = self.get_mut();
        if this.closed_after_error {
            return Poll::Ready(None);
        }

        loop {
            match Pin::new(&mut this.state_stream).poll_next(context) {
                Poll::Ready(Some(
                    WebRuntimeState::Closing | WebRuntimeState::Stopped | WebRuntimeState::Failed,
                )) => return Poll::Ready(None),
                Poll::Ready(Some(_)) => {}
                Poll::Ready(None) => return Poll::Ready(None),
                Poll::Pending => break,
            }
        }

        match this.inner.as_mut().poll_next(context) {
            // @behavior selvedge.client.web.r2.frame_stream.error Web frame streams yield the first bridge stream error to attach clients.
            Poll::Ready(Some(Err(error))) => {
                this.closed_after_error = true;
                // @behavior selvedge.client.web.r2.frame_stream.close_after_error Web frame streams close after reporting a bridge stream error once.
                Poll::Ready(Some(Err(error)))
            }
            Poll::Ready(item) => Poll::Ready(item),
            Poll::Pending => Poll::Pending,
        }
    }
}

// @behavior selvedge.client.web.r2.rejected_command_response Rejected web command responses preserve the request command ID and rejection reason.
fn rejected_command_response(
    client_command_id: selvedge_local_protocol::LocalClientCommandId,
    reason: CommandRejectReason,
) -> CommandResponse {
    CommandResponse {
        client_command_id,
        outcome: CommandOutcome::Rejected(reason),
    }
}

fn not_ready_response() -> ReadyResponse {
    ReadyResponse {
        state: ReadyState::NotReady,
    }
}

#[derive(Debug)]
struct HttpRequest {
    method: String,
    path: String,
    content_type: Option<String>,
    body: Vec<u8>,
}

enum JsonRequestParseError {
    UnsupportedContentType,
    MalformedJson,
}

// @behavior selvedge.client.web.r2.http Web HTTP handling routes local readiness, command, and attach requests to JSON responses, NDJSON streams, or problem responses.
async fn handle_http_connection(mut control: WebControl, mut stream: TcpStream) -> io::Result<()> {
    let request = match read_http_request(&mut stream).await? {
        Ok(request) => request,
        // @behavior selvedge.client.web.r2.http.body_too_large Web HTTP connections return a 413 problem response when headers or body size exceeds configured limits.
        Err(HttpRequestReadError::BodyTooLarge) => {
            return write_problem_response(
                &mut stream,
                413,
                LocalHttpProblemCode::BodyTooLarge,
                "request body too large",
            )
            .await;
        }
    };
    match request.path.as_str() {
        "/selvedge/local/v1/ready" => handle_ready_route(&control, &mut stream, request).await,
        "/selvedge/local/v1/command" => handle_command_route(&control, &mut stream, request).await,
        "/selvedge/local/v1/attach" => {
            handle_attach_route(&mut control, &mut stream, request).await
        }
        _ => {
            write_problem_response(
                &mut stream,
                404,
                LocalHttpProblemCode::RouteNotFound,
                "route not found",
            )
            .await
        }
    }
}

async fn handle_ready_route(
    control: &WebControl,
    stream: &mut TcpStream,
    request: HttpRequest,
    // @behavior selvedge.client.web.r2.http.ready_route Web ready route accepts POST JSON readiness requests and writes JSON readiness responses or problem responses.
) -> io::Result<()> {
    if request.method != "POST" {
        return write_problem_response(
            stream,
            405,
            LocalHttpProblemCode::MethodNotAllowed,
            "method not allowed",
        )
        .await;
    }
    let ready_request = match parse_json_request::<ReadyRequest>(&request) {
        Ok(request) => request,
        // @behavior selvedge.client.web.r2.http.ready_route.parse_error Web ready route converts JSON parse failures into local HTTP problem responses.
        Err(error) => return write_json_parse_error(stream, error, "ready").await,
    };
    match control.ready(ready_request).await {
        Ok(response) => write_json_response(stream, 200, &response).await,
        // @behavior selvedge.client.web.r2.http.ready_route.bridge_error Web ready route converts readiness bridge errors into 500 local HTTP problem responses.
        Err(error) => {
            write_problem_response(
                stream,
                500,
                LocalHttpProblemCode::InternalFailure,
                format!("{error:?}"),
            )
            .await
        }
    }
}

async fn handle_command_route(
    control: &WebControl,
    stream: &mut TcpStream,
    request: HttpRequest,
    // @behavior selvedge.client.web.r2.http.command_route Web command route accepts POST JSON command requests and writes JSON command responses or problem responses.
) -> io::Result<()> {
    if request.method != "POST" {
        return write_problem_response(
            stream,
            405,
            LocalHttpProblemCode::MethodNotAllowed,
            "method not allowed",
        )
        .await;
    }
    let command_request = match parse_json_request::<CommandRequest>(&request) {
        Ok(request) => request,
        // @behavior selvedge.client.web.r2.http.command_route.parse_error Web command route converts JSON parse failures into local HTTP problem responses.
        Err(error) => return write_json_parse_error(stream, error, "command").await,
    };
    match control.submit_command(command_request).await {
        Ok(response) => write_json_response(stream, 200, &response).await,
        // @behavior selvedge.client.web.r2.http.command_route.bridge_error Web command route converts command bridge errors into 500 local HTTP problem responses.
        Err(error) => {
            write_problem_response(
                stream,
                500,
                LocalHttpProblemCode::InternalFailure,
                format!("{error:?}"),
            )
            .await
        }
    }
}

async fn handle_attach_route(
    control: &mut WebControl,
    stream: &mut TcpStream,
    request: HttpRequest,
    // @behavior selvedge.client.web.r2.http.attach_route Web attach route accepts POST JSON attach requests and writes accepted NDJSON streams, JSON rejections, or problem responses.
) -> io::Result<()> {
    if request.method != "POST" {
        return write_problem_response(
            stream,
            405,
            LocalHttpProblemCode::MethodNotAllowed,
            "method not allowed",
        )
        .await;
    }
    let attach_request = match parse_json_request::<AttachRequest>(&request) {
        Ok(request) => request,
        // @behavior selvedge.client.web.r2.http.attach_route.parse_error Web attach route converts JSON parse failures into local HTTP problem responses.
        Err(error) => return write_json_parse_error(stream, error, "attach").await,
    };
    let client_command_id = attach_request.client_command_id.clone();
    match control.attach(attach_request).await {
        Ok((accepted, mut frames)) => {
            write_stream_headers(stream).await?;
            write_attach_stream_item(stream, &LocalAttachStreamItem::Accepted(accepted)).await?;
            while let Some(frame) = next_web_frame(&mut frames, &client_command_id).await {
                write_attach_stream_item(stream, &frame).await?;
                if matches!(frame, LocalAttachStreamItem::StreamError(_)) {
                    break;
                }
            }
            Ok(())
        }
        // @behavior selvedge.client.web.r2.http.attach_route.rejected Web attach route writes protocol attach rejections as 409 JSON responses.
        Err(AttachRejectedOrBridgeError::Rejected(rejected)) => {
            write_json_response(stream, 409, &rejected).await
        }
        // @behavior selvedge.client.web.r2.http.attach_route.bridge_error Web attach route converts bridge errors into 500 local HTTP problem responses.
        Err(AttachRejectedOrBridgeError::Bridge(error)) => {
            write_problem_response(
                stream,
                500,
                LocalHttpProblemCode::InternalFailure,
                format!("{error:?}"),
            )
            .await
        }
    }
}

// @behavior selvedge.client.web.r2.next_frame Web attach streaming converts bridge frames and bridge errors into NDJSON stream items for the same command ID.
async fn next_web_frame(
    frames: &mut WebFrameStream,
    client_command_id: &LocalClientCommandId,
) -> Option<LocalAttachStreamItem> {
    frames.as_mut().next().await.map(|frame| match frame {
        Ok(frame) => LocalAttachStreamItem::Frame(frame),
        // @behavior selvedge.client.web.r2.next_frame.stream_error Web attach streaming converts bridge stream errors into LocalStreamError items with the same command ID.
        Err(error) => LocalAttachStreamItem::StreamError(LocalStreamError {
            client_command_id: client_command_id.clone(),
            reason: LocalStreamErrorReason::InternalFailure,
            message_text: format!("{error:?}"),
        }),
    })
}

#[derive(Debug)]
enum HttpRequestReadError {
    BodyTooLarge,
}

// @behavior selvedge.client.web.r2.read_request Web request reading applies the standard local HTTP read timeout to each accepted connection.
async fn read_http_request(
    stream: &mut TcpStream,
) -> io::Result<Result<HttpRequest, HttpRequestReadError>> {
    read_http_request_with_timeout(stream, HTTP_REQUEST_READ_TIMEOUT).await
}

// @behavior selvedge.client.web.r2.read_request_timeout Web request reads return a timeout IO error when headers or body reads exceed the configured duration.
async fn read_http_request_with_timeout(
    stream: &mut TcpStream,
    read_timeout: Duration,
) -> io::Result<Result<HttpRequest, HttpRequestReadError>> {
    match timeout(read_timeout, read_http_request_inner(stream)).await {
        Ok(result) => result,
        // @behavior selvedge.client.web.r2.read_request_timeout.elapsed Web request reads return a timed-out IO error when the configured read timeout elapses.
        Err(_) => Err(io::Error::new(
            io::ErrorKind::TimedOut,
            "HTTP request read timed out",
        )),
    }
}

// @behavior selvedge.client.web.r2.read_request_inner_result Web HTTP request parsing returns a parsed request, size failure, or IO error for the local client connection.
async fn read_http_request_inner(
    stream: &mut TcpStream,
) -> io::Result<Result<HttpRequest, HttpRequestReadError>> {
    let mut raw_headers = Vec::new();
    let mut byte = [0_u8; 1];
    // @behavior selvedge.client.web.r2.read_request_inner Web HTTP request parsing reads headers and body bytes or returns size and IO failures visible to the local client.
    while !raw_headers.ends_with(b"\r\n\r\n") {
        let read = stream.read(&mut byte).await?;
        if read == 0 {
            // @behavior selvedge.client.web.r2.read_request_inner.eof Web HTTP request parsing returns UnexpectedEof when the client closes before headers finish.
            return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                "connection closed before headers",
            ));
        }
        raw_headers.push(byte[0]);
        if raw_headers.len() > MAX_HTTP_HEADER_BYTES {
            // @behavior selvedge.client.web.r2.read_request_inner.header_limit Web HTTP request parsing reports BodyTooLarge when headers exceed the configured byte limit.
            return Ok(Err(HttpRequestReadError::BodyTooLarge));
        }
    }
    let header_text = String::from_utf8(raw_headers)
        // @behavior selvedge.client.web.r2.read_request_inner.header_utf8 Web HTTP request parsing returns InvalidData when header bytes are not UTF-8.
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error.to_string()))?;
    let mut lines = header_text.split("\r\n");
    let request_line = lines.next().unwrap_or_default();
    let mut request_parts = request_line.split_whitespace();
    let method = request_parts.next().unwrap_or_default().to_owned();
    let path = request_parts.next().unwrap_or_default().to_owned();
    let mut content_type = None;
    let mut content_length = 0_usize;
    for line in lines {
        if line.is_empty() {
            continue;
        }
        if let Some((name, value)) = line.split_once(':') {
            if name.eq_ignore_ascii_case("content-type") {
                content_type = Some(value.trim().to_ascii_lowercase());
            } else if name.eq_ignore_ascii_case("content-length") {
                content_length = value.trim().parse().unwrap_or_default();
            }
        }
    }
    if content_length > MAX_HTTP_BODY_BYTES {
        // @behavior selvedge.client.web.r2.read_request_inner.body_limit Web HTTP request parsing reports BodyTooLarge when Content-Length exceeds the configured body byte limit.
        return Ok(Err(HttpRequestReadError::BodyTooLarge));
    }
    let mut body = vec![0_u8; content_length];
    stream.read_exact(&mut body).await?;
    Ok(Ok(HttpRequest {
        method,
        path,
        content_type,
        body,
    }))
}

// @behavior selvedge.client.web.r2.parse_json Web JSON parsing accepts JSON content types and returns typed parse failures for unsupported or malformed requests.
fn parse_json_request<T: DeserializeOwned>(
    request: &HttpRequest,
) -> Result<T, JsonRequestParseError> {
    let content_type = request
        .content_type
        .as_ref()
        .ok_or(JsonRequestParseError::UnsupportedContentType)?;
    if content_type
        .split(';')
        .next()
        .ok_or(JsonRequestParseError::UnsupportedContentType)?
        .trim()
        != JSON_CONTENT_TYPE
    {
        // @behavior selvedge.client.web.r2.parse_json.unsupported_content_type Web JSON parsing rejects requests whose content type is not application JSON.
        return Err(JsonRequestParseError::UnsupportedContentType);
    }
    // @behavior selvedge.client.web.r2.parse_json.malformed Web JSON parsing returns MalformedJson when the request body cannot deserialize into the route request type.
    serde_json::from_slice(&request.body).map_err(|_| JsonRequestParseError::MalformedJson)
}

async fn write_json_parse_error(
    stream: &mut TcpStream,
    error: JsonRequestParseError,
    request_kind: &str,
    // @behavior selvedge.client.web.r2.write_json_parse_error Web JSON parse errors are written as 415 unsupported content type or 400 malformed JSON problem responses.
) -> io::Result<()> {
    match error {
        JsonRequestParseError::UnsupportedContentType => {
            write_problem_response(
                stream,
                415,
                LocalHttpProblemCode::UnsupportedContentType,
                "unsupported content type",
            )
            .await
        }
        JsonRequestParseError::MalformedJson => {
            write_problem_response(
                stream,
                400,
                LocalHttpProblemCode::MalformedJson,
                format!("malformed {request_kind} request"),
            )
            .await
        }
    }
}

async fn write_json_response<T: Serialize>(
    stream: &mut TcpStream,
    status_code: u16,
    response: &T,
    // @behavior selvedge.client.web.r2.write_json_response Web JSON responses serialize the supplied protocol value and write it with the supplied HTTP status.
) -> io::Result<()> {
    // @behavior selvedge.client.web.r2.write_json_response.serialize Web JSON responses return an IO error when response serialization fails.
    let body = serde_json::to_vec(response).map_err(|error| io::Error::other(error.to_string()))?;
    write_raw_response(stream, status_code, JSON_CONTENT_TYPE, &body).await
}

async fn write_problem_response(
    stream: &mut TcpStream,
    status_code: u16,
    code: LocalHttpProblemCode,
    message_text: impl Into<String>,
    // @behavior selvedge.client.web.r2.write_problem_response Web problem responses serialize local HTTP problem codes and messages as JSON responses.
) -> io::Result<()> {
    write_json_response(stream, status_code, &http_problem(code, message_text)).await
}

async fn write_raw_response(
    stream: &mut TcpStream,
    status_code: u16,
    content_type: &str,
    body: &[u8],
    // @behavior selvedge.client.web.r2.write_raw_response Web raw responses write HTTP status, content type, content length, close header, and body bytes.
) -> io::Result<()> {
    let headers = format!(
        "HTTP/1.1 {} {}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        status_code,
        status_text(status_code),
        body.len()
    );
    // @behavior selvedge.client.web.r2.write_raw_response.headers Web raw responses write HTTP response headers before body bytes.
    stream.write_all(headers.as_bytes()).await?;
    // @behavior selvedge.client.web.r2.write_raw_response.body Web raw responses write the supplied body bytes after headers.
    stream.write_all(body).await?;
    stream.flush().await
}

async fn write_stream_headers(stream: &mut TcpStream) -> io::Result<()> {
    let headers = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: {NDJSON_CONTENT_TYPE}\r\nConnection: close\r\n\r\n"
    );
    // @behavior selvedge.client.web.r2.write_stream_headers Web attach streams write a 200 NDJSON response header before stream items.
    stream.write_all(headers.as_bytes()).await
}

async fn write_attach_stream_item(
    stream: &mut TcpStream,
    item: &LocalAttachStreamItem,
    // @behavior selvedge.client.web.r2.write_attach_stream_item Web attach streams write each accepted, frame, or stream-error item as one NDJSON line.
) -> io::Result<()> {
    // @behavior selvedge.client.web.r2.write_attach_stream_item.serialize Web attach streams return an IO error when stream item serialization fails.
    let mut body = serde_json::to_vec(item).map_err(|error| io::Error::other(error.to_string()))?;
    body.push(b'\n');
    // @behavior selvedge.client.web.r2.write_attach_stream_item.write Web attach streams flush each serialized NDJSON item to the local client connection.
    stream.write_all(&body).await?;
    stream.flush().await
}

fn status_text(status_code: u16) -> &'static str {
    match status_code {
        200 => "OK",
        400 => "Bad Request",
        404 => "Not Found",
        405 => "Method Not Allowed",
        409 => "Conflict",
        413 => "Content Too Large",
        415 => "Unsupported Media Type",
        _ => "Internal Server Error",
    }
}

// @behavior selvedge.client.web.r2.bind_localhost Web localhost binding opens a nonblocking listener on the configured loopback host and port.
fn bind_localhost(bind: &WebLocalhostBind) -> Result<StdTcpListener, WebStartError> {
    let listener = match bind.host {
        WebLocalhostHost::Ipv4Loopback => StdTcpListener::bind((Ipv4Addr::LOCALHOST, bind.port)),
        WebLocalhostHost::Ipv6Loopback => StdTcpListener::bind((Ipv6Addr::LOCALHOST, bind.port)),
    }
    // @behavior selvedge.client.web.r2.bind_localhost.bind_failed Web localhost binding reports OS listener bind failures as BindFailed startup errors.
    .map_err(|error| WebStartError::BindFailed(error.to_string()))?;
    listener
        .set_nonblocking(true)
        // @behavior selvedge.client.web.r2.bind_localhost.nonblocking_failed Web localhost binding reports nonblocking setup failures as BindFailed startup errors.
        .map_err(|error| WebStartError::BindFailed(error.to_string()))?;
    Ok(listener)
}

#[cfg(test)]
mod tests {
    use super::*;

    struct TestBridge;

    impl WebBridge for TestBridge {
        fn ready(&self, _request: ReadyRequest) -> WebBridgeFuture<ReadyResponse> {
            Box::pin(async {
                Ok(ReadyResponse {
                    state: ReadyState::Ready,
                })
            })
        }

        fn submit_command(&self, request: CommandRequest) -> WebBridgeFuture<CommandResponse> {
            Box::pin(async move {
                Ok(CommandResponse {
                    client_command_id: request.client_command_id,
                    outcome: CommandOutcome::Accepted,
                })
            })
        }

        fn attach(&self, _request: AttachRequest) -> WebAttachFuture {
            Box::pin(async {
                Err(AttachRejectedOrBridgeError::Bridge(
                    WebBridgeError::ServerNotReady,
                ))
            })
        }
    }

    // @verifies selvedge.client.web.spawn
    #[tokio::test]
    async fn accept_error_marks_web_surface_failed() {
        let (state_tx, _state_rx) = watch::channel(WebRuntimeState::Listening);
        let control = WebControl {
            inner: Arc::new(WebControlInner {
                state_tx,
                bridge: Arc::new(TestBridge),
            }),
        };

        let status = fail_web_surface(
            &control,
            io::Error::new(io::ErrorKind::ConnectionAborted, "accept failed"),
        );

        // @verifies selvedge.client.web.r2
        assert!(matches!(status, WebExitStatus::Fatal(_)));
        // @verifies selvedge.client.web.r2
        assert_eq!(control.state().await, WebRuntimeState::Failed);
    }

    // @verifies selvedge.client.web.spawn
    #[tokio::test]
    async fn request_read_times_out_when_headers_stall() {
        let listener = TcpListener::bind(("127.0.0.1", 0))
            .await
            .expect("bind test listener");
        let addr = listener.local_addr().expect("listener addr");
        let client = tokio::spawn(async move {
            let mut stream = TcpStream::connect(addr).await.expect("connect listener");
            stream
                .write_all(b"POST /")
                .await
                .expect("write partial request");
            stream
        });
        let (mut server_stream, _addr) = listener.accept().await.expect("accept client");

        let result =
            read_http_request_with_timeout(&mut server_stream, Duration::from_millis(1)).await;

        // @verifies selvedge.client.web.r2
        assert_eq!(
            result.expect_err("stalled headers should time out").kind(),
            io::ErrorKind::TimedOut
        );
        let _ = client.await.expect("client task");
    }
}
