use std::collections::HashMap;
use std::future::Future;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use selvedge_api::ApiExecutorConfig;
use selvedge_client_sync::{
    ClientSnapshotBuildFuture, ClientSnapshotBuildRequest, ClientSnapshotBuilder,
};
use selvedge_command_model::{
    ClientSnapshot, RouterCommandEnvelope, RouterIngressWeakSender, ToolExecutionRequest,
};
use selvedge_core::{TaskRuntimeConfig, TaskRuntimeSpawnDeps};
use selvedge_domain_model::UnixTs;
use selvedge_local_client::{LocalClientConfig, LocalClientError, LocalEndpoint};
use selvedge_local_protocol::{
    CommandOutcome, CommandRequest, CommandResponse, LocalClientCommandId, LocalClientId,
    ReadyRequest, ReadyResponse, ReadyState, current_protocol_version,
};
use selvedge_router::{ToolExecutionSpawnError, ToolExecutionSpawner};
use selvedge_server::{
    LocalBindingConfig, LocalCommandMapper, LocalhostBindTarget, ServerRequestError,
    ServerStartArgs, ServerStartupError,
};
use selvedge_systemd::{
    ServiceStatus, SystemctlBackend, SystemctlBackendConfig, SystemdBackend, SystemdClient,
    SystemdConfig, SystemdScope,
};
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
        client_id: String,
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
            snapshot_builder: Arc::new(EmptySnapshotBuilder),
            command_mapper: Arc::new(UnsupportedCommandMapper),
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

    let systemd_backend = match SystemctlBackend::new(SystemctlBackendConfig {
        systemctl_path: "systemctl".into(),
        scope: SystemdScope::System,
    }) {
        Ok(backend) => backend,
        Err(error) => return CliExitStatus::ServerStartFailed(format!("{error:?}")),
    };

    run_cli_with_deps(
        args.argv,
        systemd_backend,
        DefaultCliServerRunner,
        DefaultCliLocalClientConnector,
        DefaultCliServerStartArgsBuilder::new(),
    )
    .await
}

