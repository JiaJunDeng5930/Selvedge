use crate::ChatgptLoginError;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ChatgptAuthConfig {
    pub issuer: String,
    pub client_id: String,
    pub expected_workspace_id: Option<String>,
}

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
    .map_err(ChatgptLoginError::Config)
}

pub(crate) fn read_selvedge_home() -> Result<std::path::PathBuf, ChatgptLoginError> {
    selvedge_config::selvedge_home().map_err(ChatgptLoginError::Config)
}
