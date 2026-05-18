use crate::{
    ChatgptAuthError, ChatgptAuthFile, ChatgptJwtClaims, ResolvedChatgptAuth, auth_file, config,
    jwt, lock, parse_chatgpt_jwt_claims, refresh,
};

// @behavior selvedge.auth.resolve ChatGPT auth resolution returns request credentials from local auth state or a provider refresh.
// @behavior selvedge.auth.resolve.request.entry Normal request auth resolution returns usable local credentials or refreshes credentials that need renewal.
pub(crate) async fn resolve_for_request() -> Result<ResolvedChatgptAuth, ChatgptAuthError> {
    resolve(false).await
}

// @behavior selvedge.auth.resolve.unauthorized.entry Unauthorized request auth resolution forces access-token replacement before returning credentials.
pub(crate) async fn resolve_after_unauthorized() -> Result<ResolvedChatgptAuth, ChatgptAuthError> {
    resolve(true).await
}

// @behavior selvedge.auth.resolve.flow ChatGPT auth resolution reads current config and local auth state, serializes credential updates, validates workspace claims, and persists refreshed tokens.
async fn resolve(force_refresh: bool) -> Result<ResolvedChatgptAuth, ChatgptAuthError> {
    let config = config::read_chatgpt_auth_config()?;
    let selvedge_home = config::read_selvedge_home()?;
    let auth_file_path = auth_file::auth_file_path(&selvedge_home);
    let refresh_hint = force_refresh
        .then(|| auth_file::load_refresh_hint(&auth_file_path))
        .flatten();
    let _guard = lock::lock_chatgpt_credential(&selvedge_home).await?;
    let auth_file = auth_file::load(&auth_file_path)?;
    let access_token_expired = access_token_is_expired(&auth_file.tokens.access_token);
    let id_token_requires_refresh = id_token_requires_refresh(&auth_file);
    let auth_became_usable_while_waiting =
        refresh_hint.as_ref().is_some_and(|previous_auth_file| {
            let tokens_changed = token_sets_differ(previous_auth_file, &auth_file);
            let access_token_changed =
                previous_auth_file.tokens.access_token != auth_file.tokens.access_token;

            if !tokens_changed || should_refresh(&auth_file, access_token_expired) {
                return false;
            }

            if force_refresh {
                return access_token_changed;
            }

            true
        });

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
        id_token_requires_refresh,
    )
    .await?;
    let refreshed_file = ChatgptAuthFile {
        schema_version: 1,
        provider: "chatgpt".to_owned(),
        credential_kind: "login".to_owned(),
        tokens: refreshed_tokens,
    };
    let resolved =
        build_resolved_auth_from_refresh(&refreshed_file, config.expected_workspace_id.as_deref())?;

    auth_file::persist(&auth_file_path, &refreshed_file.tokens)?;

    Ok(resolved)
}

// @behavior selvedge.auth.resolve.refresh_decision Auth resolution refreshes when the access token is expired or the id token cannot be parsed.
fn should_refresh(auth_file: &ChatgptAuthFile, access_token_expired: bool) -> bool {
    if access_token_expired {
        return true;
    }

    id_token_requires_refresh(auth_file)
}

// @constraint selvedge.auth.resolve.id_token_account A local id token that cannot be parsed requires refresh before credentials are returned.
fn id_token_requires_refresh(auth_file: &ChatgptAuthFile) -> bool {
    parse_chatgpt_jwt_claims(&auth_file.tokens.id_token).is_err()
}

// @constraint selvedge.auth.resolve.access_expiration JWT access tokens at or before their expiration time require refresh before provider use.
fn access_token_is_expired(access_token: &str) -> bool {
    let claims = match parse_chatgpt_jwt_claims(access_token) {
        Ok(claims) => claims,
        Err(_) if !jwt::header_indicates_jwt(access_token) => return false,
        Err(_) => return true,
    };
    let Some(expires_at) = claims.expires_at else {
        return false;
    };

    expires_at <= chrono::Utc::now()
}

// @behavior selvedge.auth.resolve.existing Existing auth files with valid id token claims produce caller-visible access token and account metadata.
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

// @behavior selvedge.auth.resolve.refreshed Refreshed auth tokens with valid id token claims produce caller-visible access token and account metadata before persistence.
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

// @behavior selvedge.auth.resolve.workspace Resolved ChatGPT auth rejects missing or different account IDs when expected workspace is configured.
fn build_resolved_auth(
    auth_file: &ChatgptAuthFile,
    expected_workspace_id: Option<&str>,
    id_token_claims: ChatgptJwtClaims,
) -> Result<ResolvedChatgptAuth, ChatgptAuthError> {
    if let Some(expected_workspace_id) = expected_workspace_id
        && id_token_claims.account_id.as_deref() != Some(expected_workspace_id)
    {
        // @behavior selvedge.auth.resolve.workspace_mismatch Workspace mismatches are returned as caller-visible auth errors with expected and actual account IDs.
        return Err(ChatgptAuthError::WorkspaceMismatch {
            expected: expected_workspace_id.to_owned(),
            actual: id_token_claims.account_id,
        });
    }

    Ok(ResolvedChatgptAuth {
        access_token: auth_file.tokens.access_token.clone(),
        access_token_expires_at: access_token_expiration(&auth_file.tokens.access_token),
        account_id: id_token_claims.account_id,
        user_id: id_token_claims.user_id,
        email: id_token_claims.email,
        plan_type: id_token_claims.plan_type,
    })
}

// @behavior selvedge.auth.resolve.access_expires_at Caller-visible resolved auth includes an access-token expiration only when the access token exposes a valid JWT expiration.
fn access_token_expiration(access_token: &str) -> Option<chrono::DateTime<chrono::Utc>> {
    parse_chatgpt_jwt_claims(access_token)
        .ok()
        .and_then(|claims| claims.expires_at)
}

// @constraint selvedge.auth.resolve.concurrent_reuse Waiting callers reuse repaired auth files only after persisted token values differ from the pre-lock snapshot.
fn token_sets_differ(previous: &ChatgptAuthFile, current: &ChatgptAuthFile) -> bool {
    previous.tokens.id_token != current.tokens.id_token
        || previous.tokens.access_token != current.tokens.access_token
        || previous.tokens.refresh_token != current.tokens.refresh_token
}
