//! @behavior selvedge Selvedge lets a local user keep AI-assisted tasks running on this machine and control them through localhost clients.
//! @behavior selvedge.startup A local user can ask the CLI to start or contact the Selvedge service and receive a typed result for that attempt.
//! @behavior selvedge.cli The Selvedge CLI parses process arguments, starts or contacts the local service, submits commands, and maps outcomes to process exit codes.
//! @behavior selvedge.cli.process The selvedge CLI exits with status 0 for success, 130 for interruption, and 1 for other user-visible failures.
//! @behavior selvedge.cli.local_client CLI local clients expose readiness and command submission outcomes.
//! @behavior selvedge.cli.local_connector CLI local connectors expose connection outcomes for local command submission.
//! @behavior selvedge.cli.server_args_builder CLI server argument builders expose startup argument outcomes.
//! @behavior selvedge.cli.default_server_args_builder The default server argument builder exposes the repository default server startup arguments.
//! @behavior selvedge.cli.server_runner CLI server runners expose local server exit outcomes.
//! @behavior tool.worktree The worktree helper creates focused Git worktrees under managed .worktrees storage and reports setup failures through process output.

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

// @behavior selvedge.cli.name The CLI reports the Cargo package name as its application name.
pub fn app_name() -> &'static str {
    env!("CARGO_PKG_NAME")
}

// @behavior selvedge.cli.startup_message The startup message reports that the application is ready.
pub fn startup_message() -> String {
    format!("{} is ready.", app_name())
}

// @behavior selvedge.cli.args CliRunArgs carries the full process argument vector used by CLI execution.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CliRunArgs {
    /// @behavior selvedge.cli.args.argv CliRunArgs carries the process argv vector.
    pub argv: Vec<String>,
}

// @behavior selvedge.cli.command CLI arguments resolve to either running the server or submitting a named local command.
#[derive(Clone, Debug, PartialEq)]
pub enum CliCommand {
    RunServer,
    SubmitCommand {
        command_name: String,
        payload: serde_json::Value,
        client_id: String,
    },
}

// @behavior selvedge.cli.status CLI execution returns typed exit statuses for success, argument errors, config errors, logging errors, startup failures, command outcomes, local client failures, server failures, and interruption.
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

// @behavior selvedge.cli.error CLI dependency failures are reported as local client or server dependency errors.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CliError {
    LocalClientFailed(String),
    ServerDependencyFailed(String),
}

// @behavior selvedge.cli.config CLI resolved config contains local client, systemd, readiness timeout, and retry interval settings.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CliResolvedConfig {
    /// @behavior selvedge.cli.config.local_client Resolved CLI config carries the local client endpoint and request timeout.
    pub local_client_config: LocalClientConfig,
    /// @behavior selvedge.cli.config.systemd Resolved CLI config carries the systemd unit and polling timeouts.
    pub systemd_config: SystemdConfig,
    /// @behavior selvedge.cli.config.ready_timeout Resolved CLI config carries the total readiness wait timeout.
    pub ready_timeout: Duration,
    /// @behavior selvedge.cli.config.ready_poll_interval Resolved CLI config carries the readiness retry interval.
    pub ready_poll_interval: Duration,
}

// @behavior selvedge.cli.config.default Default CLI config targets the local IPv4 endpoint, default timeout, and default systemd unit.
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

// @behavior selvedge.cli.local_client.contract Local client abstractions expose readiness and command submission results to CLI execution.
// @intent selvedge.cli.local_client.abstraction CliLocalClient abstracts local ready and command submission calls while preserving protocol request and response types.
pub trait CliLocalClient {
    /// @behavior selvedge.cli.local_client.ready CliLocalClient ready calls return the local server readiness response or CLI client error.
    fn ready(
        &mut self,
        request: ReadyRequest,
    ) -> impl Future<Output = Result<ReadyResponse, CliError>> + Send;

    /// @behavior selvedge.cli.local_client.submit CliLocalClient submit calls return the local command response or CLI client error.
    fn submit_command(
        &mut self,
        request: CommandRequest,
    ) -> impl Future<Output = Result<CommandResponse, CliError>> + Send;
}

