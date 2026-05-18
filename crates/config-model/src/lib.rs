#![doc = include_str!("../README.md")]
//! @behavior selvedge.config.model Callers materialize typed application configuration from TOML tables with defaults and validation errors exposed as typed results.

use std::{collections::BTreeMap, fmt::Display};

use http::HeaderValue;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use toml::{Table, Value};

#[derive(Debug, Clone, PartialEq, Serialize)]
// @behavior selvedge.config.model.app The materialized application config exposes server, network, logging, feature, and LLM provider settings as typed fields.
pub struct AppConfig {
    // @behavior selvedge.config.model.app.server AppConfig exposes materialized server settings to callers.
    pub server: ServerConfig,
    // @behavior selvedge.config.model.app.network AppConfig exposes materialized network settings to callers.
    pub network: NetworkConfig,
    // @behavior selvedge.config.model.app.logging AppConfig exposes materialized logging settings to callers.
    pub logging: LoggingConfig,
    // @behavior selvedge.config.model.app.feature AppConfig exposes materialized feature settings to callers.
    pub feature: FeatureConfig,
    // @behavior selvedge.config.model.app.llm AppConfig exposes materialized LLM provider settings to callers.
    pub llm: LlmConfig,
}

impl AppConfig {
    // @behavior selvedge.config.model.validate Validating an application config returns the first typed validation error from any config section.
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

    // @behavior selvedge.config.model.materialize TOML table conversion applies config defaults and rejects deserialization or validation failures through AppConfigError.
    fn try_from(table: Table) -> Result<Self, Self::Error> {
        let input: AppConfigInput = Value::Table(table).try_into()?;
        let config = input.materialize();

        config.validate()?;

        Ok(config)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize)]
// @behavior selvedge.config.model.server The server config exposes the host, port, and request timeout used by callers.
pub struct ServerConfig {
    // @behavior selvedge.config.model.server.host Server config exposes the configured bind host string.
    pub host: String,
    // @behavior selvedge.config.model.server.port Server config exposes the configured nonzero bind port.
    pub port: u16,
    // @behavior selvedge.config.model.server.timeout Server config exposes the configured nonzero request timeout in milliseconds.
    pub request_timeout_ms: u64,
}

impl ServerConfig {
    const DEFAULT_HOST: &'static str = "127.0.0.1";
    const DEFAULT_PORT: u16 = 8080;
    const DEFAULT_REQUEST_TIMEOUT_MS: u64 = 5_000;

    // @constraint selvedge.config.model.server.valid Server config validation rejects port zero and request timeout zero.
    pub fn validate(&self) -> Result<(), ValidationError> {
        // @constraint selvedge.config.model.server.valid.port Server config validation returns InvalidPort for port zero.
        if self.port == 0 {
            return Err(ValidationError::InvalidPort);
        }

        // @constraint selvedge.config.model.server.valid.timeout Server config validation returns InvalidRequestTimeout for timeout zero.
        if self.request_timeout_ms == 0 {
            return Err(ValidationError::InvalidRequestTimeout);
        }

        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize)]
// @behavior selvedge.config.model.network The network config exposes optional transport settings without substituting transport fallback values.
pub struct NetworkConfig {
    // @behavior selvedge.config.model.network.connect_timeout Network config exposes the optional connection timeout in milliseconds.
    pub connect_timeout_ms: Option<u64>,
    // @behavior selvedge.config.model.network.request_timeout Network config exposes the optional request timeout in milliseconds.
    pub request_timeout_ms: Option<u64>,
    // @behavior selvedge.config.model.network.stream_idle_timeout Network config exposes the optional stream idle timeout in milliseconds.
    pub stream_idle_timeout_ms: Option<u64>,
    // @behavior selvedge.config.model.network.ca_bundle Network config exposes the optional CA bundle path.
    pub ca_bundle_path: Option<std::path::PathBuf>,
    // @behavior selvedge.config.model.network.user_agent Network config exposes the optional HTTP user agent string.
    pub user_agent: Option<String>,
}

