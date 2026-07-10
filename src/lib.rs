use std::collections::HashMap;
use std::future::Future;
use std::process::Stdio;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use chatgpt_login::{
    ChatgptLoginProgress, ChatgptLoginProgressError, ChatgptLoginProgressFuture,
    ChatgptLoginProgressSink, run_chatgpt_login,
};
use futures_util::StreamExt;
use selvedge_api::ApiExecutorConfig;
use selvedge_client_sync::{
    ClientSnapshotBuildFuture, ClientSnapshotBuildRequest, ClientSnapshotBuilder,
};
use selvedge_command_model::{
    ClientSnapshot, RouterCommandEnvelope, RouterIngressWeakSender, ToolExecutionRequest,
};
use selvedge_core::{TaskRuntimeConfig, TaskRuntimeSpawnDeps};
use selvedge_domain_model::UnixTs;
use selvedge_local_client::{LocalClientConfig, LocalClientError, LocalEndpoint, LocalFrameStream};
use selvedge_local_protocol::{
    AttachAccepted, AttachRequest, CommandOutcome, CommandRequest, CommandResponse,
    LocalClientCommandId, LocalClientFrame, LocalClientId, LocalNoticeKind, LocalSnapshotMode,
    ReadyRequest, ReadyResponse, ReadyState,
};
use selvedge_router::{ToolExecutionSpawnError, ToolExecutionSpawner};
use selvedge_server::{
    LocalBindingConfig, LocalCommandMapper, LocalOperationCommand, LocalOperationExecutor,
    LocalOperationFailure, LocalOperationFuture, LocalOperationProgress,
    LocalOperationProgressSender, LocalOperationSuccess, LocalhostBindTarget, ServerRequestError,
    ServerStartArgs, ServerStartupError,
};
use selvedge_systemd::SystemdConfig;
use tokio::task::JoinHandle;

const DEFAULT_LOCAL_PORT: u16 = 8080;
const DEFAULT_REQUEST_TIMEOUT: Duration = Duration::from_secs(5);
const DEFAULT_READY_POLL_INTERVAL: Duration = Duration::from_millis(10);
const DEFAULT_SYSTEMD_UNIT: &str = "selvedge-server.service";

static COMMAND_ID_COUNTER: AtomicU64 = AtomicU64::new(1);

pub fn app_name() -> &'static str {
    env!("CARGO_PKG_NAME")
}

