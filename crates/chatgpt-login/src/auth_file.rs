use std::path::Path;

use chatgpt_auth::{ChatgptStoredTokens, chatgpt_auth_file_path, persist_chatgpt_auth_file};
use selvedge_model_credentials::{CredentialLockGuard, ModelCredentialError};

use crate::ChatgptLoginError;

pub(crate) async fn persist(
    selvedge_home: &Path,
    tokens: &ChatgptStoredTokens,
) -> Result<(), ChatgptLoginError> {
    let target_path = chatgpt_auth_file_path(selvedge_home);
    let lock_guard = acquire_auth_lock(selvedge_home, &target_path).await?;
    let tokens = tokens.clone();
    let persist_path = target_path.clone();

    tokio::task::spawn_blocking(move || {
        let _lock_guard = lock_guard;
        persist_chatgpt_auth_file(&persist_path, &tokens).map_err(|error| {
            ChatgptLoginError::PersistFailed {
                path: error.path,
                reason: error.reason,
            }
        })
    })
    .await
    .map_err(|error| ChatgptLoginError::PersistFailed {
        path: target_path,
        reason: format!("persist task failed: {error}"),
    })?
}

async fn acquire_auth_lock(
    selvedge_home: &Path,
    target_path: &Path,
) -> Result<CredentialLockGuard, ChatgptLoginError> {
    selvedge_model_credentials::lock_credential_from_home(selvedge_home, "chatgpt")
        .await
        .map_err(|error| map_lock_error(error, target_path))
}

fn map_lock_error(error: ModelCredentialError, target_path: &Path) -> ChatgptLoginError {
    let reason = match error {
        ModelCredentialError::Config(reason)
        | ModelCredentialError::LockFailed { reason, .. }
        | ModelCredentialError::ReadFailed { reason, .. }
        | ModelCredentialError::WriteFailed { reason, .. }
        | ModelCredentialError::InvalidRecord { reason } => reason,
        ModelCredentialError::InvalidProviderId { provider_id } => {
            format!("invalid credential provider id {provider_id:?}")
        }
    };

    ChatgptLoginError::PersistFailed {
        path: target_path.to_path_buf(),
        reason,
    }
}