// @behavior selvedge.cli.local_connector.contract Local client connectors expose connection success or CLI client failure to command submission.
// @intent selvedge.cli.local_connector.abstraction CliLocalClientConnector abstracts local client connection using the resolved local client config.
pub trait CliLocalClientConnector {
    /// @behavior selvedge.cli.local_connector.client CliLocalClientConnector chooses the concrete client type used for local calls.
    type Client: CliLocalClient;

    /// @behavior selvedge.cli.local_connector.connect CliLocalClientConnector connects with the resolved local client config or returns a CLI client error.
    fn connect(
        &self,
        config: LocalClientConfig,
    ) -> impl Future<Output = Result<Self::Client, CliError>> + Send;
}

// @behavior selvedge.cli.server_args_builder.contract Server argument builders expose startup arguments or dependency errors to CLI server execution.
// @intent selvedge.cli.server_args_builder.abstraction CliServerStartArgsBuilder maps resolved CLI config into server startup arguments.
pub trait CliServerStartArgsBuilder {
    /// @behavior selvedge.cli.server_args_builder.build Server argument builders return server startup arguments or CLI dependency errors.
    fn build(&self, resolved_config: &CliResolvedConfig) -> Result<ServerStartArgs, CliError>;
}

// @behavior selvedge.cli.default_server_args_builder.contract The default server argument builder returns the repository default server startup configuration.
// @intent selvedge.cli.default_server_args_builder.abstraction DefaultCliServerStartArgsBuilder builds the repository default server startup configuration for CLI execution.
pub struct DefaultCliServerStartArgsBuilder;

impl DefaultCliServerStartArgsBuilder {
    // @behavior selvedge.cli.default_server_args_builder.new The default server argument builder constructor returns a builder with default startup behavior.
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
        // @behavior selvedge.cli.server_args Server startup arguments bind local and web endpoints to the resolved loopback endpoint.
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
            local_binding: LocalBindingConfig {
                bind_target: local_bind_target.clone(),
            },
            web_binding: Some(selvedge_server::WebBindingConfig {
                bind_target: local_bind_target,
            }),
        })
    }
}

/// @behavior selvedge.cli.server_runner.contract Server runners expose server exit status to CLI server execution.
/// @intent selvedge.cli.server_runner.abstraction CliServerRunner abstracts running the local server while preserving server exit statuses.
pub trait CliServerRunner: Send + Sync + 'static {
    /// @behavior selvedge.cli.server_runner.run Server runners return the server exit status for supplied startup arguments.
    fn run_server(
        &self,
        args: ServerStartArgs,
    ) -> impl Future<Output = selvedge_server::ServerExitStatus> + Send;
}

