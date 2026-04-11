use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::{Arc, LazyLock, Mutex},
};

static PATH_LOCKS: LazyLock<Mutex<HashMap<PathBuf, Arc<tokio::sync::Mutex<()>>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

pub(crate) async fn lock_path(path: &Path) -> tokio::sync::OwnedMutexGuard<()> {
    let lock = {
        let mut locks = PATH_LOCKS
            .lock()
            .expect("path lock table must not be poisoned");
        locks
            .entry(path.to_path_buf())
            .or_insert_with(|| Arc::new(tokio::sync::Mutex::new(())))
            .clone()
    };

    lock.lock_owned().await
}
