use std::collections::VecDeque;
use std::future;
use std::pin::Pin;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll};
use std::time::Duration;

use futures_core::Stream;
use futures_util::StreamExt;
use futures_util::stream;
use selvedge_local_client::{
    AttachRejectedOrClientError, LocalClient, LocalClientConfig, LocalClientError, LocalConnector,
    LocalEndpoint, LocalFrameStream, LocalTransport, connect_with,
};
use selvedge_local_protocol::{
    AttachAccepted, AttachRejected, AttachRequest, CommandOutcome, CommandRequest, CommandResponse,
    LocalClientCommandId, LocalClientFrame, LocalClientId, LocalClientNoticeFrame,
    LocalClientSnapshot, LocalClientSubscription, LocalDetailLevel, LocalNotice, LocalNoticeLevel,
    LocalSnapshotMode, LocalTaskScope, ReadyResponse, ReadyState,
};
use tokio::sync::oneshot;

pub type FakeTransportStateHandle = Arc<Mutex<FakeTransportState>>;

#[derive(Clone)]
pub struct FakeLocalTransport {
    state: FakeTransportStateHandle,
}

pub struct FakeTransportState {
    pub connected_configs: Vec<LocalClientConfig>,
    pub ready_calls: usize,
    pub command_calls: usize,
    pub attach_calls: usize,
    pub close_calls: usize,
    pub close_action: CloseAction,
    pub ready_responses: VecDeque<ReadyAction>,
    pub command_responses: VecDeque<CommandAction>,
    pub attach_responses: VecDeque<AttachAction>,
}

#[derive(Clone, Copy)]
pub enum CloseAction {
    Complete,
    Hang,
}

pub enum ReadyAction {
    Response(Result<ReadyResponse, LocalClientError>),
    Hang,
}

pub enum CommandAction {
    Response(Result<CommandResponse, LocalClientError>),
    WaitForRelease {
        release_rx: oneshot::Receiver<()>,
        response: Result<CommandResponse, LocalClientError>,
    },
    Hang,
}

pub enum AttachAction {
    Response(Result<(AttachAccepted, LocalFrameStream), AttachRejectedOrClientError>),
    Accepted(Vec<Result<LocalClientFrame, LocalClientError>>),
    Rejected(AttachRejected),
    Pending,
    Hang,
}

pub struct DropNotifyingStream {
    pub drops: Arc<AtomicUsize>,
}

pub struct PollNotifyingStream {
    pub polled: Option<oneshot::Sender<()>>,
}

impl Stream for DropNotifyingStream {
    type Item = Result<LocalClientFrame, LocalClientError>;

    fn poll_next(self: Pin<&mut Self>, _context: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        Poll::Pending
    }
}

impl Stream for PollNotifyingStream {
    type Item = Result<LocalClientFrame, LocalClientError>;

    fn poll_next(mut self: Pin<&mut Self>, _context: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        if let Some(polled) = self.polled.take() {
            let _ = polled.send(());
        }
        Poll::Pending
    }
}

impl Drop for DropNotifyingStream {
    fn drop(&mut self) {
        self.drops.fetch_add(1, Ordering::SeqCst);
    }
}

impl FakeTransportState {
    pub fn new_handle() -> FakeTransportStateHandle {
        Arc::new(Mutex::new(Self {
            connected_configs: Vec::new(),
            ready_calls: 0,
            command_calls: 0,
            attach_calls: 0,
            close_calls: 0,
            close_action: CloseAction::Complete,
            ready_responses: VecDeque::new(),
            command_responses: VecDeque::new(),
            attach_responses: VecDeque::new(),
        }))
    }
}

pub struct FakeLocalConnector {
    plan: Result<FakeTransportStateHandle, LocalClientError>,
}

impl FakeLocalConnector {
    pub fn new(plan: Result<FakeTransportStateHandle, LocalClientError>) -> Self {
        Self { plan }
    }
}

impl LocalConnector for FakeLocalConnector {
    type Transport = FakeLocalTransport;

    async fn connect(self, config: LocalClientConfig) -> Result<Self::Transport, LocalClientError> {
        let state = self.plan?;
        state
            .lock()
            .expect("fake state")
            .connected_configs
            .push(config);
        Ok(FakeLocalTransport { state })
    }
}

impl LocalTransport for FakeLocalTransport {
    async fn ready(
        &self,
        _request: selvedge_local_protocol::ReadyRequest,
    ) -> Result<ReadyResponse, LocalClientError> {
        let action = {
            let mut state = self.state.lock().expect("fake state");
            state.ready_calls += 1;
            state
                .ready_responses
                .pop_front()
                .unwrap_or(ReadyAction::Response(Ok(ReadyResponse {
                    state: ReadyState::Ready,
                })))
        };

        match action {
            ReadyAction::Response(response) => response,
            ReadyAction::Hang => future::pending().await,
        }
    }

    async fn submit_command(
        &self,
        request: CommandRequest,
    ) -> Result<CommandResponse, LocalClientError> {
        let action = {
            let mut state = self.state.lock().expect("fake state");
            state.command_calls += 1;
            state.command_responses.pop_front().unwrap_or_else(|| {
                CommandAction::Response(Ok(CommandResponse {
                    client_command_id: request.client_command_id,
                    outcome: CommandOutcome::Accepted,
                }))
            })
        };

        match action {
            CommandAction::Response(response) => response,
            CommandAction::WaitForRelease {
                release_rx,
                response,
            } => {
                let _ = release_rx.await;
                response
            }
            CommandAction::Hang => future::pending().await,
        }
    }

