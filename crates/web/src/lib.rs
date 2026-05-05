#![doc = include_str!("../README.md")]

use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

use futures_core::Stream;
use selvedge_local_protocol::{
    AttachAccepted, AttachRejected, AttachRequest, CommandRequest, CommandResponse,
    LocalClientFrame, ReadyRequest, ReadyResponse,
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

    let _bridge = args.bridge;
    let (state_tx, mut state_rx) = watch::channel(WebRuntimeState::Listening);
    let control = WebControl {
        inner: Arc::new(WebControlInner { state_tx }),
    };
    let task_control = control.clone();
    let join_handle = tokio::spawn(async move {
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

    pub async fn stop(&self) {
        let _ = self.inner.state_tx.send(WebRuntimeState::Closing);
    }
}
