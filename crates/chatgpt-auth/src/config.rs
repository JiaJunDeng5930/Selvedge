const DEFAULT_ISSUER: &str = "https://auth.openai.com";
const DEFAULT_CLIENT_ID: &str = "app_EMoamEEZ73f0CkXaXp7hrann";

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChatgptAuthConfig {
    pub issuer: String,
    pub client_id: String,
    pub expected_workspace_id: Option<String>,
}

pub fn read_chatgpt_auth_config() -> Result<ChatgptAuthConfig, selvedge_config::ConfigError> {
    let settings = selvedge_config::read(|config| {
        config
            .llm
            .providers
            .get("chatgpt")
            .map(|provider| provider.settings.clone())
            .unwrap_or_default()
    })?;
    let config = ChatgptAuthConfig {
        issuer: setting_string(&settings, "issuer")
            .map_err(validation_config_error)?
            .unwrap_or_else(|| DEFAULT_ISSUER.to_owned())
            .trim_end_matches('/')
            .to_owned(),
        client_id: setting_string(&settings, "client_id")
            .map_err(validation_config_error)?
            .unwrap_or_else(|| DEFAULT_CLIENT_ID.to_owned()),
        expected_workspace_id: setting_string(&settings, "expected_workspace_id")
            .map_err(validation_config_error)?,
    };
    validate_auth_config(&config).map_err(validation_config_error)?;

    Ok(config)
}

fn setting_string(
    settings: &std::collections::BTreeMap<String, toml::Value>,
    key: &str,
) -> Result<Option<String>, String> {
    let Some(value) = settings.get(key) else {
        return Ok(None);
    };
    value
        .as_str()
        .map(str::to_owned)
        .map(Some)
        .ok_or_else(|| format!("llm.providers.chatgpt.settings.{key} must be a string"))
}

fn validation_config_error(reason: String) -> selvedge_config::ConfigError {
    selvedge_config::ConfigError::ValidationFailed(reason)
}

fn validate_auth_config(config: &ChatgptAuthConfig) -> Result<(), String> {
    let issuer = url::Url::parse(&config.issuer).map_err(|_| {
        "llm.providers.chatgpt.settings.issuer must be an absolute http or https URL".to_owned()
    })?;
    if !matches!(issuer.scheme(), "http" | "https") || issuer.host().is_none() {
        return Err(
            "llm.providers.chatgpt.settings.issuer must be an absolute http or https URL"
                .to_owned(),
        );
    }
    if !issuer.username().is_empty() || issuer.password().is_some() {
        return Err("llm.providers.chatgpt.settings.issuer must not contain userinfo".to_owned());
    }
    if issuer.scheme() == "http" && !host_is_loopback(&issuer) {
        return Err(
            "llm.providers.chatgpt.settings.issuer must use https unless it targets a loopback host"
                .to_owned(),
        );
    }
    let clean_path = issuer.path().is_empty() || issuer.path() == "/";
    if !clean_path || issuer.query().is_some() || issuer.fragment().is_some() {
        return Err("llm.providers.chatgpt.settings.issuer must be a clean base URL".to_owned());
    }
    if config.client_id.trim().is_empty() {
        return Err("llm.providers.chatgpt.settings.client_id must not be blank".to_owned());
    }
    if config
        .expected_workspace_id
        .as_deref()
        .is_some_and(|workspace| workspace.trim().is_empty())
    {
        return Err(
            "llm.providers.chatgpt.settings.expected_workspace_id must not be blank".to_owned(),
        );
    }
    Ok(())
}

fn host_is_loopback(url: &url::Url) -> bool {
    match url.host() {
        Some(url::Host::Domain(host)) => host.eq_ignore_ascii_case("localhost"),
        Some(url::Host::Ipv4(address)) => address.is_loopback(),
        Some(url::Host::Ipv6(address)) => address.is_loopback(),
        None => false,
    }
}
