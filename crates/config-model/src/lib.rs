#![doc = include_str!("../README.md")]

use std::{collections::BTreeMap, fmt::Display};

use http::HeaderValue;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use toml::Table;

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct AppConfig {
    pub server: ServerConfig,
    pub network: NetworkConfig,
    pub logging: LoggingConfig,
    pub llm: LlmConfig,
    pub harness: HarnessConfig,
    pub mcp: McpConfig,
}

impl AppConfig {
    pub fn validate(&self) -> Result<(), ValidationError> {
        self.server.validate()?;
        self.network.validate()?;
        self.logging.validate()?;
        self.llm.validate()?;
        self.harness.validate()?;
        self.mcp.validate()?;

        Ok(())
    }
}

impl TryFrom<Table> for AppConfig {
    type Error = AppConfigError;

    fn try_from(table: Table) -> Result<Self, Self::Error> {
        let mut config = Self::default();
        for (key, value) in table {
            match key.as_str() {
                "server" => config.server = value.try_into()?,
                "network" => config.network = value.try_into()?,
                "logging" => config.logging = value.try_into()?,
                "llm" => config.llm = value.try_into()?,
                "harness" => config.harness = value.try_into()?,
                "mcp" => config.mcp = value.try_into()?,
                _ => {
                    return Err(AppConfigError::Deserialize(serde::de::Error::custom(
                        format!("unknown field `{key}`"),
                    )));
                }
            }
        }
        config.validate()?;

        Ok(config)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct HarnessConfig {
    pub max_children_per_fork: u32,
    pub max_descendants_per_task: u32,
}

impl HarnessConfig {
    const DEFAULT_MAX_CHILDREN_PER_FORK: u32 = 5;
    const DEFAULT_MAX_DESCENDANTS_PER_TASK: u32 = 20;

    pub fn validate(&self) -> Result<(), ValidationError> {
        if self.max_children_per_fork == 0 {
            return Err(ValidationError::InvalidMaxChildrenPerFork);
        }
        if self.max_descendants_per_task == 0 {
            return Err(ValidationError::InvalidMaxDescendantsPerTask);
        }
        if self.max_children_per_fork > self.max_descendants_per_task {
            return Err(ValidationError::ForkLimitExceedsDescendantLimit);
        }
        Ok(())
    }
}

impl Default for HarnessConfig {
    fn default() -> Self {
        Self {
            max_children_per_fork: Self::DEFAULT_MAX_CHILDREN_PER_FORK,
            max_descendants_per_task: Self::DEFAULT_MAX_DESCENDANTS_PER_TASK,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
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

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
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

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
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

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct LlmConfig {
    pub providers: BTreeMap<String, LlmProviderConfig>,
}

impl LlmConfig {
    pub fn validate(&self) -> Result<(), ValidationError> {
        for (provider_id, provider) in &self.providers {
            validate_provider_id(provider_id)?;
            provider.validate_for_provider(provider_id)?;
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct LlmProviderConfig {
    pub base_url: Option<String>,
    pub stream_completion_timeout_ms: Option<u64>,
    pub models: Vec<String>,
    pub settings: BTreeMap<String, toml::Value>,
}

impl LlmProviderConfig {
    pub fn validate(&self) -> Result<(), ValidationError> {
        self.validate_for_provider("<provider>")
    }

    fn validate_for_provider(&self, provider_id: &str) -> Result<(), ValidationError> {
        if let Some(base_url) = &self.base_url {
            validate_provider_base_url(provider_id, base_url)?;
        }

        if self.stream_completion_timeout_ms == Some(0) {
            return Err(ValidationError::InvalidProviderStreamCompletionTimeout {
                provider_id: provider_id.to_owned(),
            });
        }

        let mut seen_models = std::collections::BTreeSet::new();
        for model in &self.models {
            if model.trim().is_empty() {
                return Err(ValidationError::BlankProviderModel {
                    provider_id: provider_id.to_owned(),
                });
            }
            if !seen_models.insert(model) {
                return Err(ValidationError::DuplicateProviderModel {
                    provider_id: provider_id.to_owned(),
                    model: model.clone(),
                });
            }
        }

        validate_settings_table(provider_id, &self.settings)
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct McpConfig {
    pub servers: BTreeMap<String, McpServerConfig>,
}

impl McpConfig {
    pub fn validate(&self) -> Result<(), ValidationError> {
        for (server_id, server) in &self.servers {
            validate_mcp_server_id(server_id)?;
            server.validate_for_server(server_id)?;
        }

        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct McpServerConfig {
    pub command: String,
    pub args: Vec<String>,
    pub env: BTreeMap<String, String>,
    pub timeout_ms: u64,
}

impl McpServerConfig {
    const DEFAULT_TIMEOUT_MS: u64 = 60_000;

    pub fn validate(&self) -> Result<(), ValidationError> {
        self.validate_for_server("<server>")
    }

    fn validate_for_server(&self, server_id: &str) -> Result<(), ValidationError> {
        if self.command.trim().is_empty() {
            return Err(ValidationError::BlankMcpServerCommand {
                server_id: server_id.to_owned(),
            });
        }

        if self.timeout_ms == 0 {
            return Err(ValidationError::InvalidMcpServerTimeout {
                server_id: server_id.to_owned(),
            });
        }

        for (index, argument) in self.args.iter().enumerate() {
            if argument.contains('\0') {
                return Err(ValidationError::InvalidMcpServerArgument {
                    server_id: server_id.to_owned(),
                    index,
                });
            }
        }

        for (key, value) in &self.env {
            if key.is_empty() || key.contains(['\0', '=']) {
                return Err(ValidationError::InvalidMcpServerEnvKey {
                    server_id: server_id.to_owned(),
                    key: key.clone(),
                });
            }
            if value.contains('\0') {
                return Err(ValidationError::InvalidMcpServerEnvValue {
                    server_id: server_id.to_owned(),
                    key: key.clone(),
                });
            }
        }

        Ok(())
    }
}

/// Whether a provider identifier is a nonempty ASCII name accepted by configuration and credentials.
pub fn is_valid_provider_id(provider_id: &str) -> bool {
    !provider_id.is_empty()
        && provider_id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_'))
}

fn validate_provider_id(provider_id: &str) -> Result<(), ValidationError> {
    if is_valid_provider_id(provider_id) {
        Ok(())
    } else {
        Err(ValidationError::InvalidProviderId {
            provider_id: provider_id.to_owned(),
        })
    }
}

fn validate_provider_base_url(provider_id: &str, raw_url: &str) -> Result<(), ValidationError> {
    let base_url =
        url::Url::parse(raw_url).map_err(|_| ValidationError::InvalidProviderBaseUrl {
            provider_id: provider_id.to_owned(),
        })?;
    ensure_explicit_authority(
        raw_url,
        &base_url,
        ValidationError::InvalidProviderBaseUrl {
            provider_id: provider_id.to_owned(),
        },
    )?;

    validate_base_url_scheme_and_authority(
        &base_url,
        ValidationError::InvalidProviderBaseUrl {
            provider_id: provider_id.to_owned(),
        },
        ValidationError::ProviderBaseUrlMustNotContainUserinfo {
            provider_id: provider_id.to_owned(),
        },
        ValidationError::ProviderBaseUrlMustUseHttps {
            provider_id: provider_id.to_owned(),
        },
    )?;

    if base_url.query().is_some() || base_url.fragment().is_some() {
        return Err(ValidationError::ProviderBaseUrlMustBeBaseUrl {
            provider_id: provider_id.to_owned(),
        });
    }

    Ok(())
}

fn validate_settings_table(
    provider_id: &str,
    settings: &BTreeMap<String, toml::Value>,
) -> Result<(), ValidationError> {
    for (key, value) in settings {
        validate_setting_key(provider_id, key)?;
        validate_setting_value(provider_id, value)?;
    }
    Ok(())
}

fn validate_setting_key(provider_id: &str, key: &str) -> Result<(), ValidationError> {
    if key.trim().is_empty() {
        return Err(ValidationError::InvalidProviderSetting {
            provider_id: provider_id.to_owned(),
            setting: key.to_owned(),
        });
    }
    Ok(())
}

fn validate_setting_value(provider_id: &str, value: &toml::Value) -> Result<(), ValidationError> {
    match value {
        toml::Value::Table(table) => {
            for (key, value) in table {
                validate_setting_key(provider_id, key)?;
                validate_setting_value(provider_id, value)?;
            }
        }
        toml::Value::Array(values) => {
            for value in values {
                validate_setting_value(provider_id, value)?;
            }
        }
        toml::Value::String(_)
        | toml::Value::Integer(_)
        | toml::Value::Float(_)
        | toml::Value::Boolean(_)
        | toml::Value::Datetime(_) => {}
    }
    Ok(())
}

fn validate_mcp_server_id(server_id: &str) -> Result<(), ValidationError> {
    if server_id.is_empty()
        || !server_id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_'))
    {
        return Err(ValidationError::InvalidMcpServerId {
            server_id: server_id.to_owned(),
        });
    }

    Ok(())
}

fn validate_base_url_scheme_and_authority(
    url: &url::Url,
    invalid_url_error: ValidationError,
    userinfo_error: ValidationError,
    https_required_error: ValidationError,
) -> Result<(), ValidationError> {
    if !matches!(url.scheme(), "http" | "https") {
        return Err(invalid_url_error);
    }

    if !url.username().is_empty() || url.password().is_some() {
        return Err(userinfo_error);
    }

    if url.scheme() == "http" && !issuer_host_is_loopback(url) {
        return Err(https_required_error);
    }

    Ok(())
}

fn ensure_explicit_authority(
    raw: &str,
    url: &url::Url,
    invalid_url_error: ValidationError,
) -> Result<(), ValidationError> {
    let Some((scheme, remainder)) = raw.split_once("://") else {
        return Err(invalid_url_error);
    };

    if !matches!(scheme.to_ascii_lowercase().as_str(), "http" | "https") {
        return Err(invalid_url_error);
    }

    let authority = remainder.split(['/', '?', '#']).next().unwrap_or_default();

    if authority.is_empty() || authority.starts_with('/') || url.host().is_none() {
        return Err(invalid_url_error);
    }

    Ok(())
}

fn issuer_host_is_loopback(issuer: &url::Url) -> bool {
    match issuer.host() {
        Some(url::Host::Domain(host)) => host.eq_ignore_ascii_case("localhost"),
        Some(url::Host::Ipv4(address)) => address.is_loopback(),
        Some(url::Host::Ipv6(address)) => address.is_loopback(),
        None => false,
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
    #[error("llm.providers contains invalid provider id {provider_id:?}")]
    InvalidProviderId { provider_id: String },
    #[error("llm.providers.{provider_id}.base_url must be an absolute http or https URL")]
    InvalidProviderBaseUrl { provider_id: String },
    #[error(
        "llm.providers.{provider_id}.base_url must use https unless it targets a loopback host"
    )]
    ProviderBaseUrlMustUseHttps { provider_id: String },
    #[error("llm.providers.{provider_id}.base_url must not contain userinfo")]
    ProviderBaseUrlMustNotContainUserinfo { provider_id: String },
    #[error("llm.providers.{provider_id}.base_url must be a clean base URL")]
    ProviderBaseUrlMustBeBaseUrl { provider_id: String },
    #[error("llm.providers.{provider_id}.stream_completion_timeout_ms must be greater than zero")]
    InvalidProviderStreamCompletionTimeout { provider_id: String },
    #[error("llm.providers.{provider_id}.models must not contain blank model names")]
    BlankProviderModel { provider_id: String },
    #[error("llm.providers.{provider_id}.models contains duplicate model {model:?}")]
    DuplicateProviderModel { provider_id: String, model: String },
    #[error("llm.providers.{provider_id}.settings contains invalid setting key {setting:?}")]
    InvalidProviderSetting {
        provider_id: String,
        setting: String,
    },
    #[error("harness.max_children_per_fork must be greater than zero")]
    InvalidMaxChildrenPerFork,
    #[error("harness.max_descendants_per_task must be greater than zero")]
    InvalidMaxDescendantsPerTask,
    #[error("harness.max_children_per_fork must not exceed harness.max_descendants_per_task")]
    ForkLimitExceedsDescendantLimit,
    #[error("mcp.servers contains invalid server id {server_id:?}")]
    InvalidMcpServerId { server_id: String },
    #[error("mcp.servers.{server_id}.command must not be blank")]
    BlankMcpServerCommand { server_id: String },
    #[error("mcp.servers.{server_id}.timeout_ms must be greater than zero")]
    InvalidMcpServerTimeout { server_id: String },
    #[error("mcp.servers.{server_id}.args[{index}] must not contain NUL")]
    InvalidMcpServerArgument { server_id: String, index: usize },
    #[error("mcp.servers.{server_id}.env contains invalid key {key:?}")]
    InvalidMcpServerEnvKey { server_id: String, key: String },
    #[error("mcp.servers.{server_id}.env.{key} must not contain NUL")]
    InvalidMcpServerEnvValue { server_id: String, key: String },
}

impl<'de> Deserialize<'de> for AppConfig {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        Self::try_from(Table::deserialize(deserializer)?).map_err(serde::de::Error::custom)
    }
}
impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            host: Self::DEFAULT_HOST.to_owned(),
            port: Self::DEFAULT_PORT,
            request_timeout_ms: Self::DEFAULT_REQUEST_TIMEOUT_MS,
        }
    }
}
impl Default for LoggingConfig {
    fn default() -> Self {
        Self {
            level: Self::DEFAULT_LEVEL,
            module_levels: BTreeMap::new(),
        }
    }
}
impl Default for McpServerConfig {
    fn default() -> Self {
        Self {
            command: String::new(),
            args: Vec::new(),
            env: BTreeMap::new(),
            timeout_ms: Self::DEFAULT_TIMEOUT_MS,
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
    fn logging_rejects_legacy_format_field() {
        let table = toml::toml! {
            [logging]
            level = "info"
            format = "text"
        };

        assert!(AppConfig::try_from(table).is_err());
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
