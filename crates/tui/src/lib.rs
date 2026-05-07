#![doc = include_str!("../README.md")]

use futures_util::StreamExt;
use selvedge_local_client::{
    AttachRejectedOrClientError, LocalClientConfig, LocalClientError, LocalTransport, connect,
};
use selvedge_local_protocol::{
    AttachRequest, CommandOutcome, CommandRequest, LocalClientCommandId, LocalClientFrame,
    LocalClientId, LocalClientSubscription, ReadyRequest, ReadyState, current_protocol_version,
};

#[derive(Clone, Debug, PartialEq)]
pub struct TuiStartArgs {
    pub client_config: LocalClientConfig,
    pub client_id: String,
    pub attach_command_id: String,
    pub subscription: LocalClientSubscription,
    pub initial_command: Option<CommandRequest>,
    pub snapshot_timeout: std::time::Duration,
}

#[derive(Clone, Debug, PartialEq, Eq)]
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
pub enum TuiExitStatus {
    Exited,
    ServerUnavailable,
    ServerNotReady,
    AttachRejected(String),
    CommandRejected(String),
    Disconnected,
    SnapshotTimeout,
    TerminalFailed(String),
    LocalClientFailed(LocalClientError),
    InvalidArgs(String),
}

#[derive(Clone, Debug, PartialEq)]
pub enum TuiInputAction {
    SubmitCommand(CommandRequest),
    Exit,
    Noop,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TuiTerminalInput {
    Line(String),
    Eof,
}

pub trait TuiCommandMapper: Send + Sync + 'static {
    fn map_input(&self, input_text: &str) -> Result<TuiInputAction, String>;
}

pub trait TuiTerminal: Send + Sync + 'static {
    fn read_input(&mut self) -> Result<TuiTerminalInput, String>;

    fn render_frame(&mut self, frame: &LocalClientFrame) -> Result<(), String>;

    fn render_error(&mut self, error: &str) -> Result<(), String>;
}

pub async fn run_tui<T, M, Term>(args: TuiStartArgs, mapper: M, terminal: Term) -> TuiExitStatus
where
    T: LocalTransport,
    M: TuiCommandMapper,
    Term: TuiTerminal,
{
    // NOTE(package-order): `selvedge-local-client` currently exposes only the
    // `LocalTransport` abstraction. After the real localhost transport lands in
    // that dependency package, this entry point must be repaired to select and
    // call that concrete transport directly instead of requiring `T`.
    let mut terminal = terminal;

    let client_id = match LocalClientId::new(args.client_id) {
        Ok(client_id) => client_id,
        Err(error) => return TuiExitStatus::InvalidArgs(format!("{error:?}")),
    };
    let attach_command_id = match LocalClientCommandId::new(args.attach_command_id) {
        Ok(client_command_id) => client_command_id,
        Err(error) => return TuiExitStatus::InvalidArgs(format!("{error:?}")),
    };

    let snapshot_timeout = args.snapshot_timeout;
    let client = match connect::<T>(args.client_config).await {
        Ok(client) => client,
        Err(LocalClientError::ConnectFailed(_)) => return TuiExitStatus::ServerUnavailable,
        Err(error) => return TuiExitStatus::LocalClientFailed(error),
    };

    let ready = client
        .ready(ReadyRequest {
            protocol_version: current_protocol_version(),
        })
        .await;
    let ready = match ready {
        Ok(ready) => ready,
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
        Err(AttachRejectedOrClientError::Rejected(rejected)) => {
            return close_after_error(
                &client,
                TuiExitStatus::AttachRejected(format!("{:?}", rejected.reason)),
            )
            .await;
        }
        Err(AttachRejectedOrClientError::Client(error)) => {
            return close_after_error(&client, TuiExitStatus::LocalClientFailed(error)).await;
        }
    };

    match tokio::time::timeout(
        snapshot_timeout,
        wait_for_initial_snapshot(&mut frames, &mut terminal),
    )
    .await
    {
        Ok(Ok(())) => {}
        Ok(Err(status)) => {
            drop(frames);
            return close_after_error(&client, status).await;
        }
        Err(_) => {
            drop(frames);
            return close_after_error(&client, TuiExitStatus::SnapshotTimeout).await;
        }
    }

    if let Some(command) = args.initial_command {
        let response = match client.submit_command(command).await {
            Ok(response) => response,
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

    let status = interactive_loop(&client, &mut frames, &mapper, &mut terminal).await;
    drop(frames);
    close_after_error(&client, status).await
}

async fn wait_for_initial_snapshot<Term: TuiTerminal>(
    frames: &mut selvedge_local_client::LocalFrameStream,
    terminal: &mut Term,
) -> Result<(), TuiExitStatus> {
    loop {
        match frames.next().await {
            Some(Ok(frame @ LocalClientFrame::Snapshot(_))) => {
                terminal
                    .render_frame(&frame)
                    .map_err(TuiExitStatus::TerminalFailed)?;
                return Ok(());
            }
            Some(Ok(frame @ LocalClientFrame::Notice(_)))
            | Some(Ok(frame @ LocalClientFrame::Event(_))) => {
                terminal
                    .render_frame(&frame)
                    .map_err(TuiExitStatus::TerminalFailed)?;
            }
            Some(Err(_)) | None => return Err(TuiExitStatus::Disconnected),
        }
    }
}

async fn interactive_loop<T, M, Term>(
    client: &selvedge_local_client::LocalClient<T>,
    frames: &mut selvedge_local_client::LocalFrameStream,
    mapper: &M,
    terminal: &mut Term,
) -> TuiExitStatus
where
    T: LocalTransport,
    M: TuiCommandMapper,
    Term: TuiTerminal,
{
    loop {
        if let Err(status) = drain_ready_frames(frames, terminal).await {
            return status;
        }

        let input = match terminal.read_input() {
            Ok(input) => input,
            Err(error) => {
                let _ = terminal.render_error(&error);
                return TuiExitStatus::TerminalFailed(error);
            }
        };

        let input_text = match input {
            TuiTerminalInput::Eof => return TuiExitStatus::Exited,
            TuiTerminalInput::Line(input_text) => input_text,
        };

        match mapper.map_input(&input_text) {
            Ok(TuiInputAction::Noop) => {}
            Ok(TuiInputAction::Exit) => return TuiExitStatus::Exited,
            Ok(TuiInputAction::SubmitCommand(command)) => {
                let response = match client.submit_command(command).await {
                    Ok(response) => response,
                    Err(error) => return TuiExitStatus::LocalClientFailed(error),
                };
                match response.outcome {
                    CommandOutcome::Accepted => {
                        if let Err(status) = drain_ready_frames(frames, terminal).await {
                            return status;
                        }
                    }
                    CommandOutcome::Rejected(reason) => {
                        return TuiExitStatus::CommandRejected(format!("{reason:?}"));
                    }
                }
            }
            Err(error) => {
                let _ = terminal.render_error(&error);
                return TuiExitStatus::TerminalFailed(error);
            }
        }
    }
}

async fn drain_ready_frames<Term: TuiTerminal>(
    frames: &mut selvedge_local_client::LocalFrameStream,
    terminal: &mut Term,
) -> Result<(), TuiExitStatus> {
    loop {
        match tokio::time::timeout(std::time::Duration::from_millis(1), frames.next()).await {
            Ok(Some(Ok(frame))) => terminal
                .render_frame(&frame)
                .map_err(TuiExitStatus::TerminalFailed)?,
            Ok(Some(Err(_))) => return Err(TuiExitStatus::Disconnected),
            Ok(None) => return Ok(()),
            Err(_) => return Ok(()),
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
