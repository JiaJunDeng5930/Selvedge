use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
};

use serde_json::{Value, json};

use crate::{
    ChatgptAuthError, ChatgptAuthFile, ChatgptAuthParseError, ChatgptStoredTokens, parse_auth_file,
};

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
    let login_method = read_required_string(object.get("login_method"), "login_method")?;
    let tokens = read_tokens(object.get("tokens"))?;

    if schema_version != 1 {
        return Err(ChatgptAuthParseError::UnsupportedSchemaVersion {
            version: schema_version,
        });
    }

    if provider != "chatgpt" {
        return Err(ChatgptAuthParseError::InvalidField {
            field: "provider",
            reason: "must equal \"chatgpt\"".to_owned(),
        });
    }

    if login_method != "device_code" {
        return Err(ChatgptAuthParseError::InvalidField {
            field: "login_method",
            reason: "must equal \"device_code\"".to_owned(),
        });
    }

    Ok(ChatgptAuthFile {
        schema_version,
        provider,
        login_method,
        tokens,
    })
}

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

    u32::try_from(integer).map_err(|_| ChatgptAuthParseError::InvalidField {
        field: "schema_version",
        reason: "must fit in u32".to_owned(),
    })
}

fn read_tokens(value: Option<&Value>) -> Result<ChatgptStoredTokens, ChatgptAuthParseError> {
    let object = value
        .ok_or(ChatgptAuthParseError::MissingField { field: "tokens" })?
        .as_object()
        .ok_or_else(|| ChatgptAuthParseError::InvalidField {
            field: "tokens",
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
    selvedge_home.join("auth/chatgpt-auth.json")
}

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

    parse_auth_file(&bytes).map_err(|error| ChatgptAuthError::AuthFileMalformed {
        path: path.to_path_buf(),
        reason: format!("{error:?}"),
    })
}

pub(crate) fn load_refresh_hint(path: &Path) -> Option<ChatgptAuthFile> {
    let bytes = fs::read(path).ok()?;

    parse_auth_file(&bytes).ok()
}

pub(crate) fn persist(path: &Path, tokens: &ChatgptStoredTokens) -> Result<(), ChatgptAuthError> {
    let parent = path
        .parent()
        .ok_or_else(|| ChatgptAuthError::PersistFailed {
            path: path.to_path_buf(),
            reason: "auth file path must have a parent directory".to_owned(),
        })?;
    fs::create_dir_all(parent).map_err(|error| ChatgptAuthError::PersistFailed {
        path: path.to_path_buf(),
        reason: error.to_string(),
    })?;

    let payload = serde_json::to_vec(&json!({
        "schema_version": 1,
        "provider": "chatgpt",
        "login_method": "device_code",
        "tokens": {
            "id_token": tokens.id_token,
            "access_token": tokens.access_token,
            "refresh_token": tokens.refresh_token,
        }
    }))
    .map_err(|error| ChatgptAuthError::PersistFailed {
        path: path.to_path_buf(),
        reason: error.to_string(),
    })?;

    let mut temp_file = tempfile::NamedTempFile::new_in(parent).map_err(|error| {
        ChatgptAuthError::PersistFailed {
            path: path.to_path_buf(),
            reason: error.to_string(),
        }
    })?;

    temp_file
        .write_all(&payload)
        .and_then(|_| temp_file.as_file_mut().sync_all())
        .map_err(|error| ChatgptAuthError::PersistFailed {
            path: path.to_path_buf(),
            reason: error.to_string(),
        })?;

    temp_file
        .persist(path)
        .map_err(|error| ChatgptAuthError::PersistFailed {
            path: path.to_path_buf(),
            reason: error.error.to_string(),
        })?;

    Ok(())
}
