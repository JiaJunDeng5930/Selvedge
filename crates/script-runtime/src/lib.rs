//! Owned JavaScript heap checkpoints and invocation-scoped host operations.

mod checkpoint;
mod engine;
mod worker;

use std::{future::Future, pin::Pin, sync::Arc, time::Duration};

use serde_json::Value;

/// Current-format, engine-specific checkpoint bytes; cloning copies heap state.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ScriptCheckpoint(pub Vec<u8>);

#[derive(Clone, Debug)]
pub struct ScriptExecutionRequest {
    pub checkpoint: ScriptCheckpoint,
    pub source: String,
    pub source_name: String,
}

#[derive(Clone, Debug)]
pub struct ScriptExecutionResult {
    pub checkpoint: ScriptCheckpoint,
    pub output: Value,
    pub is_error: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub enum HostRequest {
    Command {
        ordinal: u64,
        name: String,
        arguments: Value,
    },
    LoadModule {
        ordinal: u64,
        specifier: String,
        referrer: String,
    },
}

#[derive(Clone, Debug, PartialEq)]
pub enum HostResponse {
    Command(Value),
    Module {
        source: String,
        resolved_specifier: String,
    },
    ModuleError {
        message: String,
    },
}

#[derive(Clone, Debug, thiserror::Error)]
#[error("{message}")]
pub struct ScriptHostError {
    pub message: String,
}

/// Futures must be cancellation-safe: dropping one ends its unfinished work.
/// Durable effects and replay validation remain the host's responsibility.
pub trait ScriptHost: Send + Sync + 'static {
    fn call(
        &self,
        request: HostRequest,
    ) -> Pin<Box<dyn Future<Output = Result<HostResponse, ScriptHostError>> + Send>>;
}

#[derive(Debug, thiserror::Error)]
pub enum ScriptRuntimeError {
    #[error("script checkpoint is invalid: {0}")]
    InvalidCheckpoint(String),
    #[error("script engine failed: {0}")]
    Engine(String),
    #[error("script host failed: {0}")]
    Host(#[from] ScriptHostError),
    #[error("script execution timed out")]
    Timeout,
    #[error("script execution was cancelled")]
    Cancelled,
    #[error("script execution left {0} unsettled promises")]
    UnsettledPromises(usize),
}

#[derive(Clone)]
pub struct ScriptRuntime {
    base: Arc<ScriptCheckpoint>,
    timeout: Duration,
}

impl ScriptRuntime {
    pub fn new(bootstrap: String) -> Result<Self, ScriptRuntimeError> {
        let timeout = Duration::from_secs(30);
        Ok(Self {
            base: Arc::new(engine::bootstrap(bootstrap, timeout)?),
            timeout,
        })
    }

    /// Sets the wall-time limit for future executions, including host waits.
    pub fn with_execution_timeout(mut self, timeout: Duration) -> Self {
        self.timeout = timeout;
        self
    }

    pub fn base_checkpoint(&self) -> Result<ScriptCheckpoint, ScriptRuntimeError> {
        Ok((*self.base).clone())
    }

    pub async fn execute(
        &self,
        request: ScriptExecutionRequest,
        host: Arc<dyn ScriptHost>,
    ) -> Result<ScriptExecutionResult, ScriptRuntimeError> {
        engine::execute(request, host, self.timeout).await
    }
}
