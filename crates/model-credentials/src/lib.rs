#![doc = include_str!("../README.md")]

use std::{
    collections::HashMap,
    fs::{self, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
    sync::{Arc, LazyLock, Mutex},
};

use fs2::FileExt;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use thiserror::Error;

static PATH_LOCKS: LazyLock<Mutex<HashMap<PathBuf, Arc<tokio::sync::Mutex<()>>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CredentialKind {
    ApiKey,
    Login,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ModelCredentialRecord {
    pub schema_version: u32,
    pub provider: String,
    pub credential_kind: CredentialKind,
    pub payload: serde_json::Value,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ModelCredentialError {
    #[error("credential config failed: {0}")]
    Config(String),
    #[error("provider id {provider_id:?} is not path-safe")]
    InvalidProviderId { provider_id: String },
    #[error("credential lock failed for {path}: {reason}")]
    LockFailed { path: PathBuf, reason: String },
    #[error("credential read failed for {path}: {reason}")]
    ReadFailed { path: PathBuf, reason: String },
    #[error("credential write failed for {path}: {reason}")]
    WriteFailed { path: PathBuf, reason: String },
    #[error("credential record is invalid: {reason}")]
    InvalidRecord { reason: String },
}

struct PathLockGuard {
    pub(crate) process_guard: tokio::sync::OwnedMutexGuard<()>,
    pub(crate) lock_file: Option<std::fs::File>,
}

pub struct CredentialLockGuard {
    _guard: PathLockGuard,
}

impl Drop for PathLockGuard {
    fn drop(&mut self) {
        if let Some(lock_file) = self.lock_file.take() {
            let _ = lock_file.unlock();
        }
        let _ = &self.process_guard;
    }
}

pub async fn read_credential(
    provider_id: &str,
) -> Result<Option<ModelCredentialRecord>, ModelCredentialError> {
    let home = selvedge_config::selvedge_home()
        .map_err(|error| ModelCredentialError::Config(error.to_string()))?;

    read_credential_from_home(&home, provider_id).await
}

pub async fn credential_exists(provider_id: &str) -> Result<bool, ModelCredentialError> {
    read_credential(provider_id)
        .await
        .map(|credential| credential.is_some())
}

pub async fn write_credential(
    record: &ModelCredentialRecord,
) -> Result<PathBuf, ModelCredentialError> {
    let home = selvedge_config::selvedge_home()
        .map_err(|error| ModelCredentialError::Config(error.to_string()))?;

    write_credential_to_home(&home, record).await
}

pub async fn list_credentials() -> Result<Vec<ModelCredentialRecord>, ModelCredentialError> {
    let home = selvedge_config::selvedge_home()
        .map_err(|error| ModelCredentialError::Config(error.to_string()))?;

    list_credentials_from_home(&home).await
}

pub async fn read_credential_from_home(
    selvedge_home: &Path,
    provider_id: &str,
) -> Result<Option<ModelCredentialRecord>, ModelCredentialError> {
    let path = credential_path(selvedge_home, provider_id)?;
    let _guard = lock_path(&path).await?;
    let bytes = match fs::read(&path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => {
            return Err(ModelCredentialError::ReadFailed {
                path,
                reason: error.to_string(),
            });
        }
    };
    let record = decode_record(&bytes)?;
    if record.provider != provider_id {
        return Err(ModelCredentialError::InvalidRecord {
            reason: format!(
                "record provider {:?} does not match requested provider {:?}",
                record.provider, provider_id
            ),
        });
    }

    Ok(Some(record))
}

pub async fn write_credential_to_home(
    selvedge_home: &Path,
    record: &ModelCredentialRecord,
) -> Result<PathBuf, ModelCredentialError> {
    validate_record(record)?;
    let path = credential_path(selvedge_home, &record.provider)?;
    let _guard = lock_path(&path).await?;
    let payload =
        serde_json::to_vec(record).map_err(|error| ModelCredentialError::InvalidRecord {
            reason: error.to_string(),
        })?;
    persist_record(&path, &payload)?;

    Ok(path)
}

pub async fn lock_credential_from_home(
    selvedge_home: &Path,
    provider_id: &str,
) -> Result<CredentialLockGuard, ModelCredentialError> {
    let path = credential_path(selvedge_home, provider_id)?;
    let guard = lock_path(&path).await?;

    Ok(CredentialLockGuard { _guard: guard })
}

pub async fn list_credentials_from_home(
    selvedge_home: &Path,
) -> Result<Vec<ModelCredentialRecord>, ModelCredentialError> {
    let directory = credential_directory(selvedge_home);
    let entries = match fs::read_dir(&directory) {
        Ok(entries) => entries,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => {
            return Err(ModelCredentialError::ReadFailed {
                path: directory,
                reason: error.to_string(),
            });
        }
    };
    let mut records = Vec::new();

    for entry in entries {
        let entry = entry.map_err(|error| ModelCredentialError::ReadFailed {
            path: directory.clone(),
            reason: error.to_string(),
        })?;
        let path = entry.path();
        if path.extension().and_then(|extension| extension.to_str()) != Some("json") {
            continue;
        }
        let Some(provider_id) = path.file_stem().and_then(|stem| stem.to_str()) else {
            continue;
        };
        if let Some(record) = read_credential_from_home(selvedge_home, provider_id).await? {
            records.push(record);
        }
    }

    records.sort_by(|left, right| left.provider.cmp(&right.provider));
    Ok(records)
}

pub fn credential_path(
    selvedge_home: &Path,
    provider_id: &str,
) -> Result<PathBuf, ModelCredentialError> {
    validate_provider_id(provider_id)?;

    Ok(credential_directory(selvedge_home).join(format!("{provider_id}.json")))
}

pub fn credential_directory(selvedge_home: &Path) -> PathBuf {
    selvedge_home.join("auth/model-providers")
}

fn decode_record(bytes: &[u8]) -> Result<ModelCredentialRecord, ModelCredentialError> {
    let record = serde_json::from_slice::<ModelCredentialRecord>(bytes).map_err(|error| {
        ModelCredentialError::InvalidRecord {
            reason: error.to_string(),
        }
    })?;
    validate_record(&record)?;

    Ok(record)
}

pub fn validate_record(record: &ModelCredentialRecord) -> Result<(), ModelCredentialError> {
    if record.schema_version != 1 {
        return Err(ModelCredentialError::InvalidRecord {
            reason: format!("unsupported schema_version {}", record.schema_version),
        });
    }
    validate_provider_id(&record.provider)?;
    let Some(payload) = record.payload.as_object() else {
        return Err(ModelCredentialError::InvalidRecord {
            reason: "payload must be an object".to_owned(),
        });
    };

    match record.credential_kind {
        CredentialKind::ApiKey => match payload.get("api_key").and_then(Value::as_str) {
            Some(api_key) if !api_key.is_empty() => Ok(()),
            _ => Err(ModelCredentialError::InvalidRecord {
                reason: "api_key credentials require a non-empty payload.api_key".to_owned(),
            }),
        },
        CredentialKind::Login => {
            if payload.is_empty() {
                return Err(ModelCredentialError::InvalidRecord {
                    reason: "login credentials require a non-empty payload".to_owned(),
                });
            }
            Ok(())
        }
    }
}

fn validate_provider_id(provider_id: &str) -> Result<(), ModelCredentialError> {
    if provider_id.trim().is_empty() {
        return Err(ModelCredentialError::InvalidProviderId {
            provider_id: provider_id.to_owned(),
        });
    }
    for byte in provider_id.bytes() {
        let allowed = byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_');
        if !allowed {
            return Err(ModelCredentialError::InvalidProviderId {
                provider_id: provider_id.to_owned(),
            });
        }
    }
    Ok(())
}

async fn lock_path(path: &Path) -> Result<PathLockGuard, ModelCredentialError> {
    let process_lock = {
        let mut locks = PATH_LOCKS
            .lock()
            .map_err(|_| ModelCredentialError::LockFailed {
                path: path.to_path_buf(),
                reason: "process credential lock table poisoned".to_owned(),
            })?;
        locks
            .entry(path.to_path_buf())
            .or_insert_with(|| Arc::new(tokio::sync::Mutex::new(())))
            .clone()
    };
    let process_guard = process_lock.lock_owned().await;
    let lock_file_path = lock_file_path(path);
    let target_path = path.to_path_buf();
    let lock_file = tokio::task::spawn_blocking(move || acquire_file_lock(&lock_file_path))
        .await
        .map_err(|error| ModelCredentialError::LockFailed {
            path: target_path,
            reason: format!("failed to join credential lock task: {error}"),
        })??;

    Ok(PathLockGuard {
        process_guard,
        lock_file: Some(lock_file),
    })
}

fn acquire_file_lock(lock_file_path: &Path) -> Result<std::fs::File, ModelCredentialError> {
    let parent = lock_file_path
        .parent()
        .ok_or_else(|| ModelCredentialError::LockFailed {
            path: lock_file_path.to_path_buf(),
            reason: "lock file path must have a parent directory".to_owned(),
        })?;
    fs::create_dir_all(parent).map_err(|error| ModelCredentialError::LockFailed {
        path: lock_file_path.to_path_buf(),
        reason: error.to_string(),
    })?;
    let lock_file = OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(lock_file_path)
        .map_err(|error| ModelCredentialError::LockFailed {
            path: lock_file_path.to_path_buf(),
            reason: error.to_string(),
        })?;
    let lock_result = lock_file.lock_exclusive();
    lock_result.map_err(|error| ModelCredentialError::LockFailed {
        path: lock_file_path.to_path_buf(),
        reason: error.to_string(),
    })?;

    Ok(lock_file)
}

fn persist_record(path: &Path, payload: &[u8]) -> Result<(), ModelCredentialError> {
    let parent = path
        .parent()
        .ok_or_else(|| ModelCredentialError::WriteFailed {
            path: path.to_path_buf(),
            reason: "credential path must have a parent directory".to_owned(),
        })?;
    fs::create_dir_all(parent).map_err(|error| ModelCredentialError::WriteFailed {
        path: path.to_path_buf(),
        reason: error.to_string(),
    })?;
    let mut temp_file = tempfile::NamedTempFile::new_in(parent).map_err(|error| {
        ModelCredentialError::WriteFailed {
            path: path.to_path_buf(),
            reason: error.to_string(),
        }
    })?;
    let write_result = temp_file
        .write_all(payload)
        .and_then(|_| temp_file.as_file_mut().sync_all());
    write_result.map_err(|error| ModelCredentialError::WriteFailed {
        path: path.to_path_buf(),
        reason: error.to_string(),
    })?;
    let persist_result = temp_file.persist(path);
    persist_result.map_err(|error| ModelCredentialError::WriteFailed {
        path: path.to_path_buf(),
        reason: error.error.to_string(),
    })?;

    Ok(())
}

fn lock_file_path(credential_path: &Path) -> PathBuf {
    credential_path.with_extension("lock")
}
