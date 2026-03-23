use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(default, deny_unknown_fields)]
pub struct AppConfig {
    pub server: ServerConfig,
    pub logging: LoggingConfig,
    pub feature: FeatureConfig,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
#[serde(default, deny_unknown_fields)]
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
    pub request_timeout_ms: u64,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            host: "127.0.0.1".to_owned(),
            port: 8080,
            request_timeout_ms: 5_000,
        }
    }
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
#[serde(default, deny_unknown_fields)]
pub struct LoggingConfig {
    pub level: String,
    pub format: String,
}

impl Default for LoggingConfig {
    fn default() -> Self {
        Self {
            level: "info".to_owned(),
            format: "text".to_owned(),
        }
    }
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq, Default)]
#[serde(default, deny_unknown_fields)]
pub struct FeatureConfig {
    pub enabled: bool,
    pub rollout_percentage: u8,
}

pub fn default_app_config() -> AppConfig {
    AppConfig::default()
}

pub fn validate_app_config(config: &AppConfig) -> Result<(), ValidationError> {
    if config.server.port == 0 {
        return Err(ValidationError::InvalidPort);
    }

    if config.server.request_timeout_ms == 0 {
        return Err(ValidationError::InvalidRequestTimeout);
    }

    if config.feature.rollout_percentage > 100 {
        return Err(ValidationError::InvalidRolloutPercentage(
            config.feature.rollout_percentage,
        ));
    }

    if config.feature.enabled && config.feature.rollout_percentage == 0 {
        return Err(ValidationError::EnabledFeatureRequiresRollout);
    }

    Ok(())
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ValidationError {
    #[error("server.port must be greater than zero")]
    InvalidPort,
    #[error("server.request_timeout_ms must be greater than zero")]
    InvalidRequestTimeout,
    #[error("feature.rollout_percentage must be between 0 and 100, got {0}")]
    InvalidRolloutPercentage(u8),
    #[error("feature.rollout_percentage must be greater than zero when feature.enabled is true")]
    EnabledFeatureRequiresRollout,
}
