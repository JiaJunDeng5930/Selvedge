use std::{
    collections::HashMap,
    fs::OpenOptions,
    path::{Path, PathBuf},
    sync::{Arc, LazyLock, Mutex},
};

use fs2::FileExt;

use crate::ChatgptAuthError;

static PATH_LOCKS: LazyLock<Mutex<HashMap<PathBuf, Arc<tokio::sync::Mutex<()>>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

pub(crate) async fn lock_path(path: &Path) -> Result<PathLockGuard, ChatgptAuthError> {
    let process_lock = {
        let mut locks = PATH_LOCKS
            .lock()
            .expect("path lock table must not be poisoned");
        locks
            .entry(path.to_path_buf())
            .or_insert_with(|| Arc::new(tokio::sync::Mutex::new(())))
            .clone()
    };
    let process_guard = process_lock.lock_owned().await;
    let lock_file_path = lock_file_path(path);
    let auth_file_path = path.to_path_buf();
    let lock_file = tokio::task::spawn_blocking(move || acquire_file_lock(&lock_file_path))
        .await
        .map_err(|error| ChatgptAuthError::AuthFileReadFailed {
            path: auth_file_path.clone(),
            reason: format!("failed to join auth lock task: {error}"),
        })?
        .map_err(|error| match error {
            ChatgptAuthError::AuthFileReadFailed { reason, .. } => {
                ChatgptAuthError::AuthFileReadFailed {
                    path: auth_file_path.clone(),
                    reason,
                }
            }
            other => other,
        })?;

    Ok(PathLockGuard {
        process_guard,
        lock_file: Some(lock_file),
    })
}

pub(crate) struct PathLockGuard {
    process_guard: tokio::sync::OwnedMutexGuard<()>,
    lock_file: Option<std::fs::File>,
}

impl Drop for PathLockGuard {
    fn drop(&mut self) {
        let Some(lock_file) = self.lock_file.take() else {
            return;
        };

        let _ = lock_file.unlock();
        let _ = &self.process_guard;
    }
}

fn acquire_file_lock(lock_file_path: &Path) -> Result<std::fs::File, ChatgptAuthError> {
    let lock_parent =
        lock_file_path
            .parent()
            .ok_or_else(|| ChatgptAuthError::AuthFileReadFailed {
                path: lock_file_path.to_path_buf(),
                reason: "lock file path must have a parent directory".to_owned(),
            })?;
    std::fs::create_dir_all(lock_parent).map_err(|error| ChatgptAuthError::AuthFileReadFailed {
        path: lock_file_path.to_path_buf(),
        reason: error.to_string(),
    })?;
    let lock_file = OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(lock_file_path)
        .map_err(|error| ChatgptAuthError::AuthFileReadFailed {
            path: lock_file_path.to_path_buf(),
            reason: error.to_string(),
        })?;

    lock_file
        .lock_exclusive()
        .map_err(|error| ChatgptAuthError::AuthFileReadFailed {
            path: lock_file_path.to_path_buf(),
            reason: error.to_string(),
        })?;

    Ok(lock_file)
}

fn lock_file_path(auth_file_path: &Path) -> PathBuf {
    match auth_file_path.parent().and_then(Path::parent) {
        Some(selvedge_home) => selvedge_home.join(".chatgpt-auth.lock"),
        None => auth_file_path.with_extension("lock"),
    }
}
