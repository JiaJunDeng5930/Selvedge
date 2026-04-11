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
    let refresh_hint = force_refresh
        .then(|| auth_file::load_refresh_hint(&auth_file_path))
        .flatten();
    let _guard = lock::lock_path(&auth_file_path).await?;
    let auth_file = auth_file::load(&auth_file_path)?;
    let access_token_expired = access_token_is_expired(&auth_file.tokens.access_token);
    let auth_became_usable_while_waiting = refresh_hint
        .as_ref()
        .is_some_and(|previous_auth_file| token_sets_differ(previous_auth_file, &auth_file))
        && !should_refresh(&auth_file, access_token_expired);

    if auth_became_usable_while_waiting
        || (!force_refresh && !should_refresh(&auth_file, access_token_expired))
    {
        return build_resolved_auth_from_existing(
            &auth_file,
            &auth_file_path,
            config.expected_workspace_id.as_deref(),
        );
    }

    let refreshed_tokens = refresh::refresh(
        &config,
        &auth_file.tokens,
        force_refresh || access_token_expired,
    )
    .await?;
    let refreshed_file = ChatgptAuthFile {
        schema_version: 1,
        provider: "chatgpt".to_owned(),
        login_method: "device_code".to_owned(),
        tokens: refreshed_tokens,
    };
    let resolved =
        build_resolved_auth_from_refresh(&refreshed_file, config.expected_workspace_id.as_deref())?;

    auth_file::persist(&auth_file_path, &refreshed_file.tokens)?;

    Ok(resolved)
}

fn should_refresh(auth_file: &ChatgptAuthFile, access_token_expired: bool) -> bool {
    if access_token_expired {
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

fn build_resolved_auth_from_existing(
    auth_file: &ChatgptAuthFile,
    auth_file_path: &std::path::Path,
    expected_workspace_id: Option<&str>,
) -> Result<ResolvedChatgptAuth, ChatgptAuthError> {
    let id_token_claims =
        parse_chatgpt_jwt_claims(&auth_file.tokens.id_token).map_err(|error| {
            ChatgptAuthError::AuthFileMalformed {
                path: auth_file_path.to_path_buf(),
                reason: format!("id_token is invalid: {error:?}"),
            }
        })?;

    build_resolved_auth(auth_file, expected_workspace_id, id_token_claims)
}

fn build_resolved_auth_from_refresh(
    auth_file: &ChatgptAuthFile,
    expected_workspace_id: Option<&str>,
) -> Result<ResolvedChatgptAuth, ChatgptAuthError> {
    let id_token_claims = parse_chatgpt_jwt_claims(&auth_file.tokens.id_token).map_err(|_| {
        ChatgptAuthError::RefreshFailed {
            status: Some(200),
            provider_code: None,
            provider_message: None,
        }
    })?;

    build_resolved_auth(auth_file, expected_workspace_id, id_token_claims)
}

fn build_resolved_auth(
    auth_file: &ChatgptAuthFile,
    expected_workspace_id: Option<&str>,
    id_token_claims: ChatgptJwtClaims,
) -> Result<ResolvedChatgptAuth, ChatgptAuthError> {
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

fn token_sets_differ(previous: &ChatgptAuthFile, current: &ChatgptAuthFile) -> bool {
    previous.tokens.id_token != current.tokens.id_token
        || previous.tokens.access_token != current.tokens.access_token
        || previous.tokens.refresh_token != current.tokens.refresh_token
}