pub fn startup_message() -> String {
    format!("{} is ready.", app_name())
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CliRunArgs {
    pub argv: Vec<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub enum CliCommand {
    RunServer,
    SubmitCommand {
        command_name: String,
        payload: serde_json::Value,
        client_id: Option<String>,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CliExitStatus {
    Success,
    InvalidArgs(String),
    ConfigFailed(String),
    LoggingFailed(String),
    ServerDependencyFailed(String),
    ServerStartFailed(String),
    ServerReadyTimeout,
    ServerNotReady,
    CommandRejected(String),
    CommandFailed(String),
    LocalClientFailed(String),
    ServerRunFailed(String),
    Interrupted,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CliError {
    LocalClientFailed(String),
    ServerDependencyFailed(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CliResolvedConfig {
    pub local_client_config: LocalClientConfig,
    pub systemd_config: SystemdConfig,
    pub ready_timeout: Duration,
    pub ready_poll_interval: Duration,
}

impl Default for CliResolvedConfig {
    fn default() -> Self {
        Self {
            local_client_config: LocalClientConfig {
                endpoint: LocalEndpoint::TcpIpv4 {
                    port: DEFAULT_LOCAL_PORT,
                },
                request_timeout: DEFAULT_REQUEST_TIMEOUT,
            },
            systemd_config: SystemdConfig {
                unit_name: DEFAULT_SYSTEMD_UNIT.to_owned(),
                operation_timeout: DEFAULT_REQUEST_TIMEOUT,
                poll_interval: DEFAULT_READY_POLL_INTERVAL,
            },
            ready_timeout: DEFAULT_REQUEST_TIMEOUT,
            ready_poll_interval: DEFAULT_READY_POLL_INTERVAL,
        }
    }
}

pub trait CliLocalClient {
    fn ready(
        &mut self,
        request: ReadyRequest,
    ) -> impl Future<Output = Result<ReadyResponse, CliError>> + Send;

    fn submit_command(
        &mut self,
        request: CommandRequest,
    ) -> impl Future<Output = Result<CommandResponse, CliError>> + Send;

    fn attach(
        &mut self,
        request: AttachRequest,
    ) -> impl Future<Output = Result<(AttachAccepted, LocalFrameStream), CliError>> + Send;

    fn close(&mut self) -> impl Future<Output = Result<(), CliError>> + Send;
}

pub trait CliLocalClientConnector {
    type Client: CliLocalClient;

    fn connect(
        &self,
        config: LocalClientConfig,
    ) -> impl Future<Output = Result<Self::Client, CliError>> + Send;
}

pub trait CliServerStartArgsBuilder {
    fn build(&self, resolved_config: &CliResolvedConfig) -> Result<ServerStartArgs, CliError>;
}

pub struct DefaultCliServerStartArgsBuilder;

impl DefaultCliServerStartArgsBuilder {
    pub fn new() -> Self {
        Self
    }
}

impl Default for DefaultCliServerStartArgsBuilder {
    fn default() -> Self {
        Self::new()
    }
}

impl CliServerStartArgsBuilder for DefaultCliServerStartArgsBuilder {
    fn build(&self, resolved_config: &CliResolvedConfig) -> Result<ServerStartArgs, CliError> {
        let local_bind_target = match resolved_config.local_client_config.endpoint {
            LocalEndpoint::TcpIpv4 { port } => LocalhostBindTarget::Ipv4 { port },
            LocalEndpoint::TcpIpv6 { port } => LocalhostBindTarget::Ipv6 { port },
        };
        Ok(ServerStartArgs {
            explicit_home: selvedge_config::selvedge_home().ok(),
            api_config: ApiExecutorConfig {
                request_timeout: resolved_config.systemd_config.operation_timeout,
                max_response_bytes: None,
            },
            tool_executor: Arc::new(UnavailableToolExecutor),
            core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
                mailbox_capacity: 64,
                model_profiles: HashMap::new(),
            }),
            // NOTE: Skeleton startup wires explicit placeholders for command
            // mapping and snapshot hydration package contracts.
            snapshot_builder: Arc::new(EmptySnapshotBuilder),
            command_mapper: Arc::new(UnsupportedCommandMapper),
            local_operation_executor: Arc::new(DefaultLocalOperationExecutor),
            local_binding: LocalBindingConfig {
                bind_target: local_bind_target.clone(),
            },
            web_binding: Some(selvedge_server::WebBindingConfig {
                bind_target: local_bind_target,
            }),
        })
    }
}

pub trait CliServerRunner: Send + Sync + 'static {
    fn run_server(
        &self,
        args: ServerStartArgs,
    ) -> impl Future<Output = selvedge_server::ServerExitStatus> + Send;
}

pub trait CliServerStarter: Send + Sync + 'static {
    fn start_server(
        &self,
        resolved_config: &CliResolvedConfig,
    ) -> impl Future<Output = Result<(), CliError>> + Send;
}

pub async fn run_cli(args: CliRunArgs) -> CliExitStatus {
    let parsed_command = parse_cli_args(&args.argv);
    if let Err(error) = selvedge_config::init() {
        return CliExitStatus::ConfigFailed(error.to_string());
    }
    if let Err(error) = selvedge_logging::init() {
        return CliExitStatus::LoggingFailed(error.to_string());
    }
    if let Err(error) = parsed_command {
        return CliExitStatus::InvalidArgs(error);
    }

    run_cli_with_deps(
        args.argv,
        DefaultCliServerStarter,
        DefaultCliServerRunner,
        DefaultCliLocalClientConnector,
        DefaultCliServerStartArgsBuilder::new(),
    )
    .await
}

#[rustfmt::skip]
pub async fn run_cli_with_deps<
    S: CliServerStarter, R: CliServerRunner, C: CliLocalClientConnector, B: CliServerStartArgsBuilder,
>(
    args: Vec<String>, server_starter: S, server_runner: R,
    local_client_connector: C, server_start_args_builder: B,
) -> CliExitStatus {
    let command = match parse_cli_args(&args) {
        Ok(command) => command,
        Err(error) => return CliExitStatus::InvalidArgs(error),
    };
    let resolved_config = match resolve_cli_config() {
        Ok(config) => config,
        Err(CliConfigResolution::NotInitialized) => CliResolvedConfig::default(),
        Err(CliConfigResolution::Failed(error)) => return CliExitStatus::ConfigFailed(error),
    };

    match command {
        CliCommand::RunServer => {
            run_server_subcommand(server_runner, server_start_args_builder, &resolved_config).await
        }
        CliCommand::SubmitCommand {
            command_name,
            payload,
            client_id,
        } => {
            run_submit_command(
                server_starter,
                local_client_connector,
                resolved_config,
                command_name,
                payload,
                client_id,
            )
            .await
        }
    }
}

enum CliConfigResolution {
    NotInitialized,
    Failed(String),
}

fn resolve_cli_config() -> Result<CliResolvedConfig, CliConfigResolution> {
    selvedge_config::read(cli_resolved_config_from_app_config).map_err(|error| match error {
        selvedge_config::ConfigError::NotInitialized => CliConfigResolution::NotInitialized,
        error => CliConfigResolution::Failed(error.to_string()),
    })?
}

fn cli_resolved_config_from_app_config(
    config: &selvedge_config_model::AppConfig,
) -> Result<CliResolvedConfig, CliConfigResolution> {
    let endpoint = match config.server.host.as_str() {
        "127.0.0.1" | "localhost" => LocalEndpoint::TcpIpv4 {
            port: config.server.port,
        },
        "::1" | "[::1]" => LocalEndpoint::TcpIpv6 {
            port: config.server.port,
        },
        host => {
            return Err(CliConfigResolution::Failed(format!(
                "server.host must be loopback, got {host}"
            )));
        }
    };
    let request_timeout = Duration::from_millis(config.server.request_timeout_ms);

    Ok(CliResolvedConfig {
        local_client_config: LocalClientConfig {
            endpoint,
            request_timeout,
        },
        systemd_config: SystemdConfig {
            unit_name: DEFAULT_SYSTEMD_UNIT.to_owned(),
            operation_timeout: request_timeout,
            poll_interval: DEFAULT_READY_POLL_INTERVAL,
        },
        ready_timeout: request_timeout,
        ready_poll_interval: DEFAULT_READY_POLL_INTERVAL,
    })
}

pub fn exit_code(status: &CliExitStatus) -> i32 {
    match status {
        CliExitStatus::Success => 0,
        CliExitStatus::Interrupted => 130,
        _ => 1,
    }
}

pub fn write_cli_exit_status<W>(status: &CliExitStatus, mut writer: W) -> std::io::Result<()>
where
    W: std::io::Write,
{
    match status {
        CliExitStatus::CommandRejected(error) => {
            writeln!(writer, "Command rejected: {error}")
        }
        _ => Ok(()),
    }
}

fn parse_cli_args(args: &[String]) -> Result<CliCommand, String> {
    let tokens = args.iter().skip(1).map(String::as_str).collect::<Vec<_>>();
    if tokens == ["server"] {
        return Ok(CliCommand::RunServer);
    }
    if tokens == ["list-models"] {
        return Ok(CliCommand::SubmitCommand {
            command_name: "list-models".to_owned(),
            payload: serde_json::json!({}),
            client_id: None,
        });
    }

    let mut client_id = None;
    let mut command_name = None;
    let mut json_payload = None;
    let mut index = 0;
    while index < tokens.len() {
        if command_name.is_some() {
            if json_payload.is_some() {
                return Err("unexpected extra positional argument".to_owned());
            }
            json_payload = Some(tokens[index].to_owned());
            index += 1;
            continue;
        }

        match tokens[index] {
            "--client-id" => {
                if client_id.is_some() {
                    return Err("duplicate --client-id".to_owned());
                }
                index += 1;
                let Some(value) = tokens.get(index) else {
                    return Err("missing --client-id value".to_owned());
                };
                if value.trim().is_empty() {
                    return Err("empty --client-id".to_owned());
                }
                client_id = Some((*value).to_owned());
            }
            token if token.starts_with('-') => return Err(format!("unknown flag {token}")),
            token => command_name = Some(token.to_owned()),
        }
        index += 1;
    }

    let client_id = client_id.ok_or_else(|| "missing --client-id".to_owned())?;
    let command_name = command_name.ok_or_else(|| "expected command name".to_owned())?;
    if command_name.trim().is_empty()
        || command_name == "server"
        || command_name == "list-models"
        || command_name.starts_with('-')
    {
        return Err("invalid command name".to_owned());
    }
    let json_payload = json_payload.ok_or_else(|| "expected json payload".to_owned())?;
    if json_payload.is_empty() {
        return Err("empty json payload".to_owned());
    }
    let payload = serde_json::from_str(&json_payload)
        .map_err(|error| format!("invalid json payload: {error}"))?;

    Ok(CliCommand::SubmitCommand {
        command_name,
        payload,
        client_id: Some(client_id),
    })
}

async fn run_server_subcommand<R, B>(
    server_runner: R,
    server_start_args_builder: B,
    resolved_config: &CliResolvedConfig,
) -> CliExitStatus
where
    R: CliServerRunner,
    B: CliServerStartArgsBuilder,
{
    let args = match server_start_args_builder.build(resolved_config) {
        Ok(args) => args,
        Err(error) => return CliExitStatus::ServerDependencyFailed(format!("{error:?}")),
    };

    match server_runner.run_server(args).await {
        selvedge_server::ServerExitStatus::Stopped => CliExitStatus::Success,
        selvedge_server::ServerExitStatus::StartupFailed(error) => {
            CliExitStatus::ServerRunFailed(format!("{error:?}"))
        }
        selvedge_server::ServerExitStatus::RouterStopped => {
            CliExitStatus::ServerRunFailed("router stopped".to_owned())
        }
        selvedge_server::ServerExitStatus::Fatal(error) => CliExitStatus::ServerRunFailed(error),
    }
}

async fn run_submit_command<S, C>(
    server_starter: S,
    local_client_connector: C,
    resolved_config: CliResolvedConfig,
    command_name: String,
    payload: serde_json::Value,
    client_id: Option<String>,
) -> CliExitStatus
where
    S: CliServerStarter,
    C: CliLocalClientConnector,
{
    let client_id = match LocalClientId::new(
        client_id.unwrap_or_else(|| format!("cli-{}", std::process::id())),
    ) {
        Ok(client_id) => client_id,
        Err(error) => return CliExitStatus::InvalidArgs(format!("{error:?}")),
    };
    let attach_command_id = match LocalClientCommandId::new(next_command_id()) {
        Ok(client_command_id) => client_command_id,
        Err(error) => return CliExitStatus::InvalidArgs(format!("{error:?}")),
    };
    let submit_command_id = match LocalClientCommandId::new(next_command_id()) {
        Ok(client_command_id) => client_command_id,
        Err(error) => return CliExitStatus::InvalidArgs(format!("{error:?}")),
    };
    let request = CommandRequest {
        client_id: client_id.clone(),
        client_command_id: submit_command_id.clone(),
        command_name: command_name.clone(),
        payload,
    };

    let mut client = match connect_and_ready(&local_client_connector, &resolved_config).await {
        ReadyProbe::Ready(client) => client,
        ReadyProbe::Failed(error) => return CliExitStatus::LocalClientFailed(format!("{error:?}")),
        ReadyProbe::Unavailable | ReadyProbe::NotReady => {
            if let Err(error) = server_starter.start_server(&resolved_config).await {
                return CliExitStatus::ServerStartFailed(format!("{error:?}"));
            }
            match poll_ready_client(&local_client_connector, &resolved_config).await {
                Ok(client) => client,
                Err(status) => return status,
            }
        }
    };

    let waits_for_terminal_notice = command_waits_for_terminal_notice(&command_name);
    let mut stream = if waits_for_terminal_notice {
        let attach_request = AttachRequest {
            client_id: client_id.clone(),
            client_command_id: attach_command_id.clone(),
            subscription: cli_subscription(),
        };
        let (_, mut stream) = match client.attach(attach_request).await {
            Ok(attached) => attached,
            Err(error) => {
                return CliExitStatus::LocalClientFailed(format!("{error:?}"));
            }
        };

        if let Err(status) = wait_for_empty_snapshot(&mut stream, &attach_command_id).await {
            let _ = client.close().await;
            return status;
        }
        Some(stream)
    } else {
        None
    };

    let status = match client.submit_command(request).await {
        Ok(CommandResponse {
            outcome: CommandOutcome::Accepted,
            client_command_id,
            ..
        }) => {
            if waits_for_terminal_notice {
                let Some(stream) = stream.as_mut() else {
                    return CliExitStatus::LocalClientFailed(
                        "terminal notice stream missing".to_owned(),
                    );
                };
                wait_for_terminal_frame(stream, &client_command_id, &command_name).await
            } else {
                CliExitStatus::Success
            }
        }
        Ok(CommandResponse {
            outcome: CommandOutcome::Rejected(reason),
            ..
        }) => CliExitStatus::CommandRejected(format!("{reason:?}")),
        Err(error) => CliExitStatus::LocalClientFailed(format!("{error:?}")),
    };

    let _ = client.close().await;
    status
}

fn command_waits_for_terminal_notice(command_name: &str) -> bool {
    command_name == "list-models" || command_name == "login-chatgpt"
}

async fn poll_ready_client<C>(
    connector: &C,
    resolved_config: &CliResolvedConfig,
) -> Result<C::Client, CliExitStatus>
where
    C: CliLocalClientConnector,
{
    let Some(deadline) = ready_deadline_from_now(resolved_config.ready_timeout) else {
        return Err(CliExitStatus::ServerReadyTimeout);
    };
    loop {
        if tokio::time::Instant::now() >= deadline {
            return Err(CliExitStatus::ServerReadyTimeout);
        }
        match connect_and_ready(connector, resolved_config).await {
            ReadyProbe::Ready(client) => return Ok(client),
            ReadyProbe::Failed(error) => {
                return Err(CliExitStatus::LocalClientFailed(format!("{error:?}")));
            }
            ReadyProbe::Unavailable | ReadyProbe::NotReady => {
                let now = tokio::time::Instant::now();
                let Some(sleep_for) =
                    ready_retry_sleep_duration(now, deadline, resolved_config.ready_poll_interval)
                else {
                    return Err(CliExitStatus::ServerReadyTimeout);
                };
                if !sleep_for.is_zero() {
                    tokio::time::sleep(sleep_for).await;
                }
            }
        }
    }
}

fn ready_retry_sleep_duration(
    now: tokio::time::Instant,
    deadline: tokio::time::Instant,
    poll_interval: Duration,
) -> Option<Duration> {
    if now >= deadline {
        return None;
    }

    Some(std::cmp::min(poll_interval, deadline.duration_since(now)))
}

fn ready_deadline_from_now(timeout: Duration) -> Option<tokio::time::Instant> {
    tokio::time::Instant::now().checked_add(timeout)
}

enum ReadyProbe<C> {
    Ready(C),
    NotReady,
    Unavailable,
    Failed(CliError),
}

async fn connect_and_ready<C>(
    connector: &C,
    resolved_config: &CliResolvedConfig,
) -> ReadyProbe<C::Client>
where
    C: CliLocalClientConnector,
{
    let mut client = match connector
        .connect(resolved_config.local_client_config.clone())
        .await
    {
        Ok(client) => client,
        Err(_) => return ReadyProbe::Unavailable,
    };
    match client.ready(ReadyRequest {}).await {
        Ok(ReadyResponse {
            state: ReadyState::Ready,
            ..
        }) => ReadyProbe::Ready(client),
        Ok(_) => ReadyProbe::NotReady,
        Err(error) => ReadyProbe::Failed(error),
    }
}

fn cli_subscription() -> selvedge_local_protocol::LocalClientSubscription {
    selvedge_local_protocol::LocalClientSubscription {
        task_scope: selvedge_local_protocol::LocalTaskScope::AllTasks,
        detail_level: selvedge_local_protocol::LocalDetailLevel::Verbose,
        snapshot_mode: LocalSnapshotMode::Empty,
        include_model_call_status: true,
        include_tool_execution_status: true,
        include_debug_notices: true,
    }
}

async fn wait_for_empty_snapshot(
    stream: &mut LocalFrameStream,
    attach_command_id: &LocalClientCommandId,
) -> Result<(), CliExitStatus> {
    match stream.next().await {
        Some(Ok(LocalClientFrame::Snapshot(frame)))
            if &frame.client_command_id == attach_command_id
                && snapshot_is_empty(&frame.snapshot) =>
        {
            Ok(())
        }
        Some(Ok(LocalClientFrame::Snapshot(_))) => Err(CliExitStatus::LocalClientFailed(
            "attach delivered non-empty snapshot".to_owned(),
        )),
        Some(Ok(_)) => Err(CliExitStatus::LocalClientFailed(
            "attach delivered frame before snapshot".to_owned(),
        )),
        Some(Err(error)) => Err(CliExitStatus::LocalClientFailed(format!("{error:?}"))),
        None => Err(CliExitStatus::LocalClientFailed(
            "attach stream closed before snapshot".to_owned(),
        )),
    }
}

fn snapshot_is_empty(snapshot: &selvedge_local_protocol::LocalClientSnapshot) -> bool {
    snapshot.tasks.is_empty()
        && snapshot.task_parent_edges.is_empty()
        && snapshot.history_nodes.is_empty()
        && snapshot.task_versions.is_empty()
}

async fn wait_for_terminal_frame(
    stream: &mut LocalFrameStream,
    submit_command_id: &LocalClientCommandId,
    command_name: &str,
) -> CliExitStatus {
    while let Some(frame) = stream.next().await {
        match frame {
            Ok(LocalClientFrame::Notice(frame)) => match frame.notice.kind {
                LocalNoticeKind::LoginUserCode {
                    client_command_id,
                    verification_url,
                    user_code,
                } if &client_command_id == submit_command_id => {
                    println!("Open this URL to authenticate ChatGPT:");
                    println!("{verification_url}");
                    println!("User code: {user_code}");
                }
                LocalNoticeKind::CommandCompleted {
                    client_command_id,
                    command_name: completed_command,
                } if &client_command_id == submit_command_id
                    && completed_command == command_name =>
                {
                    println!("{}", frame.notice.message_text);
                    return CliExitStatus::Success;
                }
                LocalNoticeKind::CommandFailed {
                    client_command_id,
                    command_name: failed_command,
                } if &client_command_id == submit_command_id && failed_command == command_name => {
                    println!("{}", frame.notice.message_text);
                    return CliExitStatus::CommandFailed(frame.notice.message_text);
                }
                LocalNoticeKind::Diagnostic { .. } => {}
                _ => {}
            },
            Ok(_) => {}
            Err(error) => return CliExitStatus::LocalClientFailed(format!("{error:?}")),
        }
    }

    CliExitStatus::LocalClientFailed("attach stream closed before command terminal".to_owned())
}

fn next_command_id() -> String {
    let counter = COMMAND_ID_COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("cli-{}-{counter}", std::process::id())
}

pub struct DefaultCliLocalClientConnector;

pub struct DefaultCliLocalClient(
    selvedge_local_client::LocalClient<selvedge_local_client::HttpLocalTransport>,
);

impl CliLocalClientConnector for DefaultCliLocalClientConnector {
    type Client = DefaultCliLocalClient;

    async fn connect(&self, config: LocalClientConfig) -> Result<Self::Client, CliError> {
        selvedge_local_client::connect_http(config)
            .await
            .map(DefaultCliLocalClient)
            .map_err(map_local_client_error)
    }
}

impl CliLocalClient for DefaultCliLocalClient {
    async fn ready(&mut self, request: ReadyRequest) -> Result<ReadyResponse, CliError> {
        self.0.ready(request).await.map_err(map_local_client_error)
    }

    async fn submit_command(
        &mut self,
        request: CommandRequest,
    ) -> Result<CommandResponse, CliError> {
        self.0
            .submit_command(request)
            .await
            .map_err(map_local_client_error)
    }

    async fn attach(
        &mut self,
        request: AttachRequest,
    ) -> Result<(AttachAccepted, LocalFrameStream), CliError> {
        self.0
            .attach(request)
            .await
            .map_err(|error| CliError::LocalClientFailed(format!("{error:?}")))
    }

    async fn close(&mut self) -> Result<(), CliError> {
        self.0.close().await.map_err(map_local_client_error)
    }
}

fn map_local_client_error(error: LocalClientError) -> CliError {
    CliError::LocalClientFailed(format!("{error:?}"))
}

struct DefaultCliServerRunner;

impl CliServerRunner for DefaultCliServerRunner {
    async fn run_server(&self, args: ServerStartArgs) -> selvedge_server::ServerExitStatus {
        selvedge_server::run_server(args).await
    }
}

struct DefaultCliServerStarter;

impl CliServerStarter for DefaultCliServerStarter {
    async fn start_server(&self, _resolved_config: &CliResolvedConfig) -> Result<(), CliError> {
        let current_exe = match std::env::current_exe() {
            Ok(current_exe) => current_exe,
            Err(error) => {
                return Err(CliError::ServerDependencyFailed(error.to_string()));
            }
        };
        std::process::Command::new(current_exe)
            .arg("server")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map(|_| ())
            .map_err(|error| CliError::ServerDependencyFailed(error.to_string()))
    }
}

struct DefaultLocalOperationExecutor;

impl LocalOperationExecutor for DefaultLocalOperationExecutor {
    fn execute(
        &self,
        command: LocalOperationCommand,
        progress_tx: LocalOperationProgressSender,
    ) -> LocalOperationFuture {
        Box::pin(async move {
            match command {
                LocalOperationCommand::LoginChatgpt => {
                    let sink = ServerLoginProgressSink { progress_tx };
                    match run_chatgpt_login(sink).await {
                        Ok(result) => Ok(LocalOperationSuccess {
                            message_text: format!(
                                "ChatGPT login complete.\nAuth file: {}",
                                result.auth_file_path.display()
                            ),
                        }),
                        Err(error) => Err(LocalOperationFailure {
                            message_text: format!("ChatGPT login failed: {error:?}"),
                        }),
                    }
                }
                LocalOperationCommand::ListModels => list_models_operation().await,
            }
        })
    }
}

async fn list_models_operation() -> Result<LocalOperationSuccess, LocalOperationFailure> {
    let llm_config = match selvedge_config::read(|config| config.llm.clone()) {
        Ok(llm_config) => llm_config,
        Err(error) => {
            return Err(LocalOperationFailure {
                message_text: format!("failed to read model provider config: {error}"),
            });
        }
    };
    let selvedge_home = match selvedge_config::selvedge_home() {
        Ok(selvedge_home) => selvedge_home,
        Err(error) => {
            return Err(LocalOperationFailure {
                message_text: format!("failed to read selvedge home: {error}"),
            });
        }
    };
    let listings = match selvedge_model_providers::default_registry()
        .list_configured_models_from_home(&selvedge_home, &llm_config)
        .await
    {
        Ok(listings) => listings,
        Err(error) => {
            return Err(LocalOperationFailure {
                message_text: format!("failed to list configured models: {error}"),
            });
        }
    };
    let message_text = if listings.is_empty() {
        "No configured model providers.".to_owned()
    } else {
        listings
            .into_iter()
            .map(|listing| {
                let models = if listing.models.is_empty() {
                    "(no models discovered)".to_owned()
                } else {
                    listing.models.join(", ")
                };
                format!("{}: {}", listing.provider_id, models)
            })
            .collect::<Vec<_>>()
            .join("\n")
    };

    Ok(LocalOperationSuccess { message_text })
}

struct ServerLoginProgressSink {
    progress_tx: LocalOperationProgressSender,
}

impl ChatgptLoginProgressSink for ServerLoginProgressSink {
    fn emit(&self, progress: ChatgptLoginProgress) -> ChatgptLoginProgressFuture {
        let progress_tx = self.progress_tx.clone();
        Box::pin(async move {
            match progress {
                ChatgptLoginProgress::UserCode {
                    verification_url,
                    user_code,
                } => match progress_tx.send(LocalOperationProgress::LoginUserCode {
                    verification_url,
                    user_code,
                }) {
                    Ok(()) => Ok(()),
                    Err(_) => Err(ChatgptLoginProgressError),
                },
                ChatgptLoginProgress::Waiting => Ok(()),
                ChatgptLoginProgress::Diagnostic { message_text } => {
                    match progress_tx.send(LocalOperationProgress::Diagnostic { message_text }) {
                        Ok(()) => Ok(()),
                        Err(_) => Err(ChatgptLoginProgressError),
                    }
                }
            }
        })
    }
}

struct UnavailableToolExecutor;

impl ToolExecutionSpawner for UnavailableToolExecutor {
    fn spawn_tool_execution(
        &self,
        _request: ToolExecutionRequest,
        _router_tx: RouterIngressWeakSender,
    ) -> Result<JoinHandle<()>, ToolExecutionSpawnError> {
        Err(ToolExecutionSpawnError::ToolExecutorUnavailable)
    }
}

// NOTE: Skeleton snapshot hydration returns an empty snapshot with a stable
// zero timestamp, so attach clients receive a deterministic initial frame.
struct EmptySnapshotBuilder;

impl ClientSnapshotBuilder for EmptySnapshotBuilder {
    fn build_snapshot(&self, _request: ClientSnapshotBuildRequest) -> ClientSnapshotBuildFuture {
        Box::pin(async {
            Ok(ClientSnapshot {
                generated_at: UnixTs(0),
                tasks: Vec::new(),
                task_parent_edges: Vec::new(),
                history_nodes: Vec::new(),
                task_versions: Vec::new(),
            })
        })
    }
}

// NOTE: Skeleton command mapping rejects all command names through the normal
// server unsupported-command outcome.
struct UnsupportedCommandMapper;

impl LocalCommandMapper for UnsupportedCommandMapper {
    fn map_command(
        &self,
        _request: CommandRequest,
    ) -> Result<RouterCommandEnvelope, ServerRequestError> {
        Err(ServerRequestError::UnsupportedCommand)
    }
}

impl From<ServerStartupError> for CliError {
    fn from(error: ServerStartupError) -> Self {
        Self::ServerDependencyFailed(format!("{error:?}"))
    }
}

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::sync::{Arc, Mutex};

    use selvedge_local_protocol::{
        CommandRejectReason, LocalClientNoticeFrame, LocalClientSnapshot, LocalClientSnapshotFrame,
        LocalClientSubscription, LocalDetailLevel, LocalNotice, LocalNoticeKind, LocalNoticeLevel,
        LocalTaskScope,
    };
    use selvedge_server::ServerExitStatus;

    use super::*;

    #[tokio::test]
    async fn command_uses_ready_client_without_systemd_start() {
        let connector = FakeConnector::new(vec![Ok(FakeClientPlan::ready_accepted())]);
        let connector_state = connector.state.clone();
        let starter = FakeServerStarter::new();

        let status = run_cli_with_deps(
            command_argv(),
            starter.clone(),
            FakeServerRunner::stopped(),
            connector,
            DefaultCliServerStartArgsBuilder::new(),
        )
        .await;

        assert_eq!(status, CliExitStatus::Success);
        assert_eq!(connector_state.lock().expect("connector").connect_calls, 1);
        assert_eq!(starter.start_calls(), 0);
    }

    #[tokio::test]
    async fn command_auto_starts_server_then_reconnects_and_submits() {
        let connector = FakeConnector::new(vec![
            Ok(FakeClientPlan::not_ready()),
            Ok(FakeClientPlan::ready_accepted()),
        ]);
        let connector_state = connector.state.clone();
        let starter = FakeServerStarter::new();

        let status = run_cli_with_deps(
            command_argv(),
            starter.clone(),
            FakeServerRunner::stopped(),
            connector,
            DefaultCliServerStartArgsBuilder::new(),
        )
        .await;

        assert_eq!(status, CliExitStatus::Success);
        assert_eq!(connector_state.lock().expect("connector").connect_calls, 2);
        assert_eq!(starter.start_calls(), 1);
    }

    #[tokio::test]
    async fn command_ready_failure_returns_local_client_failure_without_systemd_start() {
        let connector = FakeConnector::new(vec![Ok(FakeClientPlan {
            ready: Err(CliError::LocalClientFailed("protocol mismatch".to_owned())),
            submit: Ok(CommandResponse {
                client_command_id: LocalClientCommandId::new("response-1").expect("command id"),
                outcome: CommandOutcome::Accepted,
            }),
            attach_frames: Vec::new(),
        })]);
        let starter = FakeServerStarter::new();

        let status = run_cli_with_deps(
            command_argv(),
            starter.clone(),
            FakeServerRunner::stopped(),
            connector,
            DefaultCliServerStartArgsBuilder::new(),
        )
        .await;

        assert_eq!(
            status,
            CliExitStatus::LocalClientFailed("LocalClientFailed(\"protocol mismatch\")".to_owned())
        );
        assert_eq!(starter.start_calls(), 0);
    }

    #[tokio::test]
    async fn command_rejection_is_not_success() {
        let connector = FakeConnector::new(vec![Ok(FakeClientPlan {
            ready: Ok(ready_response(ReadyState::Ready)),
            submit: Ok(CommandResponse {
                client_command_id: LocalClientCommandId::new("response-1").expect("command id"),
                outcome: CommandOutcome::Rejected(CommandRejectReason::UnsupportedCommand),
            }),
            attach_frames: vec![Ok(empty_snapshot_frame("cli-attach"))],
        })]);

        let status = run_cli_with_deps(
            command_argv(),
            FakeServerStarter::new(),
            FakeServerRunner::stopped(),
            connector,
            DefaultCliServerStartArgsBuilder::new(),
        )
        .await;

        assert_eq!(
            status,
            CliExitStatus::CommandRejected("UnsupportedCommand".to_owned())
        );
    }

    #[test]
    fn ready_retry_sleep_is_capped_to_remaining_time() {
        let now = tokio::time::Instant::now();
        let deadline = now + Duration::from_millis(10);

        assert_eq!(
            ready_retry_sleep_duration(now, deadline, Duration::from_millis(100)),
            Some(Duration::from_millis(10))
        );
        assert_eq!(
            ready_retry_sleep_duration(deadline, deadline, Duration::from_millis(100)),
            None
        );
        assert_eq!(
            ready_retry_sleep_duration(
                deadline + Duration::from_millis(1),
                deadline,
                Duration::from_millis(100)
            ),
            None
        );
    }

    #[test]
    fn ready_deadline_overflow_is_handled() {
        assert_eq!(ready_deadline_from_now(Duration::MAX), None);
    }

    #[test]
    fn command_rejection_status_writes_stderr() {
        let mut stderr = Vec::new();

        write_cli_exit_status(
            &CliExitStatus::CommandRejected("UnsupportedCommand".to_owned()),
            &mut stderr,
        )
        .expect("write stderr");

        assert_eq!(
            String::from_utf8(stderr).expect("stderr utf8"),
            "Command rejected: UnsupportedCommand\n"
        );
    }

    #[tokio::test]
    async fn usage_error_has_no_side_effects() {
        let connector = FakeConnector::new(Vec::new());
        let connector_state = connector.state.clone();
        let starter = FakeServerStarter::new();
        let runner = FakeServerRunner::stopped();
        let runner_state = runner.state.clone();

        let status = run_cli_with_deps(
            vec!["selvedge".to_owned(), "--unknown".to_owned()],
            starter.clone(),
            runner,
            connector,
            DefaultCliServerStartArgsBuilder::new(),
        )
        .await;

        assert!(matches!(status, CliExitStatus::InvalidArgs(_)));
        assert_eq!(connector_state.lock().expect("connector").connect_calls, 0);
        assert_eq!(starter.start_calls(), 0);
        assert_eq!(runner_state.lock().expect("runner").run_calls, 0);
    }

    #[test]
    fn parser_accepts_json_payload_that_starts_with_dash() {
        let command = parse_cli_args(&[
            "selvedge".to_owned(),
            "--client-id".to_owned(),
            "client-1".to_owned(),
            "set-number".to_owned(),
            "-1".to_owned(),
        ])
        .expect("negative JSON number should parse as payload");

        assert_eq!(
            command,
            CliCommand::SubmitCommand {
                command_name: "set-number".to_owned(),
                payload: serde_json::json!(-1),
                client_id: Some("client-1".to_owned()),
            }
        );
    }

    #[test]
    fn parser_accepts_list_models_command() {
        let command = parse_cli_args(&["selvedge".to_owned(), "list-models".to_owned()])
            .expect("list models command should parse");

        assert_eq!(
            command,
            CliCommand::SubmitCommand {
                command_name: "list-models".to_owned(),
                payload: serde_json::json!({}),
                client_id: None,
            }
        );
    }

    #[tokio::test]
    async fn server_subcommand_uses_builder_and_runner_without_systemd_or_local_client() {
        let connector = FakeConnector::new(Vec::new());
        let connector_state = connector.state.clone();
        let starter = FakeServerStarter::new();
        let runner = FakeServerRunner::stopped();
        let runner_state = runner.state.clone();

        let status = run_cli_with_deps(
            vec!["selvedge".to_owned(), "server".to_owned()],
            starter.clone(),
            runner,
            connector,
            DefaultCliServerStartArgsBuilder::new(),
        )
        .await;

        assert_eq!(status, CliExitStatus::Success);
        assert_eq!(connector_state.lock().expect("connector").connect_calls, 0);
        assert_eq!(starter.start_calls(), 0);
        assert_eq!(runner_state.lock().expect("runner").run_calls, 1);
    }

    #[tokio::test]
    async fn server_builder_failure_skips_runner() {
        let runner = FakeServerRunner::stopped();
        let runner_state = runner.state.clone();

        let status = run_cli_with_deps(
            vec!["selvedge".to_owned(), "server".to_owned()],
            FakeServerStarter::new(),
            runner,
            FakeConnector::new(Vec::new()),
            FailingBuilder,
        )
        .await;

        assert!(matches!(status, CliExitStatus::ServerDependencyFailed(_)));
        assert_eq!(runner_state.lock().expect("runner").run_calls, 0);
    }

    #[tokio::test]
    async fn list_models_command_uses_unified_client_path() {
        let connector = FakeConnector::new(vec![Ok(FakeClientPlan::list_models_complete())]);
        let connector_state = connector.state.clone();
        let starter = FakeServerStarter::new();
        let server_runner = FakeServerRunner::stopped();
        let server_runner_state = server_runner.state.clone();

        let status = run_cli_with_deps(
            vec!["selvedge".to_owned(), "list-models".to_owned()],
            starter.clone(),
            server_runner,
            connector,
            DefaultCliServerStartArgsBuilder::new(),
        )
        .await;

        assert_eq!(status, CliExitStatus::Success);
        assert_eq!(connector_state.lock().expect("connector").connect_calls, 1);
        assert_eq!(starter.start_calls(), 0);
        assert_eq!(server_runner_state.lock().expect("runner").run_calls, 0);
    }

    #[tokio::test]
    async fn list_models_command_reports_terminal_failure() {
        let status = run_cli_with_deps(
            vec!["selvedge".to_owned(), "list-models".to_owned()],
            FakeServerStarter::new(),
            FakeServerRunner::stopped(),
            FakeConnector::new(vec![Ok(FakeClientPlan::list_models_failed())]),
            DefaultCliServerStartArgsBuilder::new(),
        )
        .await;

        assert_eq!(
            status,
            CliExitStatus::CommandFailed("model listing failed".to_owned())
        );
    }

    #[tokio::test]
    async fn login_chatgpt_command_reports_terminal_failure() {
        let status = run_cli_with_deps(
            vec![
                "selvedge".to_owned(),
                "--client-id".to_owned(),
                "client-1".to_owned(),
                "login-chatgpt".to_owned(),
                "{}".to_owned(),
            ],
            FakeServerStarter::new(),
            FakeServerRunner::stopped(),
            FakeConnector::new(vec![Ok(FakeClientPlan::login_chatgpt_failed())]),
            DefaultCliServerStartArgsBuilder::new(),
        )
        .await;

        assert_eq!(
            status,
            CliExitStatus::CommandFailed("login failed".to_owned())
        );
    }

    #[tokio::test]
    async fn router_backed_command_submits_without_attaching_requested_client() {
        let status = run_cli_with_deps(
            vec![
                "selvedge".to_owned(),
                "--client-id".to_owned(),
                "client-1".to_owned(),
                "send-user-input".to_owned(),
                r#"{"message":"hello"}"#.to_owned(),
            ],
            FakeServerStarter::new(),
            FakeServerRunner::stopped(),
            FakeConnector::new(vec![Ok(FakeClientPlan::router_command_without_attach())]),
            DefaultCliServerStartArgsBuilder::new(),
        )
        .await;

        assert_eq!(status, CliExitStatus::Success);
    }

    #[derive(Clone)]
    struct FakeConnector {
        state: Arc<Mutex<FakeConnectorState>>,
    }

    struct FakeConnectorState {
        connect_calls: usize,
        plans: VecDeque<Result<FakeClientPlan, CliError>>,
    }

    impl FakeConnector {
        fn new(plans: Vec<Result<FakeClientPlan, CliError>>) -> Self {
            Self {
                state: Arc::new(Mutex::new(FakeConnectorState {
                    connect_calls: 0,
                    plans: plans.into(),
                })),
            }
        }
    }

    impl CliLocalClientConnector for FakeConnector {
        type Client = FakeClient;

        async fn connect(&self, _config: LocalClientConfig) -> Result<Self::Client, CliError> {
            let mut state = self.state.lock().expect("connector");
            state.connect_calls += 1;
            state
                .plans
                .pop_front()
                .unwrap_or_else(|| Err(CliError::LocalClientFailed("no plan".to_owned())))
                .map(|plan| FakeClient { plan })
        }
    }

    struct FakeClient {
        plan: FakeClientPlan,
    }

    struct FakeClientPlan {
        ready: Result<ReadyResponse, CliError>,
        submit: Result<CommandResponse, CliError>,
        attach_frames: Vec<Result<LocalClientFrame, LocalClientError>>,
    }

    impl FakeClientPlan {
        fn ready_accepted() -> Self {
            Self {
                ready: Ok(ready_response(ReadyState::Ready)),
                submit: Ok(CommandResponse {
                    client_command_id: LocalClientCommandId::new("response-1").expect("command id"),
                    outcome: CommandOutcome::Accepted,
                }),
                attach_frames: vec![
                    Ok(empty_snapshot_frame("cli-attach")),
                    Ok(command_completed_notice("response-1", "send-user-input")),
                ],
            }
        }

        fn not_ready() -> Self {
            Self {
                ready: Ok(ready_response(ReadyState::NotReady)),
                submit: Err(CliError::LocalClientFailed(
                    "submit should not run".to_owned(),
                )),
                attach_frames: Vec::new(),
            }
        }

        fn list_models_complete() -> Self {
            Self {
                ready: Ok(ready_response(ReadyState::Ready)),
                submit: Ok(CommandResponse {
                    client_command_id: LocalClientCommandId::new("response-1").expect("command id"),
                    outcome: CommandOutcome::Accepted,
                }),
                attach_frames: vec![
                    Ok(empty_snapshot_frame("cli-attach")),
                    Ok(command_completed_notice("response-1", "list-models")),
                ],
            }
        }

        fn list_models_failed() -> Self {
            Self {
                ready: Ok(ready_response(ReadyState::Ready)),
                submit: Ok(CommandResponse {
                    client_command_id: LocalClientCommandId::new("response-1").expect("command id"),
                    outcome: CommandOutcome::Accepted,
                }),
                attach_frames: vec![
                    Ok(empty_snapshot_frame("cli-attach")),
                    Ok(command_failed_notice("response-1", "list-models")),
                ],
            }
        }

        fn login_chatgpt_failed() -> Self {
            Self {
                ready: Ok(ready_response(ReadyState::Ready)),
                submit: Ok(CommandResponse {
                    client_command_id: LocalClientCommandId::new("response-1").expect("command id"),
                    outcome: CommandOutcome::Accepted,
                }),
                attach_frames: vec![
                    Ok(empty_snapshot_frame("cli-attach")),
                    Ok(command_failed_notice_with_message(
                        "response-1",
                        "login-chatgpt",
                        "login failed",
                    )),
                ],
            }
        }

        fn router_command_without_attach() -> Self {
            Self {
                ready: Ok(ready_response(ReadyState::Ready)),
                submit: Ok(CommandResponse {
                    client_command_id: LocalClientCommandId::new("response-1").expect("command id"),
                    outcome: CommandOutcome::Accepted,
                }),
                attach_frames: Vec::new(),
            }
        }
    }

    impl CliLocalClient for FakeClient {
        async fn ready(&mut self, _request: ReadyRequest) -> Result<ReadyResponse, CliError> {
            self.plan.ready.clone()
        }

        async fn submit_command(
            &mut self,
            _request: CommandRequest,
        ) -> Result<CommandResponse, CliError> {
            self.plan.submit.clone()
        }

        async fn attach(
            &mut self,
            request: AttachRequest,
        ) -> Result<(AttachAccepted, LocalFrameStream), CliError> {
            let attach_command_id = request.client_command_id.clone();
            let accepted = AttachAccepted {
                client_id: request.client_id,
                client_command_id: request.client_command_id,
            };
            let frames = std::mem::take(&mut self.plan.attach_frames)
                .into_iter()
                .map(|frame| {
                    frame.map(|frame| match frame {
                        LocalClientFrame::Snapshot(mut frame) => {
                            frame.client_command_id = attach_command_id.clone();
                            LocalClientFrame::Snapshot(frame)
                        }
                        LocalClientFrame::Notice(mut frame) => {
                            frame.client_command_id = attach_command_id.clone();
                            LocalClientFrame::Notice(frame)
                        }
                        other => other,
                    })
                })
                .collect::<Vec<_>>();
            Ok((accepted, Box::pin(futures_util::stream::iter(frames))))
        }

        async fn close(&mut self) -> Result<(), CliError> {
            Ok(())
        }
    }

    #[derive(Clone)]
    struct FakeServerStarter {
        state: Arc<Mutex<FakeServerStarterState>>,
    }

    struct FakeServerStarterState {
        start_calls: usize,
    }

    impl FakeServerStarter {
        fn new() -> Self {
            Self {
                state: Arc::new(Mutex::new(FakeServerStarterState { start_calls: 0 })),
            }
        }

        fn start_calls(&self) -> usize {
            self.state.lock().expect("starter").start_calls
        }
    }

    impl CliServerStarter for FakeServerStarter {
        async fn start_server(&self, _resolved_config: &CliResolvedConfig) -> Result<(), CliError> {
            self.state.lock().expect("starter").start_calls += 1;
            Ok(())
        }
    }

    #[derive(Clone)]
    struct FakeServerRunner {
        state: Arc<Mutex<FakeServerRunnerState>>,
    }

    struct FakeServerRunnerState {
        run_calls: usize,
        status: ServerExitStatus,
    }

    impl FakeServerRunner {
        fn stopped() -> Self {
            Self {
                state: Arc::new(Mutex::new(FakeServerRunnerState {
                    run_calls: 0,
                    status: ServerExitStatus::Stopped,
                })),
            }
        }
    }

    impl CliServerRunner for FakeServerRunner {
        async fn run_server(&self, _args: ServerStartArgs) -> ServerExitStatus {
            let mut state = self.state.lock().expect("runner");
            state.run_calls += 1;
            state.status.clone()
        }
    }

    struct FailingBuilder;

    impl CliServerStartArgsBuilder for FailingBuilder {
        fn build(&self, _resolved_config: &CliResolvedConfig) -> Result<ServerStartArgs, CliError> {
            Err(CliError::ServerDependencyFailed("missing dep".to_owned()))
        }
    }

    fn empty_snapshot_frame(command_id: &str) -> LocalClientFrame {
        LocalClientFrame::Snapshot(LocalClientSnapshotFrame {
            delivery_seq: 1,
            client_command_id: LocalClientCommandId::new(command_id).expect("command id"),
            snapshot: LocalClientSnapshot {
                generated_at: 0,
                tasks: Vec::new(),
                task_parent_edges: Vec::new(),
                history_nodes: Vec::new(),
                task_versions: Vec::new(),
            },
        })
    }

    fn command_completed_notice(command_id: &str, command_name: &str) -> LocalClientFrame {
        LocalClientFrame::Notice(LocalClientNoticeFrame {
            delivery_seq: 3,
            client_command_id: LocalClientCommandId::new("cli-attach").expect("attach id"),
            notice: LocalNotice {
                level: LocalNoticeLevel::Info,
                kind: LocalNoticeKind::CommandCompleted {
                    client_command_id: LocalClientCommandId::new(command_id).expect("command id"),
                    command_name: command_name.to_owned(),
                },
                message_text: "chatgpt: gpt-5, gpt-5-codex".to_owned(),
            },
        })
    }

    fn command_failed_notice(command_id: &str, command_name: &str) -> LocalClientFrame {
        command_failed_notice_with_message(command_id, command_name, "model listing failed")
    }

    fn command_failed_notice_with_message(
        command_id: &str,
        command_name: &str,
        message_text: &str,
    ) -> LocalClientFrame {
        LocalClientFrame::Notice(LocalClientNoticeFrame {
            delivery_seq: 3,
            client_command_id: LocalClientCommandId::new("cli-attach").expect("attach id"),
            notice: LocalNotice {
                level: LocalNoticeLevel::Error,
                kind: LocalNoticeKind::CommandFailed {
                    client_command_id: LocalClientCommandId::new(command_id).expect("command id"),
                    command_name: command_name.to_owned(),
                },
                message_text: message_text.to_owned(),
            },
        })
    }

    fn command_argv() -> Vec<String> {
        vec![
            "selvedge".to_owned(),
            "--client-id".to_owned(),
            "client-1".to_owned(),
            "send-user-input".to_owned(),
            serde_json::json!({"message":"hello"}).to_string(),
        ]
    }

    fn ready_response(state: ReadyState) -> ReadyResponse {
        ReadyResponse { state }
    }

    #[allow(dead_code)]
    fn subscription() -> LocalClientSubscription {
        LocalClientSubscription {
            task_scope: LocalTaskScope::AllTasks,
            detail_level: LocalDetailLevel::Summary,
            snapshot_mode: selvedge_local_protocol::LocalSnapshotMode::CurrentState,
            include_model_call_status: false,
            include_tool_execution_status: false,
            include_debug_notices: false,
        }
    }
}
