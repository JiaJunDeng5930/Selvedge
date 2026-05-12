#![doc = include_str!("../README.md")]
#![allow(clippy::result_large_err)]
//! @behavior selvedge.login ChatGPT device-code login starts provider challenges, polls authorization, exchanges grants, and persists local auth state.

mod auth_file;
mod config;
mod device_code;
mod id_token;
mod token_exchange;

use std::{path::PathBuf, time::Duration};

/// @behavior selvedge.login.challenge Starting device-code login returns the verification URL, user code, device auth ID, poll interval, issue time, and expiry time visible to callers.
#[derive(Clone, Debug)]
pub struct DeviceCodeChallenge {
    /// @behavior selvedge.login.challenge.verification_url Starting device-code login returns the provider verification URL where the user completes authorization.
    pub verification_url: String,
    /// @behavior selvedge.login.challenge.user_code Starting device-code login returns the user code displayed to the provider authorization page.
    pub user_code: String,
    /// @behavior selvedge.login.challenge.device_auth_id Starting device-code login returns the provider device authorization ID used by polling.
    pub device_auth_id: String,
    /// @behavior selvedge.login.challenge.poll_interval Starting device-code login returns the caller-visible interval for the next poll attempt.
    pub poll_interval: Duration,
    /// @behavior selvedge.login.challenge.issued_at Starting device-code login returns the time when the local challenge was issued.
    pub issued_at: chrono::DateTime<chrono::Utc>,
    /// @behavior selvedge.login.challenge.expires_at Starting device-code login returns the local challenge expiry time used by poll and completion.
    pub expires_at: chrono::DateTime<chrono::Utc>,
}

/// @behavior selvedge.login.poll_outcome A device-code poll reports pending, authorized, or expired state to the caller for one provider poll attempt.
#[derive(Clone, Debug)]
pub enum DeviceCodePollOutcome {
    Pending { next_poll_after: Duration },
    Authorized(DeviceCodeAuthorization),
    Expired,
}

/// @behavior selvedge.login.authorization Successful device-code polling returns the authorization code and verifier required for token exchange.
#[derive(Clone, Debug)]
pub struct DeviceCodeAuthorization {
    /// @behavior selvedge.login.authorization.code Successful device-code polling returns the authorization code used for token exchange.
    pub authorization_code: String,
    /// @behavior selvedge.login.authorization.verifier Successful device-code polling returns the code verifier used for token exchange.
    pub code_verifier: String,
}

/// @behavior selvedge.login.result Completing device-code login returns the persisted auth file path and account metadata parsed from the id token.
#[derive(Clone, Debug)]
pub struct ChatgptLoginResult {
    /// @behavior selvedge.login.result.auth_file_path Completed device-code login returns the path of the persisted ChatGPT auth file.
    pub auth_file_path: PathBuf,
    /// @behavior selvedge.login.result.account_id Completed device-code login returns the ChatGPT account ID parsed from the id token.
    pub account_id: String,
    /// @behavior selvedge.login.result.user_id Completed device-code login returns the ChatGPT user ID when the id token carries it.
    pub user_id: Option<String>,
    /// @behavior selvedge.login.result.email Completed device-code login returns the ChatGPT email when the id token carries it.
    pub email: Option<String>,
    /// @behavior selvedge.login.result.plan_type Completed device-code login returns the ChatGPT plan type when the id token carries it.
    pub plan_type: Option<String>,
}

/// @behavior selvedge.login.errors Device-code login reports config, transport, provider rejection, invalid token, workspace, expiry, and persistence failures to callers.
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

/// @behavior selvedge.login.start Starting device-code login reads current auth config and requests a provider challenge.
pub async fn start_device_code_login() -> Result<DeviceCodeChallenge, ChatgptLoginError> {
    let config = config::read_chatgpt_auth_config()?;

    device_code::start(&config).await
}

/// @behavior selvedge.login.poll Polling device-code login performs one provider poll unless the challenge has already expired.
pub async fn poll_device_code_login(
    challenge: &DeviceCodeChallenge,
) -> Result<DeviceCodePollOutcome, ChatgptLoginError> {
    if chrono::Utc::now() >= challenge.expires_at {
        return Ok(DeviceCodePollOutcome::Expired);
    }

    let config = config::read_chatgpt_auth_config()?;

    device_code::poll(&config, challenge).await
}

/// @behavior selvedge.login.complete Completing device-code login exchanges the authorization grant, validates account claims, persists auth state, and returns login metadata.
pub async fn complete_device_code_login(
    challenge: &DeviceCodeChallenge,
    authorization: DeviceCodeAuthorization,
) -> Result<ChatgptLoginResult, ChatgptLoginError> {
    if chrono::Utc::now() >= challenge.expires_at {
        // @behavior selvedge.login.complete.expired Completing an expired device-code challenge returns ChallengeExpired before network or file side effects.
        return Err(ChatgptLoginError::ChallengeExpired);
    }

    let config = config::read_chatgpt_auth_config()?;
    let selvedge_home = config::read_selvedge_home()?;
    let token_set = token_exchange::exchange(&config, &authorization).await?;
    let claims = id_token::parse(&token_set.id_token)?;

    if let Some(expected_workspace_id) = &config.expected_workspace_id
        && claims.account_id != *expected_workspace_id
    {
        // @behavior selvedge.login.complete.workspace_mismatch Completing login returns a workspace mismatch before persisting credentials for another account.
        return Err(ChatgptLoginError::WorkspaceMismatch {
            expected: expected_workspace_id.clone(),
            actual: Some(claims.account_id.clone()),
        });
    }

    let auth_file_path = auth_file::auth_file_path(&selvedge_home);
    auth_file::persist(&auth_file_path, &token_set).await?;

    Ok(auth_file::build_result(auth_file_path, claims))
}
