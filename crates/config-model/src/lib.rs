#![doc = include_str!("../README.md")]

use std::{collections::BTreeMap, fmt::Display};

use http::HeaderValue;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use toml::{Table, Value};

#[derive(Debug, Clone, PartialEq, Serialize)]
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

#[derive(Debug, Clone, PartialEq, Serialize)]
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

#[derive(Debug, Clone, PartialEq, Serialize)]
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

#[derive(Debug, Clone, PartialEq, Serialize)]
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

#[derive(Debug, Clone, PartialEq, Serialize)]
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

fn validate_provider_id(provider_id: &str) -> Result<(), ValidationError> {
    if provider_id.trim().is_empty() {
        return Err(ValidationError::InvalidProviderId {
            provider_id: provider_id.to_owned(),
        });
    }

    for byte in provider_id.bytes() {
        let allowed = byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_');
        if !allowed {
            return Err(ValidationError::InvalidProviderId {
                provider_id: provider_id.to_owned(),
            });
        }
    }

    Ok(())
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
    #[error("feature.rollout_percentage must be between 0 and 100, got {0}")]
    InvalidRolloutPercentage(u8),
    #[error("feature.rollout_percentage must be greater than zero when feature.enabled is true")]
    EnabledFeatureRequiresRollout,
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
    providers: BTreeMap<String, LlmProviderConfigInput>,
}

impl LlmConfigInput {
    fn materialize(self) -> LlmConfig {
        LlmConfig {
            providers: self
                .providers
                .into_iter()
                .map(|(provider_id, provider)| (provider_id, provider.materialize()))
                .collect(),
        }
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct LlmProviderConfigInput {
    base_url: Option<String>,
    stream_completion_timeout_ms: Option<u64>,
    models: Vec<String>,
    settings: BTreeMap<String, toml::Value>,
}

impl LlmProviderConfigInput {
    fn materialize(self) -> LlmProviderConfig {
        LlmProviderConfig {
            base_url: self.base_url,
            stream_completion_timeout_ms: self.stream_completion_timeout_ms,
            models: self.models,
            settings: self.settings,
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
