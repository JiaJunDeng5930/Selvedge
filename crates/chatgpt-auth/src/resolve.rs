use crate::{
    ChatgptAuthError, ChatgptJwtClaims, ChatgptStoredTokens, ResolvedChatgptAuth, auth_file,
    config, jwt, lock, parse_chatgpt_jwt_claims, refresh,
};

pub(crate) async fn resolve_for_request() -> Result<ResolvedChatgptAuth, ChatgptAuthError> {
    resolve(false).await
}

pub(crate) async fn resolve_after_unauthorized() -> Result<ResolvedChatgptAuth, ChatgptAuthError> {
    resolve(true).await
}

async fn resolve(force_refresh: bool) -> Result<ResolvedChatgptAuth, ChatgptAuthError> {
    let config = config::read_chatgpt_auth_config().map_err(ChatgptAuthError::Config)?;
    let selvedge_home = selvedge_config::selvedge_home().map_err(ChatgptAuthError::Config)?;
    let auth_file_path = auth_file::auth_file_path(&selvedge_home);
    let refresh_hint = force_refresh
        .then(|| auth_file::load_refresh_hint(&selvedge_home))
        .flatten();
    let guard = lock::lock_chatgpt_credential(&selvedge_home).await?;
    let stored = auth_file::load(&guard)?;
    let tokens = stored.tokens;
    let now = chrono::Utc::now();
    let access_token_expired = !jwt::access_token_is_usable(&tokens.access_token, now);
    let id_token_requires_refresh = parse_chatgpt_jwt_claims(&tokens.id_token).is_err();
    let proactive_refresh = should_refresh_proactively(
        access_token_expiration(&tokens.access_token),
        stored.last_refresh,
        now,
    );
    let needs_refresh = access_token_expired || id_token_requires_refresh || proactive_refresh;
    let auth_became_usable_while_waiting = refresh_hint.as_ref().is_some_and(|previous_tokens| {
        previous_tokens.access_token != tokens.access_token && !needs_refresh
    });

    if auth_became_usable_while_waiting || (!force_refresh && !needs_refresh) {
        return build_resolved_auth_from_existing(
            &tokens,
            &auth_file_path,
            config.expected_workspace_id.as_deref(),
        );
    }

    let refreshed_tokens = refresh::refresh(
        &config,
        &tokens,
        force_refresh || access_token_expired || proactive_refresh,
        id_token_requires_refresh,
    )
    .await?;
    let resolved = build_resolved_auth_from_refresh(
        &refreshed_tokens,
        config.expected_workspace_id.as_deref(),
    )?;

    auth_file::persist(&guard, &refreshed_tokens).map_err(|error| {
        ChatgptAuthError::PersistFailed {
            path: error.path,
            reason: error.reason,
        }
    })?;

    Ok(resolved)
}

fn should_refresh_proactively(
    expires_at: Option<chrono::DateTime<chrono::Utc>>,
    last_refresh: chrono::DateTime<chrono::Utc>,
    now: chrono::DateTime<chrono::Utc>,
) -> bool {
    // NOTE: A readable JWT expiry takes precedence over the age fallback,
    // which is needed for opaque access tokens and JWTs without an expiry.
    match expires_at {
        Some(expires_at) => expires_at <= now + chrono::Duration::minutes(5),
        None => last_refresh < now - chrono::Duration::days(8),
    }
}

fn build_resolved_auth_from_existing(
    tokens: &ChatgptStoredTokens,
    auth_file_path: &std::path::Path,
    expected_workspace_id: Option<&str>,
) -> Result<ResolvedChatgptAuth, ChatgptAuthError> {
    let id_token_claims = parse_chatgpt_jwt_claims(&tokens.id_token).map_err(|error| {
        ChatgptAuthError::AuthFileMalformed {
            path: auth_file_path.to_path_buf(),
            reason: format!("id_token is invalid: {error:?}"),
        }
    })?;

    build_resolved_auth(tokens, expected_workspace_id, id_token_claims)
}

fn build_resolved_auth_from_refresh(
    tokens: &ChatgptStoredTokens,
    expected_workspace_id: Option<&str>,
) -> Result<ResolvedChatgptAuth, ChatgptAuthError> {
    let id_token_claims = parse_chatgpt_jwt_claims(&tokens.id_token).map_err(|_| {
        ChatgptAuthError::RefreshFailed {
            status: Some(200),
            provider_code: None,
            provider_message: None,
        }
    })?;

    build_resolved_auth(tokens, expected_workspace_id, id_token_claims)
}

fn build_resolved_auth(
    tokens: &ChatgptStoredTokens,
    expected_workspace_id: Option<&str>,
    id_token_claims: ChatgptJwtClaims,
) -> Result<ResolvedChatgptAuth, ChatgptAuthError> {
    if let Some(expected_workspace_id) = expected_workspace_id
        && id_token_claims.account_id.as_deref() != Some(expected_workspace_id)
    {
        return Err(ChatgptAuthError::WorkspaceMismatch {
            expected: expected_workspace_id.to_owned(),
            actual: id_token_claims.account_id,
        });
    }

    Ok(ResolvedChatgptAuth {
        access_token: tokens.access_token.clone(),
        access_token_expires_at: access_token_expiration(&tokens.access_token),
        account_id: id_token_claims.account_id,
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
