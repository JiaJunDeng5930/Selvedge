#![doc = include_str!("../README.md")]
#![allow(clippy::result_large_err)]
//! @behavior selvedge.login ChatGPT device-code login starts provider challenges, polls authorization, exchanges grants, and persists local auth state.

mod auth_file;
mod config;
mod device_code;
mod id_token;
mod token_exchange;

use std::future::Future;
use std::path::PathBuf;
use std::pin::Pin;
use std::time::Duration;

use tokio::sync::Semaphore;

static LOGIN_GATE: Semaphore = Semaphore::const_new(1);

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

/// @behavior selvedge.login.result Completing device-code login returns the persisted auth file path and available account metadata parsed from the id token.
#[derive(Clone, Debug)]
pub struct ChatgptLoginResult {
    /// @behavior selvedge.login.result.auth_file_path Completed device-code login returns the path of the persisted ChatGPT auth file.
    pub auth_file_path: PathBuf,
    /// @behavior selvedge.login.result.account_id Completed device-code login returns the ChatGPT account ID when the id token carries it.
    pub account_id: Option<String>,
    /// @behavior selvedge.login.result.user_id Completed device-code login returns the ChatGPT user ID when the id token carries it.
    pub user_id: Option<String>,
    /// @behavior selvedge.login.result.email Completed device-code login returns the ChatGPT email when the id token carries it.
    pub email: Option<String>,
    /// @behavior selvedge.login.result.plan_type Completed device-code login returns the ChatGPT plan type when the id token carries it.
    pub plan_type: Option<String>,
}

/// @behavior selvedge.login.errors Device-code login reports config, transport, provider rejection, invalid token, workspace, expiry, persistence, concurrency, and cancellation failures to callers.
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
// @behavior selvedge.login.progress ChatGPT login progress reports the user code prompt, waiting polls, or diagnostic text to callers.
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
// @behavior selvedge.login.progress.error Progress sinks report cancellation with a typed progress error.
pub struct ChatgptLoginProgressError;

// @behavior selvedge.login.progress.future ChatGPT login progress futures resolve after accepting progress or reporting cancellation.
// @intent selvedge.login.progress.future.abstraction ChatgptLoginProgressFuture abstracts asynchronous progress delivery for login callers.
pub type ChatgptLoginProgressFuture =
    Pin<Box<dyn Future<Output = Result<(), ChatgptLoginProgressError>> + Send>>;

// @behavior selvedge.login.progress.sink Progress sinks receive user-code prompts, wait markers, and diagnostics during the login operation.
// @intent selvedge.login.progress.sink.abstraction ChatgptLoginProgressSink lets callers route login progress to CLI, server, or tests without changing provider logic.
pub trait ChatgptLoginProgressSink: Send + Sync {
    /// @behavior selvedge.login.progress.sink.emit Progress sinks return success after accepting progress or a typed progress error on cancellation.
    fn emit(&self, progress: ChatgptLoginProgress) -> ChatgptLoginProgressFuture;
}

#[derive(Clone, Debug)]
// @behavior selvedge.login.progress.sink.noop The noop progress sink accepts every progress event without side effects.
pub struct NoopChatgptLoginProgressSink;

impl ChatgptLoginProgressSink for NoopChatgptLoginProgressSink {
    fn emit(&self, _progress: ChatgptLoginProgress) -> ChatgptLoginProgressFuture {
        Box::pin(async { Ok(()) })
    }
}

/// @behavior selvedge.login.run The ChatGPT login operation runs the whole device-code login flow and reports user-visible progress through the supplied sink.
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
        // @behavior selvedge.login.run.cancelled ChatGPT login returns cancelled when progress delivery fails.
        .map_err(|_| ChatgptLoginError::Cancelled)?;

    // @behavior selvedge.login.run.initial_interval ChatGPT login waits for the provider-supplied poll interval before the first device-code poll.
    sleep_until_next_poll(&challenge, challenge.poll_interval).await?;

    loop {
        if chrono::Utc::now() >= challenge.expires_at {
            // @behavior selvedge.login.run.expired Local expiry detection returns ChallengeExpired before another provider poll.
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
                // @behavior selvedge.login.run.authorized Authorized provider polls complete the device-code grant and persist credentials.
                return complete_device_code_login(&challenge, authorization).await;
            }
            DeviceCodePollOutcome::Expired => {
                // @behavior selvedge.login.run.provider_expired Provider expiry outcomes return ChallengeExpired to the caller.
                return Err(ChatgptLoginError::ChallengeExpired);
            }
        }
    }
}

// @behavior selvedge.login.run.poll_sleep ChatGPT login caps provider poll sleeps at the remaining device-code challenge lifetime.
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
        // @behavior selvedge.login.run.poll_sleep.expired ChatGPT login returns ChallengeExpired when a bounded poll sleep reaches the challenge expiry.
        return Err(ChatgptLoginError::ChallengeExpired);
    }

    Ok(())
}

// @constraint selvedge.login.run.poll_sleep.bound Poll sleep duration is bounded by the remaining local challenge lifetime.
fn bounded_poll_sleep_duration(
    now: chrono::DateTime<chrono::Utc>,
    expires_at: chrono::DateTime<chrono::Utc>,
    requested: Duration,
) -> Option<Duration> {
    let remaining = expires_at.signed_duration_since(now).to_std().ok()?;
    Some(requested.min(remaining))
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

/// @behavior selvedge.login.complete Completing device-code login exchanges the authorization grant, validates configured workspace claims, persists auth state, and returns login metadata.
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
        && claims.account_id.as_deref() != Some(expected_workspace_id)
    {
        // @behavior selvedge.login.complete.workspace_mismatch Completing login returns a workspace mismatch before persisting credentials outside the configured workspace.
        return Err(ChatgptLoginError::WorkspaceMismatch {
            expected: expected_workspace_id.clone(),
            actual: claims.account_id.clone(),
        });
    }

    let auth_file_path = auth_file::auth_file_path(&selvedge_home);
    auth_file::persist(&auth_file_path, &token_set).await?;

    Ok(auth_file::build_result(auth_file_path, claims))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    // @verifies selvedge.login.run.poll_sleep.bound
    fn bounded_poll_sleep_caps_requested_interval_at_expiry() {
        let now = chrono::Utc::now();
        let duration = bounded_poll_sleep_duration(
            now,
            now + chrono::Duration::milliseconds(50),
            Duration::from_secs(5),
        )
        .expect("duration before expiry");

        // @verifies selvedge.login.run.poll_sleep.bound
        assert!(duration <= Duration::from_millis(50));
    }

    #[test]
    // @verifies selvedge.login.run.poll_sleep.bound
    fn bounded_poll_sleep_returns_none_after_expiry() {
        let now = chrono::Utc::now();

        // @verifies selvedge.login.run.poll_sleep.bound
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
