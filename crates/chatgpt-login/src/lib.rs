#![doc = include_str!("../README.md")]
#![allow(clippy::result_large_err)]

mod auth_file;
mod device_code;
mod token_exchange;

use std::future::Future;
use std::path::PathBuf;
use std::pin::Pin;
use std::time::Duration;

use chatgpt_auth::{
    ChatgptJwtClaims, chatgpt_auth_file_path, parse_chatgpt_jwt_claims, read_chatgpt_auth_config,
};
use tokio::sync::Semaphore;

static LOGIN_GATE: Semaphore = Semaphore::const_new(1);

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
    pub account_id: Option<String>,
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
    LoginAlreadyRunning,
    Cancelled,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ChatgptLoginProgress {
    UserCode {
        verification_url: String,
        user_code: String,
    },
    Waiting,
    Diagnostic {
        message_text: String,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChatgptLoginProgressError;

pub type ChatgptLoginProgressFuture =
    Pin<Box<dyn Future<Output = Result<(), ChatgptLoginProgressError>> + Send>>;

pub trait ChatgptLoginProgressSink: Send + Sync {
    fn emit(&self, progress: ChatgptLoginProgress) -> ChatgptLoginProgressFuture;
}

#[derive(Clone, Debug)]
pub struct NoopChatgptLoginProgressSink;

impl ChatgptLoginProgressSink for NoopChatgptLoginProgressSink {
    fn emit(&self, _progress: ChatgptLoginProgress) -> ChatgptLoginProgressFuture {
        Box::pin(async { Ok(()) })
    }
}

pub async fn run_chatgpt_login<S>(progress_sink: S) -> Result<ChatgptLoginResult, ChatgptLoginError>
where
    S: ChatgptLoginProgressSink,
{
    let _permit = LOGIN_GATE
        .try_acquire()
        .map_err(|_| ChatgptLoginError::LoginAlreadyRunning)?;
    let challenge = start_device_code_login().await?;
    progress_sink
        .emit(ChatgptLoginProgress::UserCode {
            verification_url: challenge.verification_url.clone(),
            user_code: challenge.user_code.clone(),
        })
        .await
        .map_err(|_| ChatgptLoginError::Cancelled)?;

    sleep_until_next_poll(&challenge, challenge.poll_interval).await?;

    loop {
        if chrono::Utc::now() >= challenge.expires_at {
            return Err(ChatgptLoginError::ChallengeExpired);
        }
        let outcome = poll_device_code_login(&challenge).await?;
        match outcome {
            DeviceCodePollOutcome::Pending { next_poll_after } => {
                progress_sink
                    .emit(ChatgptLoginProgress::Waiting)
                    .await
                    .map_err(|_| ChatgptLoginError::Cancelled)?;
                sleep_until_next_poll(&challenge, next_poll_after).await?;
            }
            DeviceCodePollOutcome::Authorized(authorization) => {
                return complete_device_code_login(&challenge, authorization).await;
            }
            DeviceCodePollOutcome::Expired => {
                return Err(ChatgptLoginError::ChallengeExpired);
            }
        }
    }
}

async fn sleep_until_next_poll(
    challenge: &DeviceCodeChallenge,
    requested: Duration,
) -> Result<(), ChatgptLoginError> {
    let Some(duration) =
        bounded_poll_sleep_duration(chrono::Utc::now(), challenge.expires_at, requested)
    else {
        return Err(ChatgptLoginError::ChallengeExpired);
    };
    tokio::time::sleep(duration).await;
    if chrono::Utc::now() >= challenge.expires_at {
        return Err(ChatgptLoginError::ChallengeExpired);
    }

    Ok(())
}

fn bounded_poll_sleep_duration(
    now: chrono::DateTime<chrono::Utc>,
    expires_at: chrono::DateTime<chrono::Utc>,
    requested: Duration,
) -> Option<Duration> {
    let remaining = expires_at.signed_duration_since(now).to_std().ok()?;
    Some(requested.min(remaining))
}

pub async fn start_device_code_login() -> Result<DeviceCodeChallenge, ChatgptLoginError> {
    let config = read_chatgpt_auth_config().map_err(ChatgptLoginError::Config)?;

    device_code::start(&config).await
}

pub async fn poll_device_code_login(
    challenge: &DeviceCodeChallenge,
) -> Result<DeviceCodePollOutcome, ChatgptLoginError> {
    if chrono::Utc::now() >= challenge.expires_at {
        return Ok(DeviceCodePollOutcome::Expired);
    }

    let config = read_chatgpt_auth_config().map_err(ChatgptLoginError::Config)?;

    device_code::poll(&config, challenge).await
}

pub async fn complete_device_code_login(
    challenge: &DeviceCodeChallenge,
    authorization: DeviceCodeAuthorization,
) -> Result<ChatgptLoginResult, ChatgptLoginError> {
    if chrono::Utc::now() >= challenge.expires_at {
        return Err(ChatgptLoginError::ChallengeExpired);
    }

    let config = read_chatgpt_auth_config().map_err(ChatgptLoginError::Config)?;
    let selvedge_home = selvedge_config::selvedge_home().map_err(ChatgptLoginError::Config)?;
    let token_set = token_exchange::exchange(&config, &authorization).await?;
    let claims = parse_chatgpt_jwt_claims(&token_set.id_token).map_err(|error| {
        ChatgptLoginError::InvalidTokenSet {
            reason: format!("id_token claims are invalid: {error:?}"),
        }
    })?;

    if let Some(expected_workspace_id) = &config.expected_workspace_id
        && claims.account_id.as_deref() != Some(expected_workspace_id)
    {
        return Err(ChatgptLoginError::WorkspaceMismatch {
            expected: expected_workspace_id.clone(),
            actual: claims.account_id.clone(),
        });
    }

    let auth_file_path = chatgpt_auth_file_path(&selvedge_home);
    auth_file::persist(&selvedge_home, &token_set).await?;

    Ok(build_result(auth_file_path, claims))
}

fn build_result(auth_file_path: PathBuf, claims: ChatgptJwtClaims) -> ChatgptLoginResult {
    ChatgptLoginResult {
        auth_file_path,
        account_id: claims.account_id,
        user_id: claims.user_id,
        email: claims.email,
        plan_type: claims.plan_type,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bounded_poll_sleep_caps_requested_interval_at_expiry() {
        let now = chrono::Utc::now();
        let duration = bounded_poll_sleep_duration(
            now,
            now + chrono::Duration::milliseconds(50),
            Duration::from_secs(5),
        )
        .expect("duration before expiry");

        assert!(duration <= Duration::from_millis(50));
    }

    #[test]
    fn bounded_poll_sleep_returns_none_after_expiry() {
        let now = chrono::Utc::now();

        assert_eq!(
            bounded_poll_sleep_duration(
                now,
                now - chrono::Duration::milliseconds(1),
                Duration::from_secs(5),
            ),
            None
        );
    }
}
