#![doc = include_str!("../README.md")]

use std::{
    env,
    ffi::OsString,
    fs,
    io::Write,
    path::{Path, PathBuf},
    sync::{LazyLock, OnceLock, RwLock},
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

static CONFIG_SERVICE: LazyLock<RwLock<Option<ConfigService>>> =
    LazyLock::new(|| RwLock::new(None));

pub fn init() -> Result<(), ConfigError> {
    init_with_cli::<PathBuf, _, _, _>(None, std::iter::empty::<(String, String)>())
}

pub fn init_with_path<P>(path: P) -> Result<(), ConfigError>
where
    P: Into<PathBuf>,
{
    init_with_cli(Some(path), std::iter::empty::<(String, String)>())
}

pub fn init_with_cli<P, I, K, V>(
    explicit_path: Option<P>,
    cli_overrides: I,
) -> Result<(), ConfigError>
where
    P: Into<PathBuf>,
    I: IntoIterator<Item = (K, V)>,
    K: Into<String>,
    V: Into<String>,
{
    let resolved_path = if let Some(path) = explicit_path {
        Some(resolve_explicit_path(path.into())?)
    } else if let Some(path) = env::var_os(CONFIG_PATH_ENV) {
        Some(resolve_env_path(PathBuf::from(path))?)
    } else {
        resolve_search_path()?
    };
    let mut merged_table = load_file_table(resolved_path.as_deref())?;
    let env_table = load_env_table()?;
    let cli_table = load_cli_table(cli_overrides)?;

    merge_tables(&mut merged_table, &env_table);
    merge_tables(&mut merged_table, &cli_table);

    let base_config = AppConfig::try_from(merged_table).map_err(map_model_error)?;
    let service = ConfigService::new(base_config, resolved_path);
    let mut global = CONFIG_SERVICE
        .write()
        .map_err(|_| ConfigError::LoadFailed("config service lock poisoned".to_owned()))?;

    if global.is_some() {
        return Err(ConfigError::AlreadyInitialized);
    }

    *global = Some(service);

    Ok(())
}

pub fn read<R, F>(reader: F) -> Result<R, ConfigError>
where
    F: FnOnce(&AppConfig) -> R,
{
    let config = materialize_current_config()?;

    Ok(reader(&config))
}

pub fn update_runtime<V>(path: &str, value: V) -> Result<(), ConfigError>
where
    V: Serialize,
{
    apply_update(path, value, false)
}

pub fn update_runtime_and_persist<V>(path: &str, value: V) -> Result<(), ConfigError>
where
    V: Serialize,
{
    apply_update(path, value, true)
}

fn apply_update<V>(path: &str, value: V, persist: bool) -> Result<(), ConfigError>
where
    V: Serialize,
{
    let value = Value::try_from(value)
        .map_err(|error| ConfigError::InvalidUpdateValue(error.to_string()))?;
    let mut global = CONFIG_SERVICE
        .write()
        .map_err(|_| ConfigError::LoadFailed("config service lock poisoned".to_owned()))?;
    let service = global.as_mut().ok_or(ConfigError::NotInitialized)?;

    service.apply_update(path, value, persist)
}

#[derive(Debug)]
struct ConfigService {
    base_config: OnceLock<AppConfig>,
    current_config_path: OnceLock<Option<PathBuf>>,
    runtime_patch: RwLock<Table>,
}

impl ConfigService {
    fn new(base_config: AppConfig, current_config_path: Option<PathBuf>) -> Self {
        let service = Self {
            base_config: OnceLock::new(),
            current_config_path: OnceLock::new(),
            runtime_patch: RwLock::new(Table::new()),
        };

        service
            .base_config
            .set(base_config)
            .expect("base config must be initialized exactly once");
        service
            .current_config_path
            .set(current_config_path)
            .expect("current config path must be initialized exactly once");

        service
    }

    fn materialize_config(&self) -> Result<AppConfig, ConfigError> {
        let mut merged_table = serialize_app_config(self.base_config())?;
        let runtime_patch = self
            .runtime_patch
            .read()
            .map_err(|_| ConfigError::LoadFailed("runtime patch lock poisoned".to_owned()))?;

        merge_tables(&mut merged_table, &runtime_patch);

        AppConfig::try_from(merged_table).map_err(map_model_error)
    }

    fn apply_update(&mut self, path: &str, value: Value, persist: bool) -> Result<(), ConfigError> {
        let mut candidate_patch = {
            let runtime_patch = self
                .runtime_patch
                .get_mut()
                .map_err(|_| ConfigError::LoadFailed("runtime patch lock poisoned".to_owned()))?;
            runtime_patch.clone()
        };

        apply_override(&mut candidate_patch, path, value.clone())?;
        self.materialize_candidate(&candidate_patch)?;

        if persist {
            self.persist_update(path, value)?;
        }

        let runtime_patch = self
            .runtime_patch
            .get_mut()
            .map_err(|_| ConfigError::LoadFailed("runtime patch lock poisoned".to_owned()))?;
        *runtime_patch = candidate_patch;

        Ok(())
    }

    fn materialize_candidate(&self, runtime_patch: &Table) -> Result<AppConfig, ConfigError> {
        let mut merged_table = serialize_app_config(self.base_config())?;

        merge_tables(&mut merged_table, runtime_patch);

        AppConfig::try_from(merged_table).map_err(map_model_error)
    }

    fn persist_update(&self, path: &str, value: Value) -> Result<(), ConfigError> {
        let current_path = self
            .current_config_path()
            .as_deref()
            .ok_or(ConfigError::PersistUnavailable)?;
        let mut durable_table = load_file_table(Some(current_path))?;

        apply_override(&mut durable_table, path, value)?;
        AppConfig::try_from(durable_table.clone()).map_err(map_model_error)?;
        write_config_file(current_path, &durable_table)
    }

    fn base_config(&self) -> &AppConfig {
        self.base_config
            .get()
            .expect("base config must be initialized before use")
    }

    fn current_config_path(&self) -> &Option<PathBuf> {
        self.current_config_path
            .get()
            .expect("current config path must be initialized before use")
    }
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ConfigError {
    #[error("config service has already been initialized")]
    AlreadyInitialized,
    #[error("config service has not been initialized")]
    NotInitialized,
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
        return fs::canonicalize(&path).map_err(|_| ConfigError::InvalidExplicitPath(path));
    }

    Err(ConfigError::InvalidExplicitPath(path))
}

fn materialize_current_config() -> Result<AppConfig, ConfigError> {
    let global = CONFIG_SERVICE
        .read()
        .map_err(|_| ConfigError::LoadFailed("config service lock poisoned".to_owned()))?;
    let service = global.as_ref().ok_or(ConfigError::NotInitialized)?;

    service.materialize_config()
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
    let mut paths = Vec::with_capacity(SEARCH_PATH_PATTERNS.len());

    for pattern in SEARCH_PATH_PATTERNS {
        match pattern {
            "./selvedge.toml" => paths.push(PathBuf::from(pattern)),
            "$XDG_CONFIG_HOME/selvedge/config.toml" => {
                if let Some(xdg_config_home) = env::var_os("XDG_CONFIG_HOME") {
                    paths.push(PathBuf::from(xdg_config_home).join("selvedge/config.toml"));
                }
            }
            "~/.config/selvedge/config.toml" => {
                if let Some(home) = env::var_os("HOME") {
                    paths.push(PathBuf::from(home).join(".config/selvedge/config.toml"));
                }
            }
            _ => {}
        }
    }

    paths
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

fn load_env_table() -> Result<Table, ConfigError> {
    load_env_table_from_entries(env::vars_os())
}

fn load_env_table_from_entries<I>(entries: I) -> Result<Table, ConfigError>
where
    I: IntoIterator<Item = (OsString, OsString)>,
{
    let normalized_prefix = format!("{}_", CONFIG_ENV_PREFIX);
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
        let value = parse_toml_like_value(&raw_value)
            .map_err(|error| ConfigError::LoadFailed(error.to_string()))?;

        apply_override(&mut table, &path, value)?;
    }

    Ok(table)
}

fn load_cli_table<I, K, V>(entries: I) -> Result<Table, ConfigError>
where
    I: IntoIterator<Item = (K, V)>,
    K: Into<String>,
    V: Into<String>,
{
    let mut table = Table::new();

    for (path, raw_value) in entries {
        let path = path.into();
        let value = parse_toml_like_value(&raw_value.into())
            .map_err(|error| ConfigError::LoadFailed(error.to_string()))?;

        apply_override(&mut table, &path, value)?;
    }

    Ok(table)
}

fn parse_toml_like_value(raw: &str) -> Result<Value, toml::de::Error> {
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
fn reset_for_test() {
    let mut global = CONFIG_SERVICE
        .write()
        .expect("config service lock must not be poisoned");
    *global = None;
}

#[cfg(test)]
mod tests {
    use std::env;
    use std::ffi::OsString;
    use std::path::{Path, PathBuf};
    use std::sync::{LazyLock, Mutex};

    use super::{
        CONFIG_SERVICE, ConfigError, Value, load_env_table_from_entries,
        materialize_current_config, persistence_directory, reset_for_test,
    };

    static TEST_LOCK: LazyLock<Mutex<()>> = LazyLock::new(|| Mutex::new(()));

    #[test]
    fn env_entries_build_nested_override_table() {
        let table = load_env_table_from_entries(vec![
            (
                OsString::from("SELVEDGE_APP_SERVER__PORT"),
                OsString::from("7200"),
            ),
            (
                OsString::from("SELVEDGE_APP_SERVER__HOST"),
                OsString::from("api.internal"),
            ),
        ])
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

        let table = load_env_table_from_entries(vec![
            (
                OsString::from("SELVEDGE_APP_SERVER__PORT"),
                OsString::from("7200"),
            ),
            (
                OsString::from("SELVEDGE_APP_SERVER__HOST"),
                OsString::from_vec(vec![0xff, 0xfe]),
            ),
        ])
        .expect("build env override table");

        let server = table
            .get("server")
            .and_then(Value::as_table)
            .expect("server table");

        assert_eq!(server.get("port"), Some(&Value::Integer(7200)));
        assert!(server.get("host").is_none());
    }

    #[test]
    fn read_requires_initialization() {
        let _guard = TEST_LOCK.lock().expect("test lock");
        reset_for_test();

        let error = crate::read(|config| config.server.port).expect_err("must fail before init");

        assert_eq!(error, ConfigError::NotInitialized);
    }

    #[test]
    fn init_with_explicit_path_rejects_directory() {
        let _guard = TEST_LOCK.lock().expect("test lock");
        reset_for_test();
        let tempdir = tempfile::TempDir::new().expect("tempdir");
        let config_dir = tempdir.path().join("config");

        std::fs::create_dir_all(&config_dir).expect("create config dir");

        let error =
            crate::init_with_path(config_dir).expect_err("directory path should fail during init");

        assert!(matches!(error, ConfigError::InvalidExplicitPath(_)));
    }

    #[test]
    fn bare_relative_config_path_uses_current_directory_for_persistence() {
        let parent = persistence_directory(Path::new("config.toml"));

        assert_eq!(parent, Path::new("."));
    }

    #[test]
    fn update_runtime_rejects_empty_path_segments() {
        let _guard = TEST_LOCK.lock().expect("test lock");
        reset_for_test();
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

        crate::init_with_path(config_path).expect("init config service");
        let error = crate::update_runtime("feature..enabled", true)
            .expect_err("malformed path should fail");

        assert_eq!(
            error,
            ConfigError::InvalidUpdatePath("feature..enabled".to_owned())
        );
    }

    #[test]
    fn materialize_current_config_releases_global_lock_before_returning() {
        let _guard = TEST_LOCK.lock().expect("test lock");
        reset_for_test();
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

        crate::init_with_path(config_path).expect("init config service");

        let config = materialize_current_config().expect("materialize current config");
        let write_guard = CONFIG_SERVICE
            .try_write()
            .expect("global config lock should be released after materializing");

        assert_eq!(config.server.port, 8080);
        drop(write_guard);
    }

    #[test]
    fn explicit_relative_path_is_canonicalized_for_persistence() {
        let _guard = TEST_LOCK.lock().expect("test lock");
        reset_for_test();
        let original_dir = env::current_dir().expect("current dir");
        let tempdir = tempfile::TempDir::new().expect("tempdir");
        let config_dir = tempdir.path().join("workspace/config");
        let work_dir = tempdir.path().join("workspace/bin");
        let moved_dir = tempdir.path().join("other/place");
        let config_path = config_dir.join("selvedge.toml");

        std::fs::create_dir_all(&config_dir).expect("create config dir");
        std::fs::create_dir_all(&work_dir).expect("create work dir");
        std::fs::create_dir_all(&moved_dir).expect("create moved dir");
        std::fs::write(
            &config_path,
            r#"
[server]
host = "127.0.0.1"
port = 8080
request_timeout_ms = 5000

[logging]
level = "info"
format = "text"
"#,
        )
        .expect("write config");

        let relative_path = relative_path_from(&work_dir, &config_path);
        let test_result = (|| -> Result<(), String> {
            env::set_current_dir(&work_dir).map_err(|error| error.to_string())?;
            crate::init_with_path(&relative_path).map_err(|error| error.to_string())?;
            env::set_current_dir(&moved_dir).map_err(|error| error.to_string())?;
            crate::update_runtime_and_persist("logging.level", "debug")
                .map_err(|error| error.to_string())?;

            Ok(())
        })();

        env::set_current_dir(&original_dir).expect("restore current dir");
        test_result.expect("persist runtime update");

        let persisted =
            std::fs::read_to_string(&config_path).expect("read persisted config from source path");
        let drifted_path = moved_dir.join(relative_path);

        assert!(persisted.contains("level = \"debug\""));
        assert_ne!(drifted_path, config_path);
        assert!(!drifted_path.exists());
    }

    fn relative_path_from(base: &Path, target: &Path) -> PathBuf {
        let base_components = base.components().collect::<Vec<_>>();
        let target_components = target.components().collect::<Vec<_>>();
        let shared_prefix_len = base_components
            .iter()
            .zip(&target_components)
            .take_while(|(left, right)| left == right)
            .count();
        let mut relative = PathBuf::new();

        for _ in &base_components[shared_prefix_len..] {
            relative.push("..");
        }

        for component in &target_components[shared_prefix_len..] {
            relative.push(component.as_os_str());
        }

        relative
    }
}
