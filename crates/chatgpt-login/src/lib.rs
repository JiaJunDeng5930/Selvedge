#![doc = include_str!("../README.md")]
#![allow(clippy::result_large_err)]

mod auth_file;
mod config;
mod device_code;
mod id_token;
mod token_exchange;

use std::{path::PathBuf, time::Duration};

#[derive(Clone, Debug)]
pub struct DeviceCodeChallenge {
    pub verification_url: String,
    pub user_code: String,
    pub device_auth_id: String,
    pub poll_interval: Duration,
    pub issued_at: chrono::DateTime<chrono::Utc>,
    pub expires_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Clone, Debug)]
pub enum DeviceCodePollOutcome {
    Pending { next_poll_after: Duration },
    Authorized(DeviceCodeAuthorization),
    Expired,
}

#[derive(Clone, Debug)]
pub struct DeviceCodeAuthorization {
    pub authorization_code: String,
    pub code_verifier: String,
}

#[derive(Clone, Debug)]
pub struct ChatgptLoginResult {
    pub auth_file_path: PathBuf,
    pub account_id: String,
    pub user_id: Option<String>,
    pub email: Option<String>,
    pub plan_type: Option<String>,
}

#[derive(Debug)]
pub enum ChatgptLoginError {
    Config(selvedge_config::ConfigError),
    Transport(selvedge_client::HttpError),
    DeviceCodeUnsupported,
    DeviceCodeStartRejected {
        status: u16,
        body: Option<String>,
    },
    DeviceCodeStartInvalidResponse {
        reason: String,
    },
    DeviceCodePollRejected {
        status: u16,
        body: Option<String>,
    },
    InvalidAuthorizationGrant {
        reason: String,
    },
    TokenExchangeRejected {
        status: u16,
        body: Option<String>,
    },
    InvalidTokenSet {
        reason: String,
    },
    WorkspaceMismatch {
        expected: String,
        actual: Option<String>,
    },
    ChallengeExpired,
    PersistFailed {
        path: PathBuf,
        reason: String,
    },
}

pub async fn start_device_code_login() -> Result<DeviceCodeChallenge, ChatgptLoginError> {
    let config = config::read_chatgpt_auth_config()?;

    device_code::start(&config).await
}

pub async fn poll_device_code_login(
    challenge: &DeviceCodeChallenge,
) -> Result<DeviceCodePollOutcome, ChatgptLoginError> {
    if chrono::Utc::now() >= challenge.expires_at {
        return Ok(DeviceCodePollOutcome::Expired);
    }

    let config = config::read_chatgpt_auth_config()?;

    device_code::poll(&config, challenge).await
}

pub async fn complete_device_code_login(
    challenge: &DeviceCodeChallenge,
    authorization: DeviceCodeAuthorization,
) -> Result<ChatgptLoginResult, ChatgptLoginError> {
    if chrono::Utc::now() >= challenge.expires_at {
        return Err(ChatgptLoginError::ChallengeExpired);
    }

    let config = config::read_chatgpt_auth_config()?;
    let selvedge_home = config::read_selvedge_home()?;
    let token_set = token_exchange::exchange(&config, &authorization).await?;
    let claims = id_token::parse(&token_set.id_token)?;

    if let Some(expected_workspace_id) = &config.expected_workspace_id
        && claims.account_id != *expected_workspace_id
    {
        return Err(ChatgptLoginError::WorkspaceMismatch {
            expected: expected_workspace_id.clone(),
            actual: Some(claims.account_id.clone()),
        });
    }

    let auth_file_path = auth_file::auth_file_path(&selvedge_home);
    auth_file::persist(&auth_file_path, &token_set).await?;

    Ok(auth_file::build_result(auth_file_path, claims))
}
