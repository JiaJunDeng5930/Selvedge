use std::path::Path;

use selvedge_model_credentials::{CredentialLockGuard, ModelCredentialError};

use crate::{ChatgptAuthError, auth_file};

pub(crate) async fn lock_chatgpt_credential(
    selvedge_home: &Path,
) -> Result<PathLockGuard, ChatgptAuthError> {
    let auth_file_path = auth_file::auth_file_path(selvedge_home);
    let guard = selvedge_model_credentials::lock_credential_from_home(selvedge_home, "chatgpt")
        .await
        .map_err(|error| map_lock_error(error, auth_file_path))?;

    Ok(PathLockGuard { _guard: guard })
}

pub(crate) struct PathLockGuard {
    _guard: CredentialLockGuard,
}

fn map_lock_error(
    error: ModelCredentialError,
    auth_file_path: std::path::PathBuf,
) -> ChatgptAuthError {
    match error {
        ModelCredentialError::InvalidProviderId { provider_id } => {
            ChatgptAuthError::AuthFileReadFailed {
                path: auth_file_path,
                reason: format!("invalid credential provider id {provider_id:?}"),
            }
        }
        ModelCredentialError::LockFailed { reason, .. } => ChatgptAuthError::AuthFileReadFailed {
            path: auth_file_path,
            reason,
        },
        ModelCredentialError::ReadFailed { path, reason }
        | ModelCredentialError::WriteFailed { path, reason } => {
            ChatgptAuthError::AuthFileReadFailed { path, reason }
        }
        ModelCredentialError::Config(reason) | ModelCredentialError::InvalidRecord { reason } => {
            ChatgptAuthError::AuthFileReadFailed {
                path: auth_file_path,
                reason,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::{sync::oneshot, time::Duration};

    #[tokio::test]
    async fn chatgpt_auth_lock_waits_for_model_credential_lock() {
        let temp = tempfile::tempdir().expect("temp home");
        let first = selvedge_model_credentials::lock_credential_from_home(temp.path(), "chatgpt")
            .await
            .expect("first credential lock");
        let home = temp.path().to_path_buf();
        let (started_tx, started_rx) = oneshot::channel();
        let (acquired_tx, mut acquired_rx) = oneshot::channel();

        let task = tokio::spawn(async move {
            started_tx.send(()).expect("started signal sends");
            let _second = lock_chatgpt_credential(&home).await.expect("chatgpt lock");
            acquired_tx.send(()).expect("acquired signal sends");
        });
        started_rx.await.expect("started signal arrives");

        assert!(
            tokio::time::timeout(Duration::from_millis(20), &mut acquired_rx)
                .await
                .is_err()
        );
        drop(first);
        tokio::time::timeout(Duration::from_millis(100), &mut acquired_rx)
            .await
            .expect("acquired signal arrives")
            .expect("acquired signal succeeds");
        task.await.expect("lock task joins");
    }
}
