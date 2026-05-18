use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
};

use selvedge_model_credentials::{CredentialLockGuard, ModelCredentialError};
use serde_json::json;

use crate::{ChatgptLoginError, id_token::ParsedIdToken, token_exchange::TokenSet};

// @behavior selvedge.login.auth_file Completed ChatGPT login persists provider tokens into the local ChatGPT auth file.
// @behavior selvedge.login.auth_file.path Completed ChatGPT login writes auth state to `<selvedge_home>/auth/model-providers/chatgpt.json`.
pub(crate) fn auth_file_path(selvedge_home: &Path) -> PathBuf {
    selvedge_home.join("auth/model-providers/chatgpt.json")
}

// @behavior selvedge.login.auth_file.persist Completed ChatGPT login persists the token set on a blocking task before returning success.
pub(crate) async fn persist(
    target_path: &Path,
    token_set: &TokenSet,
) -> Result<(), ChatgptLoginError> {
    let _lock_guard = acquire_auth_lock(target_path).await?;
    let target_path = target_path.to_path_buf();
    let token_set = token_set.clone();
    let persist_path = target_path.clone();

    tokio::task::spawn_blocking(move || persist_blocking(&persist_path, &token_set))
        .await
        // @behavior selvedge.login.auth_file.persist_join Persist task join failures are returned as caller-visible auth file persist failures.
        .map_err(|error| ChatgptLoginError::PersistFailed {
            path: target_path,
            reason: format!("persist task failed: {error}"),
        })?
}

// @behavior selvedge.login.auth_file.atomic Completed ChatGPT login writes the ChatGPT auth file atomically under the shared provider credential lock.
fn persist_blocking(target_path: &Path, token_set: &TokenSet) -> Result<(), ChatgptLoginError> {
    let parent = target_path
        .parent()
        // @behavior selvedge.login.auth_file.parent Persisting completed login reports auth file paths without parent directories as persist failures.
        .ok_or_else(|| ChatgptLoginError::PersistFailed {
            path: target_path.to_path_buf(),
            reason: "auth file path must have a parent directory".to_owned(),
        })?;
    // @behavior selvedge.login.auth_file.directory Persisting completed login creates the target auth directory or reports a persist failure.
    fs::create_dir_all(parent).map_err(|error| ChatgptLoginError::PersistFailed {
        path: target_path.to_path_buf(),
        reason: error.to_string(),
    })?;

    let payload = serde_json::to_vec(&json!({
        "schema_version": 1,
        "provider": "chatgpt",
        "credential_kind": "login",
        "payload": {
            "tokens": {
                "id_token": token_set.id_token,
                "access_token": token_set.access_token,
                "refresh_token": token_set.refresh_token,
            }
        }
    }))
    // @behavior selvedge.login.auth_file.encode Persisting completed login reports serialization failures as persist failures with the target path.
    .map_err(|error| ChatgptLoginError::PersistFailed {
        path: target_path.to_path_buf(),
        reason: error.to_string(),
    })?;
    // @behavior selvedge.login.auth_file.temp Persisting completed login reports temporary file creation failures as persist failures with the target path.
    let mut temp_file = tempfile::NamedTempFile::new_in(parent).map_err(|error| {
        ChatgptLoginError::PersistFailed {
            path: target_path.to_path_buf(),
            reason: error.to_string(),
        }
    })?;

    temp_file
        .write_all(&payload)
        .and_then(|_| temp_file.as_file_mut().sync_all())
        // @behavior selvedge.login.auth_file.write Persisting completed login reports payload write and sync failures as persist failures with the target path.
        .map_err(|error| ChatgptLoginError::PersistFailed {
            path: target_path.to_path_buf(),
            reason: error.to_string(),
        })?;

    temp_file
        .persist(target_path)
        // @behavior selvedge.login.auth_file.replace Persisting completed login reports atomic replacement failures as persist failures with the target path.
        .map_err(|error| ChatgptLoginError::PersistFailed {
            path: target_path.to_path_buf(),
            reason: error.error.to_string(),
        })?;

    Ok(())
}

// @behavior selvedge.login.auth_file.lock Completed ChatGPT login takes the shared ChatGPT provider credential lock before replacing stored credentials.
async fn acquire_auth_lock(target_path: &Path) -> Result<CredentialLockGuard, ChatgptLoginError> {
    let selvedge_home = selvedge_home_from_auth_file_path(target_path)?;
    selvedge_model_credentials::lock_credential_from_home(&selvedge_home, "chatgpt")
        .await
        .map_err(|error| map_lock_error(error, target_path))
}

// @constraint selvedge.login.auth_file.lock_path Completed ChatGPT login derives the Selvedge home from the provider credential path before locking.
fn selvedge_home_from_auth_file_path(target_path: &Path) -> Result<PathBuf, ChatgptLoginError> {
    target_path
        .parent()
        .and_then(Path::parent)
        .and_then(Path::parent)
        .map(Path::to_path_buf)
        .ok_or_else(|| ChatgptLoginError::PersistFailed {
            path: target_path.to_path_buf(),
            reason: "auth file path must be under a Selvedge home".to_owned(),
        })
}

// @behavior selvedge.login.auth_file.lock_error Completed ChatGPT login maps provider credential lock failures into auth file persist failures.
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

// @behavior selvedge.login.auth_file.result Completed ChatGPT login returns the target auth file path and profile claims after persistence succeeds.
pub(crate) fn build_result(
    target_path: PathBuf,
    claims: ParsedIdToken,
) -> crate::ChatgptLoginResult {
    crate::ChatgptLoginResult {
        auth_file_path: target_path,
        account_id: claims.account_id,
        user_id: claims.user_id,
        email: claims.email,
        plan_type: claims.plan_type,
    }
}
