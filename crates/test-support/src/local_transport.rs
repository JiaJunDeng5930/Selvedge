use std::collections::VecDeque;
use std::future;
use std::pin::Pin;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, LazyLock, Mutex};
use std::task::{Context, Poll};
use std::time::Duration;

use futures_core::Stream;
use futures_util::StreamExt;
use futures_util::stream;
use selvedge_local_client::{
    AttachRejectedOrClientError, LocalClient, LocalClientConfig, LocalClientError, LocalEndpoint,
    LocalFrameStream, LocalTransport, connect,
};
use selvedge_local_protocol::{
    AttachAccepted, AttachRejected, AttachRequest, CommandOutcome, CommandRequest, CommandResponse,
    LocalClientCommandId, LocalClientFrame, LocalClientId, LocalClientNoticeFrame,
    LocalClientSnapshot, LocalClientSubscription, LocalDetailLevel, LocalNotice, LocalNoticeLevel,
    LocalSnapshotMode, LocalTaskScope, ReadyResponse, ReadyState, current_protocol_version,
};
use tokio::sync::oneshot;

static CONNECT_PLAN: LazyLock<Mutex<Option<Result<FakeTransportStateHandle, LocalClientError>>>> =
    LazyLock::new(|| Mutex::new(None));

// @behavior selvedge.testsupport.local_transport.state_handle Fake transport state handles share scripted responses and recorded calls across the fake client boundary.
pub type FakeTransportStateHandle = Arc<Mutex<FakeTransportState>>;

// @behavior selvedge.testsupport.local_transport Local transport test support scripts local protocol transport responses and stream behavior.
// @behavior selvedge.testsupport.local_transport.fake Scripted local transports expose controllable local protocol responses and call counts for client-facing tests.
#[derive(Clone)]
pub struct FakeLocalTransport {
    state: FakeTransportStateHandle,
}

// @behavior selvedge.testsupport.local_transport.state Fake transport state records connection configs, call counts, close behavior, and scripted response queues.
pub struct FakeTransportState {
    // @behavior selvedge.testsupport.local_transport.connected_configs Fake transport state records every local client config passed to connect.
    pub connected_configs: Vec<LocalClientConfig>,
    // @behavior selvedge.testsupport.local_transport.ready_calls Fake transport state counts ready requests.
    pub ready_calls: usize,
    // @behavior selvedge.testsupport.local_transport.command_calls Fake transport state counts command submissions.
    pub command_calls: usize,
    // @behavior selvedge.testsupport.local_transport.attach_calls Fake transport state counts attach requests.
    pub attach_calls: usize,
    // @behavior selvedge.testsupport.local_transport.close_calls Fake transport state counts close requests.
    pub close_calls: usize,
    // @behavior selvedge.testsupport.local_transport.close_script Fake transport state stores the close action script.
    pub close_action: CloseAction,
    // @behavior selvedge.testsupport.local_transport.ready_script Fake transport state stores queued ready response actions.
    pub ready_responses: VecDeque<ReadyAction>,
    // @behavior selvedge.testsupport.local_transport.command_script Fake transport state stores queued command response actions.
    pub command_responses: VecDeque<CommandAction>,
    // @behavior selvedge.testsupport.local_transport.attach_script Fake transport state stores queued attach response actions.
    pub attach_responses: VecDeque<AttachAction>,
}

// @behavior selvedge.testsupport.local_transport.close_action Close actions script whether transport close completes or remains pending.
#[derive(Clone, Copy)]
pub enum CloseAction {
    Complete,
    Hang,
}

// @behavior selvedge.testsupport.local_transport.ready_action Ready actions script a ready response or a pending ready call.
pub enum ReadyAction {
    Response(Result<ReadyResponse, LocalClientError>),
    Hang,
}

// @behavior selvedge.testsupport.local_transport.command_action Command actions script command responses, release-gated responses, or pending command calls.
pub enum CommandAction {
    Response(Result<CommandResponse, LocalClientError>),
    WaitForRelease {
        release_rx: oneshot::Receiver<()>,
        response: Result<CommandResponse, LocalClientError>,
    },
    Hang,
}

// @behavior selvedge.testsupport.local_transport.attach_action Attach actions script accepted streams, rejected attach requests, client errors, or pending attach calls.
pub enum AttachAction {
    Response(Result<(AttachAccepted, LocalFrameStream), AttachRejectedOrClientError>),
    Accepted(Vec<Result<LocalClientFrame, LocalClientError>>),
    Rejected(AttachRejected),
    Pending,
    Hang,
}

// @behavior selvedge.testsupport.local_transport.drop_stream Drop-notifying streams let tests observe when active attach streams are released.
pub struct DropNotifyingStream {
    // @behavior selvedge.testsupport.local_transport.drop_counter Drop-notifying streams increment the shared counter when the stream is dropped.
    pub drops: Arc<AtomicUsize>,
}

