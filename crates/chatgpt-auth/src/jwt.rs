use base64::Engine;
use chrono::TimeZone;
use serde_json::Value;

use crate::{ChatgptJwtClaims, JwtParseError};

// @behavior selvedge.auth.jwt ChatGPT JWT parsing exposes account metadata and token timing information used by request authentication.
// @behavior selvedge.auth.jwt.parse.claims JWT parsing extracts ChatGPT account metadata from a three-segment token without validating signatures.
pub(crate) fn parse(token: &str) -> Result<ChatgptJwtClaims, JwtParseError> {
    let mut segments = token.split('.');
    let header = read_segment(segments.next())?;
    let payload = read_segment(segments.next())?;
    let _signature = read_segment(segments.next())?;

    if segments.next().is_some() {
        return Err(JwtParseError::InvalidFormat);
    }

    let _header_object = decode_json_object_segment(header)?;
    let payload_object = decode_json_object_segment(payload)?;
    let auth_object = payload_object
        .get("https://api.openai.com/auth")
        .and_then(Value::as_object);
    let profile_object = payload_object
        .get("https://api.openai.com/profile")
        .and_then(Value::as_object);

    Ok(ChatgptJwtClaims {
        subject: read_optional_string(payload_object.get("sub")),
        account_id: read_optional_string_from_object(auth_object, "chatgpt_account_id").or_else(
            || {
                read_optional_string(
                    payload_object.get("https://api.openai.com/auth.chatgpt_account_id"),
                )
            },
        ),
        user_id: read_optional_string_from_object(auth_object, "chatgpt_user_id")
            .or_else(|| {
                read_optional_string(
                    payload_object.get("https://api.openai.com/auth.chatgpt_user_id"),
                )
            })
            .or_else(|| read_optional_string_from_object(auth_object, "user_id"))
            .or_else(|| read_optional_string(payload_object.get("sub"))),
        email: read_optional_string(payload_object.get("email"))
            .or_else(|| read_optional_string_from_object(profile_object, "email")),
        plan_type: read_optional_string_from_object(auth_object, "chatgpt_plan_type").or_else(
            || {
                read_optional_string(
                    payload_object.get("https://api.openai.com/auth.chatgpt_plan_type"),
                )
            },
        ),
        expires_at: read_expiration(payload_object.get("exp"))?,
    })
}

// @behavior selvedge.auth.jwt.header Auth resolution treats tokens with JWT-like headers as structured tokens when deciding whether malformed access tokens require refresh.
pub(crate) fn header_indicates_jwt(token: &str) -> bool {
    let mut segments = token.split('.');
    let Ok(header) = read_segment(segments.next()) else {
        return false;
    };
    let Ok(header_object) = decode_json_object_segment(header) else {
        return false;
    };

    if header_object
        .get("typ")
        .and_then(Value::as_str)
        .is_some_and(|value| value.eq_ignore_ascii_case("jwt"))
    {
        return true;
    }

    header_object.contains_key("alg") && !header_object.contains_key("enc")
}

// @constraint selvedge.auth.jwt.segments JWT parsing requires exactly three nonempty token segments before exposing claims.
fn read_segment(segment: Option<&str>) -> Result<&str, JwtParseError> {
    match segment {
        Some(segment) if !segment.is_empty() => Ok(segment),
        _ => Err(JwtParseError::InvalidFormat),
    }
}

// @constraint selvedge.auth.jwt.json JWT header and payload segments must decode to JSON objects before claims are returned.
fn decode_json_object_segment(
    segment: &str,
) -> Result<serde_json::Map<String, Value>, JwtParseError> {
    let decoded = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(segment)
        .map_err(|_| JwtParseError::InvalidBase64)?;
    let value: Value = serde_json::from_slice(&decoded).map_err(|_| JwtParseError::InvalidJson)?;

    value.as_object().cloned().ok_or(JwtParseError::InvalidJson)
}

// @constraint selvedge.auth.jwt.optional_string Empty JWT string claims are omitted from caller-visible auth metadata.
fn read_optional_string(value: Option<&Value>) -> Option<String> {
    value
        .and_then(Value::as_str)
        .filter(|text| !text.is_empty())
        .map(ToOwned::to_owned)
}

fn read_optional_string_from_object(
    object: Option<&serde_json::Map<String, Value>>,
    field: &str,
) -> Option<String> {
    read_optional_string(object.and_then(|object| object.get(field)))
}

// @constraint selvedge.auth.jwt.expiration JWT expiration claims must be valid Unix timestamps before request auth exposes an expiration time.
fn read_expiration(
    value: Option<&Value>,
) -> Result<Option<chrono::DateTime<chrono::Utc>>, JwtParseError> {
    let Some(value) = value else {
        return Ok(None);
    };
    let seconds = value.as_i64().ok_or(JwtParseError::InvalidExpiration)?;
    let timestamp = chrono::Utc
        .timestamp_opt(seconds, 0)
        .single()
        .ok_or(JwtParseError::InvalidExpiration)?;

    Ok(Some(timestamp))
}
