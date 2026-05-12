use std::{path::PathBuf, time::Duration};

use crate::{HttpError, build_error, duration_millis_or_zero};

// @behavior selvedge.client.config HTTP calls read network configuration at call time and expose invalid configuration as HttpError.
#[derive(Debug, Clone)]
pub(crate) struct ResolvedCallConfig {
    /// @behavior selvedge.client.config.connect_timeout Resolved call config carries the optional network connect timeout.
    pub(crate) connect_timeout: Option<Duration>,
    /// @behavior selvedge.client.config.request_timeout Resolved call config carries the optional request timeout for one call.
    pub(crate) request_timeout: Option<Duration>,
    /// @behavior selvedge.client.config.stream_idle_timeout Resolved call config carries the optional stream idle timeout.
    pub(crate) stream_idle_timeout: Option<Duration>,
    /// @behavior selvedge.client.config.ca_bundle_path Resolved call config carries the optional CA bundle path for HTTPS calls.
    pub(crate) ca_bundle_path: Option<PathBuf>,
    /// @behavior selvedge.client.config.user_agent Resolved call config carries the optional default user agent.
    pub(crate) user_agent: Option<String>,
}

// @behavior selvedge.client.config.resolve Resolving call config returns the effective HTTP settings for one request.
pub(crate) fn resolve_call_config(
    timeout_override: Option<Duration>,
) -> Result<ResolvedCallConfig, HttpError> {
    // @constraint selvedge.client.config.timeout A per-request timeout override of zero is rejected before an HTTP request is built.
    if timeout_override.is_some_and(|timeout| timeout.is_zero()) {
        return Err(build_error("request.timeout must be greater than zero"));
    }

    // @behavior selvedge.client.config.read Each HTTP call observes the current network configuration values for timeouts, CA bundle, and user agent.
    let (
        connect_timeout_ms,
        request_timeout_ms,
        stream_idle_timeout_ms,
        ca_bundle_path,
        user_agent,
    ) = selvedge_config::read(|config| {
        (
            config.network.connect_timeout_ms,
            config.network.request_timeout_ms,
            config.network.stream_idle_timeout_ms,
            config.network.ca_bundle_path.clone(),
            config.network.user_agent.clone(),
        )
    })?;

    // @behavior selvedge.client.config.ca_bundle_path.relative Relative network.ca_bundle_path values resolve under the current Selvedge home for HTTP calls.
    let ca_bundle_path = match ca_bundle_path {
        // @behavior selvedge.client.config.ca_bundle_path.home_error A missing Selvedge home while resolving a relative CA bundle path is returned as an HTTP configuration error.
        Some(path) if path.is_relative() => Some(selvedge_config::selvedge_home()?.join(path)),
        other => other,
    };

    // @behavior selvedge.client.config.override A request timeout supplied on the HttpRequest applies only to that call and takes precedence over network.request_timeout_ms.
    let config = ResolvedCallConfig {
        connect_timeout: connect_timeout_ms.map(Duration::from_millis),
        request_timeout: timeout_override.or_else(|| request_timeout_ms.map(Duration::from_millis)),
        stream_idle_timeout: stream_idle_timeout_ms.map(Duration::from_millis),
        ca_bundle_path,
        user_agent,
    };

    // @behavior selvedge.client.config.log Resolving HTTP call configuration emits a structured debug log with configured timeout and optional setting presence.
    crate::log_event!(
        selvedge_logging::LogLevel::Debug,
        "http config resolved";
        connect_timeout_ms = duration_millis_or_zero(config.connect_timeout),
        request_timeout_ms = duration_millis_or_zero(config.request_timeout),
        stream_idle_timeout_ms = duration_millis_or_zero(config.stream_idle_timeout),
        has_ca_bundle = config.ca_bundle_path.is_some(),
        has_user_agent = config.user_agent.is_some()
    );

    Ok(config)
}
