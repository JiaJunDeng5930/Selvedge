#![doc = include_str!("../README.md")]

use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;
use std::sync::atomic::{AtomicU8, Ordering};

use futures_core::Stream;
use selvedge_local_protocol::{
    AttachAccepted, AttachRejected, AttachRequest, CommandRequest, CommandResponse,
    LocalClientFrame, ReadyRequest, ReadyResponse,
};
use tokio::sync::Notify;
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
    state: AtomicU8,
    stop_notify: Notify,
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
    let control = WebControl {
        inner: Arc::new(WebControlInner {
            state: AtomicU8::new(web_state_code(WebRuntimeState::Listening)),
            stop_notify: Notify::new(),
        }),
    };
    let task_control = control.clone();
    let join_handle = tokio::spawn(async move {
        loop {
            if task_control.inner.state.load(Ordering::SeqCst)
                == web_state_code(WebRuntimeState::Closing)
            {
                break;
            }
            task_control.inner.stop_notify.notified().await;
        }
        task_control
            .inner
            .state
            .store(web_state_code(WebRuntimeState::Stopped), Ordering::SeqCst);
        WebExitStatus::Stopped
    });

    Ok(WebHandle {
        control,
        join_handle,
    })
}

impl WebControl {
    pub async fn state(&self) -> WebRuntimeState {
        web_state_from_code(self.inner.state.load(Ordering::SeqCst))
    }

    pub async fn stop(&self) {
        self.inner
            .state
            .store(web_state_code(WebRuntimeState::Closing), Ordering::SeqCst);
        self.inner.stop_notify.notify_waiters();
    }
}

fn web_state_code(state: WebRuntimeState) -> u8 {
    match state {
        WebRuntimeState::Binding => 0,
        WebRuntimeState::Listening => 1,
        WebRuntimeState::Closing => 2,
        WebRuntimeState::Stopped => 3,
        WebRuntimeState::Failed => 4,
    }
}

fn web_state_from_code(code: u8) -> WebRuntimeState {
    match code {
        0 => WebRuntimeState::Binding,
        1 => WebRuntimeState::Listening,
        2 => WebRuntimeState::Closing,
        3 => WebRuntimeState::Stopped,
        _ => WebRuntimeState::Failed,
    }
}
