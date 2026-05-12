use http::HeaderMap;
use serde::Deserialize;
use serde_json::Value;

use crate::{
    ChatgptAuthError, ChatgptStoredTokens, config::ChatgptAuthConfig, jwt, parse_chatgpt_jwt_claims,
};

// @behavior selvedge.auth.refresh ChatGPT auth refresh obtains provider replacement tokens and maps refresh failures into caller-visible auth errors.
// @behavior selvedge.auth.refresh.request Token refresh sends the current refresh token to the configured issuer OAuth token endpoint as form data.
pub(crate) async fn refresh(
    config: &ChatgptAuthConfig,
    current_tokens: &ChatgptStoredTokens,
    require_replacement_access_token: bool,
    require_new_id_token: bool,
) -> Result<ChatgptStoredTokens, ChatgptAuthError> {
    let response = selvedge_client::execute(selvedge_client::HttpRequest {
        method: selvedge_client::HttpMethod::Post,
        url: format!("{}/oauth/token", config.issuer),
        headers: HeaderMap::new(),
        body: selvedge_client::HttpRequestBody::FormUrlEncoded(vec![
            ("client_id".to_owned(), config.client_id.clone()),
            ("grant_type".to_owned(), "refresh_token".to_owned()),
            (
                "refresh_token".to_owned(),
                current_tokens.refresh_token.clone(),
            ),
        ]),
        timeout: None,
        compression: selvedge_client::RequestCompression::None,
    })
    .await
    // @behavior selvedge.auth.refresh.transport Refresh transport failures are mapped into caller-visible ChatGPT auth errors.
    .map_err(map_transport_error)?;

    let payload: Value =
        // @behavior selvedge.auth.refresh.success_json Refresh success bodies that are invalid JSON are returned as refresh failures.
        serde_json::from_slice(&response.body).map_err(|_| invalid_success_response(200, None))?;
    let diagnostics = extract_error_diagnostics_value(&payload);
    let response_body: RefreshResponse = serde_json::from_value(payload)
        // @behavior selvedge.auth.refresh.success_shape Refresh success JSON that cannot decode as a token response is returned as a refresh failure.
        .map_err(|_| invalid_success_response(200, diagnostics.clone()))?;

    merge_tokens(
        current_tokens,
        response_body,
        require_replacement_access_token,
        require_new_id_token,
        diagnostics,
    )
}

// @behavior selvedge.auth.refresh.error_status Refresh HTTP status failures expose provider diagnostics and map reauthentication codes to reauthentication-required errors.
fn map_transport_error(error: selvedge_client::HttpError) -> ChatgptAuthError {
    match error {
        selvedge_client::HttpError::Status(status_error) => {
            let diagnostics = extract_error_diagnostics(&status_error.body);

            if diagnostics
                .provider_code
                .as_deref()
                .is_some_and(is_reauthentication_code)
            {
                return ChatgptAuthError::ReauthenticationRequired {
                    provider_code: diagnostics.provider_code,
                    provider_message: diagnostics.provider_message,
                };
            }

            ChatgptAuthError::RefreshFailed {
                status: Some(status_error.status.as_u16()),
                provider_code: diagnostics.provider_code,
                provider_message: diagnostics.provider_message,
            }
        }
        other => ChatgptAuthError::Transport(other),
    }
}

// @constraint selvedge.auth.refresh.reauthentication_codes Provider codes that invalidate refresh credentials require user reauthentication.
fn is_reauthentication_code(code: &str) -> bool {
    matches!(
        code,
        "invalid_grant"
            | "refresh_token_expired"
            | "refresh_token_reused"
            | "refresh_token_invalidated"
    )
}

// @behavior selvedge.auth.refresh.merge Successful refresh responses update returned token values while retaining omitted reusable tokens.
fn merge_tokens(
    current_tokens: &ChatgptStoredTokens,
    response: RefreshResponse,
    require_replacement_access_token: bool,
    require_new_id_token: bool,
    diagnostics: Option<ProviderErrorDiagnostics>,
) -> Result<ChatgptStoredTokens, ChatgptAuthError> {
    let id_token = merge_id_token_value(
        response.id_token,
        &current_tokens.id_token,
        require_new_id_token,
        diagnostics.clone(),
    )?;
    let access_token = merge_access_token_value(
        response.access_token,
        &current_tokens.access_token,
        require_replacement_access_token,
        diagnostics.clone(),
    )?;
    let refresh_token = merge_token_value(
        response.refresh_token,
        &current_tokens.refresh_token,
        diagnostics,
    )?;

    Ok(ChatgptStoredTokens {
        id_token,
        access_token,
        refresh_token,
    })
}

// @constraint selvedge.auth.refresh.merge_optional Optional refresh response token fields must be nonempty strings when the provider includes them.
fn merge_token_value(
    response_value: Option<Value>,
    current_value: &str,
    diagnostics: Option<ProviderErrorDiagnostics>,
) -> Result<String, ChatgptAuthError> {
    let Some(value) = response_value else {
        return Ok(current_value.to_owned());
    };
    let token = value
        .as_str()
        .ok_or_else(|| invalid_success_response(200, diagnostics.clone()))?;

    if token.is_empty() {
        // @constraint selvedge.auth.refresh.merge_optional.empty Empty optional token values from refresh success responses are rejected before credentials are returned.
        return Err(invalid_success_response(200, diagnostics));
    }

    Ok(token.to_owned())
}

