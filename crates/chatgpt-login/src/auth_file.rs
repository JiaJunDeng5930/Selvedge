use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
};

use selvedge_model_credentials::{CredentialLockGuard, ModelCredentialError};
use serde_json::json;

use crate::{ChatgptLoginError, id_token::ParsedIdToken, token_exchange::TokenSet};

pub(crate) fn auth_file_path(selvedge_home: &Path) -> PathBuf {
    selvedge_home.join("auth/model-providers/chatgpt.json")
}

pub(crate) async fn persist(
    target_path: &Path,
    token_set: &TokenSet,
) -> Result<(), ChatgptLoginError> {
    let lock_guard = acquire_auth_lock(target_path).await?;
    let target_path = target_path.to_path_buf();
    let token_set = token_set.clone();
    let persist_path = target_path.clone();

    tokio::task::spawn_blocking(move || persist_blocking(&persist_path, &token_set, lock_guard))
        .await
        .map_err(|error| ChatgptLoginError::PersistFailed {
            path: target_path,
            reason: format!("persist task failed: {error}"),
        })?
}

fn persist_blocking(
    target_path: &Path,
    token_set: &TokenSet,
    _lock_guard: CredentialLockGuard,
) -> Result<(), ChatgptLoginError> {
    let parent = target_path
        .parent()
        .ok_or_else(|| ChatgptLoginError::PersistFailed {
            path: target_path.to_path_buf(),
            reason: "auth file path must have a parent directory".to_owned(),
        })?;
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
    .map_err(|error| ChatgptLoginError::PersistFailed {
        path: target_path.to_path_buf(),
        reason: error.to_string(),
    })?;
    let mut temp_file = tempfile::NamedTempFile::new_in(parent).map_err(|error| {
        ChatgptLoginError::PersistFailed {
            path: target_path.to_path_buf(),
            reason: error.to_string(),
        }
    })?;

    temp_file
        .write_all(&payload)
        .and_then(|_| temp_file.as_file_mut().sync_all())
        .map_err(|error| ChatgptLoginError::PersistFailed {
            path: target_path.to_path_buf(),
            reason: error.to_string(),
        })?;

    temp_file
        .persist(target_path)
        .map_err(|error| ChatgptLoginError::PersistFailed {
            path: target_path.to_path_buf(),
            reason: error.error.to_string(),
        })?;

    Ok(())
}

async fn acquire_auth_lock(target_path: &Path) -> Result<CredentialLockGuard, ChatgptLoginError> {
    let selvedge_home = selvedge_home_from_auth_file_path(target_path)?;
    selvedge_model_credentials::lock_credential_from_home(&selvedge_home, "chatgpt")
        .await
        .map_err(|error| map_lock_error(error, target_path))
}

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
