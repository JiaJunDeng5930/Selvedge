use base64::Engine;
use serde::Deserialize;

use crate::ChatgptLoginError;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ParsedIdToken {
    pub account_id: String,
    pub user_id: Option<String>,
    pub email: Option<String>,
    pub plan_type: Option<String>,
}

pub(crate) fn parse(id_token: &str) -> Result<ParsedIdToken, ChatgptLoginError> {
    let mut segments = id_token.split('.');
    let _header = segments.next();
    let payload = segments
        .next()
        .ok_or_else(|| ChatgptLoginError::InvalidTokenSet {
            reason: "id_token must contain a payload segment".to_owned(),
        })?;
    let _signature = segments
        .next()
        .ok_or_else(|| ChatgptLoginError::InvalidTokenSet {
            reason: "id_token must contain a signature segment".to_owned(),
        })?;

    if segments.next().is_some() {
        return Err(ChatgptLoginError::InvalidTokenSet {
            reason: "id_token must contain exactly three segments".to_owned(),
        });
    }

    let payload = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(payload)
        .map_err(|error| ChatgptLoginError::InvalidTokenSet {
            reason: format!("id_token payload is not valid base64url: {error}"),
        })?;
    let claims: IdTokenClaims =
        serde_json::from_slice(&payload).map_err(|error| ChatgptLoginError::InvalidTokenSet {
            reason: format!("id_token payload is not valid json: {error}"),
        })?;
    let account_id = match claims.account_id {
        Some(account_id) if !account_id.is_empty() => account_id,
        _ => {
            return Err(ChatgptLoginError::InvalidTokenSet {
                reason: "id_token missing account_id".to_owned(),
            });
        }
    };
    let user_id = match claims.chatgpt_user_id {
        Some(user_id) if !user_id.is_empty() => Some(user_id),
        _ => claims.sub.filter(|sub| !sub.is_empty()),
    };

    Ok(ParsedIdToken {
        account_id,
        user_id,
        email: claims.email.filter(|email| !email.is_empty()),
        plan_type: claims.plan_type.filter(|plan_type| !plan_type.is_empty()),
    })
}

#[derive(Debug, Deserialize)]
struct IdTokenClaims {
    #[serde(rename = "https://api.openai.com/auth.chatgpt_account_id")]
    account_id: Option<String>,
    #[serde(rename = "https://api.openai.com/auth.chatgpt_user_id")]
    chatgpt_user_id: Option<String>,
    #[serde(rename = "https://api.openai.com/auth.chatgpt_plan_type")]
    plan_type: Option<String>,
    sub: Option<String>,
    email: Option<String>,
}
