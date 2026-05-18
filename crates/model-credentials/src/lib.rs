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

/// @behavior selvedge.model.credentials Model credential storage persists provider-scoped credential envelopes under the selected Selvedge home.
/// @behavior selvedge.model.credentials.kind Credential records distinguish API key and login payload envelopes.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CredentialKind {
    ApiKey,
    Login,
}

/// @behavior selvedge.model.credentials.record Credential records expose schema version, provider id, credential kind, and provider-specific payload.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ModelCredentialRecord {
    /// @behavior selvedge.model.credentials.record.schema_version Credential records expose the credential envelope schema version.
    pub schema_version: u32,
    /// @behavior selvedge.model.credentials.record.provider Credential records expose the provider id used for their storage path.
    pub provider: String,
    /// @behavior selvedge.model.credentials.record.kind Credential records expose the credential kind used by provider completion rules.
    pub credential_kind: CredentialKind,
    /// @behavior selvedge.model.credentials.record.payload Credential records expose provider-specific credential payload JSON.
    pub payload: serde_json::Value,
}

/// @behavior selvedge.model.credentials.error Credential store errors report selected-home, provider id, lock, IO, JSON, and envelope failures.
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

// @constraint selvedge.model.credentials.lock.guard Credential lock guards hold process and file locks for one credential path.
struct PathLockGuard {
    /// @constraint selvedge.model.credentials.lock.guard.process Credential lock guards hold the process mutex guard until drop.
    pub(crate) process_guard: tokio::sync::OwnedMutexGuard<()>,
    /// @constraint selvedge.model.credentials.lock.guard.file Credential lock guards hold the exclusive file lock until drop.
    pub(crate) lock_file: Option<std::fs::File>,
}

/// @constraint selvedge.model.credentials.lock.public_guard Public credential lock guards hold the shared credential path lock until drop.
pub struct CredentialLockGuard {
    _guard: PathLockGuard,
}

impl Drop for PathLockGuard {
    // @behavior selvedge.model.credentials.lock.release Dropping a credential lock guard releases the file lock before the process guard is dropped.
    fn drop(&mut self) {
        if let Some(lock_file) = self.lock_file.take() {
            let _ = lock_file.unlock();
        }
        let _ = &self.process_guard;
    }
}

/// @behavior selvedge.model.credentials.read Selected-home credential reads resolve Selvedge home and read the provider credential record from that home.
pub async fn read_credential(
    provider_id: &str,
) -> Result<Option<ModelCredentialRecord>, ModelCredentialError> {
    let home = selvedge_config::selvedge_home()
        .map_err(|error| ModelCredentialError::Config(error.to_string()))?;

    read_credential_from_home(&home, provider_id).await
}

/// @behavior selvedge.model.credentials.exists Selected-home credential existence checks report whether the provider credential record is present.
pub async fn credential_exists(provider_id: &str) -> Result<bool, ModelCredentialError> {
    read_credential(provider_id)
        .await
        .map(|credential| credential.is_some())
}

/// @behavior selvedge.model.credentials.write Selected-home credential writes resolve Selvedge home and persist the provider credential record under that home.
pub async fn write_credential(
    record: &ModelCredentialRecord,
) -> Result<PathBuf, ModelCredentialError> {
    let home = selvedge_config::selvedge_home()
        .map_err(|error| ModelCredentialError::Config(error.to_string()))?;

    write_credential_to_home(&home, record).await
}

/// @behavior selvedge.model.credentials.list Selected-home credential listing resolves Selvedge home and returns all valid provider credential records.
pub async fn list_credentials() -> Result<Vec<ModelCredentialRecord>, ModelCredentialError> {
    let home = selvedge_config::selvedge_home()
        .map_err(|error| ModelCredentialError::Config(error.to_string()))?;

    list_credentials_from_home(&home).await
}

/// @behavior selvedge.model.credentials.read.from_home Credential reads from an explicit home return the provider credential record or absence from the canonical provider path.
pub async fn read_credential_from_home(
    selvedge_home: &Path,
    provider_id: &str,
) -> Result<Option<ModelCredentialRecord>, ModelCredentialError> {
    let path = credential_path(selvedge_home, provider_id)?;
    let _guard = lock_path(&path).await?;
    let bytes = match fs::read(&path) {
        Ok(bytes) => bytes,
        // @behavior selvedge.model.credentials.read.from_home.absent Credential reads return absence when the provider credential file is missing.
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        // @behavior selvedge.model.credentials.read.from_home.read_error Credential reads surface file read failures with the credential path.
        Err(error) => {
            return Err(ModelCredentialError::ReadFailed {
                path,
                reason: error.to_string(),
            });
        }
    };
    let record = decode_record(&bytes)?;
    if record.provider != provider_id {
        // @constraint selvedge.model.credentials.read.from_home.provider_match Credential reads require the record provider field to match the requested provider id.
        return Err(ModelCredentialError::InvalidRecord {
            reason: format!(
                "record provider {:?} does not match requested provider {:?}",
                record.provider, provider_id
            ),
        });
    }

    Ok(Some(record))
}

