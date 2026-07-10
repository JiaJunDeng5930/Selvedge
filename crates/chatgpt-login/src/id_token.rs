use base64::Engine;
use serde::Deserialize;

use crate::ChatgptLoginError;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ParsedIdToken {
    pub account_id: Option<String>,
    pub user_id: Option<String>,
    pub email: Option<String>,
    pub plan_type: Option<String>,
}

pub(crate) fn parse(id_token: &str) -> Result<ParsedIdToken, ChatgptLoginError> {
    let mut segments = id_token.split('.');
    let header = read_required_segment(segments.next(), "header")?;
    let payload = read_required_segment(segments.next(), "payload")?;
    let _signature = read_required_segment(segments.next(), "signature")?;

    if segments.next().is_some() {
        return Err(ChatgptLoginError::InvalidTokenSet {
            reason: "id_token must contain exactly three segments".to_owned(),
        });
    }

    let _header = decode_json_segment(header, "header")?;
    let payload = decode_json_segment(payload, "payload")?;
    let claims: IdTokenClaims =
        serde_json::from_slice(&payload).map_err(|error| ChatgptLoginError::InvalidTokenSet {
            reason: format!("id_token payload is not valid json: {error}"),
        })?;
    let auth = claims.auth.unwrap_or_default();
    let account_id = non_empty(auth.chatgpt_account_id).or_else(|| non_empty(claims.account_id));
    let user_id = non_empty(auth.chatgpt_user_id)
        .or_else(|| non_empty(claims.chatgpt_user_id))
        .or_else(|| non_empty(auth.user_id))
        .or_else(|| non_empty(claims.sub));

    Ok(ParsedIdToken {
        account_id,
        user_id,
        email: non_empty(claims.email)
            .or_else(|| claims.profile.and_then(|profile| non_empty(profile.email))),
        plan_type: non_empty(auth.chatgpt_plan_type).or_else(|| non_empty(claims.plan_type)),
    })
}

fn read_required_segment<'a>(
    segment: Option<&'a str>,
    name: &str,
) -> Result<&'a str, ChatgptLoginError> {
    match segment {
        Some(segment) if !segment.is_empty() => Ok(segment),
        _ => Err(ChatgptLoginError::InvalidTokenSet {
            reason: format!("id_token must contain a {name} segment"),
        }),
    }
}

fn decode_json_segment(segment: &str, name: &str) -> Result<Vec<u8>, ChatgptLoginError> {
    let decoded = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(segment)
        .map_err(|error| ChatgptLoginError::InvalidTokenSet {
            reason: format!("id_token {name} is not valid base64url: {error}"),
        })?;
    let value: serde_json::Value =
        serde_json::from_slice(&decoded).map_err(|error| ChatgptLoginError::InvalidTokenSet {
            reason: format!("id_token {name} is not valid json: {error}"),
        })?;

    if !value.is_object() {
        return Err(ChatgptLoginError::InvalidTokenSet {
            reason: format!("id_token {name} must be a json object"),
        });
    }

    Ok(decoded)
}

#[derive(Debug, Deserialize)]
struct IdTokenClaims {
    #[serde(rename = "https://api.openai.com/auth", default)]
    auth: Option<AuthClaims>,
    #[serde(rename = "https://api.openai.com/auth.chatgpt_account_id")]
    account_id: Option<String>,
    #[serde(rename = "https://api.openai.com/auth.chatgpt_user_id")]
    chatgpt_user_id: Option<String>,
    #[serde(rename = "https://api.openai.com/auth.chatgpt_plan_type")]
    plan_type: Option<String>,
    #[serde(rename = "https://api.openai.com/profile", default)]
    profile: Option<ProfileClaims>,
    sub: Option<String>,
    email: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
struct AuthClaims {
    #[serde(default)]
    chatgpt_account_id: Option<String>,
    #[serde(default)]
    chatgpt_user_id: Option<String>,
    #[serde(default)]
    user_id: Option<String>,
    #[serde(default)]
    chatgpt_plan_type: Option<String>,
}

#[derive(Debug, Deserialize)]
struct ProfileClaims {
    #[serde(default)]
    email: Option<String>,
}

fn non_empty(value: Option<String>) -> Option<String> {
    value.filter(|value| !value.is_empty())
}
