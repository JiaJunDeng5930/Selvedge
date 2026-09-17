#![doc = include_str!("../README.md")]

use std::future::Future;
use std::io;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, TcpListener as StdTcpListener};
use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Poll};
use std::time::Duration;

use bytes::Bytes;
use futures_core::Stream;
use futures_util::StreamExt;
use http_body_util::BodyExt;
use hyper::body::Body;
use selvedge_local_protocol::{
    AttachAccepted, AttachRejectReason, AttachRejected, AttachRequest, CommandOutcome,
    CommandRejectReason, CommandRequest, CommandResponse, LocalAttachStreamItem,
    LocalClientCommandId, LocalClientFrame, LocalHttpProblemCode, LocalStreamError,
    LocalStreamErrorReason, MAX_LOCAL_FRAME_BYTES, ReadyRequest, ReadyResponse, ReadyState,
    http_problem, validate_attach_request, validate_command_request,
};
use serde::Serialize;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::watch;
use tokio::task::{JoinHandle, JoinSet};
use tokio::time::timeout;
use tokio_stream::wrappers::WatchStream;

const JSON_CONTENT_TYPE: &str = "application/json";
const NDJSON_CONTENT_TYPE: &str = "application/x-ndjson";
const MAX_HTTP_HEADER_BYTES: usize = 16 * 1024;
const MAX_HTTP_BODY_BYTES: usize = 4 * 1024 * 1024;
const HTTP_REQUEST_READ_TIMEOUT: Duration = Duration::from_secs(5);

pub struct WebStartArgs {
    pub bind: WebLocalhostBind,
    pub bridge: Arc<dyn WebBridge>,
}

