#![doc = include_str!("../README.md")]

use std::future::Future;
use std::io;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, TcpListener as StdTcpListener};
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
use tokio::time::timeout;
use tokio_stream::StreamExt;
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
    bind: WebLocalhostBind,
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
    Binding,
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
    InvalidBindTarget,
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
    if bind.port == 0 {
        return Err(WebStartError::InvalidBindTarget);
    }
    let listener = bind_localhost(&bind)?;
    Ok(WebBindReservation { bind, listener })
}

pub fn spawn_reserved_web_surface(args: ReservedWebStartArgs) -> Result<WebHandle, WebStartError> {
    if args.bind.bind.port == 0 {
        return Err(WebStartError::InvalidBindTarget);
    }

    let handle =
        tokio::runtime::Handle::try_current().map_err(|_| WebStartError::TokioSpawnFailed)?;
    let listener =
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
                        Err(error) => return fail_web_surface(&task_control, error),
                    }
                }
            }
        }
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
    pub async fn state(&self) -> WebRuntimeState {
        self.inner.state_tx.borrow().clone()
    }

    pub async fn ready(&self, request: ReadyRequest) -> Result<ReadyResponse, WebBridgeError> {
        self.ensure_listening()?;
        if validate_ready_request(&request).is_err() {
            return Ok(not_ready_response());
        }

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

#[derive(Debug)]
struct HttpRequest {
    method: String,
    path: String,
    host: Option<String>,
    origin_allowed: bool,
    content_type: Option<String>,
    body: Vec<u8>,
}

enum JsonRequestParseError {
    UnsupportedContentType,
    MalformedJson,
}

async fn handle_http_connection(mut control: WebControl, mut stream: TcpStream) -> io::Result<()> {
    let request = match read_http_request(&mut stream).await? {
        Ok(request) => request,
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
    if !request.host.as_deref().is_some_and(is_loopback_authority) || !request.origin_allowed {
        return write_problem_response(
            &mut stream,
            403,
            LocalHttpProblemCode::RouteNotFound,
            "request target not allowed",
        )
        .await;
    }
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
        Err(error) => return write_json_parse_error(stream, error, "ready").await,
    };
    match control.ready(ready_request).await {
        Ok(response) => write_json_response(stream, 200, &response).await,
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
        Err(error) => return write_json_parse_error(stream, error, "command").await,
    };
    match control.submit_command(command_request).await {
        Ok(response) => write_json_response(stream, 200, &response).await,
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
        Err(AttachRejectedOrBridgeError::Rejected(rejected)) => {
            write_json_response(stream, 409, &rejected).await
        }
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

async fn next_web_frame(
    frames: &mut WebFrameStream,
    client_command_id: &LocalClientCommandId,
) -> Option<LocalAttachStreamItem> {
    frames.as_mut().next().await.map(|frame| match frame {
        Ok(frame) => LocalAttachStreamItem::Frame(frame),
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

async fn read_http_request(
    stream: &mut TcpStream,
) -> io::Result<Result<HttpRequest, HttpRequestReadError>> {
    read_http_request_with_timeout(stream, HTTP_REQUEST_READ_TIMEOUT).await
}

async fn read_http_request_with_timeout(
    stream: &mut TcpStream,
    read_timeout: Duration,
) -> io::Result<Result<HttpRequest, HttpRequestReadError>> {
    match timeout(read_timeout, read_http_request_inner(stream)).await {
        Ok(result) => result,
        Err(_) => Err(io::Error::new(
            io::ErrorKind::TimedOut,
            "HTTP request read timed out",
        )),
    }
}

async fn read_http_request_inner(
    stream: &mut TcpStream,
) -> io::Result<Result<HttpRequest, HttpRequestReadError>> {
    let mut raw_headers = Vec::new();
    let mut byte = [0_u8; 1];
    while !raw_headers.ends_with(b"\r\n\r\n") {
        let read = stream.read(&mut byte).await?;
        if read == 0 {
            return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                "connection closed before headers",
            ));
        }
        raw_headers.push(byte[0]);
        if raw_headers.len() > MAX_HTTP_HEADER_BYTES {
            return Ok(Err(HttpRequestReadError::BodyTooLarge));
        }
    }
    let header_text = String::from_utf8(raw_headers)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error.to_string()))?;
    let mut lines = header_text.split("\r\n");
    let request_line = lines.next().unwrap_or_default();
    let mut request_parts = request_line.split_whitespace();
    let method = request_parts.next().unwrap_or_default().to_owned();
    let path = request_parts.next().unwrap_or_default().to_owned();
    let mut host = None;
    let mut duplicate_host = false;
    let mut origin = None;
    let mut duplicate_origin = false;
    let mut content_type = None;
    let mut content_length = 0_usize;
    for line in lines {
        if line.is_empty() {
            continue;
        }
        if let Some((name, value)) = line.split_once(':') {
            if name.eq_ignore_ascii_case("host") {
                duplicate_host |= host.replace(value.trim().to_owned()).is_some();
            } else if name.eq_ignore_ascii_case("origin") {
                duplicate_origin |= origin.replace(value.trim().to_owned()).is_some();
            } else if name.eq_ignore_ascii_case("content-type") {
                content_type = Some(value.trim().to_ascii_lowercase());
            } else if name.eq_ignore_ascii_case("content-length") {
                content_length = value.trim().parse().unwrap_or_default();
            }
        }
    }
    if content_length > MAX_HTTP_BODY_BYTES {
        return Ok(Err(HttpRequestReadError::BodyTooLarge));
    }
    let mut body = vec![0_u8; content_length];
    stream.read_exact(&mut body).await?;
    Ok(Ok(HttpRequest {
        method,
        path,
        host: if duplicate_host { None } else { host },
        origin_allowed: !duplicate_origin && origin.as_deref().is_none_or(is_loopback_origin),
        content_type,
        body,
    }))
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
        return Err(JsonRequestParseError::UnsupportedContentType);
    }
    serde_json::from_slice(&request.body).map_err(|_| JsonRequestParseError::MalformedJson)
}

async fn write_json_parse_error(
    stream: &mut TcpStream,
    error: JsonRequestParseError,
    request_kind: &str,
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
) -> io::Result<()> {
    let body = serde_json::to_vec(response).map_err(|error| io::Error::other(error.to_string()))?;
    write_raw_response(stream, status_code, JSON_CONTENT_TYPE, &body).await
}

async fn write_problem_response(
    stream: &mut TcpStream,
    status_code: u16,
    code: LocalHttpProblemCode,
    message_text: impl Into<String>,
) -> io::Result<()> {
    write_json_response(stream, status_code, &http_problem(code, message_text)).await
}

async fn write_raw_response(
    stream: &mut TcpStream,
    status_code: u16,
    content_type: &str,
    body: &[u8],
) -> io::Result<()> {
    let headers = format!(
        "HTTP/1.1 {} {}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        status_code,
        status_text(status_code),
        body.len()
    );
    stream.write_all(headers.as_bytes()).await?;
    stream.write_all(body).await?;
    stream.flush().await
}

async fn write_stream_headers(stream: &mut TcpStream) -> io::Result<()> {
    let headers = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: {NDJSON_CONTENT_TYPE}\r\nConnection: close\r\n\r\n"
    );
    stream.write_all(headers.as_bytes()).await
}

async fn write_attach_stream_item(
    stream: &mut TcpStream,
    item: &LocalAttachStreamItem,
) -> io::Result<()> {
    let mut body = serde_json::to_vec(item).map_err(|error| io::Error::other(error.to_string()))?;
    body.push(b'\n');
    stream.write_all(&body).await?;
    stream.flush().await
}

fn status_text(status_code: u16) -> &'static str {
    match status_code {
        200 => "OK",
        400 => "Bad Request",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        409 => "Conflict",
        413 => "Content Too Large",
        415 => "Unsupported Media Type",
        _ => "Internal Server Error",
    }
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

        assert_eq!(
            result.expect_err("stalled headers should time out").kind(),
            io::ErrorKind::TimedOut
        );
        let _ = client.await.expect("client task");
    }
}
