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
    persist_chatgpt_auth_file(&lock_guard, tokens).map_err(|error| {
        ChatgptLoginError::PersistFailed {
            path: error.path,
            reason: error.reason,
        }
    })
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
        ModelCredentialError::UnsupportedSchemaVersion { version } => {
            format!("unsupported schema_version {version}")
        }
        ModelCredentialError::InvalidProviderId { provider_id } => {
            format!("invalid credential provider id {provider_id:?}")
        }
    };

    ChatgptLoginError::PersistFailed {
        path: target_path.to_path_buf(),
        reason,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{future::Future, task::Poll};

    #[tokio::test]
    async fn persistence_waits_for_credential_lock() {
        let home = tempfile::tempdir().expect("temporary home");
        let first = selvedge_model_credentials::lock_credential_from_home(home.path(), "chatgpt")
            .await
            .expect("hold credential lock");
        let tokens = ChatgptStoredTokens {
            id_token: "id-token".to_owned(),
            access_token: "access-token".to_owned(),
            refresh_token: "refresh-token".to_owned(),
        };
        let mut pending = Box::pin(persist(home.path(), &tokens));
        // Poll the actual login persistence boundary, so no scheduler delay can
        // masquerade as waiting for the already-held credential lock.
        std::future::poll_fn(|context| {
            assert!(pending.as_mut().poll(context).is_pending());
            Poll::Ready(())
        })
        .await;
        assert!(!first.path().exists());
        drop(first);
        pending.await.expect("persist after releasing lock");
        let stored: serde_json::Value = serde_json::from_slice(
            &std::fs::read(chatgpt_auth_file_path(home.path())).expect("stored credentials"),
        )
        .expect("credential JSON");
        assert_eq!(stored["payload"]["tokens"]["access_token"], "access-token");
    }
}
