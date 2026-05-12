use http::HeaderMap;
use serde::Deserialize;

use crate::{ChatgptLoginError, config::ChatgptAuthConfig};

// @behavior selvedge.login.token_exchange Completed ChatGPT login exchanges provider authorization for tokens before local persistence.
// @behavior selvedge.login.token_exchange.tokens Successful authorization exchange returns id, access, and refresh tokens for persistence.
#[derive(Clone, Debug)]
pub(crate) struct TokenSet {
    // @behavior selvedge.login.token_exchange.id_token Successful authorization exchange returns the id token persisted into the ChatGPT auth file.
    pub id_token: String,
    // @behavior selvedge.login.token_exchange.access_token Successful authorization exchange returns the access token persisted into the ChatGPT auth file.
    pub access_token: String,
    // @behavior selvedge.login.token_exchange.refresh_token Successful authorization exchange returns the refresh token persisted into the ChatGPT auth file.
    pub refresh_token: String,
}

// @behavior selvedge.login.token_exchange.request Completing device-code login exchanges the authorization code and verifier at the configured issuer OAuth token endpoint.
pub(crate) async fn exchange(
    config: &ChatgptAuthConfig,
    authorization: &crate::DeviceCodeAuthorization,
) -> Result<TokenSet, ChatgptLoginError> {
    let response = selvedge_client::execute(selvedge_client::HttpRequest {
        method: selvedge_client::HttpMethod::Post,
        url: format!("{}/oauth/token", config.issuer),
        headers: HeaderMap::new(),
        body: selvedge_client::HttpRequestBody::FormUrlEncoded(vec![
            ("grant_type".to_owned(), "authorization_code".to_owned()),
            ("code".to_owned(), authorization.authorization_code.clone()),
            (
                "redirect_uri".to_owned(),
                format!("{}/deviceauth/callback", config.issuer),
            ),
            ("client_id".to_owned(), config.client_id.clone()),
            (
                "code_verifier".to_owned(),
                authorization.code_verifier.clone(),
            ),
        ]),
        timeout: None,
        compression: selvedge_client::RequestCompression::None,
    })
    .await
    // @behavior selvedge.login.token_exchange.transport Token exchange transport failures are mapped into caller-visible ChatGPT login errors.
    .map_err(map_exchange_error)?;
    let payload: TokenExchangeResponse =
        serde_json::from_slice(&response.body).map_err(|error| {
            ChatgptLoginError::InvalidTokenSet {
                reason: format!("failed to parse token response body: {error}"),
            }
        })?;

    Ok(TokenSet {
        id_token: read_required_token(payload.id_token, "id_token")?,
        access_token: read_required_token(payload.access_token, "access_token")?,
        refresh_token: read_required_token(payload.refresh_token, "refresh_token")?,
    })
}

// @behavior selvedge.login.token_exchange.error_status Token exchange status failures expose provider status and optional response body to callers.
fn map_exchange_error(error: selvedge_client::HttpError) -> ChatgptLoginError {
    match error {
        selvedge_client::HttpError::Status(status_error) => {
            ChatgptLoginError::TokenExchangeRejected {
                status: status_error.status.as_u16(),
                body: if status_error.body.is_empty() {
                    None
                } else {
                    Some(String::from_utf8_lossy(&status_error.body).into_owned())
                },
            }
        }
        other => ChatgptLoginError::Transport(other),
    }
}

// @constraint selvedge.login.token_exchange.required_tokens Token exchange success responses must contain nonempty id, access, and refresh tokens before login can complete.
fn read_required_token(
    value: Option<String>,
    field_name: &str,
) -> Result<String, ChatgptLoginError> {
    match value {
        Some(value) if !value.is_empty() => Ok(value),
        _ => Err(ChatgptLoginError::InvalidTokenSet {
            reason: format!("token response missing {field_name}"),
        }),
    }
}

// @intent selvedge.login.token_exchange.response The token exchange response adapter carries provider token fields into required token validation.
#[derive(Debug, Deserialize)]
struct TokenExchangeResponse {
    id_token: Option<String>,
    access_token: Option<String>,
    refresh_token: Option<String>,
}
