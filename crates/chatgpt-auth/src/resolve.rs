use crate::{
    ChatgptAuthError, ChatgptAuthFile, ChatgptJwtClaims, ResolvedChatgptAuth, auth_file, config,
    lock, parse_chatgpt_jwt_claims, refresh,
};

pub(crate) async fn resolve_for_request() -> Result<ResolvedChatgptAuth, ChatgptAuthError> {
    resolve(false).await
}

pub(crate) async fn resolve_after_unauthorized() -> Result<ResolvedChatgptAuth, ChatgptAuthError> {
    resolve(true).await
}

async fn resolve(force_refresh: bool) -> Result<ResolvedChatgptAuth, ChatgptAuthError> {
    let config = config::read_chatgpt_auth_config()?;
    let selvedge_home = config::read_selvedge_home()?;
    let auth_file_path = auth_file::auth_file_path(&selvedge_home);
    let _guard = lock::lock_path(&auth_file_path).await;
    let auth_file = auth_file::load(&auth_file_path)?;

    if !force_refresh && !should_refresh(&auth_file) {
        return build_resolved_auth(auth_file, config.expected_workspace_id.as_deref());
    }

    let refreshed_tokens = refresh::refresh(&config, &auth_file.tokens).await?;

    auth_file::persist(&auth_file_path, &refreshed_tokens)?;

    let refreshed_file = ChatgptAuthFile {
        schema_version: 1,
        provider: "chatgpt".to_owned(),
        login_method: "device_code".to_owned(),
        tokens: refreshed_tokens,
    };

    build_resolved_auth(refreshed_file, config.expected_workspace_id.as_deref())
}

fn should_refresh(auth_file: &ChatgptAuthFile) -> bool {
    if access_token_is_expired(&auth_file.tokens.access_token) {
        return true;
    }

    let Ok(id_token_claims) = parse_chatgpt_jwt_claims(&auth_file.tokens.id_token) else {
        return true;
    };

    id_token_claims.account_id.is_none()
}

fn access_token_is_expired(access_token: &str) -> bool {
    let Ok(claims) = parse_chatgpt_jwt_claims(access_token) else {
        return false;
    };
    let Some(expires_at) = claims.expires_at else {
        return false;
    };

    expires_at <= chrono::Utc::now()
}

fn build_resolved_auth(
    auth_file: ChatgptAuthFile,
    expected_workspace_id: Option<&str>,
) -> Result<ResolvedChatgptAuth, ChatgptAuthError> {
    let id_token_claims =
        parse_chatgpt_jwt_claims(&auth_file.tokens.id_token).map_err(|error| {
            ChatgptAuthError::AuthFileMalformed {
                path: std::path::PathBuf::from("<resolved-id-token>"),
                reason: format!("id_token is invalid: {error:?}"),
            }
        })?;
    let account_id = id_token_claims
        .account_id
        .clone()
        .ok_or(ChatgptAuthError::MissingAccountId)?;

    if let Some(expected_workspace_id) = expected_workspace_id
        && account_id != expected_workspace_id
    {
        return Err(ChatgptAuthError::WorkspaceMismatch {
            expected: expected_workspace_id.to_owned(),
            actual: Some(account_id),
        });
    }

    Ok(ResolvedChatgptAuth {
        access_token: auth_file.tokens.access_token.clone(),
        access_token_expires_at: access_token_expiration(&auth_file.tokens.access_token),
        account_id,
        user_id: id_token_claims.user_id,
        email: id_token_claims.email,
        plan_type: id_token_claims.plan_type,
    })
}

fn access_token_expiration(access_token: &str) -> Option<chrono::DateTime<chrono::Utc>> {
    parse_chatgpt_jwt_claims(access_token)
        .ok()
        .and_then(|claims| claims.expires_at)
}

#[allow(dead_code)]
fn _claims(_claims: &ChatgptJwtClaims) {}