// @behavior selvedge.cli.run run_cli initializes config and logging before running the parsed CLI command.
pub async fn run_cli(args: CliRunArgs) -> CliExitStatus {
    let parsed_command = parse_cli_args(&args.argv);
    if let Err(error) = selvedge_config::init() {
        // @behavior selvedge.cli.config_error Config initialization failure returns ConfigFailed.
        return CliExitStatus::ConfigFailed(error.to_string());
    }
    if let Err(error) = selvedge_logging::init() {
        // @behavior selvedge.cli.logging_error Logging initialization failure returns LoggingFailed.
        return CliExitStatus::LoggingFailed(error.to_string());
    }
    if let Err(error) = parsed_command {
        // @behavior selvedge.cli.invalid_args Invalid process arguments return InvalidArgs after startup initialization completes.
        return CliExitStatus::InvalidArgs(error);
    }

    // @behavior selvedge.cli.systemd_backend Systemd backend construction failure returns ServerStartFailed.
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

// @behavior selvedge.cli.deps run_cli_with_deps parses arguments, resolves config, and executes the requested command through injected dependencies.
pub async fn run_cli_with_deps(
    args: Vec<String>,
    systemd_backend: impl SystemdBackend,
    server_runner: impl CliServerRunner,
    local_client_connector: impl CliLocalClientConnector,
    server_start_args_builder: impl CliServerStartArgsBuilder,
) -> CliExitStatus {
    // @behavior selvedge.cli.deps.argument_parse Injected CLI execution parses supplied arguments before calling injected dependencies.
    let command = match parse_cli_args(&args) {
        Ok(command) => command,
        // @behavior selvedge.cli.deps.invalid_args Invalid injected CLI arguments return InvalidArgs before dependency calls.
        Err(error) => return CliExitStatus::InvalidArgs(error),
    };
    let resolved_config = match resolve_cli_config() {
        Ok(config) => config,
        // @behavior selvedge.cli.config.uninitialized Uninitialized config resolution uses the default CLI config.
        Err(CliConfigResolution::NotInitialized) => CliResolvedConfig::default(),
        // @behavior selvedge.cli.config.failed Config resolution failures return ConfigFailed.
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
    // @behavior selvedge.cli.config.read CLI config resolution reads the current application config and maps config errors to CLI config resolution outcomes.
    selvedge_config::read(cli_resolved_config_from_app_config).map_err(|error| match error {
        selvedge_config::ConfigError::NotInitialized => CliConfigResolution::NotInitialized,
        error => CliConfigResolution::Failed(error.to_string()),
    })?
}

fn cli_resolved_config_from_app_config(
    config: &selvedge_config_model::AppConfig,
) -> Result<CliResolvedConfig, CliConfigResolution> {
    // @constraint selvedge.cli.config.loopback CLI server.host accepts only loopback hosts for local client and server operations.
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

    // @behavior selvedge.cli.config.defaults CLI config resolution derives local client, systemd, and readiness timeouts from the loaded app config.
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

// @behavior selvedge.cli.process.exit_code CLI exit status maps Success to 0, Interrupted to 130, and all other statuses to 1.
pub fn exit_code(status: &CliExitStatus) -> i32 {
    match status {
        CliExitStatus::Success => 0,
        CliExitStatus::Interrupted => 130,
        _ => 1,
    }
}

// @behavior selvedge.cli.parse The server subcommand runs the local server and other command names require --client-id plus a JSON payload.
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
                // @constraint selvedge.cli.parse.extra_positional Extra positional arguments after the JSON payload return an argument error.
                return Err("unexpected extra positional argument".to_owned());
            }
            json_payload = Some(tokens[index].to_owned());
            index += 1;
            continue;
        }

        match tokens[index] {
            "--client-id" => {
                if client_id.is_some() {
                    // @constraint selvedge.cli.parse_client_id_duplicate Duplicate --client-id flags return an argument error.
                    return Err("duplicate --client-id".to_owned());
                }
                index += 1;
                let Some(value) = tokens.get(index) else {
                    // @constraint selvedge.cli.parse_client_id_missing Missing --client-id values return an argument error.
                    return Err("missing --client-id value".to_owned());
                };
                if value.trim().is_empty() {
                    // @constraint selvedge.cli.parse_client_id_empty Empty --client-id values return an argument error.
                    return Err("empty --client-id".to_owned());
                }
                client_id = Some((*value).to_owned());
            }
            // @constraint selvedge.cli.parse.flag Unknown flags return an argument error.
            token if token.starts_with('-') => return Err(format!("unknown flag {token}")),
            token => command_name = Some(token.to_owned()),
        }
        index += 1;
    }

    let client_id = client_id.ok_or_else(|| "missing --client-id".to_owned())?;
    let command_name = command_name.ok_or_else(|| "expected command name".to_owned())?;
    if command_name.trim().is_empty() || command_name == "server" || command_name.starts_with('-') {
        // @constraint selvedge.cli.parse.command_name Submitted command names must be non-empty user command names.
        return Err("invalid command name".to_owned());
    }
    let json_payload = json_payload.ok_or_else(|| "expected json payload".to_owned())?;
    if json_payload.is_empty() {
        return Err("empty json payload".to_owned());
    }
    let payload = serde_json::from_str(&json_payload)
        .map_err(|error| format!("invalid json payload: {error}"))?;

    // @behavior selvedge.cli.parse.payload Command submission parses the positional payload as JSON before local submission.
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
    // @behavior selvedge.cli.server The server subcommand builds server startup arguments and returns success only when the server stops normally.
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
    // @behavior selvedge.cli.submit Command submission probes an existing local server, starts systemd when needed, waits for readiness, and submits to a ready local client.
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
        // @behavior selvedge.cli.submit.ready_existing A ready local server receives the command without starting systemd.
        ReadyProbe::Ready(mut client) => return submit_ready_command(&mut client, request).await,
        ReadyProbe::Failed(error) => return CliExitStatus::LocalClientFailed(format!("{error:?}")),
        ReadyProbe::Unavailable | ReadyProbe::NotReady => {}
    }

    let systemd = match SystemdClient::new(resolved_config.systemd_config.clone(), systemd_backend)
    {
        Ok(systemd) => systemd,
        // @behavior selvedge.cli.submit.systemd_create_failure Systemd client construction failure returns ServerStartFailed.
        Err(error) => return CliExitStatus::ServerStartFailed(format!("{error:?}")),
    };

    if let Err(error) = systemd.start_service().await {
        return CliExitStatus::ServerStartFailed(format!("{error:?}"));
    }
    match systemd.wait_service_active().await {
        Ok(ServiceStatus::Active) => {}
        // @behavior selvedge.cli.submit.service_failed A failed systemd service state returns ServerStartFailed with the service message.
        Ok(ServiceStatus::Failed { message }) => return CliExitStatus::ServerStartFailed(message),
        // @behavior selvedge.cli.submit.service_unready A non-active systemd service state returns ServerStartFailed with status text.
        Ok(status) => return CliExitStatus::ServerStartFailed(format!("{status:?}")),
        // @behavior selvedge.cli.submit.service_wait_error A systemd wait error returns ServerStartFailed with error text.
        Err(error) => return CliExitStatus::ServerStartFailed(format!("{error:?}")),
    }

    let Some(deadline) = ready_deadline_from_now(resolved_config.ready_timeout) else {
        // @constraint selvedge.cli.submit.deadline_overflow Readiness deadline overflow returns ServerReadyTimeout.
        return CliExitStatus::ServerReadyTimeout;
    };
    loop {
        if tokio::time::Instant::now() >= deadline {
            // @behavior selvedge.cli.submit.ready_timeout Readiness polling returns ServerReadyTimeout when the deadline is reached.
            return CliExitStatus::ServerReadyTimeout;
        }
        match connect_and_ready(&local_client_connector, &resolved_config).await {
            ReadyProbe::Ready(mut client) => {
                return submit_ready_command(&mut client, request).await;
            }
            ReadyProbe::Failed(error) => {
                return CliExitStatus::LocalClientFailed(format!("{error:?}"));
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

// @constraint selvedge.cli.submit.retry_sleep Readiness retry sleep is capped to the remaining deadline duration.
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
    // @constraint selvedge.cli.submit.deadline Readiness timeout must fit in Tokio Instant arithmetic to produce a polling deadline.
    tokio::time::Instant::now().checked_add(timeout)
}

// @behavior selvedge.cli.ready_probe Ready probing classifies a local client as ready, not ready, unavailable, or failed.
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
    // @behavior selvedge.cli.ready_probe.connect Connection failure during readiness probing is treated as unavailable for auto-start decisions.
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
        // @behavior selvedge.cli.ready_probe.ready Ready protocol state makes the local client eligible for command submission.
        }) => ReadyProbe::Ready(client),
        Ok(_) => ReadyProbe::NotReady,
        Err(error) => ReadyProbe::Failed(error),
    }
}

