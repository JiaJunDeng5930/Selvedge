#![doc = include_str!("../README.md")]

use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll};
use std::time::Duration;

use futures_core::Stream;
use selvedge_local_protocol::{
    AttachAccepted, AttachRejected, AttachRequest, CommandRequest, CommandResponse,
    LocalClientFrame, ReadyRequest, ReadyResponse, validate_attach_request,
    validate_command_request, validate_ready_request,
};

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

#[derive(Debug)]
struct ClientState {
    state: LocalClientState,
    attach_open: bool,
    attach_generation: u64,
    recent_error: Option<LocalClientError>,
}

impl ClientState {
    fn ready() -> Self {
        Self {
            state: LocalClientState::Ready,
            attach_open: false,
            attach_generation: 0,
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
                let attach_generation = guard.complete_attach_success();
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
        let mut state = self.state.lock().expect("local client state lock");
        if state.state == LocalClientState::Closing {
            state.state = LocalClientState::Closed;
            state.attach_open = false;
            state.recent_error = None;
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

    fn complete_attach_success(mut self) -> u64 {
        let mut state = self.state.lock().expect("local client state lock");
        if state.state == self.pending {
            state.attach_generation = state.attach_generation.wrapping_add(1);
            state.attach_open = true;
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
    inner: LocalFrameStream,
    state: Arc<Mutex<ClientState>>,
    attach_generation: u64,
    closed_reported: bool,
}

impl Stream for ClientFrameStream {
    type Item = Result<LocalClientFrame, LocalClientError>;

    fn poll_next(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let this = self.get_mut();
        if this.closed_reported {
            return Poll::Ready(None);
        }

        match this.inner.as_mut().poll_next(cx) {
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
    let mut state = state.lock().expect("local client state lock");
    if state.attach_generation != attach_generation {
        return;
    }
    state.attach_open = false;
    if state.state == LocalClientState::Attached {
        state.state = LocalClientState::Ready;
    }
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
