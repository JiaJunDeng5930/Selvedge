#![doc = include_str!("../README.md")]

use std::{
    env,
    ffi::OsString,
    fmt, fs,
    io::Write,
    path::{Path, PathBuf},
    sync::RwLock,
};

use selvedge_config_model::{AppConfig, AppConfigError};
use serde::Serialize;
use tempfile::NamedTempFile;
use thiserror::Error;
use toml::{Table, Value};

const CONFIG_PATH_ENV: &str = "SELVEDGE_CONFIG";
const CONFIG_ENV_PREFIX: &str = "SELVEDGE_APP";
const SEARCH_PATH_PATTERNS: [&str; 3] = [
    "./selvedge.toml",
    "$XDG_CONFIG_HOME/selvedge/config.toml",
    "~/.config/selvedge/config.toml",
];

pub struct AppConfigStore {
    base_config: AppConfig,
    runtime_patch: RwLock<Table>,
    current_config_path: Option<PathBuf>,
}

impl fmt::Debug for AppConfigStore {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AppConfigStore")
            .field("current_config_path", &self.current_config_path)
            .finish_non_exhaustive()
    }
}

impl AppConfigStore {
    pub fn load() -> Result<Self, ConfigError> {
        Self::load_inner(None)
    }

    pub fn load_with_explicit_path<P>(path: P) -> Result<Self, ConfigError>
    where
        P: Into<PathBuf>,
    {
        Self::load_inner(Some(path.into()))
    }

    pub fn read<R, F>(&self, reader: F) -> Result<R, ConfigError>
    where
        F: FnOnce(&AppConfig) -> R,
    {
        let config = {
            let runtime_patch = self
                .runtime_patch
                .read()
                .map_err(|_| ConfigError::LoadFailed("config state lock poisoned".to_owned()))?;
            self.materialize_config(&runtime_patch)?
        };

        Ok(reader(&config))
    }

    pub fn update_runtime<V>(&self, path: &str, value: V) -> Result<(), ConfigError>
    where
        V: Serialize,
    {
        self.apply_update(path, value, false)
    }

    pub fn update_runtime_and_persist<V>(&self, path: &str, value: V) -> Result<(), ConfigError>
    where
        V: Serialize,
    {
        self.apply_update(path, value, true)
    }

    fn load_inner(explicit_path: Option<PathBuf>) -> Result<Self, ConfigError> {
        let current_config_path = if let Some(path) = explicit_path {
            Some(resolve_explicit_path(path)?)
        } else if let Some(path) = env::var_os(CONFIG_PATH_ENV) {
            Some(resolve_env_path(PathBuf::from(path))?)
        } else {
            resolve_search_path()?
        };
        let mut merged_table = load_file_table(current_config_path.as_deref())?;
        let env_table = load_env_table(CONFIG_ENV_PREFIX)?;

        merge_tables(&mut merged_table, &env_table);

        let base_config = AppConfig::try_from(merged_table).map_err(map_model_error)?;

        Ok(Self {
            base_config,
            runtime_patch: RwLock::new(Table::new()),
            current_config_path,
        })
    }

    fn apply_update<V>(&self, path: &str, value: V, persist: bool) -> Result<(), ConfigError>
    where
        V: Serialize,
    {
        let value = Value::try_from(value)
            .map_err(|error| ConfigError::InvalidUpdateValue(error.to_string()))?;
        let mut runtime_patch = self
            .runtime_patch
            .write()
            .map_err(|_| ConfigError::LoadFailed("config state lock poisoned".to_owned()))?;
        let mut candidate_patch = runtime_patch.clone();

        apply_override(&mut candidate_patch, path, value.clone())?;
        self.materialize_config(&candidate_patch)?;

        if persist {
            let current_path = self
                .current_config_path
                .as_deref()
                .ok_or(ConfigError::PersistUnavailable)?;
            self.persist_update(current_path, path, value)?;
        }

        *runtime_patch = candidate_patch;

        Ok(())
    }

