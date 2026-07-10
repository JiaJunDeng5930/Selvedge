use http::HeaderMap;
use serde::Deserialize;

use crate::{ChatgptLoginError, config::ChatgptAuthConfig};

#[derive(Clone, Debug)]
pub(crate) struct TokenSet {
    pub id_token: String,
    pub access_token: String,
    pub refresh_token: String,
}

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

#[derive(Debug, Deserialize)]
struct TokenExchangeResponse {
    id_token: Option<String>,
    access_token: Option<String>,
    refresh_token: Option<String>,
}
