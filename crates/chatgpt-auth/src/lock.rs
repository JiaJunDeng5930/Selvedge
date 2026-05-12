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

// @behavior selvedge.auth.lock Auth file resolution serializes refresh and persistence for the same auth path across async tasks and processes.
pub(crate) async fn lock_path(path: &Path) -> Result<PathLockGuard, ChatgptAuthError> {
    let process_lock = {
        let mut locks = PATH_LOCKS
            .lock()
            // @constraint selvedge.auth.lock.table The in-process auth path lock table must remain available while resolving ChatGPT credentials.
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
        // @behavior selvedge.auth.lock.join A failed blocking lock task is returned as an auth file read failure for the target auth path.
        .map_err(|error| ChatgptAuthError::AuthFileReadFailed {
            path: auth_file_path.clone(),
            reason: format!("failed to join auth lock task: {error}"),
        })?
        // @behavior selvedge.auth.lock.path_error File-lock acquisition failures are reported against the target auth file path.
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

// @constraint selvedge.auth.lock.guard The path lock guard holds both the in-process mutex and filesystem lock until the credential operation completes.
pub(crate) struct PathLockGuard {
    process_guard: tokio::sync::OwnedMutexGuard<()>,
    lock_file: Option<std::fs::File>,
}

// @behavior selvedge.auth.lock.release Auth file locks are released when the credential operation guard is dropped.
impl Drop for PathLockGuard {
    fn drop(&mut self) {
        let Some(lock_file) = self.lock_file.take() else {
            return;
        };

        let _ = lock_file.unlock();
        let _ = &self.process_guard;
    }
}

// @behavior selvedge.auth.lock.file Auth resolution creates and exclusively locks the ChatGPT auth lock file before reading or writing credentials.
fn acquire_file_lock(lock_file_path: &Path) -> Result<std::fs::File, ChatgptAuthError> {
    let lock_parent = lock_file_path
        .parent()
        // @behavior selvedge.auth.lock.parent Auth lock acquisition reports lock paths without parent directories as auth file read failures.
        .ok_or_else(|| ChatgptAuthError::AuthFileReadFailed {
            path: lock_file_path.to_path_buf(),
            reason: "lock file path must have a parent directory".to_owned(),
        })?;
    // @behavior selvedge.auth.lock.directory Auth lock acquisition creates the lock directory or reports an auth file read failure.
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
        // @behavior selvedge.auth.lock.open Auth lock acquisition reports lock file open failures as auth file read failures.
        .map_err(|error| ChatgptAuthError::AuthFileReadFailed {
            path: lock_file_path.to_path_buf(),
            reason: error.to_string(),
        })?;

    lock_file
        .lock_exclusive()
        // @behavior selvedge.auth.lock.exclusive Auth lock acquisition reports exclusive lock failures as auth file read failures.
        .map_err(|error| ChatgptAuthError::AuthFileReadFailed {
            path: lock_file_path.to_path_buf(),
            reason: error.to_string(),
        })?;

    Ok(lock_file)
}

// @constraint selvedge.auth.lock.path The shared ChatGPT auth lock path lives at `<selvedge_home>/.chatgpt-auth.lock` for normal auth file locations.
fn lock_file_path(auth_file_path: &Path) -> PathBuf {
    match auth_file_path.parent().and_then(Path::parent) {
        Some(selvedge_home) => selvedge_home.join(".chatgpt-auth.lock"),
        None => auth_file_path.with_extension("lock"),
    }
}
