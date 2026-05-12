use crate::ChatgptAuthError;

// @behavior selvedge.auth.config ChatGPT auth resolution reads the issuer, client ID, and optional expected workspace from current configuration.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ChatgptAuthConfig {
    // @behavior selvedge.auth.config.issuer Auth resolution sends provider requests to the configured ChatGPT issuer after trailing slash normalization.
    pub issuer: String,
    // @behavior selvedge.auth.config.client_id Auth resolution sends the configured ChatGPT client ID in refresh requests.
    pub client_id: String,
    // @constraint selvedge.auth.config.expected_workspace Auth resolution enforces the configured expected workspace ID against id token account claims.
    pub expected_workspace_id: Option<String>,
}

// @behavior selvedge.auth.config.read Each auth resolution call reads current ChatGPT auth configuration and trims trailing issuer slashes before network use.
pub(crate) fn read_chatgpt_auth_config() -> Result<ChatgptAuthConfig, ChatgptAuthError> {
    selvedge_config::read(|config| ChatgptAuthConfig {
        issuer: config
            .llm
            .providers
            .chatgpt
            .auth
            .issuer
            .trim_end_matches('/')
            .to_owned(),
        client_id: config.llm.providers.chatgpt.auth.client_id.clone(),
        expected_workspace_id: config
            .llm
            .providers
            .chatgpt
            .auth
            .expected_workspace_id
            .clone(),
    })
    // @behavior selvedge.auth.config.error Config read failures are returned as caller-visible ChatGPT auth config errors.
    .map_err(ChatgptAuthError::Config)
}

// @behavior selvedge.auth.config.home Auth resolution reads the current Selvedge home before locating the ChatGPT auth file.
pub(crate) fn read_selvedge_home() -> Result<std::path::PathBuf, ChatgptAuthError> {
    selvedge_config::selvedge_home().map_err(ChatgptAuthError::Config)
}