// @constraint selvedge.auth.refresh.access_token Required replacement access tokens must be new, nonempty, and usable before auth state is persisted.
fn merge_access_token_value(
    response_value: Option<Value>,
    current_value: &str,
    require_replacement_access_token: bool,
    diagnostics: Option<ProviderErrorDiagnostics>,
) -> Result<String, ChatgptAuthError> {
    let Some(value) = response_value else {
        if require_replacement_access_token {
            // @constraint selvedge.auth.refresh.access_token.required Required replacement access tokens must be present in refresh success responses.
            return Err(invalid_success_response(200, diagnostics));
        }

        return Ok(current_value.to_owned());
    };
    let token = value
        .as_str()
        .ok_or_else(|| invalid_success_response(200, diagnostics.clone()))?;

    if token.is_empty() {
        // @constraint selvedge.auth.refresh.access_token.empty Replacement access tokens must contain a value before credentials are returned.
        return Err(invalid_success_response(200, diagnostics.clone()));
    }

    if require_replacement_access_token && token == current_value {
        // @constraint selvedge.auth.refresh.access_token.changed Forced refresh requires a replacement access token that differs from the stored token.
        return Err(invalid_success_response(200, diagnostics));
    }

    if !access_token_is_usable(token) {
        // @constraint selvedge.auth.refresh.access_token.usable Replacement access tokens must be opaque or valid unexpired JWTs before credentials are returned.
        return Err(invalid_success_response(200, diagnostics));
    }

    Ok(token.to_owned())
}

// @constraint selvedge.auth.refresh.id_token Required replacement id tokens must be nonempty before auth state is returned or persisted.
fn merge_id_token_value(
    response_value: Option<Value>,
    current_value: &str,
    require_new_id_token: bool,
    diagnostics: Option<ProviderErrorDiagnostics>,
) -> Result<String, ChatgptAuthError> {
    let Some(value) = response_value else {
        if require_new_id_token {
            // @constraint selvedge.auth.refresh.id_token.required Required replacement id tokens must be present in refresh success responses.
            return Err(invalid_success_response(200, diagnostics));
        }

        return Ok(current_value.to_owned());
    };
    let token = value
        .as_str()
        .ok_or_else(|| invalid_success_response(200, diagnostics.clone()))?;

    if token.is_empty() {
        // @constraint selvedge.auth.refresh.id_token.empty Replacement id tokens must contain a value before credentials are returned.
        return Err(invalid_success_response(200, diagnostics));
    }

    Ok(token.to_owned())
}

// @behavior selvedge.auth.refresh.invalid_success Invalid OAuth success bodies surface as refresh failures or reauthentication-required errors with provider diagnostics.
fn invalid_success_response(
    status: u16,
    diagnostics: Option<ProviderErrorDiagnostics>,
) -> ChatgptAuthError {
    let diagnostics = diagnostics.unwrap_or_default();

    if diagnostics
        .provider_code
        .as_deref()
        .is_some_and(is_reauthentication_code)
    {
        return ChatgptAuthError::ReauthenticationRequired {
            provider_code: diagnostics.provider_code,
            provider_message: diagnostics.provider_message,
        };
    }

    ChatgptAuthError::RefreshFailed {
        status: Some(status),
        provider_code: diagnostics.provider_code,
        provider_message: diagnostics.provider_message,
    }
}

// @behavior selvedge.auth.refresh.diagnostics Refresh errors expose provider code and message fields from JSON response bodies when present.
fn extract_error_diagnostics(body: &[u8]) -> ProviderErrorDiagnostics {
    let Ok(value) = serde_json::from_slice::<Value>(body) else {
        return ProviderErrorDiagnostics::default();
    };

    extract_error_diagnostics_value(&value).unwrap_or_default()
}

// @behavior selvedge.auth.refresh.diagnostics_value Refresh success and error payloads can carry provider diagnostics that shape caller-visible auth errors.
fn extract_error_diagnostics_value(value: &Value) -> Option<ProviderErrorDiagnostics> {
    let object = value.as_object()?;

    Some(ProviderErrorDiagnostics {
        provider_code: read_string_field(object, &["provider_code", "code", "error"]),
        provider_message: read_string_field(
            object,
            &["provider_message", "message", "error_description"],
        ),
    })
}

// @constraint selvedge.auth.refresh.diagnostics_fields Empty provider diagnostic strings are omitted from caller-visible refresh errors.
fn read_string_field(object: &serde_json::Map<String, Value>, names: &[&str]) -> Option<String> {
    names.iter().find_map(|name| {
        object
            .get(*name)
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned)
    })
}

// @constraint selvedge.auth.refresh.access_usable Refresh responses may return opaque access tokens, and JWT access tokens must be unexpired.
fn access_token_is_usable(token: &str) -> bool {
    match parse_chatgpt_jwt_claims(token) {
        Ok(claims) => claims
            .expires_at
            .is_none_or(|expires_at| expires_at > chrono::Utc::now()),
        Err(_) => !jwt::header_indicates_jwt(token),
    }
}

// @intent selvedge.auth.refresh.diagnostics_struct Provider diagnostics carry provider-authored refresh failure details into public error variants.
#[derive(Clone, Debug, Default)]
struct ProviderErrorDiagnostics {
    provider_code: Option<String>,
    provider_message: Option<String>,
}

// @intent selvedge.auth.refresh.response Refresh response decoding accepts provider token fields while preserving response validation in merge logic.
#[derive(Debug, Deserialize)]
struct RefreshResponse {
    #[serde(default)]
    id_token: Option<Value>,
    #[serde(default)]
    access_token: Option<Value>,
    #[serde(default)]
    refresh_token: Option<Value>,
}
