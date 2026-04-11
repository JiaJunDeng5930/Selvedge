use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
};

use serde_json::json;

use crate::{ChatgptLoginError, id_token::ParsedIdToken, token_exchange::TokenSet};

pub(crate) fn auth_file_path(selvedge_home: &Path) -> PathBuf {
    selvedge_home.join("auth/chatgpt-auth.json")
}

pub(crate) fn persist(target_path: &Path, token_set: &TokenSet) -> Result<(), ChatgptLoginError> {
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
        "login_method": "device_code",
        "tokens": {
            "id_token": token_set.id_token,
            "access_token": token_set.access_token,
            "refresh_token": token_set.refresh_token,
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
