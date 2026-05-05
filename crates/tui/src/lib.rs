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
    Disconnected,
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

pub trait TuiCommandMapper: Send + Sync + 'static {
    fn map_input(&self, input_text: &str) -> Result<TuiInputAction, String>;
}

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
        Err(error) => return TuiExitStatus::InvalidArgs(format!("{error:?}")),
    };
    let attach_command_id = match LocalClientCommandId::new(args.attach_command_id) {
        Ok(client_command_id) => client_command_id,
        Err(error) => return TuiExitStatus::InvalidArgs(format!("{error:?}")),
    };

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

    loop {
        match frames.next().await {
            Some(Ok(LocalClientFrame::Snapshot(_))) => break,
            Some(Ok(LocalClientFrame::Notice(_))) | Some(Ok(LocalClientFrame::Event(_))) => {}
            Some(Err(_)) | None => {
                drop(frames);
                return close_after_error(&client, TuiExitStatus::Disconnected).await;
            }
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
            CommandOutcome::Accepted | CommandOutcome::Rejected(_) => {}
        }
    }

    drop(frames);
    let _ = client.close().await;
    TuiExitStatus::Exited
}

async fn close_after_error<T: LocalTransport>(
    client: &selvedge_local_client::LocalClient<T>,
    status: TuiExitStatus,
) -> TuiExitStatus {
    let _ = client.close().await;
    status
}
