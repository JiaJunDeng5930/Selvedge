use std::time::Duration;

use chrono::Utc;
use http::HeaderMap;
use serde::Deserialize;
use serde_json::json;

use crate::{ChatgptLoginError, DeviceCodeChallenge, config::ChatgptAuthConfig};

pub(crate) async fn start(
    config: &ChatgptAuthConfig,
) -> Result<DeviceCodeChallenge, ChatgptLoginError> {
    let response = selvedge_client::execute(selvedge_client::HttpRequest {
        method: selvedge_client::HttpMethod::Post,
        url: format!("{}/api/accounts/deviceauth/usercode", config.issuer),
        headers: HeaderMap::new(),
        body: selvedge_client::HttpRequestBody::Json(json!({
            "client_id": config.client_id,
        })),
        timeout: None,
        compression: selvedge_client::RequestCompression::None,
    })
    .await
    .map_err(map_transport_error)?;

    let payload: StartDeviceCodeResponse =
        serde_json::from_slice(&response.body).map_err(|error| {
            ChatgptLoginError::DeviceCodeStartInvalidResponse {
                reason: format!("failed to parse start response body: {error}"),
            }
        })?;
    let device_auth_id = read_required_field(payload.device_auth_id, "device_auth_id")?;
    let user_code = match (payload.user_code, payload.usercode) {
        (Some(user_code), _) if !user_code.is_empty() => user_code,
        (_, Some(usercode)) if !usercode.is_empty() => usercode,
        _ => {
            return Err(ChatgptLoginError::DeviceCodeStartInvalidResponse {
                reason: "start response missing user_code".to_owned(),
            });
        }
    };
    let interval_seconds = payload
        .interval
        .ok_or_else(|| ChatgptLoginError::DeviceCodeStartInvalidResponse {
            reason: "start response missing interval".to_owned(),
        })?
        .into_u64()?;
    let issued_at = Utc::now();

    Ok(DeviceCodeChallenge {
        verification_url: format!("{}/codex/device", config.issuer),
        user_code,
        device_auth_id,
        poll_interval: Duration::from_secs(interval_seconds),
        issued_at,
        expires_at: issued_at + chrono::Duration::minutes(15),
    })
}

pub(crate) async fn poll(
    config: &ChatgptAuthConfig,
    challenge: &DeviceCodeChallenge,
) -> Result<crate::DeviceCodePollOutcome, ChatgptLoginError> {
    let response = selvedge_client::execute(selvedge_client::HttpRequest {
        method: selvedge_client::HttpMethod::Post,
        url: format!("{}/api/accounts/deviceauth/token", config.issuer),
        headers: HeaderMap::new(),
        body: selvedge_client::HttpRequestBody::Json(json!({
            "device_auth_id": challenge.device_auth_id,
            "user_code": challenge.user_code,
        })),
        timeout: None,
        compression: selvedge_client::RequestCompression::None,
    })
    .await;

    match response {
        Ok(response) => {
            let payload: PollDeviceCodeResponse =
                serde_json::from_slice(&response.body).map_err(|error| {
                    ChatgptLoginError::InvalidAuthorizationGrant {
                        reason: format!("failed to parse poll response body: {error}"),
                    }
                })?;
            let authorization_code =
                read_poll_field(payload.authorization_code, "authorization_code")?;
            let code_verifier = read_poll_field(payload.code_verifier, "code_verifier")?;

            Ok(crate::DeviceCodePollOutcome::Authorized(
                crate::DeviceCodeAuthorization {
                    authorization_code,
                    code_verifier,
                },
            ))
        }
        Err(selvedge_client::HttpError::Status(status_error))
            if matches!(status_error.status.as_u16(), 403 | 404) =>
        {
            // The public contract treats both 403 and 404 as "still pending".
            Ok(crate::DeviceCodePollOutcome::Pending {
                next_poll_after: challenge.poll_interval,
            })
        }
        Err(selvedge_client::HttpError::Status(status_error)) => {
            Err(ChatgptLoginError::DeviceCodePollRejected {
                status: status_error.status.as_u16(),
                body: status_body(&status_error.body),
            })
        }
        Err(other) => Err(ChatgptLoginError::Transport(other)),
    }
}

fn map_transport_error(error: selvedge_client::HttpError) -> ChatgptLoginError {
    match error {
        selvedge_client::HttpError::Status(status_error) => {
            if status_error.status.as_u16() == 404 {
                return ChatgptLoginError::DeviceCodeUnsupported;
            }

            ChatgptLoginError::DeviceCodeStartRejected {
                status: status_error.status.as_u16(),
                body: status_body(&status_error.body),
            }
        }
        other => ChatgptLoginError::Transport(other),
    }
}

fn read_required_field(
    value: Option<String>,
    field_name: &str,
) -> Result<String, ChatgptLoginError> {
    match value {
        Some(value) if !value.is_empty() => Ok(value),
        _ => Err(ChatgptLoginError::DeviceCodeStartInvalidResponse {
            reason: format!("start response missing {field_name}"),
        }),
    }
}

fn status_body(body: &[u8]) -> Option<String> {
    if body.is_empty() {
        return None;
    }

    Some(String::from_utf8_lossy(body).into_owned())
}

fn read_poll_field(value: Option<String>, field_name: &str) -> Result<String, ChatgptLoginError> {
    match value {
        Some(value) if !value.is_empty() => Ok(value),
        _ => Err(ChatgptLoginError::InvalidAuthorizationGrant {
            reason: format!("poll response missing {field_name}"),
        }),
    }
}

#[derive(Debug, Deserialize)]
struct StartDeviceCodeResponse {
    device_auth_id: Option<String>,
    user_code: Option<String>,
    usercode: Option<String>,
    interval: Option<IntervalValue>,
}

#[derive(Debug, Deserialize)]
struct PollDeviceCodeResponse {
    authorization_code: Option<String>,
    code_verifier: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum IntervalValue {
    String(String),
    Number(u64),
}

impl IntervalValue {
    fn into_u64(self) -> Result<u64, ChatgptLoginError> {
        match self {
            Self::String(value) => value.parse::<u64>().map_err(|error| {
                ChatgptLoginError::DeviceCodeStartInvalidResponse {
                    reason: format!("start response interval is invalid: {error}"),
                }
            }),
            Self::Number(value) => Ok(value),
        }
    }
}
