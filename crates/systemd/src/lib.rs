#![doc = include_str!("../README.md")]
//! @behavior selvedge.operations The CLI can ask systemd to start the configured Selvedge unit and wait until the unit reaches a terminal startup state.
//! @behavior selvedge.operations.systemd Systemd operations preserve unit status, start requests, timeouts, and typed systemd error behavior.
//! @behavior selvedge.operations.systemd.systemctl Systemctl boundaries expose process configuration, captured output, backend creation, and command parsing behavior.
//! @intent selvedge.operations.systemd.runner The runner abstraction lets systemd backends use production or test process execution while preserving the same outcomes.
//! @constraint selvedge.operations.systemd.validate Systemd service and backend configuration must pass validation before operations run.

use std::future::Future;
use std::path::PathBuf;
use std::pin::Pin;
use std::sync::Arc;
use std::time::{Duration, Instant};

use tokio::io::AsyncReadExt;

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.operations.systemd.config Systemd clients receive the unit name, operation timeout, and poll interval used for service operations.
pub struct SystemdConfig {
    // @behavior selvedge.operations.systemd.config.unit_name Systemd service operations target the configured unit name.
    pub unit_name: String,
    // @behavior selvedge.operations.systemd.config.operation_timeout Systemd service operations use the configured operation timeout for status, start, and wait calls.
    pub operation_timeout: Duration,
    // @behavior selvedge.operations.systemd.config.poll_interval Waiting for service activation observes the configured poll interval between status checks.
    pub poll_interval: Duration,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.operations.systemd.status Service status reports not-installed, inactive, activating, active, failed, or unknown unit states to callers.
pub enum ServiceStatus {
    NotInstalled,
    Inactive,
    Activating,
    Active,
    Failed { message: String },
    Unknown { raw_state: String },
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.operations.systemd.start_outcome Service start calls report whether a start was requested, already running, or already starting.
pub enum StartServiceOutcome {
    StartRequested,
    AlreadyRunning,
    AlreadyStarting,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.operations.systemd.error Systemd failures are returned as typed validation, availability, missing-unit, rejection, timeout, or backend errors.
pub enum SystemdError {
    InvalidUnitName,
    InvalidOperationTimeout,
    InvalidPollInterval,
    // @behavior selvedge.operations.systemd.error.unavailable Unavailable errors expose why systemctl could not be launched or addressed.
    Unavailable(String),
    UnitNotFound,
    // @behavior selvedge.operations.systemd.error.start_rejected Start rejections expose the stderr text returned by systemctl.
    StartRejected(String),
    Timeout,
    // @behavior selvedge.operations.systemd.error.backend_failure Backend failures expose process, parsing, or task-join failure details.
    BackendFailure(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.operations.systemd.scope Systemd scope selects whether systemctl commands use the system manager or user manager.
pub enum SystemdScope {
    System,
    User,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.operations.systemd.systemctl.config Systemctl backend configuration exposes the executable path and scope used for process calls.
pub struct SystemctlBackendConfig {
    // @behavior selvedge.operations.systemd.systemctl.config.path Systemctl backend configuration exposes the systemctl executable path.
    pub systemctl_path: PathBuf,
    // @behavior selvedge.operations.systemd.systemctl.config.scope Systemctl backend configuration exposes the manager scope for systemctl commands.
    pub scope: SystemdScope,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.operations.systemd.systemctl.output Systemctl process output exposes exit code, stdout bytes, and stderr bytes to status and start parsing.
pub struct SystemctlProcessOutput {
    // @behavior selvedge.operations.systemd.systemctl.output.exit_code Systemctl process output exposes the process exit code when the process reports one.
    pub exit_code: Option<i32>,
    // @behavior selvedge.operations.systemd.systemctl.output.stdout Systemctl process output exposes captured stdout bytes for status parsing.
    pub stdout: Vec<u8>,
    // @behavior selvedge.operations.systemd.systemctl.output.stderr Systemctl process output exposes captured stderr bytes for start rejection and backend failure messages.
    pub stderr: Vec<u8>,
}

// @behavior selvedge.operations.systemd.process_runner Systemctl process runners execute configured commands with captured output and timeout-aware systemd errors.
// @intent selvedge.operations.systemd.process_runner.abstraction The systemd abstraction isolates systemctl command execution and service status parsing for CLI operations.
pub trait SystemctlProcessRunner {
    /// @behavior selvedge.operations.systemd.process_run Systemctl execution runs the requested program, arguments, and timeout and returns captured process output or systemd error.
    fn run(
        &self,
        program: &str,
        args: &[String],
        timeout: Duration,
    ) -> impl Future<Output = Result<SystemctlProcessOutput, SystemdError>> + Send;
}

// @behavior selvedge.operations.systemd.backend Systemd backends expose unit status queries and unit start requests with typed systemd outcomes.
// @intent selvedge.operations.systemd.backend.abstraction The systemd abstraction isolates systemctl command execution and service status parsing for CLI operations.
pub trait SystemdBackend: Send + Sync + 'static {
    /// @behavior selvedge.operations.systemd.query_status Systemd status queries return the configured unit status or a typed systemd error within the operation timeout.
    fn query_status(
        &self,
        unit_name: &str,
        operation_timeout: Duration,
    ) -> impl Future<Output = Result<ServiceStatus, SystemdError>> + Send;

    /// @behavior selvedge.operations.systemd.start_unit Systemd start requests return start acknowledgement or a typed rejection within the operation timeout.
    fn start_unit(
        &self,
        unit_name: &str,
        operation_timeout: Duration,
    ) -> impl Future<Output = Result<StartServiceOutcome, SystemdError>> + Send;
}

// @intent selvedge.operations.systemd.systemctl_backend SystemctlBackend adapts the systemctl process boundary into the systemd backend interface used by CLI operations.
// @intent selvedge.operations.systemd.systemctl_runner_field SystemctlBackend stores production and test process runners behind one backend-owned command execution boundary.
// @behavior selvedge.operations.systemd.systemctl.backend Systemctl backends translate systemctl process output into service status and start outcomes.
pub struct SystemctlBackend {
    config: SystemctlBackendConfig,
    runner: Arc<dyn ErasedSystemctlProcessRunner>,
}

// @behavior selvedge.operations.systemd.client Systemd clients validate configuration and expose query, start, and wait operations to callers.
pub struct SystemdClient<B: SystemdBackend> {
    // @behavior selvedge.operations.systemd.client.config Systemd clients expose the service operation configuration used by all calls.
    pub config: SystemdConfig,
    // @behavior selvedge.operations.systemd.client.backend Systemd clients expose the backend used to query and start the configured service.
    pub backend: B,
}

// @intent selvedge.operations.systemd.runner.erased The systemd abstraction isolates systemctl command execution and service status parsing for CLI operations.
trait ErasedSystemctlProcessRunner: Send + Sync {
    fn run_boxed<'a>(
        &'a self,
        program: &'a str,
        args: &'a [String],
        timeout: Duration,
    ) -> Pin<Box<dyn Future<Output = Result<SystemctlProcessOutput, SystemdError>> + Send + 'a>>;
}

impl<R> ErasedSystemctlProcessRunner for R
where
    R: SystemctlProcessRunner + Send + Sync + 'static,
{
    // @intent selvedge.operations.systemd.run_boxed The erased runner method adapts concrete systemctl futures into one boxed process execution future.
    fn run_boxed<'a>(
        &'a self,
        program: &'a str,
        args: &'a [String],
        timeout: Duration,
    ) -> Pin<Box<dyn Future<Output = Result<SystemctlProcessOutput, SystemdError>> + Send + 'a>>
    {
        Box::pin(self.run(program, args, timeout))
    }
}

struct StdSystemctlProcessRunner;

async fn read_child_pipe<R>(mut pipe: R) -> Result<Vec<u8>, SystemdError>
where
    R: tokio::io::AsyncRead + Unpin,
{
    let mut output = Vec::new();
    pipe.read_to_end(&mut output)
        .await
        // @behavior selvedge.operations.systemd.std_run.pipe_read Captured stdout and stderr pipe read failures return backend failure errors.
        .map_err(|error| SystemdError::BackendFailure(error.to_string()))?;
    Ok(output)
}

impl SystemctlProcessRunner for StdSystemctlProcessRunner {
    // @behavior selvedge.operations.systemd.std_run The standard runner starts systemctl with captured stdout and stderr and returns timeout or process output.
    async fn run(
        &self,
        program: &str,
        args: &[String],
        timeout: Duration,
    ) -> Result<SystemctlProcessOutput, SystemdError> {
        let mut child = tokio::process::Command::new(program)
            .args(args)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .kill_on_drop(true)
            .spawn()
            // @behavior selvedge.operations.systemd.std_run.spawn_error Systemctl spawn failures return unavailable errors with the launch failure message.
            .map_err(|error| SystemdError::Unavailable(error.to_string()))?;

        let stdout = child.stdout.take().ok_or_else(|| {
            SystemdError::BackendFailure("failed to capture systemctl stdout".to_owned())
        })?;
        let stderr = child.stderr.take().ok_or_else(|| {
            SystemdError::BackendFailure("failed to capture systemctl stderr".to_owned())
        })?;
        let stdout_reader = tokio::spawn(read_child_pipe(stdout));
        let stderr_reader = tokio::spawn(read_child_pipe(stderr));

        // @behavior selvedge.operations.systemd.std_run.wait Standard systemctl execution waits for process completion only within the requested timeout.
        let status = match tokio::time::timeout(timeout, child.wait()).await {
            Ok(Ok(status)) => status,
            // @behavior selvedge.operations.systemd.std_run.wait_error Process wait failures return backend failure errors with the wait failure message.
            Ok(Err(error)) => return Err(SystemdError::BackendFailure(error.to_string())),
            // @behavior selvedge.operations.systemd.std_run.timeout_kill Timed-out systemctl processes are asked to terminate before a timeout error is returned.
            Err(_) => {
                let _ = child.start_kill();
                let _ = child.wait().await;
                // @behavior selvedge.operations.systemd.std_run.timeout Systemctl process timeouts return the typed timeout error.
                return Err(SystemdError::Timeout);
            }
        };

        let stdout = stdout_reader
            .await
            // @behavior selvedge.operations.systemd.std_run.stdout_join Stdout reader task failures return backend failure errors.
            .map_err(|error| SystemdError::BackendFailure(error.to_string()))??;
        let stderr = stderr_reader
            .await
            // @behavior selvedge.operations.systemd.std_run.stderr_join Stderr reader task failures return backend failure errors.
            .map_err(|error| SystemdError::BackendFailure(error.to_string()))??;

        Ok(SystemctlProcessOutput {
            exit_code: status.code(),
            stdout,
            stderr,
        })
    }
}

impl SystemctlBackend {
    // @behavior selvedge.operations.systemd.systemctl.new Production systemctl backends validate their config before accepting service operations.
    pub fn new(config: SystemctlBackendConfig) -> Result<Self, SystemdError> {
        Self::new_with_runner(config, StdSystemctlProcessRunner)
    }

