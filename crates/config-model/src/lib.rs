#![doc = include_str!("../README.md")]

use std::{collections::BTreeMap, fmt::Display};

use serde::{Deserialize, Serialize};
use thiserror::Error;
use toml::{Table, Value};

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct AppConfig {
    pub server: ServerConfig,
    pub logging: LoggingConfig,
    pub feature: FeatureConfig,
}

impl AppConfig {
    pub fn validate(&self) -> Result<(), ValidationError> {
        self.server.validate()?;
        self.logging.validate()?;
        self.feature.validate()?;

        Ok(())
    }
}

impl TryFrom<Table> for AppConfig {
    type Error = AppConfigError;

    fn try_from(table: Table) -> Result<Self, Self::Error> {
        let input: AppConfigInput = Value::Table(table).try_into()?;
        let config = input.materialize();

        config.validate()?;

        Ok(config)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
    pub request_timeout_ms: u64,
}

impl ServerConfig {
    const DEFAULT_HOST: &'static str = "127.0.0.1";
    const DEFAULT_PORT: u16 = 8080;
    const DEFAULT_REQUEST_TIMEOUT_MS: u64 = 5_000;

    pub fn validate(&self) -> Result<(), ValidationError> {
        if self.port == 0 {
            return Err(ValidationError::InvalidPort);
        }

        if self.request_timeout_ms == 0 {
            return Err(ValidationError::InvalidRequestTimeout);
        }

        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct LoggingConfig {
    pub level: LogFilter,
    pub module_levels: BTreeMap<String, LogFilter>,
}

impl LoggingConfig {
    const DEFAULT_LEVEL: LogFilter = LogFilter::Info;

    pub fn validate(&self) -> Result<(), ValidationError> {
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LogFilter {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}

impl Display for LogFilter {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let rendered = match self {
            Self::Trace => "trace",
            Self::Debug => "debug",
            Self::Info => "info",
            Self::Warn => "warn",
            Self::Error => "error",
        };

        formatter.write_str(rendered)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct FeatureConfig {
    pub enabled: bool,
    pub rollout_percentage: u8,
}

impl FeatureConfig {
    const DEFAULT_ENABLED: bool = false;
    const DEFAULT_ROLLOUT_PERCENTAGE: u8 = 0;

    pub fn validate(&self) -> Result<(), ValidationError> {
        if self.rollout_percentage > 100 {
            return Err(ValidationError::InvalidRolloutPercentage(
                self.rollout_percentage,
            ));
        }

        if self.enabled && self.rollout_percentage == 0 {
            return Err(ValidationError::EnabledFeatureRequiresRollout);
        }

        Ok(())
    }
}

#[derive(Debug, Error)]
pub enum AppConfigError {
    #[error("failed to deserialize config input: {0}")]
    Deserialize(#[from] toml::de::Error),
    #[error(transparent)]
    Validation(#[from] ValidationError),
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

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct AppConfigInput {
    server: ServerConfigInput,
    logging: LoggingConfigInput,
    feature: FeatureConfigInput,
}

impl AppConfigInput {
    fn materialize(self) -> AppConfig {
        AppConfig {
            server: self.server.materialize(),
            logging: self.logging.materialize(),
            feature: self.feature.materialize(),
        }
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct ServerConfigInput {
    host: Option<String>,
    port: Option<u16>,
    request_timeout_ms: Option<u64>,
}

impl ServerConfigInput {
    fn materialize(self) -> ServerConfig {
        ServerConfig {
            host: self
                .host
                .unwrap_or_else(|| ServerConfig::DEFAULT_HOST.to_owned()),
            port: self.port.unwrap_or(ServerConfig::DEFAULT_PORT),
            request_timeout_ms: self
                .request_timeout_ms
                .unwrap_or(ServerConfig::DEFAULT_REQUEST_TIMEOUT_MS),
        }
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct LoggingConfigInput {
    level: Option<LogFilter>,
    module_levels: BTreeMap<String, LogFilter>,
    format: Option<String>,
}

impl LoggingConfigInput {
    fn materialize(self) -> LoggingConfig {
        let _ = self.format;

        LoggingConfig {
            level: self.level.unwrap_or(LoggingConfig::DEFAULT_LEVEL),
            module_levels: self.module_levels,
        }
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct FeatureConfigInput {
    enabled: Option<bool>,
    rollout_percentage: Option<u8>,
}

impl FeatureConfigInput {
    fn materialize(self) -> FeatureConfig {
        FeatureConfig {
            enabled: self.enabled.unwrap_or(FeatureConfig::DEFAULT_ENABLED),
            rollout_percentage: self
                .rollout_percentage
                .unwrap_or(FeatureConfig::DEFAULT_ROLLOUT_PERCENTAGE),
        }
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::{AppConfig, AppConfigError, LogFilter};

    #[test]
    fn logging_defaults_to_info_without_module_overrides() {
        let config = AppConfig::try_from(toml::Table::new()).expect("default config");

        assert_eq!(config.logging.level, LogFilter::Info);
        assert!(config.logging.module_levels.is_empty());
    }

    #[test]
    fn logging_accepts_strongly_typed_module_level_overrides() {
        let table = toml::toml! {
            [logging]
            level = "warn"

            [logging.module_levels]
            "selvedge::router" = "debug"
            "selvedge::worker" = "error"
        };

        let config = AppConfig::try_from(table).expect("config with module overrides");

        let expected = BTreeMap::from([
            ("selvedge::router".to_owned(), LogFilter::Debug),
            ("selvedge::worker".to_owned(), LogFilter::Error),
        ]);

        assert_eq!(config.logging.level, LogFilter::Warn);
        assert_eq!(config.logging.module_levels, expected);
    }

    #[test]
    fn logging_accepts_legacy_format_field_without_using_it() {
        let table = toml::toml! {
            [logging]
            level = "info"
            format = "text"
        };

        let config = AppConfig::try_from(table).expect("config with legacy format field");

        assert_eq!(config.logging.level, LogFilter::Info);
        assert!(config.logging.module_levels.is_empty());
    }
}
