use std::{
    collections::HashMap,
    fs::OpenOptions,
    path::{Path, PathBuf},
    sync::{Arc, LazyLock, Mutex},
};

use fs2::FileExt;

static PATH_LOCKS: LazyLock<Mutex<HashMap<PathBuf, Arc<tokio::sync::Mutex<()>>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

pub(crate) async fn lock_path(path: &Path) -> PathLockGuard {
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
    let lock_file = tokio::task::spawn_blocking(move || acquire_file_lock(&lock_file_path))
        .await
        .expect("lock file acquisition task must not panic");

    PathLockGuard {
        process_guard,
        lock_file: Some(lock_file),
    }
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

fn acquire_file_lock(lock_file_path: &Path) -> std::fs::File {
    let lock_file = OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(lock_file_path)
        .expect("chatgpt auth lock file must open");

    lock_file
        .lock_exclusive()
        .expect("chatgpt auth lock file must lock");

    lock_file
}

fn lock_file_path(auth_file_path: &Path) -> PathBuf {
    match auth_file_path.parent().and_then(Path::parent) {
        Some(selvedge_home) => selvedge_home.join(".chatgpt-auth.lock"),
        None => auth_file_path.with_extension("lock"),
    }
}