    // @behavior selvedge.operations.systemd.systemctl.new_with_runner Systemctl backends accept a caller-supplied runner after backend config validation succeeds.
    pub fn new_with_runner<R>(
        config: SystemctlBackendConfig,
        runner: R,
    ) -> Result<Self, SystemdError>
    where
        R: SystemctlProcessRunner + Send + Sync + 'static,
    {
        validate_systemctl_config(&config)?;

        Ok(Self {
            config,
            runner: Arc::new(runner),
        })
    }

    fn program(&self) -> Result<&str, SystemdError> {
        self.config
            .systemctl_path
            .to_str()
            .ok_or_else(|| SystemdError::Unavailable("systemctl path is not UTF-8".to_owned()))
    }

    fn scope_arg(&self) -> String {
        match self.config.scope {
            SystemdScope::System => "--system".to_owned(),
            SystemdScope::User => "--user".to_owned(),
        }
    }
}

impl SystemdBackend for SystemctlBackend {
    // @behavior selvedge.operations.systemd.backend_query Systemctl status queries invoke show with load and active state properties and parse the captured output.
    async fn query_status(
        &self,
        unit_name: &str,
        operation_timeout: Duration,
    ) -> Result<ServiceStatus, SystemdError> {
        let args = vec![
            self.scope_arg(),
            "show".to_owned(),
            "--property=LoadState".to_owned(),
            "--property=ActiveState".to_owned(),
            unit_name.to_owned(),
        ];
        let output = self
            .runner
            .run_boxed(self.program()?, &args, operation_timeout)
            .await?;

        parse_systemctl_show_output(output)
    }

