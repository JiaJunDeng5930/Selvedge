use crate::ChatgptLoginError;

// @behavior selvedge.login.config Device-code login reads the issuer, client ID, and optional expected workspace from current ChatGPT auth configuration.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ChatgptAuthConfig {
    // @behavior selvedge.login.config.issuer Device-code login sends provider requests to the configured ChatGPT issuer after trailing slash normalization.
    pub issuer: String,
    // @behavior selvedge.login.config.client_id Device-code login sends the configured ChatGPT client ID in provider requests.
    pub client_id: String,
    // @constraint selvedge.login.config.expected_workspace Completed login enforces the configured expected workspace ID against id token account claims.
    pub expected_workspace_id: Option<String>,
}

// @behavior selvedge.login.config.read Each login call reads current ChatGPT auth configuration and trims trailing issuer slashes before network use.
pub(crate) fn read_chatgpt_auth_config() -> Result<ChatgptAuthConfig, ChatgptLoginError> {
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
    // @behavior selvedge.login.config.error Config read failures are returned as caller-visible ChatGPT login config errors.
    .map_err(ChatgptLoginError::Config)
}

// @behavior selvedge.login.config.home Completed login reads the current Selvedge home before locating the ChatGPT auth file.
pub(crate) fn read_selvedge_home() -> Result<std::path::PathBuf, ChatgptLoginError> {
    selvedge_config::selvedge_home().map_err(ChatgptLoginError::Config)
}