impl NetworkConfig {
    // @constraint selvedge.config.model.network.valid Network config validation rejects zero timeout values and user agents that cannot be represented as HTTP header values.
    pub fn validate(&self) -> Result<(), ValidationError> {
        // @constraint selvedge.config.model.network.valid.connect_timeout Network config validation returns InvalidConnectTimeout for connection timeout zero.
        if self.connect_timeout_ms == Some(0) {
            return Err(ValidationError::InvalidConnectTimeout);
        }

        // @constraint selvedge.config.model.network.valid.request_timeout Network config validation returns InvalidNetworkRequestTimeout for request timeout zero.
        if self.request_timeout_ms == Some(0) {
            return Err(ValidationError::InvalidNetworkRequestTimeout);
        }

        // @constraint selvedge.config.model.network.valid.stream_idle_timeout Network config validation returns InvalidStreamIdleTimeout for stream idle timeout zero.
        if self.stream_idle_timeout_ms == Some(0) {
            return Err(ValidationError::InvalidStreamIdleTimeout);
        }

        // @constraint selvedge.config.model.network.valid.user_agent Network config validation returns InvalidUserAgent for header-invalid user agent values.
        if let Some(user_agent) = &self.user_agent {
            HeaderValue::from_str(user_agent)
                .map_err(|_| ValidationError::InvalidUserAgent(user_agent.clone()))?;
        }

        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
// @behavior selvedge.config.model.logging The logging config exposes a global log filter and module-level log filter overrides.
pub struct LoggingConfig {
    // @behavior selvedge.config.model.logging.level Logging config exposes the global log filter.
    pub level: LogFilter,
    // @behavior selvedge.config.model.logging.module_levels Logging config exposes module path log filter overrides.
    pub module_levels: BTreeMap<String, LogFilter>,
}

impl LoggingConfig {
    const DEFAULT_LEVEL: LogFilter = LogFilter::Info;

    // @behavior selvedge.config.model.logging.valid Logging config validation accepts the strongly typed logging fields.
    pub fn validate(&self) -> Result<(), ValidationError> {
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
// @behavior selvedge.config.model.logging.filter Log filters deserialize from lowercase config values and render back to lowercase strings.
pub enum LogFilter {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}

impl Display for LogFilter {
    // @behavior selvedge.config.model.logging.filter.display Formatting a log filter returns the lowercase config spelling.
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let rendered = match self {
            Self::Trace => "trace",
            Self::Debug => "debug",
            Self::Info => "info",
            Self::Warn => "warn",
            Self::Error => "error",
        };

        // @behavior selvedge.config.model.logging.filter.display.write Formatting writes the lowercase log filter spelling to the formatter.
        formatter.write_str(rendered)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
// @behavior selvedge.config.model.feature The feature config exposes feature enablement and rollout percentage to callers.
pub struct FeatureConfig {
    // @behavior selvedge.config.model.feature.enabled Feature config exposes whether the feature is enabled.
    pub enabled: bool,
    // @behavior selvedge.config.model.feature.rollout Feature config exposes the rollout percentage.
    pub rollout_percentage: u8,
}

impl FeatureConfig {
    const DEFAULT_ENABLED: bool = false;
    const DEFAULT_ROLLOUT_PERCENTAGE: u8 = 0;

    // @constraint selvedge.config.model.feature.valid Feature validation rejects rollout percentages above 100 and enabled features with zero rollout.
    pub fn validate(&self) -> Result<(), ValidationError> {
        // @constraint selvedge.config.model.feature.valid.range Feature validation returns InvalidRolloutPercentage for values above 100.
        if self.rollout_percentage > 100 {
            return Err(ValidationError::InvalidRolloutPercentage(
                self.rollout_percentage,
            ));
        }

        // @constraint selvedge.config.model.feature.valid.enabled_rollout Feature validation returns EnabledFeatureRequiresRollout for enabled features with zero rollout.
        if self.enabled && self.rollout_percentage == 0 {
            return Err(ValidationError::EnabledFeatureRequiresRollout);
        }

        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize)]
// @behavior selvedge.config.model.llm The LLM config exposes provider-specific settings to callers.
pub struct LlmConfig {
    // @behavior selvedge.config.model.llm.providers_field LLM config exposes provider settings keyed by provider id.
    pub providers: BTreeMap<String, LlmProviderConfig>,
}

impl LlmConfig {
    // @behavior selvedge.config.model.llm.valid LLM config validation returns provider validation errors as typed validation results.
    pub fn validate(&self) -> Result<(), ValidationError> {
        for (provider_id, provider) in &self.providers {
            validate_provider_id(provider_id)?;
            provider.validate_for_provider(provider_id)?;
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize)]
// @behavior selvedge.config.model.llm.provider LLM provider config exposes non-sensitive settings and manual model names for a provider id.
pub struct LlmProviderConfig {
    // @behavior selvedge.config.model.llm.provider.base_url Provider config may expose a non-sensitive provider base URL override.
    pub base_url: Option<String>,
    // @behavior selvedge.config.model.llm.provider.timeout Provider config may expose a nonzero provider stream completion timeout override.
    pub stream_completion_timeout_ms: Option<u64>,
    // @behavior selvedge.config.model.llm.provider.models Provider config exposes manually configured model names for providers whose models cannot be discovered or built in.
    pub models: Vec<String>,
    // @behavior selvedge.config.model.llm.provider.settings Provider config exposes non-sensitive provider-specific settings without storing credentials.
    pub settings: BTreeMap<String, toml::Value>,
}

impl LlmProviderConfig {
    // @constraint selvedge.config.model.llm.provider.valid Standalone provider validation applies generic provider config limits before the provider id is known.
    pub fn validate(&self) -> Result<(), ValidationError> {
        self.validate_for_provider("<provider>")
    }

    // @constraint selvedge.config.model.llm.provider.valid_for_provider Provider validation applies base URL, timeout, model list, and settings limits to a concrete provider id.
    fn validate_for_provider(&self, provider_id: &str) -> Result<(), ValidationError> {
        if let Some(base_url) = &self.base_url {
            validate_provider_base_url(provider_id, base_url)?;
        }

        if self.stream_completion_timeout_ms == Some(0) {
            // @constraint selvedge.config.model.llm.provider.timeout.nonzero Provider stream completion timeout validation rejects zero values.
            return Err(ValidationError::InvalidProviderStreamCompletionTimeout {
                provider_id: provider_id.to_owned(),
            });
        }

        let mut seen_models = std::collections::BTreeSet::new();
        for model in &self.models {
            if model.trim().is_empty() {
                // @constraint selvedge.config.model.llm.provider.models.nonblank Provider model list validation rejects blank names.
                return Err(ValidationError::BlankProviderModel {
                    provider_id: provider_id.to_owned(),
                });
            }
            if !seen_models.insert(model) {
                // @constraint selvedge.config.model.llm.provider.models.unique Provider model list validation rejects duplicate names.
                return Err(ValidationError::DuplicateProviderModel {
                    provider_id: provider_id.to_owned(),
                    model: model.clone(),
                });
            }
        }

        validate_settings_table(provider_id, &self.settings)
    }
}

// @constraint selvedge.config.model.llm.provider_id Provider ids are validated for nonblank path-safe spelling before provider-map entries are accepted.
fn validate_provider_id(provider_id: &str) -> Result<(), ValidationError> {
    if provider_id.trim().is_empty() {
        // @constraint selvedge.config.model.llm.provider_id.nonblank Provider ids must contain visible characters.
        return Err(ValidationError::InvalidProviderId {
            provider_id: provider_id.to_owned(),
        });
    }

    for byte in provider_id.bytes() {
        let allowed = byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_');
        if !allowed {
            // @constraint selvedge.config.model.llm.provider_id.path_safe Provider ids must use ASCII alphanumeric characters, dots, hyphens, or underscores.
            return Err(ValidationError::InvalidProviderId {
                provider_id: provider_id.to_owned(),
            });
        }
    }

    Ok(())
}

// @constraint selvedge.config.model.llm.provider.base_url.valid Provider base URL validation accepts clean http or https URLs with explicit authorities.
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
        // @constraint selvedge.config.model.llm.provider.base_url.base_shape Provider base URL validation rejects query strings and fragments.
        return Err(ValidationError::ProviderBaseUrlMustBeBaseUrl {
            provider_id: provider_id.to_owned(),
        });
    }

    Ok(())
}

// @constraint selvedge.config.model.llm.provider.settings.valid Provider settings validation applies key and value limits recursively.
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
        // @constraint selvedge.config.model.llm.provider.settings.key Provider settings validation rejects blank setting keys.
        return Err(ValidationError::InvalidProviderSetting {
            provider_id: provider_id.to_owned(),
            setting: key.to_owned(),
        });
    }
    Ok(())
}

// @constraint selvedge.config.model.llm.provider.settings.value Provider settings validation accepts TOML scalar, array, and table values with valid nested keys.
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

// @constraint selvedge.config.model.url.scheme Configured ChatGPT URLs use http or https, omit userinfo, and use https for non-loopback hosts.
fn validate_base_url_scheme_and_authority(
    url: &url::Url,
    invalid_url_error: ValidationError,
    userinfo_error: ValidationError,
    https_required_error: ValidationError,
) -> Result<(), ValidationError> {
    // @constraint selvedge.config.model.url.scheme.allowed ChatGPT URL validation returns the configured invalid URL error for schemes outside http and https.
    if !matches!(url.scheme(), "http" | "https") {
        return Err(invalid_url_error);
    }

    // @constraint selvedge.config.model.url.scheme.userinfo ChatGPT URL validation returns the configured userinfo error for URLs containing username or password values.
    if !url.username().is_empty() || url.password().is_some() {
        return Err(userinfo_error);
    }

    // @constraint selvedge.config.model.url.scheme.https ChatGPT URL validation returns the configured HTTPS-required error for non-loopback http URLs.
    if url.scheme() == "http" && !issuer_host_is_loopback(url) {
        return Err(https_required_error);
    }

    Ok(())
}

// @constraint selvedge.config.model.url ChatGPT URL validation preserves absolute authority, scheme, userinfo, and loopback HTTPS rules.
fn ensure_explicit_authority(
    raw: &str,
    url: &url::Url,
    invalid_url_error: ValidationError,
) -> Result<(), ValidationError> {
    // @constraint selvedge.config.model.url.authority Configured ChatGPT URLs must contain an explicit http or https authority.
    // @constraint selvedge.config.model.url.authority.separator ChatGPT URL validation returns the configured invalid URL error when the scheme separator is absent.
    let Some((scheme, remainder)) = raw.split_once("://") else {
        return Err(invalid_url_error);
    };

    // @constraint selvedge.config.model.url.authority.scheme ChatGPT URL validation returns the configured invalid URL error when the explicit scheme is outside http and https.
    if !matches!(scheme.to_ascii_lowercase().as_str(), "http" | "https") {
        return Err(invalid_url_error);
    }

    let authority = remainder.split(['/', '?', '#']).next().unwrap_or_default();

    // @constraint selvedge.config.model.url.authority.host ChatGPT URL validation returns the configured invalid URL error when the authority lacks a host.
    if authority.is_empty() || authority.starts_with('/') || url.host().is_none() {
        return Err(invalid_url_error);
    }

    Ok(())
}

// @constraint selvedge.config.model.url.loopback Loopback URL detection returns true only for localhost and loopback IP hosts.
fn issuer_host_is_loopback(issuer: &url::Url) -> bool {
    // @behavior selvedge.config.model.url.loopback.result Loopback URL detection treats localhost, IPv4 loopback, and IPv6 loopback hosts as local development targets.
    // @constraint selvedge.config.model.url.loopback.host Loopback URL detection returns false when a URL has no host.
    match issuer.host() {
        Some(url::Host::Domain(host)) => host.eq_ignore_ascii_case("localhost"),
        Some(url::Host::Ipv4(address)) => address.is_loopback(),
        Some(url::Host::Ipv6(address)) => address.is_loopback(),
        None => false,
    }
}

#[derive(Debug, Error)]
// @behavior selvedge.config.model.error App config conversion errors expose deserialization failures and validation failures to callers.
pub enum AppConfigError {
    #[error("failed to deserialize config input: {0}")]
    Deserialize(#[from] toml::de::Error),
    #[error(transparent)]
    Validation(#[from] ValidationError),
}

#[derive(Debug, Error, PartialEq, Eq)]
// @behavior selvedge.config.model.validation_error Validation errors expose stable messages for invalid config fields and cross-field constraints.
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
// @intent selvedge.config.model.input The input config layer accepts partial TOML sections before materializing the public typed config.
struct AppConfigInput {
    server: ServerConfigInput,
    network: NetworkConfigInput,
    logging: LoggingConfigInput,
    feature: FeatureConfigInput,
    llm: LlmConfigInput,
}

impl AppConfigInput {
    // @behavior selvedge.config.model.input.materialize Partial app config input materializes every top-level section into the public typed config.
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
// @intent selvedge.config.model.server.input The server input layer accepts omitted fields before applying server defaults.
struct ServerConfigInput {
    host: Option<String>,
    port: Option<u16>,
    request_timeout_ms: Option<u64>,
}

impl ServerConfigInput {
    // @behavior selvedge.config.model.server.defaults Missing server input fields materialize to host 127.0.0.1, port 8080, and request timeout 5000 milliseconds.
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
// @intent selvedge.config.model.network.input The network input layer preserves optional transport settings from TOML.
struct NetworkConfigInput {
    connect_timeout_ms: Option<u64>,
    request_timeout_ms: Option<u64>,
    stream_idle_timeout_ms: Option<u64>,
    ca_bundle_path: Option<std::path::PathBuf>,
    user_agent: Option<String>,
}

impl NetworkConfigInput {
    // @behavior selvedge.config.model.network.defaults Missing network input fields materialize to None for every optional transport setting.
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
// @intent selvedge.config.model.logging.input The logging input layer accepts current logging fields and the legacy format field.
struct LoggingConfigInput {
    level: Option<LogFilter>,
    module_levels: BTreeMap<String, LogFilter>,
    format: Option<String>,
}

impl LoggingConfigInput {
    // @behavior selvedge.config.model.logging.defaults Missing logging input fields materialize to the info level with no module overrides while the legacy format value is ignored.
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
// @intent selvedge.config.model.feature.input The feature input layer accepts omitted feature fields before applying feature defaults.
struct FeatureConfigInput {
    enabled: Option<bool>,
    rollout_percentage: Option<u8>,
}

impl FeatureConfigInput {
    // @behavior selvedge.config.model.feature.defaults Missing feature input fields materialize to disabled with zero rollout percentage.
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
// @intent selvedge.config.model.llm.input The LLM input layer accepts omitted provider sections before applying provider defaults.
struct LlmConfigInput {
    providers: BTreeMap<String, LlmProviderConfigInput>,
}

impl LlmConfigInput {
    // @behavior selvedge.config.model.llm.defaults Missing LLM input sections materialize to an empty provider map.
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
// @intent selvedge.config.model.llm.provider.input The LLM provider input layer accepts partial non-sensitive provider settings before materializing a provider config.
struct LlmProviderConfigInput {
    base_url: Option<String>,
    stream_completion_timeout_ms: Option<u64>,
    models: Vec<String>,
    settings: BTreeMap<String, toml::Value>,
}

impl LlmProviderConfigInput {
    // @behavior selvedge.config.model.llm.provider.defaults Missing provider input fields materialize to absent overrides, an empty manual model list, and empty settings.
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

        // @verifies selvedge.config.model.network.defaults
        assert_eq!(config.network.connect_timeout_ms, None);
        // @verifies selvedge.config.model.network.defaults
        assert_eq!(config.network.request_timeout_ms, None);
        // @verifies selvedge.config.model.network.defaults
        assert_eq!(config.network.stream_idle_timeout_ms, None);
        // @verifies selvedge.config.model.network.defaults
        assert_eq!(config.network.ca_bundle_path, None);
        // @verifies selvedge.config.model.network.defaults
        assert_eq!(config.network.user_agent, None);
        // @verifies selvedge.config.model.logging.defaults
        assert_eq!(config.logging.level, LogFilter::Info);
        // @verifies selvedge.config.model.logging.defaults
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

        // @verifies selvedge.config.model.logging.level
        assert_eq!(config.logging.level, LogFilter::Warn);
        // @verifies selvedge.config.model.logging.module_levels
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

        // @verifies selvedge.config.model.logging.defaults
        assert_eq!(config.logging.level, LogFilter::Info);
        // @verifies selvedge.config.model.logging.defaults
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

        // @verifies selvedge.config.model.network.connect_timeout
        assert_eq!(config.network.connect_timeout_ms, Some(1_000));
        // @verifies selvedge.config.model.network.request_timeout
        assert_eq!(config.network.request_timeout_ms, Some(30_000));
        // @verifies selvedge.config.model.network.stream_idle_timeout
        assert_eq!(config.network.stream_idle_timeout_ms, Some(300_000));
        // @verifies selvedge.config.model.network.ca_bundle
        assert_eq!(
            config.network.ca_bundle_path.as_deref(),
            Some(std::path::Path::new("/tmp/ca.pem"))
        );
        // @verifies selvedge.config.model.network.user_agent
        assert_eq!(
            config.network.user_agent.as_deref(),
            Some("selvedge-client/test")
        );
    }
}
