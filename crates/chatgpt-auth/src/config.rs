use crate::ChatgptAuthError;

const DEFAULT_ISSUER: &str = "https://auth.openai.com";
const DEFAULT_CLIENT_ID: &str = "app_EMoamEEZ73f0CkXaXp7hrann";

// @behavior selvedge.auth.config ChatGPT auth resolution reads the issuer, client ID, and optional expected workspace from the chatgpt provider settings.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ChatgptAuthConfig {
    // @behavior selvedge.auth.config.issuer Auth resolution sends provider requests to the configured ChatGPT issuer after trailing slash normalization.
    pub issuer: String,
    // @behavior selvedge.auth.config.client_id Auth resolution sends the configured ChatGPT client ID in refresh requests.
    pub client_id: String,
    // @constraint selvedge.auth.config.expected_workspace Auth resolution enforces the configured expected workspace ID against id token account claims.
    pub expected_workspace_id: Option<String>,
}

// @behavior selvedge.auth.config.read Each auth resolution call reads current ChatGPT provider settings and trims trailing issuer slashes before network use.
pub(crate) fn read_chatgpt_auth_config() -> Result<ChatgptAuthConfig, ChatgptAuthError> {
    let settings = selvedge_config::read(|config| {
        config
            .llm
            .providers
            .get("chatgpt")
            .map(|provider| provider.settings.clone())
            .unwrap_or_default()
    })
    // @behavior selvedge.auth.config.error Config read failures are returned as caller-visible ChatGPT auth config errors.
    .map_err(ChatgptAuthError::Config)?;
    let config = ChatgptAuthConfig {
        issuer: setting_string(&settings, "issuer")
            .map_err(validation_config_error)?
            .unwrap_or_else(|| DEFAULT_ISSUER.to_owned())
            .trim_end_matches('/')
            .to_owned(),
        client_id: setting_string(&settings, "client_id")
            .map_err(validation_config_error)?
            .unwrap_or_else(|| DEFAULT_CLIENT_ID.to_owned()),
        // @constraint selvedge.auth.config.valid.settings_type.read ChatGPT auth config reading returns validation failures for non-string known provider settings.
        expected_workspace_id: setting_string(&settings, "expected_workspace_id")
            .map_err(validation_config_error)?,
    };
    // @constraint selvedge.auth.config.valid.read ChatGPT auth config reading returns validation failures for invalid provider settings.
    validate_auth_config(&config).map_err(|reason| {
        ChatgptAuthError::Config(selvedge_config::ConfigError::ValidationFailed(reason))
    })?;

    Ok(config)
}

// @behavior selvedge.auth.config.home Auth resolution reads the current Selvedge home before locating the ChatGPT credential record.
pub(crate) fn read_selvedge_home() -> Result<std::path::PathBuf, ChatgptAuthError> {
    selvedge_config::selvedge_home().map_err(ChatgptAuthError::Config)
}

// @constraint selvedge.auth.config.valid.settings_type ChatGPT auth provider settings with known string keys must be TOML strings.
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

fn validation_config_error(reason: String) -> ChatgptAuthError {
    ChatgptAuthError::Config(selvedge_config::ConfigError::ValidationFailed(reason))
}

// @constraint selvedge.auth.config.valid ChatGPT auth config accepts clean issuer URLs, nonblank client IDs, and nonblank workspace pins.
fn validate_auth_config(config: &ChatgptAuthConfig) -> Result<(), String> {
    let issuer = url::Url::parse(&config.issuer).map_err(|_| {
        "llm.providers.chatgpt.settings.issuer must be an absolute http or https URL".to_owned()
    })?;
    if !matches!(issuer.scheme(), "http" | "https") || issuer.host().is_none() {
        // @constraint selvedge.auth.config.valid.issuer ChatGPT auth issuer validation requires an absolute http or https URL with a host.
        return Err(
            "llm.providers.chatgpt.settings.issuer must be an absolute http or https URL"
                .to_owned(),
        );
    }
    if !issuer.username().is_empty() || issuer.password().is_some() {
        // @constraint selvedge.auth.config.valid.userinfo ChatGPT auth issuer validation rejects embedded userinfo.
        return Err("llm.providers.chatgpt.settings.issuer must not contain userinfo".to_owned());
    }
    if issuer.scheme() == "http" && !host_is_loopback(&issuer) {
        // @constraint selvedge.auth.config.valid.http ChatGPT auth issuer validation allows plain http only for loopback hosts.
        return Err(
            "llm.providers.chatgpt.settings.issuer must use https unless it targets a loopback host"
                .to_owned(),
        );
    }
    let clean_path = issuer.path().is_empty() || issuer.path() == "/";
    if !clean_path || issuer.query().is_some() || issuer.fragment().is_some() {
        // @constraint selvedge.auth.config.valid.base ChatGPT auth issuer validation requires a base URL shape with no query or fragment.
        return Err("llm.providers.chatgpt.settings.issuer must be a clean base URL".to_owned());
    }
    if config.client_id.trim().is_empty() {
        // @constraint selvedge.auth.config.valid.client_id ChatGPT auth client ID validation rejects blank values.
        return Err("llm.providers.chatgpt.settings.client_id must not be blank".to_owned());
    }
    if config
        .expected_workspace_id
        .as_deref()
        .is_some_and(|workspace| workspace.trim().is_empty())
    {
        // @constraint selvedge.auth.config.valid.workspace ChatGPT auth workspace validation rejects blank workspace pins.
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
