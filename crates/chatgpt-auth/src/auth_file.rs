use crate::{
    ChatgptAuthError, ChatgptAuthFileWriteError, ChatgptAuthParseError, ChatgptStoredTokens,
};
use selvedge_model_credentials::{
    CredentialKind, CredentialLockGuard, ModelCredentialError, ModelCredentialRecord,
};
use serde_json::{Value, json};
use std::path::{Path, PathBuf};

pub(crate) struct StoredAuth {
    pub tokens: ChatgptStoredTokens,
    pub last_refresh: chrono::DateTime<chrono::Utc>,
}

pub(crate) fn parse(bytes: &[u8]) -> Result<ChatgptStoredTokens, ChatgptAuthParseError> {
    from_record(
        selvedge_model_credentials::decode_record(bytes).map_err(|error| match error {
            ModelCredentialError::UnsupportedSchemaVersion { version } => {
                ChatgptAuthParseError::UnsupportedSchemaVersion { version }
            }
            error => ChatgptAuthParseError::InvalidJson {
                reason: error.to_string(),
            },
        })?,
    )
    .map(|stored| stored.tokens)
}

fn from_record(record: ModelCredentialRecord) -> Result<StoredAuth, ChatgptAuthParseError> {
    if record.provider != "chatgpt" {
        return Err(ChatgptAuthParseError::InvalidField {
            field: "provider",
            reason: "must equal \"chatgpt\"".to_owned(),
        });
    }
    if record.credential_kind != CredentialKind::Login {
        return Err(ChatgptAuthParseError::InvalidField {
            field: "credential_kind",
            reason: "must equal \"login\"".to_owned(),
        });
    }
    let tokens = read_tokens(Some(&record.payload))?;
    let last_refresh =
        read_required_string(record.payload.get("last_refresh"), "payload.last_refresh")?;
    let last_refresh = chrono::DateTime::parse_from_rfc3339(&last_refresh)
        .map_err(|_| ChatgptAuthParseError::InvalidField {
            field: "payload.last_refresh",
            reason: "must be an RFC3339 timestamp".to_owned(),
        })?
        .with_timezone(&chrono::Utc);
    Ok(StoredAuth {
        tokens,
        last_refresh,
    })
}

fn read_tokens(value: Option<&Value>) -> Result<ChatgptStoredTokens, ChatgptAuthParseError> {
    let envelope = value
        .ok_or(ChatgptAuthParseError::MissingField { field: "tokens" })?
        .as_object()
        .ok_or_else(|| ChatgptAuthParseError::InvalidField {
            field: "tokens",
            reason: "must be an object".to_owned(),
        })?;
    let object = envelope
        .get("tokens")
        .ok_or(ChatgptAuthParseError::MissingField {
            field: "payload.tokens",
        })?
        .as_object()
        .ok_or_else(|| ChatgptAuthParseError::InvalidField {
            field: "payload.tokens",
            reason: "must be an object".to_owned(),
        })?;

    Ok(ChatgptStoredTokens {
        id_token: read_required_string(object.get("id_token"), "tokens.id_token")?,
        access_token: read_required_string(object.get("access_token"), "tokens.access_token")?,
        refresh_token: read_required_string(object.get("refresh_token"), "tokens.refresh_token")?,
    })
}

fn read_required_string(
    value: Option<&Value>,
    field: &'static str,
) -> Result<String, ChatgptAuthParseError> {
    let value = value.ok_or(ChatgptAuthParseError::MissingField { field })?;
    let text = value
        .as_str()
        .ok_or_else(|| ChatgptAuthParseError::InvalidField {
            field,
            reason: "must be a string".to_owned(),
        })?;

    if text.is_empty() {
        return Err(ChatgptAuthParseError::InvalidField {
            field,
            reason: "must not be empty".to_owned(),
        });
    }

    Ok(text.to_owned())
}

pub(crate) fn auth_file_path(selvedge_home: &Path) -> PathBuf {
    selvedge_model_credentials::credential_path(selvedge_home, "chatgpt")
        .expect("built-in provider id is valid")
}

pub(crate) fn load(guard: &CredentialLockGuard) -> Result<StoredAuth, ChatgptAuthError> {
    let path = guard.path().to_owned();
    let record = guard
        .read()
        .map_err(|error| match error {
            ModelCredentialError::ReadFailed { path, reason } => {
                ChatgptAuthError::AuthFileReadFailed { path, reason }
            }
            error => ChatgptAuthError::AuthFileMalformed {
                path: path.clone(),
                reason: error.to_string(),
            },
        })?
        .ok_or_else(|| ChatgptAuthError::AuthFileMissing { path: path.clone() })?;
    from_record(record).map_err(|error| ChatgptAuthError::AuthFileMalformed {
        path,
        reason: format!("{error:?}"),
    })
}

pub(crate) fn load_refresh_hint(home: &Path) -> Option<ChatgptStoredTokens> {
    let record =
        selvedge_model_credentials::read_credential_snapshot_from_home(home, "chatgpt").ok()??;
    from_record(record).ok().map(|stored| stored.tokens)
}

pub(crate) fn persist(
    guard: &CredentialLockGuard,
    tokens: &ChatgptStoredTokens,
) -> Result<(), ChatgptAuthFileWriteError> {
    for (field, value) in [
        ("id_token", &tokens.id_token),
        ("access_token", &tokens.access_token),
        ("refresh_token", &tokens.refresh_token),
    ] {
        if value.is_empty() {
            return Err(ChatgptAuthFileWriteError {
                path: guard.path().to_owned(),
                reason: format!("tokens.{field} must not be empty"),
            });
        }
    }
    guard.write(&ModelCredentialRecord {
        schema_version: 1,
        provider: "chatgpt".to_owned(),
        credential_kind: CredentialKind::Login,
        payload: json!({ "last_refresh": chrono::Utc::now().to_rfc3339(), "tokens": { "id_token": tokens.id_token, "access_token": tokens.access_token, "refresh_token": tokens.refresh_token } }),
    }).map_err(|error| ChatgptAuthFileWriteError { path: guard.path().to_owned(), reason: error.to_string() })
}
