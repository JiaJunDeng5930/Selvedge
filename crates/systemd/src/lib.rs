#![doc = include_str!("../README.md")]

use std::future::Future;
use std::time::{Duration, Instant};

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
    Unavailable(String),
    UnitNotFound,
    StartRejected(String),
    Timeout,
    BackendFailure(String),
}

pub trait SystemdBackend: Send + Sync + 'static {
    fn query_status(
        &self,
        unit_name: &str,
    ) -> impl Future<Output = Result<ServiceStatus, SystemdError>> + Send;

    fn start_unit(
        &self,
        unit_name: &str,
    ) -> impl Future<Output = Result<StartServiceOutcome, SystemdError>> + Send;
}

pub struct SystemdClient<B: SystemdBackend> {
    pub config: SystemdConfig,
    pub backend: B,
}

impl<B: SystemdBackend> SystemdClient<B> {
    pub fn new(config: SystemdConfig, backend: B) -> Result<Self, SystemdError> {
        validate_config(&config)?;

        Ok(Self { config, backend })
    }

    pub async fn query_service_status(&self) -> Result<ServiceStatus, SystemdError> {
        self.backend.query_status(&self.config.unit_name).await
    }

    pub async fn start_service(&self) -> Result<StartServiceOutcome, SystemdError> {
        match self.query_service_status().await? {
            ServiceStatus::Active => Ok(StartServiceOutcome::AlreadyRunning),
            ServiceStatus::Activating => Ok(StartServiceOutcome::AlreadyStarting),
            ServiceStatus::NotInstalled => Err(SystemdError::UnitNotFound),
            ServiceStatus::Inactive
            | ServiceStatus::Failed { .. }
            | ServiceStatus::Unknown { .. } => {
                self.backend.start_unit(&self.config.unit_name).await
            }
        }
    }

    pub async fn wait_service_active(&self) -> Result<ServiceStatus, SystemdError> {
        let deadline = Instant::now() + self.config.operation_timeout;
        loop {
            match self.query_service_status().await? {
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

    if config.operation_timeout.is_zero() || config.poll_interval.is_zero() {
        return Err(SystemdError::InvalidUnitName);
    }

    Ok(())
}
