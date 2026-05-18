use crate::ChatgptLoginError;

const DEFAULT_ISSUER: &str = "https://auth.openai.com";
const DEFAULT_CLIENT_ID: &str = "app_EMoamEEZ73f0CkXaXp7hrann";

// @behavior selvedge.login.config Device-code login reads the issuer, client ID, and optional expected workspace from current ChatGPT provider settings.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ChatgptAuthConfig {
    // @behavior selvedge.login.config.issuer Device-code login sends provider requests to the configured ChatGPT issuer after trailing slash normalization.
    pub issuer: String,
    // @behavior selvedge.login.config.client_id Device-code login sends the configured ChatGPT client ID in provider requests.
    pub client_id: String,
    // @constraint selvedge.login.config.expected_workspace Completed login enforces the configured expected workspace ID against id token account claims.
    pub expected_workspace_id: Option<String>,
}

// @behavior selvedge.login.config.read Each login call reads current ChatGPT provider settings and trims trailing issuer slashes before network use.
pub(crate) fn read_chatgpt_auth_config() -> Result<ChatgptAuthConfig, ChatgptLoginError> {
    let config = selvedge_config::read(|config| {
        let settings = config
            .llm
            .providers
            .get("chatgpt")
            .map(|provider| provider.settings.clone())
            .unwrap_or_default();
        ChatgptAuthConfig {
            issuer: setting_string(&settings, "issuer")
                .unwrap_or_else(|| DEFAULT_ISSUER.to_owned())
                .trim_end_matches('/')
                .to_owned(),
            client_id: setting_string(&settings, "client_id")
                .unwrap_or_else(|| DEFAULT_CLIENT_ID.to_owned()),
            expected_workspace_id: setting_string(&settings, "expected_workspace_id"),
        }
    })
    // @behavior selvedge.login.config.error Config read failures are returned as caller-visible ChatGPT login config errors.
    .map_err(ChatgptLoginError::Config)?;
    validate_auth_config(&config).map_err(|reason| {
        ChatgptLoginError::Config(selvedge_config::ConfigError::ValidationFailed(reason))
    })?;

    Ok(config)
}

// @behavior selvedge.login.config.home Completed login reads the current Selvedge home before locating the ChatGPT credential record.
pub(crate) fn read_selvedge_home() -> Result<std::path::PathBuf, ChatgptLoginError> {
    selvedge_config::selvedge_home().map_err(ChatgptLoginError::Config)
}

fn setting_string(
    settings: &std::collections::BTreeMap<String, toml::Value>,
    key: &str,
) -> Option<String> {
    settings
        .get(key)
        .and_then(toml::Value::as_str)
        .map(str::to_owned)
}

// @constraint selvedge.login.config.valid ChatGPT login config accepts clean issuer URLs, nonblank client IDs, and nonblank workspace pins.
fn validate_auth_config(config: &ChatgptAuthConfig) -> Result<(), String> {
    let issuer = url::Url::parse(&config.issuer).map_err(|_| {
        "llm.providers.chatgpt.settings.issuer must be an absolute http or https URL".to_owned()
    })?;
    if !matches!(issuer.scheme(), "http" | "https") || issuer.host().is_none() {
        // @constraint selvedge.login.config.valid.issuer ChatGPT login issuer validation requires an absolute http or https URL with a host.
        return Err(
            "llm.providers.chatgpt.settings.issuer must be an absolute http or https URL"
                .to_owned(),
        );
    }
    if !issuer.username().is_empty() || issuer.password().is_some() {
        // @constraint selvedge.login.config.valid.userinfo ChatGPT login issuer validation rejects embedded userinfo.
        return Err("llm.providers.chatgpt.settings.issuer must not contain userinfo".to_owned());
    }
    if issuer.scheme() == "http" && !host_is_loopback(&issuer) {
        // @constraint selvedge.login.config.valid.http ChatGPT login issuer validation allows plain http only for loopback hosts.
        return Err(
            "llm.providers.chatgpt.settings.issuer must use https unless it targets a loopback host"
                .to_owned(),
        );
    }
    let clean_path = issuer.path().is_empty() || issuer.path() == "/";
    if !clean_path || issuer.query().is_some() || issuer.fragment().is_some() {
        // @constraint selvedge.login.config.valid.base ChatGPT login issuer validation requires a base URL shape with no query or fragment.
        return Err("llm.providers.chatgpt.settings.issuer must be a clean base URL".to_owned());
    }
    if config.client_id.trim().is_empty() {
        // @constraint selvedge.login.config.valid.client_id ChatGPT login client ID validation rejects blank values.
        return Err("llm.providers.chatgpt.settings.client_id must not be blank".to_owned());
    }
    if config
        .expected_workspace_id
        .as_deref()
        .is_some_and(|workspace| workspace.trim().is_empty())
    {
        // @constraint selvedge.login.config.valid.workspace ChatGPT login workspace validation rejects blank workspace pins.
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
