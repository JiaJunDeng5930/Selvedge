use std::{path::PathBuf, time::Duration};

use crate::{HttpError, build_error, duration_millis_or_zero};

#[derive(Debug, Clone)]
pub(crate) struct ResolvedCallConfig {
    pub(crate) connect_timeout: Option<Duration>,
    pub(crate) request_timeout: Option<Duration>,
    pub(crate) stream_idle_timeout: Option<Duration>,
    pub(crate) ca_bundle_path: Option<PathBuf>,
    pub(crate) user_agent: Option<String>,
}

pub(crate) fn resolve_call_config(
    timeout_override: Option<Duration>,
) -> Result<ResolvedCallConfig, HttpError> {
    if timeout_override.is_some_and(|timeout| timeout.is_zero()) {
        return Err(build_error("request.timeout must be greater than zero"));
    }

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

    let ca_bundle_path = match ca_bundle_path {
        Some(path) if path.is_relative() => Some(selvedge_config::selvedge_home()?.join(path)),
        other => other,
    };

    let config = ResolvedCallConfig {
        connect_timeout: connect_timeout_ms.map(Duration::from_millis),
        request_timeout: timeout_override.or_else(|| request_timeout_ms.map(Duration::from_millis)),
        stream_idle_timeout: stream_idle_timeout_ms.map(Duration::from_millis),
        ca_bundle_path,
        user_agent,
    };

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
