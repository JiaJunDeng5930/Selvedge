#![doc = include_str!("../README.md")]

use futures_util::StreamExt;
use selvedge_local_client::{
    AttachRejectedOrClientError, LocalClient, LocalClientConfig, LocalClientError, LocalTransport,
    connect_http,
};
#[cfg(test)]
use selvedge_local_client::{LocalConnector, connect_with};
use selvedge_local_protocol::{
    AttachRequest, CommandOutcome, CommandRequest, LocalClientCommandId, LocalClientFrame,
    LocalClientId, LocalClientSubscription, ReadyRequest, ReadyState,
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
pub enum TuiExitStatus {
    Exited,
    ServerUnavailable,
    ServerNotReady,
    AttachRejected(selvedge_local_protocol::AttachRejectReason),
    CommandRejected(selvedge_local_protocol::CommandRejectReason),
    Disconnected,
    SnapshotTimeout,
    LocalClientFailed(LocalClientError),
    InvalidArgs(String),
}

pub async fn run_tui(args: TuiStartArgs) -> TuiExitStatus {
    let identifiers = match validate_identifiers(&args) {
        Ok(identifiers) => identifiers,
        Err(status) => return status,
    };
    let config = args.client_config.clone();
    run_tui_with_client(args, identifiers, connect_http(config).await).await
}

#[cfg(test)]
async fn run_tui_with_transport<C: LocalConnector>(
    args: TuiStartArgs,
    connector: C,
) -> TuiExitStatus {
    let identifiers = match validate_identifiers(&args) {
        Ok(identifiers) => identifiers,
        Err(status) => return status,
    };
    let config = args.client_config.clone();
    run_tui_with_client(args, identifiers, connect_with(config, connector).await).await
}

async fn run_tui_with_client<T>(
    args: TuiStartArgs,
    identifiers: (LocalClientId, LocalClientCommandId),
    client: Result<LocalClient<T>, LocalClientError>,
) -> TuiExitStatus
where
    T: LocalTransport,
{
    let (client_id, attach_command_id) = identifiers;

    let snapshot_timeout = args.client_config.request_timeout;
    let client = match client {
        Ok(client) => client,
        Err(LocalClientError::ConnectFailed(_)) => return TuiExitStatus::ServerUnavailable,
        Err(error) => return TuiExitStatus::LocalClientFailed(error),
    };

    let ready = client.ready(ReadyRequest {}).await;
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
            client_id,
            client_command_id: attach_command_id,
            subscription: args.subscription,
        })
        .await;
    let (_accepted, mut frames) = match attach {
        Ok(attach) => attach,
        Err(AttachRejectedOrClientError::Rejected(rejected)) => {
            return close_after_error(&client, TuiExitStatus::AttachRejected(rejected.reason))
                .await;
        }
        Err(AttachRejectedOrClientError::Client(error)) => {
            return close_after_error(&client, TuiExitStatus::LocalClientFailed(error)).await;
        }
    };

    match tokio::time::timeout(snapshot_timeout, wait_for_initial_snapshot(&mut frames)).await {
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
                return close_after_error(&client, TuiExitStatus::CommandRejected(reason)).await;
            }
        }
    }

    drop(frames);
    let _ = client.close().await;
    TuiExitStatus::Exited
}

fn validate_identifiers(
    args: &TuiStartArgs,
) -> Result<(LocalClientId, LocalClientCommandId), TuiExitStatus> {
    let client_id = LocalClientId::new(args.client_id.clone())
        .map_err(|error| TuiExitStatus::InvalidArgs(format!("{error:?}")))?;
    let attach_command_id = LocalClientCommandId::new(args.attach_command_id.clone())
        .map_err(|error| TuiExitStatus::InvalidArgs(format!("{error:?}")))?;
    Ok((client_id, attach_command_id))
}

#[cfg(test)]
mod tests;

async fn wait_for_initial_snapshot(
    frames: &mut selvedge_local_client::LocalFrameStream,
) -> Result<(), TuiExitStatus> {
    loop {
        match frames.next().await {
            Some(Ok(LocalClientFrame::Snapshot(_))) => return Ok(()),
            Some(Ok(LocalClientFrame::Notice(_))) | Some(Ok(LocalClientFrame::Event(_))) => {}
            Some(Err(LocalClientError::StreamClosed)) => return Err(TuiExitStatus::Disconnected),
            Some(Err(error)) => return Err(TuiExitStatus::LocalClientFailed(error)),
            None => return Err(TuiExitStatus::Disconnected),
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
