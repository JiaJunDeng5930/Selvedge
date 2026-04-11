#![doc = include_str!("../README.md")]

use std::{collections::BTreeMap, fmt::Display};

use http::HeaderValue;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use toml::{Table, Value};

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct AppConfig {
    pub server: ServerConfig,
    pub network: NetworkConfig,
    pub logging: LoggingConfig,
    pub feature: FeatureConfig,
    pub llm: LlmConfig,
}

impl AppConfig {
    pub fn validate(&self) -> Result<(), ValidationError> {
        self.server.validate()?;
        self.network.validate()?;
        self.logging.validate()?;
        self.feature.validate()?;
        self.llm.validate()?;

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
pub struct NetworkConfig {
    pub connect_timeout_ms: Option<u64>,
    pub request_timeout_ms: Option<u64>,
    pub stream_idle_timeout_ms: Option<u64>,
    pub ca_bundle_path: Option<std::path::PathBuf>,
    pub user_agent: Option<String>,
}

impl NetworkConfig {
    pub fn validate(&self) -> Result<(), ValidationError> {
        if self.connect_timeout_ms == Some(0) {
            return Err(ValidationError::InvalidConnectTimeout);
        }

        if self.request_timeout_ms == Some(0) {
            return Err(ValidationError::InvalidNetworkRequestTimeout);
        }

        if self.stream_idle_timeout_ms == Some(0) {
            return Err(ValidationError::InvalidStreamIdleTimeout);
        }

        if let Some(user_agent) = &self.user_agent {
            HeaderValue::from_str(user_agent)
                .map_err(|_| ValidationError::InvalidUserAgent(user_agent.clone()))?;
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

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct LlmConfig {
    pub providers: LlmProvidersConfig,
}

impl LlmConfig {
    pub fn validate(&self) -> Result<(), ValidationError> {
        self.providers.validate()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct LlmProvidersConfig {
    pub chatgpt: ChatgptConfig,
}

impl LlmProvidersConfig {
    pub fn validate(&self) -> Result<(), ValidationError> {
        self.chatgpt.validate()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ChatgptConfig {
    pub auth: ChatgptAuthConfig,
}

impl ChatgptConfig {
    pub fn validate(&self) -> Result<(), ValidationError> {
        self.auth.validate()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ChatgptAuthConfig {
    pub issuer: String,
    pub client_id: String,
    pub expected_workspace_id: Option<String>,
}

impl ChatgptAuthConfig {
    const DEFAULT_ISSUER: &'static str = "https://auth.openai.com";
    const DEFAULT_CLIENT_ID: &'static str = "app_EMoamEEZ73f0CkXaXp7hrann";

    pub fn validate(&self) -> Result<(), ValidationError> {
        let issuer =
            url::Url::parse(&self.issuer).map_err(|_| ValidationError::InvalidChatgptIssuer)?;

        if !matches!(issuer.scheme(), "http" | "https") {
            return Err(ValidationError::InvalidChatgptIssuer);
        }

        if self
            .expected_workspace_id
            .as_deref()
            .is_some_and(|value| value.trim().is_empty())
        {
            return Err(ValidationError::BlankExpectedWorkspaceId);
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
    #[error("network.connect_timeout_ms must be greater than zero")]
    InvalidConnectTimeout,
    #[error("network.request_timeout_ms must be greater than zero")]
    InvalidNetworkRequestTimeout,
    #[error("network.stream_idle_timeout_ms must be greater than zero")]
    InvalidStreamIdleTimeout,
    #[error("network.user_agent must be a valid HTTP header value, got {0}")]
    InvalidUserAgent(String),
    #[error("feature.rollout_percentage must be between 0 and 100, got {0}")]
    InvalidRolloutPercentage(u8),
    #[error("feature.rollout_percentage must be greater than zero when feature.enabled is true")]
    EnabledFeatureRequiresRollout,
    #[error("llm.providers.chatgpt.auth.issuer must be an absolute http or https URL")]
    InvalidChatgptIssuer,
    #[error("llm.providers.chatgpt.auth.expected_workspace_id must not be blank")]
    BlankExpectedWorkspaceId,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct AppConfigInput {
    server: ServerConfigInput,
    network: NetworkConfigInput,
    logging: LoggingConfigInput,
    feature: FeatureConfigInput,
    llm: LlmConfigInput,
}

impl AppConfigInput {
    fn materialize(self) -> AppConfig {
        AppConfig {
            server: self.server.materialize(),
            network: self.network.materialize(),
            logging: self.logging.materialize(),
            feature: self.feature.materialize(),
            llm: self.llm.materialize(),
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
struct NetworkConfigInput {
    connect_timeout_ms: Option<u64>,
    request_timeout_ms: Option<u64>,
    stream_idle_timeout_ms: Option<u64>,
    ca_bundle_path: Option<std::path::PathBuf>,
    user_agent: Option<String>,
}

impl NetworkConfigInput {
    fn materialize(self) -> NetworkConfig {
        NetworkConfig {
            connect_timeout_ms: self.connect_timeout_ms,
            request_timeout_ms: self.request_timeout_ms,
            stream_idle_timeout_ms: self.stream_idle_timeout_ms,
            ca_bundle_path: self.ca_bundle_path,
            user_agent: self.user_agent,
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

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct LlmConfigInput {
    providers: LlmProvidersConfigInput,
}

impl LlmConfigInput {
    fn materialize(self) -> LlmConfig {
        LlmConfig {
            providers: self.providers.materialize(),
        }
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct LlmProvidersConfigInput {
    chatgpt: ChatgptConfigInput,
}

impl LlmProvidersConfigInput {
    fn materialize(self) -> LlmProvidersConfig {
        LlmProvidersConfig {
            chatgpt: self.chatgpt.materialize(),
        }
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct ChatgptConfigInput {
    auth: ChatgptAuthConfigInput,
}

impl ChatgptConfigInput {
    fn materialize(self) -> ChatgptConfig {
        ChatgptConfig {
            auth: self.auth.materialize(),
        }
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct ChatgptAuthConfigInput {
    issuer: Option<String>,
    client_id: Option<String>,
    expected_workspace_id: Option<String>,
}

impl ChatgptAuthConfigInput {
    fn materialize(self) -> ChatgptAuthConfig {
        ChatgptAuthConfig {
            issuer: self
                .issuer
                .unwrap_or_else(|| ChatgptAuthConfig::DEFAULT_ISSUER.to_owned()),
            client_id: self
                .client_id
                .unwrap_or_else(|| ChatgptAuthConfig::DEFAULT_CLIENT_ID.to_owned()),
            expected_workspace_id: self.expected_workspace_id,
        }
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::{AppConfig, LogFilter};

    #[test]
    fn logging_defaults_to_info_without_module_overrides() {
        let config = AppConfig::try_from(toml::Table::new()).expect("default config");

        assert_eq!(config.network.connect_timeout_ms, None);
        assert_eq!(config.network.request_timeout_ms, None);
        assert_eq!(config.network.stream_idle_timeout_ms, None);
        assert_eq!(config.network.ca_bundle_path, None);
        assert_eq!(config.network.user_agent, None);
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

    #[test]
    fn network_accepts_optional_transport_settings() {
        let table = toml::toml! {
            [network]
            connect_timeout_ms = 1_000
            request_timeout_ms = 30_000
            stream_idle_timeout_ms = 300_000
            ca_bundle_path = "/tmp/ca.pem"
            user_agent = "selvedge-client/test"
        };

        let config = AppConfig::try_from(table).expect("network config");

        assert_eq!(config.network.connect_timeout_ms, Some(1_000));
        assert_eq!(config.network.request_timeout_ms, Some(30_000));
        assert_eq!(config.network.stream_idle_timeout_ms, Some(300_000));
        assert_eq!(
            config.network.ca_bundle_path.as_deref(),
            Some(std::path::Path::new("/tmp/ca.pem"))
        );
        assert_eq!(
            config.network.user_agent.as_deref(),
            Some("selvedge-client/test")
        );
    }
}
