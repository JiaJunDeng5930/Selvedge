use base64::Engine;
use chrono::TimeZone;
use serde_json::Value;

use crate::{ChatgptJwtClaims, JwtParseError};

pub(crate) fn parse(token: &str) -> Result<ChatgptJwtClaims, JwtParseError> {
    let mut segments = token.split('.');
    let _header = read_segment(segments.next())?;
    let payload = read_segment(segments.next())?;
    let _signature = read_segment(segments.next())?;

    if segments.next().is_some() {
        return Err(JwtParseError::InvalidFormat);
    }

    let payload_bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(payload)
        .map_err(|_| JwtParseError::InvalidBase64)?;
    let payload_value: Value =
        serde_json::from_slice(&payload_bytes).map_err(|_| JwtParseError::InvalidJson)?;
    let payload_object = payload_value
        .as_object()
        .ok_or(JwtParseError::InvalidJson)?;

    Ok(ChatgptJwtClaims {
        subject: read_optional_string(payload_object.get("sub")),
        account_id: read_optional_string(
            payload_object.get("https://api.openai.com/auth.chatgpt_account_id"),
        ),
        user_id: read_optional_string(
            payload_object.get("https://api.openai.com/auth.chatgpt_user_id"),
        )
        .or_else(|| read_optional_string(payload_object.get("sub"))),
        email: read_optional_string(payload_object.get("email")),
        plan_type: read_optional_string(
            payload_object.get("https://api.openai.com/auth.chatgpt_plan_type"),
        ),
        expires_at: read_expiration(payload_object.get("exp"))?,
    })
}

fn read_segment(segment: Option<&str>) -> Result<&str, JwtParseError> {
    match segment {
        Some(segment) if !segment.is_empty() => Ok(segment),
        _ => Err(JwtParseError::InvalidFormat),
    }
}

fn read_optional_string(value: Option<&Value>) -> Option<String> {
    value
        .and_then(Value::as_str)
        .filter(|text| !text.is_empty())
        .map(ToOwned::to_owned)
}

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
