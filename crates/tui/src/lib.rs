#![doc = include_str!("../README.md")]
//! @behavior selvedge.client.tui The TUI exposes local server connection, attach, snapshot, command, and exit status behavior.
//! @behavior selvedge.client.tui.run The TUI connects to a local server, checks readiness, attaches, waits for a snapshot, submits optional initial input, and returns a typed exit status.
//! @behavior selvedge.client.tui.r2 TUI startup preserves connection, readiness, attach, snapshot, command, and exit status behavior.

use futures_util::StreamExt;
use selvedge_local_client::{
    AttachRejectedOrClientError, LocalClientConfig, LocalClientError, LocalTransport, connect,
};
use selvedge_local_protocol::{
    AttachRequest, CommandOutcome, CommandRequest, LocalClientCommandId, LocalClientFrame,
    LocalClientId, LocalClientSubscription, ReadyRequest, ReadyState, current_protocol_version,
};

#[derive(Clone, Debug, PartialEq)]
// @behavior selvedge.client.tui.r2.start_args TUI startup receives local client configuration, attach identity, subscription scope, and optional initial command from its caller.
pub struct TuiStartArgs {
    // @behavior selvedge.client.tui.r2.start_args.client_config TUI startup uses the supplied local client configuration for connection and snapshot timeout behavior.
    pub client_config: LocalClientConfig,
    // @behavior selvedge.client.tui.r2.start_args.client_id TUI startup sends the supplied client ID in the attach request.
    pub client_id: String,
    // @behavior selvedge.client.tui.r2.start_args.attach_command_id TUI startup sends the supplied attach command ID in the attach request.
    pub attach_command_id: String,
    // @behavior selvedge.client.tui.r2.start_args.subscription TUI startup sends the supplied subscription scope in the attach request.
    pub subscription: LocalClientSubscription,
    // @behavior selvedge.client.tui.r2.start_args.initial_command TUI startup submits the supplied initial command after the first snapshot arrives.
    pub initial_command: Option<CommandRequest>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.client.tui.r2.runtime_state TUI runtime states describe startup, attach, interactive, disconnect, exit, and failure phases visible to callers.
pub enum TuiRuntimeState {
    Starting,
    ConnectingServer,
    Attaching,
    WaitingSnapshot,
    Interactive,
    Disconnecting,
    Exited,
    Failed,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.client.tui.r2.exit_status TUI startup returns a typed exit status for success, unavailable server, readiness, attach, command, disconnection, timeout, terminal, local client, and argument outcomes.
pub enum TuiExitStatus {
    Exited,
    ServerUnavailable,
    ServerNotReady,
    // @behavior selvedge.client.tui.r2.exit_status.attach_rejected TUI startup reports the local protocol attach rejection reason as an attach rejected status string.
    AttachRejected(String),
    // @behavior selvedge.client.tui.r2.exit_status.command_rejected TUI startup reports the initial command rejection reason as a command rejected status string.
    CommandRejected(String),
    Disconnected,
    SnapshotTimeout,
    // @behavior selvedge.client.tui.r2.exit_status.terminal_failed TUI startup reports terminal setup or rendering failure text as a terminal failed status string.
    TerminalFailed(String),
    // @behavior selvedge.client.tui.r2.exit_status.local_client_failed TUI startup reports local client transport failures as local client failed statuses.
    LocalClientFailed(LocalClientError),
    // @behavior selvedge.client.tui.r2.exit_status.invalid_args TUI startup reports invalid local client or command IDs as invalid argument status strings.
    InvalidArgs(String),
}

#[derive(Clone, Debug, PartialEq)]
// @behavior selvedge.client.tui.r2.input_action TUI input mapping returns command submission, exit, or noop actions to the runtime.
pub enum TuiInputAction {
    // @behavior selvedge.client.tui.r2.input_action.submit_command TUI input mapping can produce a local command request for submission.
    SubmitCommand(CommandRequest),
    Exit,
    Noop,
}

// @behavior selvedge.client.tui.r2.command_mapper TUI command mapping converts terminal text into command submission, exit, noop, or mapper error outcomes.
// @intent selvedge.client.tui.r2.command_mapper.intent The TUI command mapper isolates terminal input parsing from local client transport startup.
pub trait TuiCommandMapper: Send + Sync + 'static {
    /// @behavior selvedge.client.tui.r2.map_input TUI input mapping converts terminal text into a command submission, exit action, noop, or mapper error.
    fn map_input(&self, input_text: &str) -> Result<TuiInputAction, String>;
}

// @behavior selvedge.client.tui.r2.run_entry TUI startup returns a typed status after validating IDs, connecting, probing readiness, attaching, waiting for a snapshot, and handling an optional initial command.
pub async fn run_tui<T, M>(args: TuiStartArgs, mapper: M) -> TuiExitStatus
where
    T: LocalTransport,
    M: TuiCommandMapper,
{
    // NOTE(package-order): `selvedge-local-client` currently exposes only the
    // `LocalTransport` abstraction. After the real localhost transport lands in
    // that dependency package, this entry point must be repaired to select and
    // call that concrete transport directly instead of requiring `T`.
    let _mapper = mapper;

    let client_id = match LocalClientId::new(args.client_id) {
        Ok(client_id) => client_id,
        // @behavior selvedge.client.tui.r2.invalid_client_id TUI startup returns InvalidArgs when the supplied client ID fails local protocol validation.
        Err(error) => return TuiExitStatus::InvalidArgs(format!("{error:?}")),
    };
    let attach_command_id = match LocalClientCommandId::new(args.attach_command_id) {
        Ok(client_command_id) => client_command_id,
        // @behavior selvedge.client.tui.r2.invalid_attach_command_id TUI startup returns InvalidArgs when the supplied attach command ID fails local protocol validation.
        Err(error) => return TuiExitStatus::InvalidArgs(format!("{error:?}")),
    };

    let snapshot_timeout = args.client_config.request_timeout;
    let client = match connect::<T>(args.client_config).await {
        Ok(client) => client,
        // @behavior selvedge.client.tui.r2.connect_unavailable TUI startup returns ServerUnavailable when the local client cannot connect to the server endpoint.
        Err(LocalClientError::ConnectFailed(_)) => return TuiExitStatus::ServerUnavailable,
        // @behavior selvedge.client.tui.r2.connect_failure TUI startup returns LocalClientFailed when connection setup fails for a local client reason other than endpoint unavailability.
        Err(error) => return TuiExitStatus::LocalClientFailed(error),
    };

    let ready = client
        .ready(ReadyRequest {
            protocol_version: current_protocol_version(),
        })
        .await;
    let ready = match ready {
        Ok(ready) => ready,
        // @behavior selvedge.client.tui.r2.ready_failure TUI startup closes the local client and returns LocalClientFailed when the readiness request fails.
        Err(error) => {
            return close_after_error(&client, TuiExitStatus::LocalClientFailed(error)).await;
        }
    };
    if ready.state == ReadyState::NotReady {
        return close_after_error(&client, TuiExitStatus::ServerNotReady).await;
    }

    let attach = client
        .attach(AttachRequest {
            protocol_version: current_protocol_version(),
            client_id,
            client_command_id: attach_command_id,
            subscription: args.subscription,
        })
        .await;
    let (_accepted, mut frames) = match attach {
        Ok(attach) => attach,
        // @behavior selvedge.client.tui.r2.attach_rejected TUI startup closes the local client and returns AttachRejected when the server rejects the attach request.
        Err(AttachRejectedOrClientError::Rejected(rejected)) => {
            return close_after_error(
                &client,
                TuiExitStatus::AttachRejected(format!("{:?}", rejected.reason)),
            )
            .await;
        }
        // @behavior selvedge.client.tui.r2.attach_client_failure TUI startup closes the local client and returns LocalClientFailed when the attach request fails at the client layer.
        Err(AttachRejectedOrClientError::Client(error)) => {
            return close_after_error(&client, TuiExitStatus::LocalClientFailed(error)).await;
        }
    };

    // @behavior selvedge.client.tui.r2.snapshot_wait TUI startup waits for the first snapshot before submitting the optional initial command or returning success.
    match tokio::time::timeout(snapshot_timeout, wait_for_initial_snapshot(&mut frames)).await {
        Ok(Ok(())) => {}
        // @behavior selvedge.client.tui.r2.snapshot_stream_failure TUI startup closes the local client and returns the snapshot stream failure status when the attach stream ends before a snapshot.
        Ok(Err(status)) => {
            drop(frames);
            return close_after_error(&client, status).await;
        }
        // @behavior selvedge.client.tui.r2.snapshot_timeout TUI startup closes the local client and returns SnapshotTimeout when no snapshot arrives before the configured request timeout.
        Err(_) => {
            drop(frames);
            return close_after_error(&client, TuiExitStatus::SnapshotTimeout).await;
        }
    }

    if let Some(command) = args.initial_command {
        let response = match client.submit_command(command).await {
            Ok(response) => response,
            // @behavior selvedge.client.tui.r2.initial_command_failure TUI startup closes the local client and returns LocalClientFailed when initial command submission fails at the client layer.
            Err(error) => {
                drop(frames);
                return close_after_error(&client, TuiExitStatus::LocalClientFailed(error)).await;
            }
        };
        match response.outcome {
            CommandOutcome::Accepted => {}
            CommandOutcome::Rejected(reason) => {
                drop(frames);
                return close_after_error(
                    &client,
                    TuiExitStatus::CommandRejected(format!("{reason:?}")),
                )
                .await;
            }
        }
    }

    drop(frames);
    let _ = client.close().await;
    TuiExitStatus::Exited
}

async fn wait_for_initial_snapshot(
    frames: &mut selvedge_local_client::LocalFrameStream,
    // @behavior selvedge.client.tui.r2.snapshot_stream TUI snapshot waiting consumes attach stream frames until the first snapshot arrives or the stream disconnects.
) -> Result<(), TuiExitStatus> {
    loop {
        match frames.next().await {
            Some(Ok(LocalClientFrame::Snapshot(_))) => return Ok(()),
            Some(Ok(LocalClientFrame::Notice(_))) | Some(Ok(LocalClientFrame::Event(_))) => {}
            // @behavior selvedge.client.tui.r2.snapshot_stream.disconnected TUI snapshot waiting returns Disconnected when the attach stream errors or closes before a snapshot.
            Some(Err(_)) | None => return Err(TuiExitStatus::Disconnected),
        }
    }
}

async fn close_after_error<T: LocalTransport>(
    client: &selvedge_local_client::LocalClient<T>,
    status: TuiExitStatus,
) -> TuiExitStatus {
    let _ = client.close().await;
    status
}