pub struct ReservedWebStartArgs {
    pub bind: WebBindReservation,
    pub bridge: Arc<dyn WebBridge>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WebLocalhostBind {
    pub host: WebLocalhostHost,
    pub port: u16,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum WebLocalhostHost {
    Ipv4Loopback,
    Ipv6Loopback,
}

pub struct WebBindReservation {
    listener: StdTcpListener,
}

pub struct WebHandle {
    pub control: WebControl,
    pub join_handle: JoinHandle<WebExitStatus>,
}

#[derive(Clone)]
pub struct WebControl {
    inner: Arc<WebControlInner>,
}

struct WebControlInner {
    local_addr: std::net::SocketAddr,
    state_tx: watch::Sender<WebRuntimeState>,
    bridge: Arc<dyn WebBridge>,
}

pub type WebFrameStream =
    Pin<Box<dyn Stream<Item = Result<LocalClientFrame, WebBridgeError>> + Send>>;
pub type WebBridgeFuture<T> = Pin<Box<dyn Future<Output = Result<T, WebBridgeError>> + Send>>;
pub type WebAttachFuture = Pin<
    Box<
        dyn Future<Output = Result<(AttachAccepted, WebFrameStream), AttachRejectedOrBridgeError>>
            + Send,
    >,
>;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum WebRuntimeState {
    Listening,
    Closing,
    Stopped,
    Failed,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum WebExitStatus {
    Stopped,
    Fatal(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum WebStartError {
    BindFailed(String),
    TokioSpawnFailed,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum WebBridgeError {
    ServerNotReady,
    ProtocolValidationFailed,
    CommandRejected(String),
    AttachRejected(String),
    StreamClosed,
    InternalFailure(String),
}

pub trait WebBridge: Send + Sync + 'static {
    fn ready(&self, request: ReadyRequest) -> WebBridgeFuture<ReadyResponse>;
    fn submit_command(&self, request: CommandRequest) -> WebBridgeFuture<CommandResponse>;
    fn attach(&self, request: AttachRequest) -> WebAttachFuture;
}

#[derive(Debug)]
pub enum AttachRejectedOrBridgeError {
    Rejected(AttachRejected),
    Bridge(WebBridgeError),
}

pub fn spawn_web_surface(args: WebStartArgs) -> Result<WebHandle, WebStartError> {
    let bind = reserve_web_bind(args.bind)?;
    spawn_reserved_web_surface(ReservedWebStartArgs {
        bind,
        bridge: args.bridge,
    })
}

pub fn reserve_web_bind(bind: WebLocalhostBind) -> Result<WebBindReservation, WebStartError> {
    let listener = bind_localhost(&bind)?;
    Ok(WebBindReservation { listener })
}

pub fn spawn_reserved_web_surface(args: ReservedWebStartArgs) -> Result<WebHandle, WebStartError> {
    let handle =
        tokio::runtime::Handle::try_current().map_err(|_| WebStartError::TokioSpawnFailed)?;
    let listener =
        TcpListener::from_std(args.bind.listener).map_err(|_| WebStartError::TokioSpawnFailed)?;
    let local_addr = listener
        .local_addr()
        .map_err(|error| WebStartError::BindFailed(error.to_string()))?;
    let (state_tx, mut state_rx) = watch::channel(WebRuntimeState::Listening);
    let control = WebControl {
        inner: Arc::new(WebControlInner {
            local_addr,
            state_tx,
            bridge: args.bridge,
        }),
    };
    let task_control = control.clone();
    let join_handle = handle.spawn(async move {
        let mut connections = JoinSet::new();
        let mut failure = None;
        loop {
            tokio::select! {
                biased;
                state_change = state_rx.changed() => {
                    if state_change.is_err() || *state_rx.borrow() == WebRuntimeState::Closing { break; }
                }
                _ = connections.join_next(), if !connections.is_empty() => {}
                accepted = listener.accept() => match accepted {
                    Ok((stream, _)) => {
                        connections.spawn(handle_http_connection(task_control.clone(), stream));
                    }
                    Err(error) => { failure = Some(error); break; }
                }
            }
        }
        drop(listener);
        connections.abort_all();
        while connections.join_next().await.is_some() {}
        if let Some(error) = failure { return fail_web_surface(&task_control, error); }
        let _ = task_control.inner.state_tx.send(WebRuntimeState::Stopped);
        WebExitStatus::Stopped
    });

    Ok(WebHandle {
        control,
        join_handle,
    })
}

fn fail_web_surface(control: &WebControl, error: io::Error) -> WebExitStatus {
    let _ = control.inner.state_tx.send(WebRuntimeState::Failed);
    WebExitStatus::Fatal(error.to_string())
}

impl WebControl {
    pub fn local_addr(&self) -> std::net::SocketAddr {
        self.inner.local_addr
    }

    pub async fn state(&self) -> WebRuntimeState {
        self.inner.state_tx.borrow().clone()
    }

    pub async fn ready(&self, request: ReadyRequest) -> Result<ReadyResponse, WebBridgeError> {
        self.ensure_listening()?;

        match self.inner.bridge.ready(request).await {
            Ok(response) => Ok(response),
            Err(WebBridgeError::ServerNotReady) | Err(WebBridgeError::ProtocolValidationFailed) => {
                Ok(not_ready_response())
            }
            Err(error) => Err(error),
        }
    }

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
            Err(WebBridgeError::ServerNotReady) => Ok(rejected_command_response(
                client_command_id,
                CommandRejectReason::ServerNotReady,
            )),
            Err(WebBridgeError::ProtocolValidationFailed) => Ok(rejected_command_response(
                client_command_id,
                CommandRejectReason::MalformedRequest,
            )),
            Err(error) => Err(error),
        }
    }

    pub async fn attach(
        &self,
        request: AttachRequest,
    ) -> Result<(AttachAccepted, WebFrameStream), AttachRejectedOrBridgeError> {
        self.ensure_listening()
            .map_err(AttachRejectedOrBridgeError::Bridge)?;
        let client_command_id = request.client_command_id.clone();
        if validate_attach_request(&request).is_err() {
            let reason = AttachRejectReason::MalformedRequest;
            return Err(AttachRejectedOrBridgeError::Rejected(AttachRejected {
                client_command_id,
                reason,
            }));
        }

        match self.inner.bridge.attach(request).await {
            Ok((accepted, stream)) => Ok((accepted, self.wrap_frame_stream(stream))),
            Err(AttachRejectedOrBridgeError::Bridge(WebBridgeError::ServerNotReady)) => {
                Err(AttachRejectedOrBridgeError::Rejected(AttachRejected {
                    client_command_id,
                    reason: AttachRejectReason::ServerNotReady,
                }))
            }
            Err(AttachRejectedOrBridgeError::Bridge(WebBridgeError::ProtocolValidationFailed)) => {
                Err(AttachRejectedOrBridgeError::Rejected(AttachRejected {
                    client_command_id,
                    reason: AttachRejectReason::MalformedRequest,
                }))
            }
            Err(error) => Err(error),
        }
    }

    pub async fn stop(&self) {
        let _ = self.inner.state_tx.send(WebRuntimeState::Closing);
    }

    fn ensure_listening(&self) -> Result<(), WebBridgeError> {
        if *self.inner.state_tx.borrow() == WebRuntimeState::Listening {
            Ok(())
        } else {
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
            Poll::Ready(Some(Err(error))) => {
                this.closed_after_error = true;
                Poll::Ready(Some(Err(error)))
            }
            Poll::Ready(item) => Poll::Ready(item),
            Poll::Pending => Poll::Pending,
        }
    }
}

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

type ResponseBody = http_body_util::combinators::UnsyncBoxBody<Bytes, io::Error>;
type HttpResponse = hyper::Response<ResponseBody>;

async fn handle_http_connection(control: WebControl, stream: TcpStream) {
    let service = hyper::service::service_fn(move |request| {
        let control = control.clone();
        async move { Ok::<_, std::convert::Infallible>(handle_http_request(control, request).await) }
    });
    let _ = hyper::server::conn::http1::Builder::new()
        .keep_alive(false)
        .half_close(true)
        .max_buf_size(MAX_HTTP_HEADER_BYTES)
        .timer(hyper_util::rt::TokioTimer::new())
        .header_read_timeout(HTTP_REQUEST_READ_TIMEOUT)
        .serve_connection(hyper_util::rt::TokioIo::new(stream), service)
        .await;
}

async fn handle_http_request(
    control: WebControl,
    request: hyper::Request<hyper::body::Incoming>,
) -> HttpResponse {
    let headers = request.headers();
    let header_bytes = headers
        .iter()
        .map(|(name, value)| name.as_str().len() + value.as_bytes().len() + 4)
        .sum::<usize>()
        + request.method().as_str().len()
        + request.uri().to_string().len()
        + 12;
    if header_bytes > MAX_HTTP_HEADER_BYTES {
        return problem_response(
            431,
            LocalHttpProblemCode::BodyTooLarge,
            "request headers too large",
        );
    }
    let host_allowed = headers.get_all("host").iter().count() == 1
        && headers
            .get("host")
            .and_then(|value| value.to_str().ok())
            .is_some_and(is_loopback_authority);
    let origin_allowed = headers.get_all("origin").iter().count() <= 1
        && headers
            .get("origin")
            .is_none_or(|value| value.to_str().is_ok_and(is_loopback_origin));
    if !host_allowed || !origin_allowed {
        return problem_response(
            403,
            LocalHttpProblemCode::RouteNotFound,
            "request target not allowed",
        );
    }
    let path = request.uri().path().to_owned();
    if !matches!(
        path.as_str(),
        "/selvedge/local/v1/ready" | "/selvedge/local/v1/command" | "/selvedge/local/v1/attach"
    ) {
        return problem_response(404, LocalHttpProblemCode::RouteNotFound, "route not found");
    }
    if request.method() != hyper::Method::POST {
        return problem_response(
            405,
            LocalHttpProblemCode::MethodNotAllowed,
            "method not allowed",
        );
    }
    if !headers
        .get("content-type")
        .and_then(|value| value.to_str().ok())
        .is_some_and(|value| {
            value
                .split(';')
                .next()
                .is_some_and(|media| media.trim().eq_ignore_ascii_case(JSON_CONTENT_TYPE))
        })
    {
        return problem_response(
            415,
            LocalHttpProblemCode::UnsupportedContentType,
            "unsupported content type",
        );
    }
    if request
        .body()
        .size_hint()
        .upper()
        .is_some_and(|size| size > MAX_HTTP_BODY_BYTES as u64)
    {
        return problem_response(
            413,
            LocalHttpProblemCode::BodyTooLarge,
            "request body too large",
        );
    }
    let body = match timeout(
        HTTP_REQUEST_READ_TIMEOUT,
        http_body_util::Limited::new(request.into_body(), MAX_HTTP_BODY_BYTES).collect(),
    )
    .await
    {
        Ok(Ok(body)) => body.to_bytes(),
        Ok(Err(error)) if error.is::<http_body_util::LengthLimitError>() => {
            return problem_response(
                413,
                LocalHttpProblemCode::BodyTooLarge,
                "request body too large",
            );
        }
        Ok(Err(_)) => {
            return problem_response(
                400,
                LocalHttpProblemCode::MalformedJson,
                "invalid request body framing",
            );
        }
        Err(_) => {
            return problem_response(
                408,
                LocalHttpProblemCode::MalformedJson,
                "request body read timed out",
            );
        }
    };
    match path.as_str() {
        "/selvedge/local/v1/ready" => match serde_json::from_slice::<ReadyRequest>(&body) {
            Ok(request) => match control.ready(request).await {
                Ok(response) => json_response(200, &response),
                Err(error) => bridge_problem(error),
            },
            Err(_) => malformed_request(),
        },
        "/selvedge/local/v1/command" => match serde_json::from_slice::<CommandRequest>(&body) {
            Ok(request) => match control.submit_command(request).await {
                Ok(response) => json_response(200, &response),
                Err(error) => bridge_problem(error),
            },
            Err(_) => malformed_request(),
        },
        _ => {
            let request = match serde_json::from_slice::<AttachRequest>(&body) {
                Ok(request) => request,
                Err(_) => return malformed_request(),
            };
            let command_id = request.client_command_id.clone();
            match control.attach(request).await {
                Ok((accepted, frames)) => {
                    let stream_command_id = command_id.clone();
                    let items = futures_util::stream::once(async move {
                        LocalAttachStreamItem::Accepted(accepted)
                    })
                    .chain(frames.map(move |frame| match frame {
                        Ok(frame) => LocalAttachStreamItem::Frame(frame),
                        Err(error) => LocalAttachStreamItem::StreamError(LocalStreamError {
                            client_command_id: command_id.clone(),
                            reason: LocalStreamErrorReason::InternalFailure,
                            message_text: format!("{error:?}"),
                        }),
                    }));
                    let items = items.scan(false, move |ended, item| {
                        let next = if *ended {
                            None
                        } else {
                            let (bytes, terminal) = encode_stream_item(item, &stream_command_id);
                            *ended = terminal;
                            Some(Ok::<_, io::Error>(hyper::body::Frame::data(Bytes::from(
                                bytes,
                            ))))
                        };
                        std::future::ready(next)
                    });
                    response(
                        200,
                        NDJSON_CONTENT_TYPE,
                        http_body_util::StreamBody::new(items).boxed_unsync(),
                    )
                }
                Err(AttachRejectedOrBridgeError::Rejected(rejected)) => {
                    json_response(409, &rejected)
                }
                Err(AttachRejectedOrBridgeError::Bridge(error)) => bridge_problem(error),
            }
        }
    }
}

// Stop serialization at the wire budget rather than allocating an unbounded snapshot.
struct BoundedFrame(Vec<u8>);
impl io::Write for BoundedFrame {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        if bytes.len() > MAX_LOCAL_FRAME_BYTES.saturating_sub(self.0.len()) {
            return Err(io::Error::other("local frame exceeds wire budget"));
        }
        self.0.extend_from_slice(bytes);
        Ok(bytes.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

fn encode_stream_item(
    item: LocalAttachStreamItem,
    command_id: &LocalClientCommandId,
) -> (Vec<u8>, bool) {
    let mut body = BoundedFrame(Vec::new());
    let terminal = matches!(item, LocalAttachStreamItem::StreamError(_));
    if serde_json::to_writer(&mut body, &item).is_err() {
        let error = LocalAttachStreamItem::StreamError(LocalStreamError {
            client_command_id: command_id.clone(),
            reason: LocalStreamErrorReason::FrameTooLarge,
            message_text: format!("encoded frame exceeds {MAX_LOCAL_FRAME_BYTES} bytes"),
        });
        let mut bytes = serde_json::to_vec(&error).expect("stream error serializes");
        bytes.push(b'\n');
        return (bytes, true);
    }
    body.0.push(b'\n');
    (body.0, terminal)
}

fn response(status: u16, content_type: &'static str, body: ResponseBody) -> HttpResponse {
    let mut response = hyper::Response::new(body);
    *response.status_mut() = hyper::StatusCode::from_u16(status).expect("HTTP status constant");
    response.headers_mut().insert(
        "content-type",
        hyper::header::HeaderValue::from_static(content_type),
    );
    response
}

fn json_response<T: Serialize>(status: u16, value: &T) -> HttpResponse {
    let bytes = serde_json::to_vec(value).expect("local protocol JSON value serializes");
    response(
        status,
        JSON_CONTENT_TYPE,
        http_body_util::Full::new(Bytes::from(bytes))
            .map_err(|never| match never {})
            .boxed_unsync(),
    )
}
fn problem_response(
    status: u16,
    code: LocalHttpProblemCode,
    message: impl Into<String>,
) -> HttpResponse {
    json_response(status, &http_problem(code, message))
}
fn malformed_request() -> HttpResponse {
    problem_response(
        400,
        LocalHttpProblemCode::MalformedJson,
        "malformed JSON request",
    )
}
fn bridge_problem(error: WebBridgeError) -> HttpResponse {
    problem_response(
        500,
        LocalHttpProblemCode::InternalFailure,
        format!("{error:?}"),
    )
}

fn is_loopback_origin(origin: &str) -> bool {
    let Some(authority) = origin
        .strip_prefix("http://")
        .or_else(|| origin.strip_prefix("https://"))
    else {
        return false;
    };

    !authority.contains(['/', '?', '#']) && is_loopback_authority(authority)
}

fn is_loopback_authority(authority: &str) -> bool {
    let host = if let Some(bracketed) = authority.strip_prefix('[') {
        let Some((host, suffix)) = bracketed.split_once(']') else {
            return false;
        };
        if !suffix.is_empty()
            && suffix
                .strip_prefix(':')
                .and_then(|port| port.parse::<u16>().ok())
                .is_none()
        {
            return false;
        }
        host
    } else if let Some((host, port)) = authority.split_once(':') {
        if authority.matches(':').count() != 1 || port.parse::<u16>().is_err() {
            return false;
        }
        host
    } else {
        authority
    };

    host.parse::<IpAddr>()
        .is_ok_and(|address| address.is_loopback())
}

fn bind_localhost(bind: &WebLocalhostBind) -> Result<StdTcpListener, WebStartError> {
    let listener = match bind.host {
        WebLocalhostHost::Ipv4Loopback => StdTcpListener::bind((Ipv4Addr::LOCALHOST, bind.port)),
        WebLocalhostHost::Ipv6Loopback => StdTcpListener::bind((Ipv6Addr::LOCALHOST, bind.port)),
    }
    .map_err(|error| WebStartError::BindFailed(error.to_string()))?;
    listener
        .set_nonblocking(true)
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

    #[tokio::test]
    async fn accept_error_marks_web_surface_failed() {
        let (state_tx, _state_rx) = watch::channel(WebRuntimeState::Listening);
        let control = WebControl {
            inner: Arc::new(WebControlInner {
                local_addr: "127.0.0.1:1".parse().expect("address"),
                state_tx,
                bridge: Arc::new(TestBridge),
            }),
        };

        let status = fail_web_surface(
            &control,
            io::Error::new(io::ErrorKind::ConnectionAborted, "accept failed"),
        );

        assert!(matches!(status, WebExitStatus::Fatal(_)));
        assert_eq!(control.state().await, WebRuntimeState::Failed);
    }
}
