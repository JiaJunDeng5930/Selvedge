use std::time::Duration;

use chrono::Utc;
use http::HeaderMap;
use serde::Deserialize;
use serde_json::json;

use crate::{ChatgptLoginError, DeviceCodeChallenge, config::ChatgptAuthConfig};

// @behavior selvedge.login.start.request Starting device-code login posts the client ID to the configured issuer device-code endpoint.
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
    // @behavior selvedge.login.start.transport Device-code start transport failures are mapped into caller-visible ChatGPT login errors.
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
            // @constraint selvedge.login.start.user_code Device-code start responses must include a nonempty user code before a challenge is returned.
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

// @behavior selvedge.login.poll.request Polling device-code login posts the challenge identifiers to the configured issuer token endpoint once.
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
        // @behavior selvedge.login.poll.authorized Polling device-code login decodes successful provider responses into authorization grants or invalid-grant errors.
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
        // @behavior selvedge.login.poll.pending Polling device-code login maps provider 403 and 404 status responses to a pending outcome.
        Err(selvedge_client::HttpError::Status(status_error))
            if matches!(status_error.status.as_u16(), 403 | 404) =>
        {
            // The public contract treats both 403 and 404 as "still pending".
            Ok(crate::DeviceCodePollOutcome::Pending {
                next_poll_after: challenge.poll_interval,
            })
        }
        // @behavior selvedge.login.poll.rejected Polling device-code login reports provider status rejections with status and response body.
        Err(selvedge_client::HttpError::Status(status_error)) => {
            Err(ChatgptLoginError::DeviceCodePollRejected {
                status: status_error.status.as_u16(),
                body: status_body(&status_error.body),
            })
        }
        // @behavior selvedge.login.poll.transport Polling device-code login reports transport failures as caller-visible transport errors.
        Err(other) => Err(ChatgptLoginError::Transport(other)),
    }
}

// @behavior selvedge.login.start.error_status Device-code start maps provider 404 to unsupported and other status responses to caller-visible start rejection details.
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

// @constraint selvedge.login.start.required_fields Device-code start responses must contain nonempty challenge fields before a challenge is returned.
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

// @behavior selvedge.login.provider_body Provider status response bodies are exposed as lossy UTF-8 text when a login error includes a body.
fn status_body(body: &[u8]) -> Option<String> {
    if body.is_empty() {
        return None;
    }

    Some(String::from_utf8_lossy(body).into_owned())
}

// @constraint selvedge.login.poll.required_fields Authorized poll responses must contain nonempty authorization_code and code_verifier values.
fn read_poll_field(value: Option<String>, field_name: &str) -> Result<String, ChatgptLoginError> {
    match value {
        Some(value) if !value.is_empty() => Ok(value),
        _ => Err(ChatgptLoginError::InvalidAuthorizationGrant {
            reason: format!("poll response missing {field_name}"),
        }),
    }
}

// @intent selvedge.login.start.response The provider start response adapter accepts known challenge field spellings before public challenge construction.
#[derive(Debug, Deserialize)]
struct StartDeviceCodeResponse {
    device_auth_id: Option<String>,
    user_code: Option<String>,
    usercode: Option<String>,
    interval: Option<IntervalValue>,
}

// @intent selvedge.login.poll.response The provider poll response adapter carries authorization fields into the public authorized outcome.
#[derive(Debug, Deserialize)]
struct PollDeviceCodeResponse {
    authorization_code: Option<String>,
    code_verifier: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
// @constraint selvedge.login.start.interval_value Device-code start accepts string or numeric provider poll interval values before returning a caller-visible challenge.
enum IntervalValue {
    String(String),
    Number(u64),
}

// @constraint selvedge.login.start.interval Device-code start responses must provide a positive poll interval before a challenge is returned.
impl IntervalValue {
    fn into_u64(self) -> Result<u64, ChatgptLoginError> {
        match self {
            Self::String(value) => {
                // @constraint selvedge.login.start.interval_string String poll interval values must parse as seconds before a challenge is returned.
                validate_interval_seconds(value.parse::<u64>().map_err(|error| {
                    ChatgptLoginError::DeviceCodeStartInvalidResponse {
                        reason: format!("start response interval is invalid: {error}"),
                    }
                })?)
            }
            Self::Number(value) => validate_interval_seconds(value),
        }
    }
}

// @constraint selvedge.login.start.interval_positive Device-code poll intervals returned to callers must be greater than zero seconds.
fn validate_interval_seconds(value: u64) -> Result<u64, ChatgptLoginError> {
    if value == 0 {
        return Err(ChatgptLoginError::DeviceCodeStartInvalidResponse {
            reason: "start response interval must be greater than zero".to_owned(),
        });
    }

    Ok(value)
}