    // @behavior selvedge.operations.systemd.backend_start Systemctl start requests invoke start and return StartRequested only for an exit code of zero.
    async fn start_unit(
        &self,
        unit_name: &str,
        operation_timeout: Duration,
    ) -> Result<StartServiceOutcome, SystemdError> {
        let args = vec![self.scope_arg(), "start".to_owned(), unit_name.to_owned()];
        let output = self
            .runner
            .run_boxed(self.program()?, &args, operation_timeout)
            .await?;

        if output.exit_code == Some(0) {
            Ok(StartServiceOutcome::StartRequested)
        } else {
            // @behavior selvedge.operations.systemd.backend_start.rejected Failed systemctl start exits return start-rejected errors with stderr text.
            Err(SystemdError::StartRejected(stderr_text(&output)))
        }
    }
}

impl<B: SystemdBackend> SystemdClient<B> {
    // @behavior selvedge.operations.systemd.client.new New systemd clients validate service operation configuration before accepting calls.
    pub fn new(config: SystemdConfig, backend: B) -> Result<Self, SystemdError> {
        validate_config(&config)?;

        Ok(Self { config, backend })
    }

    // @behavior selvedge.operations.systemd.client.query Service status queries validate config and return the backend status for the configured unit.
    pub async fn query_service_status(&self) -> Result<ServiceStatus, SystemdError> {
        validate_config(&self.config)?;
        self.backend
            .query_status(&self.config.unit_name, self.config.operation_timeout)
            .await
    }