async fn submit_ready_command<C>(client: &mut C, request: CommandRequest) -> CliExitStatus
where
    C: CliLocalClient,
{
    // @behavior selvedge.cli.submit.outcome Accepted command responses return Success, rejected responses return CommandRejected, and client errors return LocalClientFailed.
    match client.submit_command(request).await {
        Ok(CommandResponse {
            outcome: CommandOutcome::Accepted,
            ..
        }) => CliExitStatus::Success,
        Ok(CommandResponse {
            outcome: CommandOutcome::Rejected(reason),
            ..
        }) => CliExitStatus::CommandRejected(format!("{reason:?}")),
        // @behavior selvedge.cli.submit.error Local client submission errors return LocalClientFailed with error text.
        Err(error) => CliExitStatus::LocalClientFailed(format!("{error:?}")),
    }
}

// @behavior selvedge.cli.command_id CLI command ids include the process id and a monotonically increasing counter.
fn next_command_id() -> String {
    // @behavior selvedge.cli.command_id.counter Each generated CLI command id advances the process-local counter.
    let counter = COMMAND_ID_COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("cli-{}-{counter}", std::process::id())
}

// @behavior selvedge.cli.local_connector.default_struct The default local client connector uses HTTP local transport for CLI command submission.
pub struct DefaultCliLocalClientConnector;

// @behavior selvedge.cli.local_client.default Default local clients call the HTTP local transport and map transport errors to CLI client errors.
pub struct DefaultCliLocalClient(
    selvedge_local_client::LocalClient<selvedge_local_client::HttpLocalTransport>,
);

