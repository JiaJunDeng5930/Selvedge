use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
};

use serde_json::{Value, json};

use crate::{
    ChatgptAuthError, ChatgptAuthFile, ChatgptAuthParseError, ChatgptStoredTokens, parse_auth_file,
};

// @behavior selvedge.auth.file.parse.schema Auth file parsing accepts only the ChatGPT device-code schema version and token fields that request resolution can consume.
pub(crate) fn parse(bytes: &[u8]) -> Result<ChatgptAuthFile, ChatgptAuthParseError> {
    let json: Value =
        serde_json::from_slice(bytes).map_err(|error| ChatgptAuthParseError::InvalidJson {
            reason: error.to_string(),
        })?;
    let object = json
        .as_object()
        .ok_or_else(|| ChatgptAuthParseError::InvalidJson {
            reason: "top-level JSON value must be an object".to_owned(),
        })?;

    let schema_version = read_schema_version(object.get("schema_version"))?;
    let provider = read_required_string(object.get("provider"), "provider")?;
    let credential_kind = read_required_string(object.get("credential_kind"), "credential_kind")?;
    let tokens = read_tokens(object.get("payload"))?;

    if schema_version != 1 {
        // @behavior selvedge.auth.file.parse.unsupported_schema Auth file parsing reports unsupported schema versions as structured parse errors.
        return Err(ChatgptAuthParseError::UnsupportedSchemaVersion {
            version: schema_version,
        });
    }

    if provider != "chatgpt" {
        // @behavior selvedge.auth.file.parse.provider Auth file parsing reports provider values outside the ChatGPT contract as structured parse errors.
        return Err(ChatgptAuthParseError::InvalidField {
            field: "provider",
            reason: "must equal \"chatgpt\"".to_owned(),
        });
    }

    if credential_kind != "login" {
        // @behavior selvedge.auth.file.parse.credential_kind Auth file parsing reports credential kinds outside the login contract as structured parse errors.
        return Err(ChatgptAuthParseError::InvalidField {
            field: "credential_kind",
            reason: "must equal \"login\"".to_owned(),
        });
    }

    Ok(ChatgptAuthFile {
        schema_version,
        provider,
        credential_kind,
        tokens,
    })
}

// @constraint selvedge.auth.file.schema_version The persisted ChatGPT auth schema version must be a positive integer that fits in a u32.
fn read_schema_version(value: Option<&Value>) -> Result<u32, ChatgptAuthParseError> {
    let value = value.ok_or(ChatgptAuthParseError::MissingField {
        field: "schema_version",
    })?;
    let integer = value
        .as_u64()
        .ok_or_else(|| ChatgptAuthParseError::InvalidField {
            field: "schema_version",
            reason: "must be a positive integer".to_owned(),
        })?;

    // @constraint selvedge.auth.file.schema_version.range Auth file parsing rejects schema versions that exceed the public u32 schema field.
    u32::try_from(integer).map_err(|_| ChatgptAuthParseError::InvalidField {
        field: "schema_version",
        reason: "must fit in u32".to_owned(),
    })
}

// @behavior selvedge.auth.file.tokens.required Auth file parsing requires id_token, access_token, and refresh_token values before credentials can be resolved.
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

// @constraint selvedge.auth.file.required_string Required auth file string fields must be present and nonempty in caller-visible parse results.
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
        // @constraint selvedge.auth.file.required_string.empty Required auth file string fields must contain a value before parsing succeeds.
        return Err(ChatgptAuthParseError::InvalidField {
            field,
            reason: "must not be empty".to_owned(),
        });
    }

    Ok(text.to_owned())
}

// @behavior selvedge.auth.file.path ChatGPT auth state is read from and written to the provider credential record at `<selvedge_home>/auth/model-providers/chatgpt.json`.
pub(crate) fn auth_file_path(selvedge_home: &Path) -> PathBuf {
    selvedge_home.join("auth/model-providers/chatgpt.json")
}

