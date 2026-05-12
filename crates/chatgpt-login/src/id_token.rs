use base64::Engine;
use serde::Deserialize;

use crate::ChatgptLoginError;

// @behavior selvedge.login.id_token Completed ChatGPT login reads account metadata from the provider id token before persisting auth state.
// @behavior selvedge.login.id_token.claims Completed login exposes ChatGPT account ID, user ID, email, and plan claims parsed from the id token.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ParsedIdToken {
    // @behavior selvedge.login.id_token.account_id Completed login returns and validates the ChatGPT account ID parsed from the id token.
    pub account_id: String,
    // @behavior selvedge.login.id_token.user_id Completed login returns the ChatGPT user ID parsed from the id token when present.
    pub user_id: Option<String>,
    // @behavior selvedge.login.id_token.email Completed login returns the email parsed from the id token when present.
    pub email: Option<String>,
    // @behavior selvedge.login.id_token.plan_type Completed login returns the plan type parsed from the id token when present.
    pub plan_type: Option<String>,
}

// @behavior selvedge.login.id_token.parse Completed login parses the id token payload and rejects token sets without a nonempty ChatGPT account ID.
pub(crate) fn parse(id_token: &str) -> Result<ParsedIdToken, ChatgptLoginError> {
    let mut segments = id_token.split('.');
    let header = read_required_segment(segments.next(), "header")?;
    let payload = read_required_segment(segments.next(), "payload")?;
    let _signature = read_required_segment(segments.next(), "signature")?;

    if segments.next().is_some() {
        // @constraint selvedge.login.id_token.extra_segments Completed login rejects id tokens with more than three JWT segments.
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
    let account_id = match claims.account_id {
        Some(account_id) if !account_id.is_empty() => account_id,
        _ => {
            // @constraint selvedge.login.id_token.account_required Completed login requires a nonempty ChatGPT account ID before credentials are persisted.
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

// @constraint selvedge.login.id_token.segments Completed login requires id tokens to contain exactly three nonempty segments before claims are accepted.
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

// @constraint selvedge.login.id_token.json Completed login requires id token header and payload segments to decode as JSON objects.
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
        // @constraint selvedge.login.id_token.object Completed login requires decoded id token segments to be JSON objects.
        return Err(ChatgptLoginError::InvalidTokenSet {
            reason: format!("id_token {name} must be a json object"),
        });
    }

    Ok(decoded)
}

// @intent selvedge.login.id_token.claim_adapter The id token claim adapter maps provider claim names into the login result fields.
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