impl CliLocalClientConnector for DefaultCliLocalClientConnector {
    // @behavior selvedge.cli.local_connector.default_client The default connector returns the default HTTP local client type.
    type Client = DefaultCliLocalClient;

    // @behavior selvedge.cli.local_connector.default_connect The default connector connects through the HTTP local transport with the resolved config.
    async fn connect(&self, config: LocalClientConfig) -> Result<Self::Client, CliError> {
        selvedge_local_client::connect_http(config)
            .await
            .map(DefaultCliLocalClient)
            .map_err(map_local_client_error)
    }
}

impl CliLocalClient for DefaultCliLocalClient {
    // @behavior selvedge.cli.local_client.default_ready Default local client ready calls forward requests to the HTTP local transport.
    async fn ready(&mut self, request: ReadyRequest) -> Result<ReadyResponse, CliError> {
        self.0.ready(request).await.map_err(map_local_client_error)
    }

    // @behavior selvedge.cli.local_client.default_submit The default local client forwards command requests to the HTTP local transport.
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

// @behavior selvedge.cli.local_client.error Local client errors are converted into CLI LocalClientFailed errors with debug text.
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
    // @behavior selvedge.cli.server_args.tool_unavailable The default CLI server arguments report tool execution as unavailable.
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
    // @behavior selvedge.cli.server_args.empty_snapshot The default CLI server arguments expose an empty initial client snapshot.
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
    // @behavior selvedge.cli.server_args.unsupported_command The default CLI server arguments reject all mapped local commands as unsupported.
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

        // @verifies selvedge.cli.submit.ready_existing
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

        // @verifies selvedge.cli.submit
        assert_eq!(status, CliExitStatus::Success);
        assert_eq!(connector_state.lock().expect("connector").connect_calls, 2);
        assert_eq!(systemd.start_calls(), 1);
    }

    #[tokio::test]
    async fn command_ready_failure_returns_local_client_failure_without_systemd_start() {
        let connector = FakeConnector::new(vec![Ok(FakeClientPlan {
            ready: Err(CliError::LocalClientFailed("protocol mismatch".to_owned())),
            submit: Ok(CommandResponse {
                protocol_version: current_protocol_version(),
                client_command_id: LocalClientCommandId::new("response-1").expect("command id"),
                outcome: CommandOutcome::Accepted,
            }),
        })]);
        let systemd = FakeSystemdBackend::new(Vec::new(), Vec::new());

        let status = run_cli_with_deps(
            command_argv(),
            systemd.clone(),
            FakeServerRunner::stopped(),
            connector,
            DefaultCliServerStartArgsBuilder::new(),
        )
        .await;

        // @verifies selvedge.cli.ready_probe
        assert_eq!(
            status,
            CliExitStatus::LocalClientFailed("LocalClientFailed(\"protocol mismatch\")".to_owned())
        );
        // @verifies selvedge.cli.submit.ready_existing
        assert_eq!(systemd.start_calls(), 0);
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

        // @verifies selvedge.cli.submit.outcome
        assert_eq!(
            status,
            CliExitStatus::CommandRejected("UnsupportedCommand".to_owned())
        );
    }

    #[test]
    fn ready_retry_sleep_is_capped_to_remaining_time() {
        let now = tokio::time::Instant::now();
        let deadline = now + Duration::from_millis(10);

        // @verifies selvedge.cli.submit.retry_sleep
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
        // @verifies selvedge.cli.submit.deadline
        assert_eq!(ready_deadline_from_now(Duration::MAX), None);
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

        // @verifies selvedge.cli.parse
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

        // @verifies selvedge.cli.parse.payload
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

        // @verifies selvedge.cli.server
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

        // @verifies selvedge.cli.server
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
        async fn query_status(
            &self,
            _unit_name: &str,
            _operation_timeout: Duration,
        ) -> Result<ServiceStatus, SystemdError> {
            self.state
                .lock()
                .expect("systemd")
                .query_results
                .pop_front()
                .unwrap_or(Ok(ServiceStatus::Active))
        }

        async fn start_unit(
            &self,
            _unit_name: &str,
            _operation_timeout: Duration,
        ) -> Result<StartServiceOutcome, SystemdError> {
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