pub async fn run_cli_with_deps<S, R, C, B>(
    args: Vec<String>,
    systemd_backend: S,
    server_runner: R,
    local_client_connector: C,
    server_start_args_builder: B,
) -> CliExitStatus
where
    S: SystemdBackend,
    R: CliServerRunner,
    C: CliLocalClientConnector,
    B: CliServerStartArgsBuilder,
{
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
                systemd_backend,
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

fn parse_cli_args(args: &[String]) -> Result<CliCommand, String> {
    let tokens = args.iter().skip(1).map(String::as_str).collect::<Vec<_>>();
    if tokens == ["server"] {
        return Ok(CliCommand::RunServer);
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
    if command_name.trim().is_empty() || command_name == "server" || command_name.starts_with('-') {
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
        client_id,
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
    systemd_backend: S,
    local_client_connector: C,
    resolved_config: CliResolvedConfig,
    command_name: String,
    payload: serde_json::Value,
    client_id: String,
) -> CliExitStatus
where
    S: SystemdBackend,
    C: CliLocalClientConnector,
{
    let client_id = match LocalClientId::new(client_id) {
        Ok(client_id) => client_id,
        Err(error) => return CliExitStatus::InvalidArgs(format!("{error:?}")),
    };
    let client_command_id = match LocalClientCommandId::new(next_command_id()) {
        Ok(client_command_id) => client_command_id,
        Err(error) => return CliExitStatus::InvalidArgs(format!("{error:?}")),
    };
    let request = CommandRequest {
        protocol_version: current_protocol_version(),
        client_id,
        client_command_id,
        command_name,
        payload,
    };

    match connect_and_ready(&local_client_connector, &resolved_config).await {
        ReadyProbe::Ready(mut client) => return submit_ready_command(&mut client, request).await,
        ReadyProbe::Unavailable | ReadyProbe::NotReady => {}
    }

    let systemd = match SystemdClient::new(resolved_config.systemd_config.clone(), systemd_backend)
    {
        Ok(systemd) => systemd,
        Err(error) => return CliExitStatus::ServerStartFailed(format!("{error:?}")),
    };

    if let Err(error) = systemd.start_service().await {
        return CliExitStatus::ServerStartFailed(format!("{error:?}"));
    }
    match systemd.wait_service_active().await {
        Ok(ServiceStatus::Active) => {}
        Ok(ServiceStatus::Failed { message }) => return CliExitStatus::ServerStartFailed(message),
        Ok(status) => return CliExitStatus::ServerStartFailed(format!("{status:?}")),
        Err(error) => return CliExitStatus::ServerStartFailed(format!("{error:?}")),
    }

    let deadline = tokio::time::Instant::now() + resolved_config.ready_timeout;
    loop {
        if tokio::time::Instant::now() >= deadline {
            return CliExitStatus::ServerReadyTimeout;
        }
        match connect_and_ready(&local_client_connector, &resolved_config).await {
            ReadyProbe::Ready(mut client) => {
                return submit_ready_command(&mut client, request).await;
            }
            ReadyProbe::Unavailable | ReadyProbe::NotReady => {
                let now = tokio::time::Instant::now();
                let Some(sleep_for) =
                    ready_retry_sleep_duration(now, deadline, resolved_config.ready_poll_interval)
                else {
                    return CliExitStatus::ServerReadyTimeout;
                };
                if sleep_for.is_zero() {
                    continue;
                }
                tokio::time::sleep(sleep_for).await;
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

enum ReadyProbe<C> {
    Ready(C),
    NotReady,
    Unavailable,
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
    match client
        .ready(ReadyRequest {
            protocol_version: current_protocol_version(),
        })
        .await
    {
        Ok(ReadyResponse {
            state: ReadyState::Ready,
            ..
        }) => ReadyProbe::Ready(client),
        Ok(_) => ReadyProbe::NotReady,
        Err(_) => ReadyProbe::Unavailable,
    }
}

async fn submit_ready_command<C>(client: &mut C, request: CommandRequest) -> CliExitStatus
where
    C: CliLocalClient,
{
    match client.submit_command(request).await {
        Ok(CommandResponse {
            outcome: CommandOutcome::Accepted,
            ..
        }) => CliExitStatus::Success,
        Ok(CommandResponse {
            outcome: CommandOutcome::Rejected(reason),
            ..
        }) => CliExitStatus::CommandRejected(format!("{reason:?}")),
        Err(error) => CliExitStatus::LocalClientFailed(format!("{error:?}")),
    }
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
        CommandRejectReason, LocalClientSubscription, LocalDetailLevel, LocalTaskScope,
    };
    use selvedge_server::ServerExitStatus;
    use selvedge_systemd::{StartServiceOutcome, SystemdError};

    use super::*;

    #[tokio::test]
    async fn command_uses_ready_client_without_systemd_start() {
        let connector = FakeConnector::new(vec![Ok(FakeClientPlan::ready_accepted())]);
        let connector_state = connector.state.clone();
        let systemd = FakeSystemdBackend::new(Vec::new(), Vec::new());

        let status = run_cli_with_deps(
            command_argv(),
            systemd.clone(),
            FakeServerRunner::stopped(),
            connector,
            DefaultCliServerStartArgsBuilder::new(),
        )
        .await;

        assert_eq!(status, CliExitStatus::Success);
        assert_eq!(connector_state.lock().expect("connector").connect_calls, 1);
        assert_eq!(systemd.start_calls(), 0);
    }

    #[tokio::test]
    async fn command_auto_starts_systemd_then_reconnects_and_submits() {
        let connector = FakeConnector::new(vec![
            Ok(FakeClientPlan::not_ready()),
            Ok(FakeClientPlan::ready_accepted()),
        ]);
        let connector_state = connector.state.clone();
        let systemd = FakeSystemdBackend::new(
            vec![Ok(ServiceStatus::Inactive), Ok(ServiceStatus::Active)],
            vec![Ok(StartServiceOutcome::StartRequested)],
        );

        let status = run_cli_with_deps(
            command_argv(),
            systemd.clone(),
            FakeServerRunner::stopped(),
            connector,
            DefaultCliServerStartArgsBuilder::new(),
        )
        .await;

        assert_eq!(status, CliExitStatus::Success);
        assert_eq!(connector_state.lock().expect("connector").connect_calls, 2);
        assert_eq!(systemd.start_calls(), 1);
    }

    #[tokio::test]
    async fn command_rejection_is_not_success() {
        let connector = FakeConnector::new(vec![Ok(FakeClientPlan {
            ready: Ok(ready_response(ReadyState::Ready)),
            submit: Ok(CommandResponse {
                protocol_version: current_protocol_version(),
                client_command_id: LocalClientCommandId::new("response-1").expect("command id"),
                outcome: CommandOutcome::Rejected(CommandRejectReason::UnsupportedCommand),
            }),
        })]);

        let status = run_cli_with_deps(
            command_argv(),
            FakeSystemdBackend::new(Vec::new(), Vec::new()),
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

    #[tokio::test]
    async fn usage_error_has_no_side_effects() {
        let connector = FakeConnector::new(Vec::new());
        let connector_state = connector.state.clone();
        let systemd = FakeSystemdBackend::new(Vec::new(), Vec::new());
        let runner = FakeServerRunner::stopped();
        let runner_state = runner.state.clone();

        let status = run_cli_with_deps(
            vec!["selvedge".to_owned(), "--unknown".to_owned()],
            systemd.clone(),
            runner,
            connector,
            DefaultCliServerStartArgsBuilder::new(),
        )
        .await;

        assert!(matches!(status, CliExitStatus::InvalidArgs(_)));
        assert_eq!(connector_state.lock().expect("connector").connect_calls, 0);
        assert_eq!(systemd.start_calls(), 0);
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
                client_id: "client-1".to_owned(),
            }
        );
    }

    #[tokio::test]
    async fn server_subcommand_uses_builder_and_runner_without_systemd_or_local_client() {
        let connector = FakeConnector::new(Vec::new());
        let connector_state = connector.state.clone();
        let systemd = FakeSystemdBackend::new(Vec::new(), Vec::new());
        let runner = FakeServerRunner::stopped();
        let runner_state = runner.state.clone();

        let status = run_cli_with_deps(
            vec!["selvedge".to_owned(), "server".to_owned()],
            systemd.clone(),
            runner,
            connector,
            DefaultCliServerStartArgsBuilder::new(),
        )
        .await;

        assert_eq!(status, CliExitStatus::Success);
        assert_eq!(connector_state.lock().expect("connector").connect_calls, 0);
        assert_eq!(systemd.start_calls(), 0);
        assert_eq!(runner_state.lock().expect("runner").run_calls, 1);
    }

    #[tokio::test]
    async fn server_builder_failure_skips_runner() {
        let runner = FakeServerRunner::stopped();
        let runner_state = runner.state.clone();

        let status = run_cli_with_deps(
            vec!["selvedge".to_owned(), "server".to_owned()],
            FakeSystemdBackend::new(Vec::new(), Vec::new()),
            runner,
            FakeConnector::new(Vec::new()),
            FailingBuilder,
        )
        .await;

        assert!(matches!(status, CliExitStatus::ServerDependencyFailed(_)));
        assert_eq!(runner_state.lock().expect("runner").run_calls, 0);
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
    }

    impl FakeClientPlan {
        fn ready_accepted() -> Self {
            Self {
                ready: Ok(ready_response(ReadyState::Ready)),
                submit: Ok(CommandResponse {
                    protocol_version: current_protocol_version(),
                    client_command_id: LocalClientCommandId::new("response-1").expect("command id"),
                    outcome: CommandOutcome::Accepted,
                }),
            }
        }

        fn not_ready() -> Self {
            Self {
                ready: Ok(ready_response(ReadyState::NotReady)),
                submit: Err(CliError::LocalClientFailed(
                    "submit should not run".to_owned(),
                )),
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
    }

    #[derive(Clone)]
    struct FakeSystemdBackend {
        state: Arc<Mutex<FakeSystemdState>>,
    }

    struct FakeSystemdState {
        query_results: VecDeque<Result<ServiceStatus, SystemdError>>,
        start_results: VecDeque<Result<StartServiceOutcome, SystemdError>>,
        start_calls: usize,
    }

    impl FakeSystemdBackend {
        fn new(
            query_results: Vec<Result<ServiceStatus, SystemdError>>,
            start_results: Vec<Result<StartServiceOutcome, SystemdError>>,
        ) -> Self {
            Self {
                state: Arc::new(Mutex::new(FakeSystemdState {
                    query_results: query_results.into(),
                    start_results: start_results.into(),
                    start_calls: 0,
                })),
            }
        }

        fn start_calls(&self) -> usize {
            self.state.lock().expect("systemd").start_calls
        }
    }

    impl SystemdBackend for FakeSystemdBackend {
        async fn query_status(&self, _unit_name: &str) -> Result<ServiceStatus, SystemdError> {
            self.state
                .lock()
                .expect("systemd")
                .query_results
                .pop_front()
                .unwrap_or(Ok(ServiceStatus::Active))
        }

        async fn start_unit(&self, _unit_name: &str) -> Result<StartServiceOutcome, SystemdError> {
            let mut state = self.state.lock().expect("systemd");
            state.start_calls += 1;
            state
                .start_results
                .pop_front()
                .unwrap_or(Ok(StartServiceOutcome::StartRequested))
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
        ReadyResponse {
            protocol_version: current_protocol_version(),
            state,
        }
    }

    #[allow(dead_code)]
    fn subscription() -> LocalClientSubscription {
        LocalClientSubscription {
            task_scope: LocalTaskScope::AllTasks,
            detail_level: LocalDetailLevel::Summary,
            include_model_call_status: false,
            include_tool_execution_status: false,
            include_debug_notices: false,
        }
    }
}
