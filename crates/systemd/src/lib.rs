#![doc = include_str!("../README.md")]

use std::future::Future;
use std::path::PathBuf;
use std::pin::Pin;
use std::sync::Arc;
use std::time::{Duration, Instant};

use tokio::io::AsyncReadExt;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SystemdConfig {
    pub unit_name: String,
    pub operation_timeout: Duration,
    pub poll_interval: Duration,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ServiceStatus {
    NotInstalled,
    Inactive,
    Activating,
    Active,
    Failed { message: String },
    Unknown { raw_state: String },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum StartServiceOutcome {
    StartRequested,
    AlreadyRunning,
    AlreadyStarting,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SystemdError {
    InvalidUnitName,
    InvalidOperationTimeout,
    InvalidPollInterval,
    Unavailable(String),
    UnitNotFound,
    StartRejected(String),
    Timeout,
    BackendFailure(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SystemdScope {
    System,
    User,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SystemctlBackendConfig {
    pub systemctl_path: PathBuf,
    pub scope: SystemdScope,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SystemctlProcessOutput {
    pub exit_code: Option<i32>,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

pub trait SystemctlProcessRunner {
    fn run(
        &self,
        program: &str,
        args: &[String],
        timeout: Duration,
    ) -> impl Future<Output = Result<SystemctlProcessOutput, SystemdError>> + Send;
}

pub trait SystemdBackend: Send + Sync + 'static {
    fn query_status(
        &self,
        unit_name: &str,
        operation_timeout: Duration,
    ) -> impl Future<Output = Result<ServiceStatus, SystemdError>> + Send;

    fn start_unit(
        &self,
        unit_name: &str,
        operation_timeout: Duration,
    ) -> impl Future<Output = Result<StartServiceOutcome, SystemdError>> + Send;
}

pub struct SystemctlBackend {
    config: SystemctlBackendConfig,
    runner: Arc<dyn ErasedSystemctlProcessRunner>,
}

pub struct SystemdClient<B: SystemdBackend> {
    pub config: SystemdConfig,
    pub backend: B,
}

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
        .map_err(|error| SystemdError::BackendFailure(error.to_string()))?;
    Ok(output)
}

impl SystemctlProcessRunner for StdSystemctlProcessRunner {
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
            .map_err(|error| SystemdError::Unavailable(error.to_string()))?;

        let stdout = child.stdout.take().ok_or_else(|| {
            SystemdError::BackendFailure("failed to capture systemctl stdout".to_owned())
        })?;
        let stderr = child.stderr.take().ok_or_else(|| {
            SystemdError::BackendFailure("failed to capture systemctl stderr".to_owned())
        })?;
        let stdout_reader = tokio::spawn(read_child_pipe(stdout));
        let stderr_reader = tokio::spawn(read_child_pipe(stderr));

        let status = match tokio::time::timeout(timeout, child.wait()).await {
            Ok(Ok(status)) => status,
            Ok(Err(error)) => return Err(SystemdError::BackendFailure(error.to_string())),
            Err(_) => {
                let _ = child.start_kill();
                let _ = child.wait().await;
                return Err(SystemdError::Timeout);
            }
        };

        let stdout = stdout_reader
            .await
            .map_err(|error| SystemdError::BackendFailure(error.to_string()))??;
        let stderr = stderr_reader
            .await
            .map_err(|error| SystemdError::BackendFailure(error.to_string()))??;

        Ok(SystemctlProcessOutput {
            exit_code: status.code(),
            stdout,
            stderr,
        })
    }
}

impl SystemctlBackend {
    pub fn new(config: SystemctlBackendConfig) -> Result<Self, SystemdError> {
        Self::new_with_runner(config, StdSystemctlProcessRunner)
    }

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
            Err(SystemdError::StartRejected(stderr_text(&output)))
        }
    }
}

impl<B: SystemdBackend> SystemdClient<B> {
    pub fn new(config: SystemdConfig, backend: B) -> Result<Self, SystemdError> {
        validate_config(&config)?;

        Ok(Self { config, backend })
    }

    pub async fn query_service_status(&self) -> Result<ServiceStatus, SystemdError> {
        validate_config(&self.config)?;
        self.backend
            .query_status(&self.config.unit_name, self.config.operation_timeout)
            .await
    }

    pub async fn start_service(&self) -> Result<StartServiceOutcome, SystemdError> {
        validate_config(&self.config)?;
        match self.query_service_status().await? {
            ServiceStatus::Active => Ok(StartServiceOutcome::AlreadyRunning),
            ServiceStatus::Activating => Ok(StartServiceOutcome::AlreadyStarting),
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

    pub async fn wait_service_active(&self) -> Result<ServiceStatus, SystemdError> {
        validate_config(&self.config)?;
        let deadline = Instant::now()
            .checked_add(self.config.operation_timeout)
            .ok_or(SystemdError::Timeout)?;
        loop {
            let now = Instant::now();
            let remaining = deadline.saturating_duration_since(now);
            if remaining.is_zero() {
                return Err(SystemdError::Timeout);
            }

            let status = tokio::time::timeout(
                remaining,
                self.backend.query_status(&self.config.unit_name, remaining),
            )
            .await
            .map_err(|_| SystemdError::Timeout)??;

            match status {
                ServiceStatus::Active => return Ok(ServiceStatus::Active),
                status @ ServiceStatus::Failed { .. } => return Ok(status),
                ServiceStatus::NotInstalled => return Err(SystemdError::UnitNotFound),
                ServiceStatus::Inactive
                | ServiceStatus::Activating
                | ServiceStatus::Unknown { .. } => {}
            }

            if Instant::now() >= deadline {
                return Err(SystemdError::Timeout);
            }

            let now = Instant::now();
            let remaining = deadline.saturating_duration_since(now);
            let sleep_for = remaining.min(self.config.poll_interval);
            if sleep_for.is_zero() {
                return Err(SystemdError::Timeout);
            }
            tokio::time::sleep(sleep_for).await;
        }
    }
}

fn validate_config(config: &SystemdConfig) -> Result<(), SystemdError> {
    if config.unit_name.trim().is_empty() {
        return Err(SystemdError::InvalidUnitName);
    }

    if config.unit_name.chars().any(char::is_whitespace) {
        return Err(SystemdError::InvalidUnitName);
    }

    if config.operation_timeout.is_zero() {
        return Err(SystemdError::InvalidOperationTimeout);
    }

    if config.poll_interval.is_zero() {
        return Err(SystemdError::InvalidPollInterval);
    }

    Ok(())
}

fn validate_systemctl_config(config: &SystemctlBackendConfig) -> Result<(), SystemdError> {
    if config.systemctl_path.as_os_str().is_empty() {
        return Err(SystemdError::Unavailable(
            "systemctl path must be nonempty".to_owned(),
        ));
    }

    Ok(())
}

fn parse_systemctl_show_output(
    output: SystemctlProcessOutput,
) -> Result<ServiceStatus, SystemdError> {
    let exit_code = output.exit_code;
    let stderr = output.stderr.clone();
    let stdout = String::from_utf8(output.stdout)
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