// @behavior selvedge.auth.file.load Auth file loading maps absent, unreadable, and malformed local auth files into caller-visible auth resolution errors.
pub(crate) fn load(path: &Path) -> Result<ChatgptAuthFile, ChatgptAuthError> {
    let bytes = fs::read(path).map_err(|error| match error.kind() {
        std::io::ErrorKind::NotFound => ChatgptAuthError::AuthFileMissing {
            path: path.to_path_buf(),
        },
        _ => ChatgptAuthError::AuthFileReadFailed {
            path: path.to_path_buf(),
            reason: error.to_string(),
        },
    })?;

    // @behavior selvedge.auth.file.load.malformed Malformed local auth file content is returned as a caller-visible auth file malformed error with the target path.
    parse_auth_file(&bytes).map_err(|error| ChatgptAuthError::AuthFileMalformed {
        path: path.to_path_buf(),
        reason: format!("{error:?}"),
    })
}

// @behavior selvedge.auth.file.refresh_hint Forced refreshes may observe a pre-lock auth file snapshot to detect whether another caller already repaired credentials.
pub(crate) fn load_refresh_hint(path: &Path) -> Option<ChatgptAuthFile> {
    let bytes = fs::read(path).ok()?;

    parse_auth_file(&bytes).ok()
}

// @behavior selvedge.auth.file.persist Successful auth refresh writes the ChatGPT auth file atomically with schema version one and device-code token fields.
pub(crate) fn persist(path: &Path, tokens: &ChatgptStoredTokens) -> Result<(), ChatgptAuthError> {
    let parent = path
        .parent()
        // @behavior selvedge.auth.file.persist.parent Persisting ChatGPT auth reports target paths without parent directories as persist failures.
        .ok_or_else(|| ChatgptAuthError::PersistFailed {
            path: path.to_path_buf(),
            reason: "auth file path must have a parent directory".to_owned(),
        })?;
    // @behavior selvedge.auth.file.persist.directory Persisting ChatGPT auth creates the target auth directory or reports a persist failure.
    fs::create_dir_all(parent).map_err(|error| ChatgptAuthError::PersistFailed {
        path: path.to_path_buf(),
        reason: error.to_string(),
    })?;

    let payload = serde_json::to_vec(&json!({
        "schema_version": 1,
        "provider": "chatgpt",
        "credential_kind": "login",
        "payload": {
            "tokens": {
                "id_token": tokens.id_token,
                "access_token": tokens.access_token,
                "refresh_token": tokens.refresh_token,
            }
        }
    }))
    // @behavior selvedge.auth.file.persist.encode Persisting ChatGPT auth reports serialization failures as persist failures with the target path.
    .map_err(|error| ChatgptAuthError::PersistFailed {
        path: path.to_path_buf(),
        reason: error.to_string(),
    })?;

    // @behavior selvedge.auth.file.persist.temp Persisting ChatGPT auth reports temporary file creation failures as persist failures with the target path.
    let mut temp_file = tempfile::NamedTempFile::new_in(parent).map_err(|error| {
        ChatgptAuthError::PersistFailed {
            path: path.to_path_buf(),
            reason: error.to_string(),
        }
    })?;

    temp_file
        .write_all(&payload)
        .and_then(|_| temp_file.as_file_mut().sync_all())
        // @behavior selvedge.auth.file.persist.write Persisting ChatGPT auth reports payload write and sync failures as persist failures with the target path.
        .map_err(|error| ChatgptAuthError::PersistFailed {
            path: path.to_path_buf(),
            reason: error.to_string(),
        })?;

    temp_file
        .persist(path)
        // @behavior selvedge.auth.file.persist.replace Persisting ChatGPT auth reports atomic replacement failures as persist failures with the target path.
        .map_err(|error| ChatgptAuthError::PersistFailed {
            path: path.to_path_buf(),
            reason: error.error.to_string(),
        })?;

    Ok(())
}