    // @behavior selvedge.operations.systemd.client.start Service start checks current status and reports already-running, already-starting, missing-unit, or backend start outcomes.
    pub async fn start_service(&self) -> Result<StartServiceOutcome, SystemdError> {
        validate_config(&self.config)?;
        match self.query_service_status().await? {
            ServiceStatus::Active => Ok(StartServiceOutcome::AlreadyRunning),
            ServiceStatus::Activating => Ok(StartServiceOutcome::AlreadyStarting),
            // @behavior selvedge.operations.systemd.client.start.not_installed Starting a not-installed unit returns UnitNotFound before issuing a start request.
            ServiceStatus::NotInstalled => Err(SystemdError::UnitNotFound),
            ServiceStatus::Inactive
            | ServiceStatus::Failed { .. }
            | ServiceStatus::Unknown { .. } => {
                self.backend
                    .start_unit(&self.config.unit_name, self.config.operation_timeout)
                    .await
            }
        }
    }

    // @behavior selvedge.operations.systemd.client.wait Waiting for activation polls service status until active, failed, missing, or timed out.
    pub async fn wait_service_active(&self) -> Result<ServiceStatus, SystemdError> {
        validate_config(&self.config)?;
        let deadline = Instant::now()
            .checked_add(self.config.operation_timeout)
            .ok_or(SystemdError::Timeout)?;
        loop {
            let now = Instant::now();
            let remaining = deadline.saturating_duration_since(now);
            if remaining.is_zero() {
                // @behavior selvedge.operations.systemd.client.wait.deadline Waiting for activation returns Timeout when no operation time remains before a poll.
                return Err(SystemdError::Timeout);
            }

            // @behavior selvedge.operations.systemd.client.wait.query Each wait poll queries the configured unit only within the remaining operation time.
            let status = tokio::time::timeout(
                remaining,
                self.backend.query_status(&self.config.unit_name, remaining),
            )
            .await
            // @behavior selvedge.operations.systemd.client.wait.query_timeout Query polls that exceed remaining wait time return Timeout.
            .map_err(|_| SystemdError::Timeout)??;

            match status {
                ServiceStatus::Active => return Ok(ServiceStatus::Active),
                status @ ServiceStatus::Failed { .. } => return Ok(status),
                // @behavior selvedge.operations.systemd.client.wait.not_installed Waiting on a not-installed unit returns UnitNotFound.
                ServiceStatus::NotInstalled => return Err(SystemdError::UnitNotFound),
                ServiceStatus::Inactive
                | ServiceStatus::Activating
                | ServiceStatus::Unknown { .. } => {}
            }

            if Instant::now() >= deadline {
                // @behavior selvedge.operations.systemd.client.wait.after_query_timeout Waiting returns Timeout when the deadline passes after a nonterminal status poll.
                return Err(SystemdError::Timeout);
            }

            let now = Instant::now();
            let remaining = deadline.saturating_duration_since(now);
            let sleep_for = remaining.min(self.config.poll_interval);
            if sleep_for.is_zero() {
                // @behavior selvedge.operations.systemd.client.wait.zero_sleep Waiting returns Timeout when the remaining duration cannot cover another poll sleep.
                return Err(SystemdError::Timeout);
            }
            tokio::time::sleep(sleep_for).await;
        }
    }
}

fn validate_config(config: &SystemdConfig) -> Result<(), SystemdError> {
    if config.unit_name.trim().is_empty() {
        // @constraint selvedge.operations.systemd.validate.unit_blank Unit names must be nonblank before service operations run.
        return Err(SystemdError::InvalidUnitName);
    }

    if config.unit_name.chars().any(char::is_whitespace) {
        // @constraint selvedge.operations.systemd.validate.unit_whitespace Unit names must not contain whitespace before service operations run.
        return Err(SystemdError::InvalidUnitName);
    }

    if config.operation_timeout.is_zero() {
        // @constraint selvedge.operations.systemd.validate.operation_timeout Operation timeouts must be positive before service operations run.
        return Err(SystemdError::InvalidOperationTimeout);
    }

    if config.poll_interval.is_zero() {
        // @constraint selvedge.operations.systemd.validate.poll_interval Poll intervals must be positive before service wait operations run.
        return Err(SystemdError::InvalidPollInterval);
    }

    Ok(())
}

fn validate_systemctl_config(config: &SystemctlBackendConfig) -> Result<(), SystemdError> {
    if config.systemctl_path.as_os_str().is_empty() {
        // @constraint selvedge.operations.systemd.systemctl.config.path_empty Systemctl executable paths must be nonempty before backend creation succeeds.
        return Err(SystemdError::Unavailable(
            "systemctl path must be nonempty".to_owned(),
        ));
    }

    Ok(())
}

// @behavior selvedge.operations.systemd.parse_show Systemctl show parsing maps captured LoadState and ActiveState output into typed service status or backend failure.
fn parse_systemctl_show_output(
    output: SystemctlProcessOutput,
) -> Result<ServiceStatus, SystemdError> {
    let exit_code = output.exit_code;
    let stderr = output.stderr.clone();
    let stdout = String::from_utf8(output.stdout)
        // @constraint selvedge.operations.systemd.parse_show.utf8 Systemctl show stdout must be UTF-8 before status parsing can succeed.
        .map_err(|error| SystemdError::BackendFailure(error.to_string()))?;
    let mut load_state = None;
    let mut active_state = None;

    for line in stdout.lines() {
        if let Some(value) = line.strip_prefix("LoadState=") {
            load_state = Some(value.to_owned());
        } else if let Some(value) = line.strip_prefix("ActiveState=") {
            active_state = Some(value.to_owned());
        }
    }

    if load_state.as_deref() == Some("not-found") {
        return Ok(ServiceStatus::NotInstalled);
    }

    if exit_code != Some(0) {
        // @behavior selvedge.operations.systemd.parse_show.exit_status Nonzero systemctl show exits return backend failures with stderr text.
        return Err(SystemdError::BackendFailure(stderr_text_bytes(&stderr)));
    }

    match active_state.as_deref().unwrap_or_default() {
        "active" => Ok(ServiceStatus::Active),
        "inactive" => Ok(ServiceStatus::Inactive),
        "activating" => Ok(ServiceStatus::Activating),
        "failed" => Ok(ServiceStatus::Failed {
            message: "failed".to_owned(),
        }),
        raw_state => Ok(ServiceStatus::Unknown {
            raw_state: raw_state.to_owned(),
        }),
    }
}

fn stderr_text(output: &SystemctlProcessOutput) -> String {
    stderr_text_bytes(&output.stderr)
}

fn stderr_text_bytes(stderr: &[u8]) -> String {
    let text = String::from_utf8_lossy(stderr).trim().to_owned();
    if text.is_empty() {
        "systemctl failed".to_owned()
    } else {
        text
    }
}