// @behavior selvedge.testsupport.local_transport.poll_stream Poll-notifying streams let tests observe when pending attach readers are polled.
pub struct PollNotifyingStream {
    // @behavior selvedge.testsupport.local_transport.poll_sender Poll-notifying streams signal the sender once when first polled.
    pub polled: Option<oneshot::Sender<()>>,
}

impl Stream for DropNotifyingStream {
    type Item = Result<LocalClientFrame, LocalClientError>;

    // @behavior selvedge.testsupport.local_transport.drop_stream.poll Drop-notifying streams remain pending when polled.
    fn poll_next(self: Pin<&mut Self>, _context: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        Poll::Pending
    }
}

impl Stream for PollNotifyingStream {
    type Item = Result<LocalClientFrame, LocalClientError>;

    // @behavior selvedge.testsupport.local_transport.poll_stream.poll Poll-notifying streams notify once and then remain pending when polled.
    fn poll_next(mut self: Pin<&mut Self>, _context: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        if let Some(polled) = self.polled.take() {
            // @behavior selvedge.testsupport.local_transport.poll_stream.signal Poll-notifying streams ignore receiver cancellation after recording the poll.
            let _ = polled.send(());
        }
        Poll::Pending
    }
}

impl Drop for DropNotifyingStream {
    // @behavior selvedge.testsupport.local_transport.drop_stream.drop Drop-notifying streams increment the shared drop counter exactly once per dropped stream.
    fn drop(&mut self) {
        self.drops.fetch_add(1, Ordering::SeqCst);
    }
}

impl FakeTransportState {
    // @behavior selvedge.testsupport.local_transport.new_state Fake transport state handles start with empty scripts and zero call counts.
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

impl LocalTransport for FakeLocalTransport {
    // @behavior selvedge.testsupport.local_transport.connect Fake local transport consumes one installed connect plan and records the client config.
    async fn connect(config: LocalClientConfig) -> Result<Self, LocalClientError>
    where
        Self: Sized,
    {
        let state = match CONNECT_PLAN.lock().expect("connect plan lock").take() {
            Some(Ok(state)) => state,
            Some(Err(error)) => return Err(error),
            None => {
                return Err(LocalClientError::ConnectFailed(
                    "missing connect plan".to_owned(),
                ));
            }
        };
        state
            .lock()
            // @behavior selvedge.testsupport.local_transport.connect.state_lock Fake local transport fails fixture setup when the shared state lock is poisoned.
            .expect("fake state")
            .connected_configs
            .push(config);
        Ok(Self { state })
    }