/// @behavior selvedge.model.credentials.write.from_home Credential writes to an explicit home validate and atomically persist the provider credential record at the canonical provider path.
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

/// @behavior selvedge.model.credentials.lock.from_home Credential locking from an explicit home acquires the same provider path lock used by credential reads and writes.
pub async fn lock_credential_from_home(
    selvedge_home: &Path,
    provider_id: &str,
) -> Result<CredentialLockGuard, ModelCredentialError> {
    let path = credential_path(selvedge_home, provider_id)?;
    let guard = lock_path(&path).await?;

    Ok(CredentialLockGuard { _guard: guard })
}

/// @behavior selvedge.model.credentials.list.from_home Credential listing from an explicit home returns sorted records from JSON files in the canonical credential directory.
pub async fn list_credentials_from_home(
    selvedge_home: &Path,
) -> Result<Vec<ModelCredentialRecord>, ModelCredentialError> {
    let directory = credential_directory(selvedge_home);
    let entries = match fs::read_dir(&directory) {
        Ok(entries) => entries,
        // @behavior selvedge.model.credentials.list.from_home.absent Credential listing returns an empty list when the credential directory is missing.
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        // @behavior selvedge.model.credentials.list.from_home.read_dir_error Credential listing surfaces directory read failures with the credential directory.
        Err(error) => {
            return Err(ModelCredentialError::ReadFailed {
                path: directory,
                reason: error.to_string(),
            });
        }
    };
    let mut records = Vec::new();

    for entry in entries {
        // @behavior selvedge.model.credentials.list.from_home.entry_error Credential listing surfaces directory entry failures with the credential directory.
        let entry = entry.map_err(|error| ModelCredentialError::ReadFailed {
            path: directory.clone(),
            reason: error.to_string(),
        })?;
        let path = entry.path();
        // @behavior selvedge.model.credentials.list.from_home.skip_extension Credential listing skips files whose extension is outside the credential JSON set.
        if path.extension().and_then(|extension| extension.to_str()) != Some("json") {
            continue;
        }
        // @behavior selvedge.model.credentials.list.from_home.skip_stem Credential listing skips JSON paths whose file stem cannot be represented as UTF-8.
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

/// @behavior selvedge.model.credentials.path Credential paths resolve provider ids to `<home>/auth/model-providers/<provider>.json`.
pub fn credential_path(
    selvedge_home: &Path,
    provider_id: &str,
) -> Result<PathBuf, ModelCredentialError> {
    validate_provider_id(provider_id)?;

    Ok(credential_directory(selvedge_home).join(format!("{provider_id}.json")))
}

/// @behavior selvedge.model.credentials.directory Credential directories resolve to `<home>/auth/model-providers`.
pub fn credential_directory(selvedge_home: &Path) -> PathBuf {
    selvedge_home.join("auth/model-providers")
}

// @behavior selvedge.model.credentials.decode Credential decoding parses JSON bytes and validates the credential envelope before returning a record.
fn decode_record(bytes: &[u8]) -> Result<ModelCredentialRecord, ModelCredentialError> {
    let record = serde_json::from_slice::<ModelCredentialRecord>(bytes).map_err(|error| {
        ModelCredentialError::InvalidRecord {
            reason: error.to_string(),
        }
    })?;
    validate_record(&record)?;

    Ok(record)
}

/// @constraint selvedge.model.credentials.record.valid Credential record validation accepts schema-one records with path-safe provider ids and payloads required by the credential kind.
pub fn validate_record(record: &ModelCredentialRecord) -> Result<(), ModelCredentialError> {
    if record.schema_version != 1 {
        // @constraint selvedge.model.credentials.record.valid.schema Credential record validation accepts schema version one.
        return Err(ModelCredentialError::InvalidRecord {
            reason: format!("unsupported schema_version {}", record.schema_version),
        });
    }
    validate_provider_id(&record.provider)?;
    let Some(payload) = record.payload.as_object() else {
        // @constraint selvedge.model.credentials.record.valid.payload_object Credential record validation requires object payloads.
        return Err(ModelCredentialError::InvalidRecord {
            reason: "payload must be an object".to_owned(),
        });
    };

    match record.credential_kind {
        CredentialKind::ApiKey => match payload.get("api_key").and_then(Value::as_str) {
            Some(api_key) if !api_key.is_empty() => Ok(()),
            // @constraint selvedge.model.credentials.record.valid.api_key Credential record validation requires API key records to carry a non-empty payload api_key string.
            _ => Err(ModelCredentialError::InvalidRecord {
                reason: "api_key credentials require a non-empty payload.api_key".to_owned(),
            }),
        },
        CredentialKind::Login => {
            if payload.is_empty() {
                // @constraint selvedge.model.credentials.record.valid.login Credential record validation requires login records to carry a non-empty payload object.
                return Err(ModelCredentialError::InvalidRecord {
                    reason: "login credentials require a non-empty payload".to_owned(),
                });
            }
            Ok(())
        }
    }
}

// @constraint selvedge.model.credentials.provider_id Credential provider ids use nonblank path-safe spelling for file-backed storage.
fn validate_provider_id(provider_id: &str) -> Result<(), ModelCredentialError> {
    if provider_id.trim().is_empty() {
        // @constraint selvedge.model.credentials.provider_id.nonblank Credential provider id validation rejects blank ids.
        return Err(ModelCredentialError::InvalidProviderId {
            provider_id: provider_id.to_owned(),
        });
    }
    for byte in provider_id.bytes() {
        let allowed = byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_');
        if !allowed {
            // @constraint selvedge.model.credentials.provider_id.path_safe Credential provider id validation rejects characters outside ASCII alphanumeric, dot, hyphen, and underscore.
            return Err(ModelCredentialError::InvalidProviderId {
                provider_id: provider_id.to_owned(),
            });
        }
    }
    Ok(())
}

// @behavior selvedge.model.credentials.lock Credential path locking combines a process mutex and exclusive lock file before credential IO.
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
            // @behavior selvedge.model.credentials.lock.table Credential path locking creates one process mutex per canonical credential path.
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

// @behavior selvedge.model.credentials.lock.file Credential file locking creates the lock directory, opens the lock file, and acquires an exclusive lock.
fn acquire_file_lock(lock_file_path: &Path) -> Result<std::fs::File, ModelCredentialError> {
    let parent = lock_file_path
        .parent()
        // @behavior selvedge.model.credentials.lock.file.parent_error Credential file locking reports lock failures when the lock path has no parent directory.
        .ok_or_else(|| ModelCredentialError::LockFailed {
            path: lock_file_path.to_path_buf(),
            reason: "lock file path must have a parent directory".to_owned(),
        })?;
    // @behavior selvedge.model.credentials.lock.file.directory Credential file locking creates the parent directory for lock files before opening them.
    fs::create_dir_all(parent).map_err(|error| ModelCredentialError::LockFailed {
        path: lock_file_path.to_path_buf(),
        reason: error.to_string(),
    })?;
    // @behavior selvedge.model.credentials.lock.file.open Credential file locking opens the provider lock file for read and write access.
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
    // @behavior selvedge.model.credentials.lock.file.exclusive Credential file locking acquires an exclusive OS lock before credential IO proceeds.
    let lock_result = lock_file.lock_exclusive();
    lock_result.map_err(|error| ModelCredentialError::LockFailed {
        path: lock_file_path.to_path_buf(),
        reason: error.to_string(),
    })?;

    Ok(lock_file)
}

// @behavior selvedge.model.credentials.persist Credential persistence creates the target directory, writes a temporary file, syncs it, and atomically replaces the target record.
fn persist_record(path: &Path, payload: &[u8]) -> Result<(), ModelCredentialError> {
    let parent = path
        .parent()
        // @behavior selvedge.model.credentials.persist.parent_error Credential persistence reports write failures when the credential path has no parent directory.
        .ok_or_else(|| ModelCredentialError::WriteFailed {
            path: path.to_path_buf(),
            reason: "credential path must have a parent directory".to_owned(),
        })?;
    // @behavior selvedge.model.credentials.persist.directory Credential persistence creates the credential directory before writing records.
    fs::create_dir_all(parent).map_err(|error| ModelCredentialError::WriteFailed {
        path: path.to_path_buf(),
        reason: error.to_string(),
    })?;
    // @behavior selvedge.model.credentials.persist.temp Credential persistence writes records through a temporary file in the credential directory.
    let mut temp_file = tempfile::NamedTempFile::new_in(parent).map_err(|error| {
        ModelCredentialError::WriteFailed {
            path: path.to_path_buf(),
            reason: error.to_string(),
        }
    })?;
    // @behavior selvedge.model.credentials.persist.write Credential persistence writes and syncs the encoded credential payload before replacement.
    let write_result = temp_file
        .write_all(payload)
        .and_then(|_| temp_file.as_file_mut().sync_all());
    write_result.map_err(|error| ModelCredentialError::WriteFailed {
        path: path.to_path_buf(),
        reason: error.to_string(),
    })?;
    // @behavior selvedge.model.credentials.persist.replace Credential persistence atomically replaces the provider credential path with the synced temporary file.
    let persist_result = temp_file.persist(path);
    persist_result.map_err(|error| ModelCredentialError::WriteFailed {
        path: path.to_path_buf(),
        reason: error.error.to_string(),
    })?;

    Ok(())
}

// @behavior selvedge.model.credentials.lock.path Credential lock paths share the credential record path and use the `.lock` extension.
fn lock_file_path(credential_path: &Path) -> PathBuf {
    credential_path.with_extension("lock")
}
