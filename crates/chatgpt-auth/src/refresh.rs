use http::HeaderMap;
use serde::Deserialize;
use serde_json::Value;

use crate::{ChatgptAuthError, ChatgptStoredTokens, config::ChatgptAuthConfig};

pub(crate) async fn refresh(
    config: &ChatgptAuthConfig,
    current_tokens: &ChatgptStoredTokens,
) -> Result<ChatgptStoredTokens, ChatgptAuthError> {
    let response = selvedge_client::execute(selvedge_client::HttpRequest {
        method: selvedge_client::HttpMethod::Post,
        url: format!("{}/oauth/token", config.issuer),
        headers: HeaderMap::new(),
        body: selvedge_client::HttpRequestBody::Json(serde_json::json!({
            "client_id": config.client_id,
            "grant_type": "refresh_token",
            "refresh_token": current_tokens.refresh_token,
        })),
        timeout: None,
        compression: selvedge_client::RequestCompression::None,
    })
    .await
    .map_err(map_transport_error)?;

    let payload: RefreshResponse = serde_json::from_slice(&response.body)
        .map_err(|_| invalid_success_response(response.status.as_u16(), None))?;
    let merged = merge_tokens(current_tokens, payload)?;

    Ok(merged)
}

fn map_transport_error(error: selvedge_client::HttpError) -> ChatgptAuthError {
    match error {
        selvedge_client::HttpError::Status(status_error) => {
            let diagnostics = extract_error_diagnostics(&status_error.body);

            if status_error.status.as_u16() == 401 {
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

fn merge_tokens(
    current_tokens: &ChatgptStoredTokens,
    response: RefreshResponse,
) -> Result<ChatgptStoredTokens, ChatgptAuthError> {
    let id_token = merge_token_value(response.id_token, &current_tokens.id_token, "id_token")?;
    let access_token = merge_token_value(
        response.access_token,
        &current_tokens.access_token,
        "access_token",
    )?;
    let refresh_token = merge_token_value(
        response.refresh_token,
        &current_tokens.refresh_token,
        "refresh_token",
    )?;

    Ok(ChatgptStoredTokens {
        id_token,
        access_token,
        refresh_token,
    })
}

fn merge_token_value(
    response_value: Option<Value>,
    current_value: &str,
    field: &str,
) -> Result<String, ChatgptAuthError> {
    let Some(value) = response_value else {
        return Ok(current_value.to_owned());
    };
    let token = value
        .as_str()
        .ok_or_else(|| invalid_success_response(200, None))?;

    if token.is_empty() {
        return Err(invalid_success_response(200, None));
    }

    let _ = field;

    Ok(token.to_owned())
}

fn invalid_success_response(
    status: u16,
    diagnostics: Option<ProviderErrorDiagnostics>,
) -> ChatgptAuthError {
    let diagnostics = diagnostics.unwrap_or_default();

    ChatgptAuthError::RefreshFailed {
        status: Some(status),
        provider_code: diagnostics.provider_code,
        provider_message: diagnostics.provider_message,
    }
}

fn extract_error_diagnostics(body: &[u8]) -> ProviderErrorDiagnostics {
    let Ok(value) = serde_json::from_slice::<Value>(body) else {
        return ProviderErrorDiagnostics::default();
    };
    let Some(object) = value.as_object() else {
        return ProviderErrorDiagnostics::default();
    };

    ProviderErrorDiagnostics {
        provider_code: read_string_field(object, &["provider_code", "code", "error"]),
        provider_message: read_string_field(
            object,
            &["provider_message", "message", "error_description"],
        ),
    }
}

fn read_string_field(object: &serde_json::Map<String, Value>, names: &[&str]) -> Option<String> {
    names.iter().find_map(|name| {
        object
            .get(*name)
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned)
    })
}

#[derive(Debug, Default)]
struct ProviderErrorDiagnostics {
    provider_code: Option<String>,
    provider_message: Option<String>,
}

#[derive(Debug, Deserialize)]
struct RefreshResponse {
    #[serde(default)]
    id_token: Option<Value>,
    #[serde(default)]
    access_token: Option<Value>,
    #[serde(default)]
    refresh_token: Option<Value>,
}