    // @behavior selvedge.testsupport.local_transport.ready Fake local transport consumes one ready action and defaults to ready when no action is queued.
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
                    protocol_version: current_protocol_version(),
                    state: ReadyState::Ready,
                })))
        };

        match action {
            ReadyAction::Response(response) => response,
            ReadyAction::Hang => future::pending().await,
        }
    }

    // @behavior selvedge.testsupport.local_transport.command Fake local transport consumes one command action and defaults to accepting the submitted command.
    async fn submit_command(
        &self,
        request: CommandRequest,
    ) -> Result<CommandResponse, LocalClientError> {
        let action = {
            let mut state = self.state.lock().expect("fake state");
            state.command_calls += 1;
            state.command_responses.pop_front().unwrap_or_else(|| {
                CommandAction::Response(Ok(CommandResponse {
                    protocol_version: current_protocol_version(),
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

    // @behavior selvedge.testsupport.local_transport.attach Fake local transport consumes one attach action and defaults to an accepted empty stream.
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
                    protocol_version: current_protocol_version(),
                    client_id: request.client_id,
                    client_command_id: request.client_command_id,
                },
                Box::pin(stream::iter(frames)) as LocalFrameStream,
            )),
            Some(AttachAction::Rejected(rejected)) => {
                // @behavior selvedge.testsupport.local_transport.attach.rejected Fake local transport returns scripted attach rejections unchanged.
                Err(AttachRejectedOrClientError::Rejected(rejected))
            }
            Some(AttachAction::Pending) => Ok((
                AttachAccepted {
                    protocol_version: current_protocol_version(),
                    client_id: request.client_id,
                    client_command_id: request.client_command_id,
                },
                Box::pin(stream::pending()) as LocalFrameStream,
            )),
            Some(AttachAction::Hang) => future::pending().await,
            None => Ok((
                AttachAccepted {
                    protocol_version: current_protocol_version(),
                    client_id: request.client_id,
                    client_command_id: request.client_command_id,
                },
                Box::pin(stream::empty()) as LocalFrameStream,
            )),
        }
    }

    async fn close(&self) {
        // @behavior selvedge.testsupport.local_transport.close Fake local transport consumes the configured close action and records the close call.
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

// @behavior selvedge.testsupport.local_transport.install_connect Tests can install the next fake transport connection outcome.
pub fn install_connect_plan(plan: Result<FakeTransportStateHandle, LocalClientError>) {
    *CONNECT_PLAN.lock().expect("connect plan lock") = Some(plan);
}

// @behavior selvedge.testsupport.local_transport.connect_plan_state Tests can inspect whether a fake transport connection outcome remains installed.
pub fn connect_plan_is_some() -> bool {
    CONNECT_PLAN.lock().expect("connect plan lock").is_some()
}

// @behavior selvedge.testsupport.local_transport.ready_state Tests can create a fake transport state whose first ready response reports ready.
pub fn ready_state() -> FakeTransportStateHandle {
    let state = FakeTransportState::new_handle();
    state
        .lock()
        .expect("fake state")
        .ready_responses
        .push_back(ReadyAction::Response(Ok(ReadyResponse {
            protocol_version: current_protocol_version(),
            state: ReadyState::Ready,
        })));
    state
}

// @behavior selvedge.testsupport.local_transport.valid_local_config Tests can create a valid local client config with a stable loopback port.
pub fn valid_local_config() -> LocalClientConfig {
    LocalClientConfig {
        endpoint: LocalEndpoint::TcpIpv4 { port: 17691 },
        request_timeout: Duration::from_secs(1),
    }
}

// @behavior selvedge.testsupport.local_transport.valid_config Legacy local-client tests can create the standard valid local client config.
pub fn valid_config() -> LocalClientConfig {
    valid_local_config()
}

// @behavior selvedge.testsupport.local_transport.connected_client Tests can connect a fake local client with the standard timeout.
pub async fn connected_client(state: FakeTransportStateHandle) -> LocalClient<FakeLocalTransport> {
    connected_client_with_timeout(state, Duration::from_secs(1)).await
}

// @behavior selvedge.testsupport.local_transport.connected_client_timeout Tests can connect a fake local client with a caller-selected request timeout.
pub async fn connected_client_with_timeout(
    state: FakeTransportStateHandle,
    request_timeout: Duration,
) -> LocalClient<FakeLocalTransport> {
    install_connect_plan(Ok(state));
    connect::<FakeLocalTransport>(LocalClientConfig {
        endpoint: LocalEndpoint::TcpIpv4 { port: 17691 },
        request_timeout,
    })
    .await
    // @behavior selvedge.testsupport.local_transport.connected_client_fail Fake local client fixtures fail the calling test when the scripted connection does not succeed.
    .expect("connect client")
}

// @behavior selvedge.testsupport.local_transport.valid_command Tests can create a valid local command request with a send-user-input payload.
pub fn valid_command(command_id: &str) -> CommandRequest {
    CommandRequest {
        protocol_version: current_protocol_version(),
        client_id: LocalClientId::new("client-1").expect("client id"),
        client_command_id: LocalClientCommandId::new(command_id).expect("command id"),
        command_name: "send-user-input".to_owned(),
        payload: serde_json::json!({"message": "hello"}),
    }
}

// @behavior selvedge.testsupport.local_transport.noop_command Tests can create a valid local command request with a no-op payload.
pub fn noop_command(command_id: &str) -> CommandRequest {
    CommandRequest {
        protocol_version: current_protocol_version(),
        client_id: LocalClientId::new("client-1").expect("client id"),
        client_command_id: LocalClientCommandId::new(command_id).expect("command id"),
        command_name: "noop".to_owned(),
        payload: serde_json::json!({}),
    }
}

// @behavior selvedge.testsupport.local_transport.valid_attach Tests can create a valid local attach request with an all-task summary subscription.
pub fn valid_attach(command_id: &str) -> AttachRequest {
    valid_attach_for("client-1", command_id)
}

// @behavior selvedge.testsupport.local_transport.valid_attach_for Tests can create a valid local attach request for caller-selected client and command IDs.
pub fn valid_attach_for(client_id: &str, command_id: &str) -> AttachRequest {
    AttachRequest {
        protocol_version: current_protocol_version(),
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

// @behavior selvedge.testsupport.local_transport.notice_frame Tests can create a local notice frame with a stable sequence-derived command ID.
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

// @behavior selvedge.testsupport.local_transport.next_seq Tests can read the next notice sequence from a local frame stream.
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

// @behavior selvedge.testsupport.local_transport.empty_snapshot Tests can create an empty local client snapshot with a stable timestamp.
pub fn empty_local_snapshot() -> LocalClientSnapshot {
    LocalClientSnapshot {
        generated_at: 1,
        tasks: Vec::new(),
        task_parent_edges: Vec::new(),
        history_nodes: Vec::new(),
        task_versions: Vec::new(),
    }
}
