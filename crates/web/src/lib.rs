#![doc = include_str!("../README.md")]

use std::future::Future;
use std::net::{Ipv4Addr, Ipv6Addr, TcpListener};
use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Poll};

use futures_core::Stream;
use selvedge_local_protocol::{
    AttachAccepted, AttachRejected, AttachRequest, CommandOutcome, CommandRejectReason,
    CommandRequest, CommandResponse, LocalClientFrame, ReadyRequest, ReadyResponse,
    current_protocol_version, validate_attach_request, validate_command_request,
};
use tokio::sync::watch;
use tokio::task::JoinHandle;

pub struct WebStartArgs {
    pub bind: WebLocalhostBind,
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

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WebPageResponse {
    pub content_type: String,
    pub body: String,
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
    if args.bind.port == 0 {
        return Err(WebStartError::InvalidBindTarget);
    }

    let handle =
        tokio::runtime::Handle::try_current().map_err(|_| WebStartError::TokioSpawnFailed)?;
    let listener = bind_localhost(&args.bind)?;
    let (state_tx, mut state_rx) = watch::channel(WebRuntimeState::Listening);
    let control = WebControl {
        inner: Arc::new(WebControlInner {
            state_tx,
            bridge: args.bridge,
        }),
    };
    let task_control = control.clone();
    let join_handle = handle.spawn(async move {
        let _listener = listener;
        while state_rx.changed().await.is_ok() {
            if *state_rx.borrow() == WebRuntimeState::Closing {
                break;
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

impl WebControl {
    pub async fn state(&self) -> WebRuntimeState {
        self.inner.state_tx.borrow().clone()
    }

    pub async fn page(&self) -> Result<WebPageResponse, WebBridgeError> {
        self.ensure_listening()?;
        Ok(WebPageResponse {
            content_type: "text/html; charset=utf-8".to_owned(),
            body: "<!doctype html><html><head><title>Selvedge</title></head><body><main id=\"selvedge-root\">Selvedge</main></body></html>".to_owned(),
        })
    }

    pub async fn submit_command(
        &self,
        request: CommandRequest,
    ) -> Result<CommandResponse, WebBridgeError> {
        self.ensure_listening()?;
        let client_command_id = request.client_command_id.clone();
        if validate_command_request(&request).is_err() {
            let reason = if request.protocol_version != current_protocol_version() {
                CommandRejectReason::ProtocolVersionMismatch
            } else {
                CommandRejectReason::MalformedRequest
            };
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
        let protocol_version = current_protocol_version();
        let client_command_id = request.client_command_id.clone();
        if validate_attach_request(&request).is_err() {
            let reason = if request.protocol_version != current_protocol_version() {
                CommandRejectReason::ProtocolVersionMismatch
            } else {
                CommandRejectReason::MalformedRequest
            };
            return Err(AttachRejectedOrBridgeError::Rejected(AttachRejected {
                protocol_version,
                client_command_id,
                reason,
            }));
        }

        match self.inner.bridge.attach(request).await {
            Ok((accepted, stream)) => Ok((accepted, self.wrap_frame_stream(stream))),
            Err(AttachRejectedOrBridgeError::Bridge(WebBridgeError::ServerNotReady)) => {
                Err(AttachRejectedOrBridgeError::Rejected(AttachRejected {
                    protocol_version,
                    client_command_id,
                    reason: CommandRejectReason::ServerNotReady,
                }))
            }
            Err(AttachRejectedOrBridgeError::Bridge(WebBridgeError::ProtocolValidationFailed)) => {
                Err(AttachRejectedOrBridgeError::Rejected(AttachRejected {
                    protocol_version,
                    client_command_id,
                    reason: CommandRejectReason::MalformedRequest,
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
            state_rx: self.inner.state_tx.subscribe(),
            closed_after_error: false,
        })
    }
}

struct WebBrowserFrameStream {
    inner: WebFrameStream,
    state_rx: watch::Receiver<WebRuntimeState>,
    closed_after_error: bool,
}

impl Stream for WebBrowserFrameStream {
    type Item = Result<LocalClientFrame, WebBridgeError>;

    fn poll_next(self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let this = self.get_mut();
        if this.closed_after_error
            || matches!(
                *this.state_rx.borrow(),
                WebRuntimeState::Closing | WebRuntimeState::Stopped | WebRuntimeState::Failed
            )
        {
            return Poll::Ready(None);
        }

        match this.inner.as_mut().poll_next(context) {
            Poll::Ready(Some(Err(error))) => {
                this.closed_after_error = true;
                Poll::Ready(Some(Err(error)))
            }
            Poll::Ready(item) => Poll::Ready(item),
            Poll::Pending => {
                let state_changed = {
                    let changed = this.state_rx.changed();
                    tokio::pin!(changed);
                    Future::poll(changed.as_mut(), context)
                };
                match state_changed {
                    Poll::Ready(Ok(())) => {
                        if matches!(
                            *this.state_rx.borrow(),
                            WebRuntimeState::Closing
                                | WebRuntimeState::Stopped
                                | WebRuntimeState::Failed
                        ) {
                            Poll::Ready(None)
                        } else {
                            Poll::Pending
                        }
                    }
                    Poll::Ready(Err(_)) => Poll::Ready(None),
                    Poll::Pending => Poll::Pending,
                }
            }
        }
    }
}

fn rejected_command_response(
    client_command_id: selvedge_local_protocol::LocalClientCommandId,
    reason: CommandRejectReason,
) -> CommandResponse {
    CommandResponse {
        protocol_version: current_protocol_version(),
        client_command_id,
        outcome: CommandOutcome::Rejected(reason),
    }
}

fn bind_localhost(bind: &WebLocalhostBind) -> Result<TcpListener, WebStartError> {
    let listener = match bind.host {
        WebLocalhostHost::Ipv4Loopback => TcpListener::bind((Ipv4Addr::LOCALHOST, bind.port)),
        WebLocalhostHost::Ipv6Loopback => TcpListener::bind((Ipv6Addr::LOCALHOST, bind.port)),
    }
    .map_err(|error| WebStartError::BindFailed(error.to_string()))?;
    listener
        .set_nonblocking(true)
        .map_err(|error| WebStartError::BindFailed(error.to_string()))?;
    Ok(listener)
}