    async fn attach(
        &self,
        request: AttachRequest,
    ) -> Result<(AttachAccepted, LocalFrameStream), AttachRejectedOrClientError> {
        let action = {
            let mut state = self.state.lock().expect("fake state");
            state.attach_calls += 1;
            state.attach_responses.pop_front()
        };

        match action {
            Some(AttachAction::Response(response)) => response,
            Some(AttachAction::Accepted(frames)) => Ok((
                AttachAccepted {
                    client_id: request.client_id,
                    client_command_id: request.client_command_id,
                },
                Box::pin(stream::iter(frames)) as LocalFrameStream,
            )),
            Some(AttachAction::Rejected(rejected)) => {
                Err(AttachRejectedOrClientError::Rejected(rejected))
            }
            Some(AttachAction::Pending) => Ok((
                AttachAccepted {
                    client_id: request.client_id,
                    client_command_id: request.client_command_id,
                },
                Box::pin(stream::pending()) as LocalFrameStream,
            )),
            Some(AttachAction::Hang) => future::pending().await,
            None => Ok((
                AttachAccepted {
                    client_id: request.client_id,
                    client_command_id: request.client_command_id,
                },
                Box::pin(stream::empty()) as LocalFrameStream,
            )),
        }
    }

    async fn close(&self) {
        let action = {
            let mut state = self.state.lock().expect("fake state");
            state.close_calls += 1;
            state.close_action
        };

        match action {
            CloseAction::Complete => {}
            CloseAction::Hang => future::pending().await,
        }
    }
}

pub fn valid_local_config() -> LocalClientConfig {
    LocalClientConfig {
        endpoint: LocalEndpoint::TcpIpv4 { port: 17691 },
        request_timeout: Duration::from_secs(1),
    }
}

pub async fn connected_client(state: FakeTransportStateHandle) -> LocalClient<FakeLocalTransport> {
    connected_client_with_timeout(state, Duration::from_secs(1)).await
}

pub async fn connected_client_with_timeout(
    state: FakeTransportStateHandle,
    request_timeout: Duration,
) -> LocalClient<FakeLocalTransport> {
    connect_with(
        LocalClientConfig {
            endpoint: LocalEndpoint::TcpIpv4 { port: 17691 },
            request_timeout,
        },
        FakeLocalConnector::new(Ok(state)),
    )
    .await
    .expect("connect client")
}

pub fn valid_command(command_id: &str) -> CommandRequest {
    CommandRequest {
        client_id: LocalClientId::new("client-1").expect("client id"),
        client_command_id: LocalClientCommandId::new(command_id).expect("command id"),
        command_name: "send-user-input".to_owned(),
        payload: serde_json::json!({"message": "hello"}),
    }
}

pub fn noop_command(command_id: &str) -> CommandRequest {
    CommandRequest {
        client_id: LocalClientId::new("client-1").expect("client id"),
        client_command_id: LocalClientCommandId::new(command_id).expect("command id"),
        command_name: "noop".to_owned(),
        payload: serde_json::json!({}),
    }
}

pub fn valid_attach(command_id: &str) -> AttachRequest {
    valid_attach_for("client-1", command_id)
}

pub fn valid_attach_for(client_id: &str, command_id: &str) -> AttachRequest {
    AttachRequest {
        client_id: LocalClientId::new(client_id).expect("client id"),
        client_command_id: LocalClientCommandId::new(command_id).expect("command id"),
        subscription: LocalClientSubscription {
            task_scope: LocalTaskScope::AllTasks,
            detail_level: LocalDetailLevel::Summary,
            snapshot_mode: LocalSnapshotMode::CurrentState,
            include_model_call_status: false,
            include_tool_execution_status: false,
            include_debug_notices: false,
        },
    }
}

pub fn notice_frame(seq: u64) -> LocalClientFrame {
    LocalClientFrame::Notice(LocalClientNoticeFrame {
        delivery_seq: seq,
        client_command_id: LocalClientCommandId::new(format!("notice-{seq}")).expect("command id"),
        notice: LocalNotice {
            level: LocalNoticeLevel::Info,
            kind: selvedge_local_protocol::LocalNoticeKind::Text,
            message_text: format!("notice {seq}"),
        },
    })
}

pub async fn next_seq(stream: &mut LocalFrameStream) -> Result<u64, LocalClientError> {
    match stream.next().await {
        Some(Ok(LocalClientFrame::Notice(frame))) => Ok(frame.delivery_seq),
        Some(Ok(_)) => Err(LocalClientError::TransportFailed(
            "unexpected frame kind".to_owned(),
        )),
        Some(Err(error)) => Err(error),
        None => Err(LocalClientError::StreamClosed),
    }
}

pub fn empty_local_snapshot() -> LocalClientSnapshot {
    LocalClientSnapshot {
        generated_at: 1,
        tasks: Vec::new(),
        task_parent_edges: Vec::new(),
        history_nodes: Vec::new(),
        task_versions: Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn concurrent_connections_consume_their_own_plans() {
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("test runtime")
            .block_on(async {
                let first = FakeTransportState::new_handle();
                let second = FakeTransportState::new_handle();
                let first_config = valid_local_config();
                let second_config = LocalClientConfig {
                    endpoint: LocalEndpoint::TcpIpv4 { port: 17692 },
                    ..valid_local_config()
                };
                let (first_client, second_client) = futures_util::future::join(
                    connect_with(
                        first_config.clone(),
                        FakeLocalConnector::new(Ok(first.clone())),
                    ),
                    connect_with(
                        second_config.clone(),
                        FakeLocalConnector::new(Ok(second.clone())),
                    ),
                )
                .await;
                first_client.expect("first connection");
                second_client.expect("second connection");
                assert_eq!(
                    first.lock().expect("first state").connected_configs,
                    vec![first_config]
                );
                assert_eq!(
                    second.lock().expect("second state").connected_configs,
                    vec![second_config]
                );
            });
    }
}
