use base64::Engine;
use chrono::TimeZone;
use serde_json::Value;

use crate::{ChatgptJwtClaims, JwtParseError};

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

pub(crate) fn header_indicates_jwt(token: &str) -> bool {
    let mut segments = token.split('.');
    let Ok(header) = read_segment(segments.next()) else {
        return false;
    };
    let Ok(header_object) = decode_json_object_segment(header) else {
        return false;
    };

    header_object
        .get("typ")
        .and_then(Value::as_str)
        .is_some_and(|value| value.eq_ignore_ascii_case("jwt"))
}

fn read_segment(segment: Option<&str>) -> Result<&str, JwtParseError> {
    match segment {
        Some(segment) if !segment.is_empty() => Ok(segment),
        _ => Err(JwtParseError::InvalidFormat),
    }
}

fn decode_json_object_segment(
    segment: &str,
) -> Result<serde_json::Map<String, Value>, JwtParseError> {
    let decoded = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(segment)
        .map_err(|_| JwtParseError::InvalidBase64)?;
    let value: Value = serde_json::from_slice(&decoded).map_err(|_| JwtParseError::InvalidJson)?;

    value.as_object().cloned().ok_or(JwtParseError::InvalidJson)
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