    fn materialize_config(&self, runtime_patch: &Table) -> Result<AppConfig, ConfigError> {
        let mut merged_table = serialize_app_config(&self.base_config)?;

        merge_tables(&mut merged_table, runtime_patch);

        AppConfig::try_from(merged_table).map_err(map_model_error)
    }

    fn persist_update(
        &self,
        current_path: &Path,
        path: &str,
        value: Value,
    ) -> Result<(), ConfigError> {
        let mut durable_table = load_file_table(Some(current_path))?;

        apply_override(&mut durable_table, path, value)?;
        AppConfig::try_from(durable_table.clone()).map_err(map_model_error)?;
        write_config_file(current_path, &durable_table)
    }
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ConfigError {
    #[error("explicit config path is invalid: {0}")]
    InvalidExplicitPath(PathBuf),
    #[error("environment config path is invalid: {0}")]
    InvalidEnvPath(PathBuf),
    #[error("searched config path is invalid: {0}")]
    InvalidSearchedPath(PathBuf),
    #[error("failed to load config: {0}")]
    LoadFailed(String),
    #[error("config validation failed: {0}")]
    ValidationFailed(String),
    #[error("invalid update path: {0}")]
    InvalidUpdatePath(String),
    #[error("invalid update value: {0}")]
    InvalidUpdateValue(String),
    #[error("no active config file is selected for persistence")]
    PersistUnavailable,
    #[error("failed to persist config: {0}")]
    PersistFailed(String),
}

fn resolve_explicit_path(path: PathBuf) -> Result<PathBuf, ConfigError> {
    if path.is_file() {
        return Ok(path);
    }

    Err(ConfigError::InvalidExplicitPath(path))
}

fn resolve_env_path(path: PathBuf) -> Result<PathBuf, ConfigError> {
    if path.is_file() {
        return Ok(path);
    }

    Err(ConfigError::InvalidEnvPath(path))
}

fn resolve_search_path() -> Result<Option<PathBuf>, ConfigError> {
    for path in search_path_candidates() {
        if !path.exists() {
            continue;
        }

        if !path.is_file() {
            return Err(ConfigError::InvalidSearchedPath(path));
        }

        return Ok(Some(path));
    }

    Ok(None)
}

fn search_path_candidates() -> Vec<PathBuf> {
    SEARCH_PATH_PATTERNS
        .iter()
        .filter_map(|pattern| expand_search_path_pattern(pattern))
        .collect()
}

fn expand_search_path_pattern(pattern: &str) -> Option<PathBuf> {
    match pattern {
        "./selvedge.toml" => Some(PathBuf::from(pattern)),
        "$XDG_CONFIG_HOME/selvedge/config.toml" => env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .map(|path| path.join("selvedge/config.toml")),
        "~/.config/selvedge/config.toml" => env::var_os("HOME")
            .map(PathBuf::from)
            .map(|path| path.join(".config/selvedge/config.toml")),
        _ => None,
    }
}

fn load_file_table(path: Option<&Path>) -> Result<Table, ConfigError> {
    let Some(path) = path else {
        return Ok(Table::new());
    };

    let contents = fs::read_to_string(path)
        .map_err(|error| ConfigError::LoadFailed(format!("{path:?}: {error}")))?;

    toml::from_str::<Table>(&contents)
        .map_err(|error| ConfigError::LoadFailed(format!("{path:?}: {error}")))
}

fn load_env_table(prefix: &str) -> Result<Table, ConfigError> {
    load_env_table_from_entries(prefix, env::vars_os())
}

fn load_env_table_from_entries<I>(prefix: &str, entries: I) -> Result<Table, ConfigError>
where
    I: IntoIterator<Item = (OsString, OsString)>,
{
    if prefix.is_empty() {
        return Ok(Table::new());
    }

    let normalized_prefix = format!("{}_", prefix.to_ascii_uppercase());
    let mut table = Table::new();

    for (key, raw_value) in entries {
        let Ok(key) = key.into_string() else {
            continue;
        };
        let Ok(raw_value) = raw_value.into_string() else {
            continue;
        };

        if !key.starts_with(&normalized_prefix) {
            continue;
        }

        let suffix = &key[normalized_prefix.len()..];
        if suffix.is_empty() {
            continue;
        }

        let path = suffix
            .split("__")
            .map(str::to_ascii_lowercase)
            .collect::<Vec<_>>()
            .join(".");
        let value = parse_env_value(&raw_value)
            .map_err(|error| ConfigError::LoadFailed(error.to_string()))?;

        apply_override(&mut table, &path, value)?;
    }

    Ok(table)
}

fn parse_env_value(raw: &str) -> Result<Value, toml::de::Error> {
    let wrapped = format!("value = {raw}");

    match toml::from_str::<Table>(&wrapped) {
        Ok(mut table) => Ok(table
            .remove("value")
            .expect("wrapped TOML value must contain key")),
        Err(_) => Ok(Value::String(raw.to_owned())),
    }
}

fn apply_override(table: &mut Table, path: &str, value: Value) -> Result<(), ConfigError> {
    let segments = path.split('.').collect::<Vec<_>>();

    if segments.is_empty() || segments.iter().any(|segment| segment.is_empty()) {
        return Err(ConfigError::InvalidUpdatePath(path.to_owned()));
    }

    let mut current = table;
    for segment in &segments[..segments.len() - 1] {
        let entry = current
            .entry((*segment).to_owned())
            .or_insert_with(|| Value::Table(Table::new()));

        current = match entry {
            Value::Table(next) => next,
            _ => {
                *entry = Value::Table(Table::new());
                match entry {
                    Value::Table(next) => next,
                    _ => unreachable!("entry was just replaced with a table"),
                }
            }
        };
    }

    current.insert(segments[segments.len() - 1].to_owned(), value);

    Ok(())
}

fn merge_tables(base: &mut Table, patch: &Table) {
    for (key, patch_value) in patch {
        match (base.get_mut(key), patch_value) {
            (Some(Value::Table(base_table)), Value::Table(patch_table)) => {
                merge_tables(base_table, patch_table);
            }
            _ => {
                base.insert(key.clone(), patch_value.clone());
            }
        }
    }
}

fn serialize_app_config(config: &AppConfig) -> Result<Table, ConfigError> {
    let value =
        Value::try_from(config).map_err(|error| ConfigError::LoadFailed(error.to_string()))?;

    match value {
        Value::Table(table) => Ok(table),
        _ => Err(ConfigError::LoadFailed(
            "app config must serialize to a table".to_owned(),
        )),
    }
}

fn write_config_file(path: &Path, table: &Table) -> Result<(), ConfigError> {
    let rendered = toml::to_string_pretty(table)
        .map_err(|error| ConfigError::PersistFailed(error.to_string()))?;
    let parent = persistence_directory(path);

    fs::create_dir_all(parent).map_err(|error| ConfigError::PersistFailed(error.to_string()))?;

    let mut temp_file = NamedTempFile::new_in(parent)
        .map_err(|error| ConfigError::PersistFailed(error.to_string()))?;

    temp_file
        .write_all(rendered.as_bytes())
        .map_err(|error| ConfigError::PersistFailed(error.to_string()))?;
    temp_file
        .as_file()
        .sync_all()
        .map_err(|error| ConfigError::PersistFailed(error.to_string()))?;
    temp_file.persist(path).map_err(|error| {
        ConfigError::PersistFailed(format!("{}: {}", path.display(), error.error))
    })?;

    Ok(())
}

fn persistence_directory(path: &Path) -> &Path {
    path.parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."))
}

fn map_model_error(error: AppConfigError) -> ConfigError {
    match error {
        AppConfigError::Deserialize(error) => ConfigError::LoadFailed(error.to_string()),
        AppConfigError::Validation(error) => ConfigError::ValidationFailed(error.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use std::ffi::OsString;
    use std::path::Path;

    use super::{
        AppConfigStore, ConfigError, Value, load_env_table_from_entries, persistence_directory,
    };

    #[test]
    fn env_entries_build_nested_override_table() {
        let table = load_env_table_from_entries(
            "selvedge_test",
            vec![
                (
                    OsString::from("SELVEDGE_TEST_SERVER__PORT"),
                    OsString::from("7200"),
                ),
                (
                    OsString::from("SELVEDGE_TEST_SERVER__HOST"),
                    OsString::from("api.internal"),
                ),
            ],
        )
        .expect("build env override table");

        let server = table
            .get("server")
            .and_then(Value::as_table)
            .expect("server table");

        assert_eq!(server.get("port"), Some(&Value::Integer(7200)));
        assert_eq!(
            server.get("host"),
            Some(&Value::String("api.internal".to_owned()))
        );
    }

    #[cfg(unix)]
    #[test]
    fn env_entries_skip_non_utf8_values() {
        use std::os::unix::ffi::OsStringExt;

        let table = load_env_table_from_entries(
            "selvedge_test",
            vec![
                (
                    OsString::from("SELVEDGE_TEST_SERVER__PORT"),
                    OsString::from("7200"),
                ),
                (
                    OsString::from("SELVEDGE_TEST_SERVER__HOST"),
                    OsString::from_vec(vec![0xff, 0xfe]),
                ),
            ],
        )
        .expect("build env override table");

        let server = table
            .get("server")
            .and_then(Value::as_table)
            .expect("server table");

        assert_eq!(server.get("port"), Some(&Value::Integer(7200)));
        assert!(server.get("host").is_none());
    }

    #[test]
    fn read_drops_lock_before_running_callback() {
        let tempdir = tempfile::TempDir::new().expect("tempdir");
        let config_path = tempdir.path().join("selvedge.toml");

        std::fs::write(
            &config_path,
            r#"
[server]
host = "127.0.0.1"
port = 8080
request_timeout_ms = 5000
"#,
        )
        .expect("write config");

        let store = AppConfigStore::load_with_explicit_path(config_path).expect("load store");

        store
            .read(|_config| {
                assert!(store.runtime_patch.try_write().is_ok());
            })
            .expect("read config");
    }

    #[test]
    fn load_with_explicit_path_rejects_directory() {
        let tempdir = tempfile::TempDir::new().expect("tempdir");
        let config_dir = tempdir.path().join("config");

        std::fs::create_dir_all(&config_dir).expect("create config dir");

        let error = AppConfigStore::load_with_explicit_path(config_dir)
            .expect_err("directory path should fail during load");

        assert!(matches!(error, ConfigError::InvalidExplicitPath(_)));
    }

    #[test]
    fn bare_relative_config_path_uses_current_directory_for_persistence() {
        let parent = persistence_directory(Path::new("config.toml"));

        assert_eq!(parent, Path::new("."));
    }

    #[test]
    fn update_runtime_rejects_empty_path_segments() {
        let tempdir = tempfile::TempDir::new().expect("tempdir");
        let config_path = tempdir.path().join("selvedge.toml");

        std::fs::write(
            &config_path,
            r#"
[server]
host = "127.0.0.1"
port = 8080
request_timeout_ms = 5000
"#,
        )
        .expect("write config");

        let store = AppConfigStore::load_with_explicit_path(config_path).expect("load store");
        let error = store
            .update_runtime("feature..enabled", true)
            .expect_err("malformed path should fail");

        assert_eq!(
            error,
            ConfigError::InvalidUpdatePath("feature..enabled".to_owned())
        );
    }
}
