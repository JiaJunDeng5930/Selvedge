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

const CONFIG_HOME_ENV: &str = "SELVEDGE_HOME";
const LEGACY_CONFIG_PATH_ENV: &str = "SELVEDGE_CONFIG";
const CONFIG_ENV_PREFIX: &str = "SELVEDGE_APP";
const CONFIG_FILE_NAME: &str = "config.toml";
const SEARCH_HOME_PATTERNS: [&str; 4] = [
    "./.selvedge",
    "$XDG_CONFIG_HOME/selvedge",
    "~/.config/selvedge",
    "~/.selvedge",
];

static CONFIG_SERVICE: LazyLock<RwLock<Option<ConfigService>>> =
    LazyLock::new(|| RwLock::new(None));

pub fn init() -> Result<(), ConfigError> {
    init_with_cli::<PathBuf, _, _, _>(None, std::iter::empty::<(String, String)>())
}

pub fn init_with_home<P>(home: P) -> Result<(), ConfigError>
where
    P: Into<PathBuf>,
{
    init_with_cli(Some(home), std::iter::empty::<(String, String)>())
}

pub fn init_with_cli<P, I, K, V>(
    explicit_home: Option<P>,
    cli_overrides: I,
) -> Result<(), ConfigError>
where
    P: Into<PathBuf>,
    I: IntoIterator<Item = (K, V)>,
    K: Into<String>,
    V: Into<String>,
{
    let resolved_home = if let Some(home) = explicit_home {
        Some(resolve_explicit_home(home.into())?)
    } else if let Some(home) = env::var_os(CONFIG_HOME_ENV) {
        Some(resolve_env_home(PathBuf::from(home))?)
    } else if let Some(path) = env::var_os(LEGACY_CONFIG_PATH_ENV) {
        return Err(ConfigError::LegacyConfigEnvUnsupported(PathBuf::from(path)));
    } else {
        resolve_search_home()?
    };
    let should_create_default_home = resolved_home.is_none();
    let selvedge_home = if let Some(home) = resolved_home {
        home
    } else {
        select_default_home_candidate()
    };
    let config_path = config_path_for_home(&selvedge_home);
    let mut merged_table = load_file_table_if_exists(&config_path)?;
    let env_table = load_env_table()?;
    let cli_table = load_cli_table(cli_overrides)?;

    merge_tables(&mut merged_table, &env_table);
    merge_tables(&mut merged_table, &cli_table);

    let base_config = AppConfig::try_from(merged_table).map_err(map_model_error)?;
    let mut global = CONFIG_SERVICE
        .write()
        .map_err(|_| ConfigError::LoadFailed("config service lock poisoned".to_owned()))?;

    if global.is_some() {
        return Err(ConfigError::AlreadyInitialized);
    }

    let selvedge_home = if should_create_default_home {
        create_default_home()?
    } else {
        selvedge_home
    };

    let service = ConfigService::new(base_config, selvedge_home);
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

pub fn selvedge_home() -> Result<PathBuf, ConfigError> {
    let global = CONFIG_SERVICE
        .read()
        .map_err(|_| ConfigError::LoadFailed("config service lock poisoned".to_owned()))?;
    let service = global.as_ref().ok_or(ConfigError::NotInitialized)?;

    Ok(service.selvedge_home().to_path_buf())
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
    selvedge_home: OnceLock<PathBuf>,
    runtime_patch: RwLock<Table>,
}

impl ConfigService {
    fn new(base_config: AppConfig, selvedge_home: PathBuf) -> Self {
        let service = Self {
            base_config: OnceLock::new(),
            selvedge_home: OnceLock::new(),
            runtime_patch: RwLock::new(Table::new()),
        };

        service
            .base_config
            .set(base_config)
            .expect("base config must be initialized exactly once");
        service
            .selvedge_home
            .set(selvedge_home)
            .expect("selvedge home must be initialized exactly once");

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
        let config_path = config_path_for_home(self.selvedge_home());
        let mut durable_table = load_file_table_if_exists(&config_path)?;

        apply_override(&mut durable_table, path, value)?;
        AppConfig::try_from(durable_table.clone()).map_err(map_model_error)?;
        write_config_file(&config_path, &durable_table)
    }

    fn base_config(&self) -> &AppConfig {
        self.base_config
            .get()
            .expect("base config must be initialized before use")
    }

    fn selvedge_home(&self) -> &Path {
        self.selvedge_home
            .get()
            .expect("selvedge home must be initialized before use")
    }
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ConfigError {
    #[error("config service has already been initialized")]
    AlreadyInitialized,
    #[error("config service has not been initialized")]
    NotInitialized,
    #[error("explicit selvedge home is invalid: {0}")]
    InvalidExplicitHome(PathBuf),
    #[error("environment selvedge home is invalid: {0}")]
    InvalidEnvHome(PathBuf),
    #[error("searched selvedge home is invalid: {0}")]
    InvalidSearchedHome(PathBuf),
    #[error(
        "legacy SELVEDGE_CONFIG is unsupported; use SELVEDGE_HOME with a directory path instead: {0}"
    )]
    LegacyConfigEnvUnsupported(PathBuf),
    #[error("failed to load config: {0}")]
    LoadFailed(String),
    #[error("config validation failed: {0}")]
    ValidationFailed(String),
    #[error("invalid update path: {0}")]
    InvalidUpdatePath(String),
    #[error("invalid update value: {0}")]
    InvalidUpdateValue(String),
    #[error("failed to persist config: {0}")]
    PersistFailed(String),
}

fn resolve_explicit_home(home: PathBuf) -> Result<PathBuf, ConfigError> {
    resolve_home(home, ConfigHomeSource::Explicit)
}

fn materialize_current_config() -> Result<AppConfig, ConfigError> {
    let global = CONFIG_SERVICE
        .read()
        .map_err(|_| ConfigError::LoadFailed("config service lock poisoned".to_owned()))?;
    let service = global.as_ref().ok_or(ConfigError::NotInitialized)?;

    service.materialize_config()
}

fn resolve_env_home(home: PathBuf) -> Result<PathBuf, ConfigError> {
    resolve_home(home, ConfigHomeSource::Environment)
}

fn resolve_search_home() -> Result<Option<PathBuf>, ConfigError> {
    for home in search_home_candidates() {
        if !home.exists() {
            continue;
        }

        let resolved_home = resolve_home(home, ConfigHomeSource::Search)?;
        if !config_path_for_home(&resolved_home).is_file() {
            continue;
        }

        return Ok(Some(resolved_home));
    }

    Ok(None)
}

fn search_home_candidates() -> Vec<PathBuf> {
    let mut homes = Vec::with_capacity(SEARCH_HOME_PATTERNS.len());

    for pattern in SEARCH_HOME_PATTERNS {
        match pattern {
            "./.selvedge" => homes.push(PathBuf::from(pattern)),
            "$XDG_CONFIG_HOME/selvedge" => {
                if let Some(xdg_config_home) = env::var_os("XDG_CONFIG_HOME") {
                    homes.push(PathBuf::from(xdg_config_home).join("selvedge"));
                }
            }
            "~/.config/selvedge" => {
                if let Some(home) = env::var_os("HOME") {
                    homes.push(PathBuf::from(home).join(".config/selvedge"));
                }
            }
            "~/.selvedge" => {
                if let Some(home) = env::var_os("HOME") {
                    homes.push(PathBuf::from(home).join(".selvedge"));
                }
            }
            _ => {}
        }
    }

    homes
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

fn load_file_table_if_exists(path: &Path) -> Result<Table, ConfigError> {
    if path.exists() {
        return load_file_table(Some(path));
    }

    Ok(Table::new())
}

fn config_path_for_home(home: &Path) -> PathBuf {
    home.join(CONFIG_FILE_NAME)
}

fn create_home_with_empty_config(selvedge_home: &Path) -> Result<PathBuf, ConfigError> {
    let config_path = config_path_for_home(selvedge_home);

    fs::create_dir_all(selvedge_home).map_err(|error| {
        ConfigError::LoadFailed(format!("{}: {error}", selvedge_home.display()))
    })?;

    if !config_path.exists() {
        fs::write(&config_path, "").map_err(|error| {
            ConfigError::LoadFailed(format!("{}: {error}", config_path.display()))
        })?;
    }

    fs::canonicalize(selvedge_home).map_err(|_| {
        ConfigError::LoadFailed(format!(
            "{}: failed to canonicalize",
            selvedge_home.display()
        ))
    })
}

fn create_default_home() -> Result<PathBuf, ConfigError> {
    let mut last_error = None;

    for selvedge_home in default_home_candidates() {
        match create_home_with_empty_config(&selvedge_home) {
            Ok(home) => return Ok(home),
            Err(error) => last_error = Some(error),
        }
    }

    Err(last_error.unwrap_or_else(|| ConfigError::InvalidSearchedHome(PathBuf::from(".selvedge"))))
}

fn select_default_home_candidate() -> PathBuf {
    default_home_candidates()
        .into_iter()
        .next()
        .unwrap_or_else(|| PathBuf::from(".selvedge"))
}

fn default_home_candidates() -> Vec<PathBuf> {
    let mut homes = Vec::new();
    let local_home = env::current_dir()
        .map(|current_dir| current_dir.join(".selvedge"))
        .unwrap_or_else(|_| PathBuf::from(".selvedge"));
    if local_home.exists() {
        homes.push(local_home.clone());
    }

    if let Some(home_root) = env::var_os("HOME") {
        let home_root = PathBuf::from(home_root);
        if home_root.exists() {
            homes.push(home_root.join(".selvedge"));
            let config_home = home_root.join(".config/selvedge");
            if !homes.contains(&config_home) {
                homes.push(config_home);
            }
        }
    }

    if let Some(xdg_config_home) = env::var_os("XDG_CONFIG_HOME") {
        let xdg_home = PathBuf::from(xdg_config_home).join("selvedge");
        if !homes.contains(&xdg_home) {
            homes.push(xdg_home);
        }
    }

    if !homes.contains(&local_home) {
        homes.push(local_home);
    }

    homes
}

fn resolve_home(home: PathBuf, source: ConfigHomeSource) -> Result<PathBuf, ConfigError> {
    if !home.exists() {
        return Err(source.invalid_home(home));
    }
    if !home.is_dir() {
        return Err(source.invalid_home(home));
    }

    fs::canonicalize(&home).map_err(|_| source.invalid_home(home))
}

enum ConfigHomeSource {
    Explicit,
    Environment,
    Search,
}

impl ConfigHomeSource {
    fn invalid_home(&self, home: PathBuf) -> ConfigError {
        match self {
            Self::Explicit => ConfigError::InvalidExplicitHome(home),
            Self::Environment => ConfigError::InvalidEnvHome(home),
            Self::Search => ConfigError::InvalidSearchedHome(home),
        }
    }
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
    use std::process::Command;
    use std::sync::{LazyLock, Mutex};

    use super::{
        CONFIG_SERVICE, ConfigError, Value, config_path_for_home, load_env_table_from_entries,
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
    fn init_with_explicit_home_accepts_missing_config_file() {
        let _guard = TEST_LOCK.lock().expect("test lock");
        reset_for_test();
        let tempdir = tempfile::TempDir::new().expect("tempdir");
        let config_home = tempdir.path().join("config-home");

        std::fs::create_dir_all(&config_home).expect("create config home");

        crate::init_with_home(config_home).expect("home without config file should init");

        let port = crate::read(|config| config.server.port).expect("read default config");

        assert_eq!(port, 8080);
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
        let config_home = tempdir.path().join("config-home");
        let config_path = config_home.join("config.toml");

        std::fs::create_dir_all(&config_home).expect("create config home");

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

        crate::init_with_home(config_home).expect("init config service");
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
        let config_home = tempdir.path().join("config-home");
        let config_path = config_home.join("config.toml");

        std::fs::create_dir_all(&config_home).expect("create config home");

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

        crate::init_with_home(config_home).expect("init config service");

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
        let config_home = tempdir.path().join("workspace/config-home");
        let work_dir = tempdir.path().join("workspace/bin");
        let moved_dir = tempdir.path().join("other/place");
        let config_path = config_home.join("config.toml");

        std::fs::create_dir_all(&config_home).expect("create config home");
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

        let relative_home = relative_path_from(&work_dir, &config_home);
        let test_result = (|| -> Result<(), String> {
            env::set_current_dir(&work_dir).map_err(|error| error.to_string())?;
            crate::init_with_home(&relative_home).map_err(|error| error.to_string())?;
            env::set_current_dir(&moved_dir).map_err(|error| error.to_string())?;
            crate::update_runtime_and_persist("logging.level", "debug")
                .map_err(|error| error.to_string())?;

            Ok(())
        })();

        env::set_current_dir(&original_dir).expect("restore current dir");
        test_result.expect("persist runtime update");

        let persisted =
            std::fs::read_to_string(&config_path).expect("read persisted config from source path");
        let drifted_home = moved_dir.join(relative_home);
        let drifted_path = drifted_home.join("config.toml");

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

    #[test]
    fn init_finds_current_directory_home_for_persistence() {
        let _guard = TEST_LOCK.lock().expect("test lock");
        reset_for_test();
        let original_dir = env::current_dir().expect("current dir");
        let tempdir = tempfile::TempDir::new().expect("tempdir");
        let work_dir = tempdir.path().join("workspace");
        let config_home = work_dir.join(".selvedge");
        let config_path = config_home.join("config.toml");

        std::fs::create_dir_all(&work_dir).expect("create work dir");
        std::fs::create_dir_all(&config_home).expect("create config home");
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

        let test_result = (|| -> Result<(), String> {
            env::set_current_dir(&work_dir).map_err(|error| error.to_string())?;
            crate::init().map_err(|error| error.to_string())?;
            crate::update_runtime_and_persist("logging.level", "debug")
                .map_err(|error| error.to_string())?;

            Ok(())
        })();

        env::set_current_dir(&original_dir).expect("restore current dir");
        test_result.expect("persist runtime update");

        let persisted = std::fs::read_to_string(&config_path).expect("read persisted config");

        assert!(persisted.contains("level = \"debug\""));
    }

    #[test]
    fn cli_only_init_creates_default_home_immediately() {
        let _guard = TEST_LOCK.lock().expect("test lock");
        reset_for_test();
        if env::var_os("SELVEDGE_CONFIG_CLI_ONLY_CHILD").is_some() {
            let selected_home = crate::init_with_cli(
                None::<PathBuf>,
                vec![("server.port".to_owned(), "9100".to_owned())],
            )
            .and_then(|_| crate::selvedge_home())
            .expect("initialize cli-only config");
            let config_path = config_path_for_home(&selected_home);

            assert!(
                config_path.exists(),
                "config file should exist after cli-only init"
            );
            return;
        }

        let tempdir = tempfile::TempDir::new().expect("tempdir");
        let work_dir = tempdir.path().join("workspace");
        let home_dir = tempdir.path().join("isolated-home");
        let xdg_dir = tempdir.path().join("isolated-xdg");
        let current_executable = env::current_exe().expect("current test executable");

        std::fs::create_dir_all(&work_dir).expect("create work dir");
        std::fs::create_dir_all(&home_dir).expect("create home dir");
        std::fs::create_dir_all(&xdg_dir).expect("create xdg dir");

        let output = Command::new(current_executable)
            .arg("--exact")
            .arg("tests::cli_only_init_creates_default_home_immediately")
            .current_dir(&work_dir)
            .env("SELVEDGE_CONFIG_CLI_ONLY_CHILD", "1")
            .env("HOME", &home_dir)
            .env("XDG_CONFIG_HOME", &xdg_dir)
            .env_remove("SELVEDGE_HOME")
            .env_remove("SELVEDGE_CONFIG")
            .output()
            .expect("run cli-only child test");

        assert!(output.status.success(), "child test failed: {output:?}");
    }

    #[test]
    fn cli_only_persist_uses_reported_home() {
        let _guard = TEST_LOCK.lock().expect("test lock");
        reset_for_test();
        if env::var_os("SELVEDGE_CONFIG_CLI_ONLY_PERSIST_CHILD").is_some() {
            let original_home = crate::init_with_cli(
                None::<PathBuf>,
                vec![("server.port".to_owned(), "9100".to_owned())],
            )
            .and_then(|_| crate::selvedge_home())
            .expect("initialize cli-only config");
            let config_path = config_path_for_home(&original_home);

            crate::update_runtime_and_persist("logging.level", "debug").expect("persist update");

            assert!(
                config_path.is_file(),
                "persisted config missing at reported home"
            );
            assert_eq!(
                crate::selvedge_home().expect("read selected home after persist"),
                original_home
            );
            return;
        }

        let tempdir = tempfile::TempDir::new().expect("tempdir");
        let work_dir = tempdir.path().join("workspace");
        let home_dir = tempdir.path().join("isolated-home");
        let xdg_dir = tempdir.path().join("isolated-xdg");
        let current_executable = env::current_exe().expect("current test executable");

        std::fs::create_dir_all(&work_dir).expect("create work dir");
        std::fs::create_dir_all(&home_dir).expect("create home dir");
        std::fs::create_dir_all(&xdg_dir).expect("create xdg dir");

        let output = Command::new(current_executable)
            .arg("--exact")
            .arg("tests::cli_only_persist_uses_reported_home")
            .current_dir(&work_dir)
            .env("SELVEDGE_CONFIG_CLI_ONLY_PERSIST_CHILD", "1")
            .env("HOME", &home_dir)
            .env("XDG_CONFIG_HOME", &xdg_dir)
            .env_remove("SELVEDGE_HOME")
            .env_remove("SELVEDGE_CONFIG")
            .output()
            .expect("run cli-only persist child test");

        assert!(output.status.success(), "child test failed: {output:?}");
    }

    #[cfg(unix)]
    #[test]
    fn deferred_home_prefers_writable_fallback() {
        use std::fs;
        use std::os::unix::fs::PermissionsExt;

        let _guard = TEST_LOCK.lock().expect("test lock");
        reset_for_test();
        if env::var_os("SELVEDGE_CONFIG_WRITABLE_FALLBACK_CHILD").is_some() {
            let selected_home = crate::init_with_cli(
                None::<PathBuf>,
                vec![("server.port".to_owned(), "9100".to_owned())],
            )
            .and_then(|_| crate::selvedge_home())
            .expect("select deferred home");

            let xdg_home = env::var_os("XDG_CONFIG_HOME").expect("xdg config home");
            assert_eq!(selected_home, PathBuf::from(xdg_home).join("selvedge"));
            return;
        }

        let tempdir = tempfile::TempDir::new().expect("tempdir");
        let work_dir = tempdir.path().join("workspace");
        let home_dir = tempdir.path().join("readonly-home");
        let xdg_dir = tempdir.path().join("xdg-home");
        let current_executable = env::current_exe().expect("current test executable");

        fs::create_dir_all(&work_dir).expect("create work dir");
        fs::create_dir_all(&home_dir).expect("create home dir");
        fs::set_permissions(&home_dir, fs::Permissions::from_mode(0o555))
            .expect("set readonly permissions");

        let output = Command::new(current_executable)
            .arg("--exact")
            .arg("tests::deferred_home_prefers_writable_fallback")
            .current_dir(&work_dir)
            .env("SELVEDGE_CONFIG_WRITABLE_FALLBACK_CHILD", "1")
            .env("HOME", &home_dir)
            .env("XDG_CONFIG_HOME", &xdg_dir)
            .env_remove("SELVEDGE_HOME")
            .env_remove("SELVEDGE_CONFIG")
            .output()
            .expect("run writable fallback child test");

        assert!(output.status.success(), "child test failed: {output:?}");
    }

    #[test]
    fn persist_recreates_missing_file_in_initialized_home() {
        let _guard = TEST_LOCK.lock().expect("test lock");
        reset_for_test();
        let tempdir = tempfile::TempDir::new().expect("tempdir");
        let config_home = tempdir.path().join("config-home");
        let config_path = config_home.join("config.toml");
        std::fs::create_dir_all(&config_home).expect("create config home");
        std::fs::write(
            &config_path,
            r#"
[server]
host = "127.0.0.1"
port = 8080
request_timeout_ms = 5000

[logging]
level = "info"
            "#,
        )
        .expect("write config");

        crate::init_with_home(&config_home).expect("init config service");
        std::fs::remove_file(&config_path).expect("remove config file");

        crate::update_runtime_and_persist("logging.level", "debug")
            .expect("persist should recreate missing config file");
        let selected_home = crate::selvedge_home().expect("read selected home");
        let persisted = std::fs::read_to_string(&config_path).expect("read recreated config");

        assert_eq!(
            selected_home,
            std::fs::canonicalize(&config_home).expect("canonicalize config home")
        );
        assert!(persisted.contains("level = \"debug\""));
    }

    #[test]
    fn bootstrapped_relative_home_is_canonicalized() {
        let _guard = TEST_LOCK.lock().expect("test lock");
        let original_dir = env::current_dir().expect("current dir");
        let tempdir = tempfile::TempDir::new().expect("tempdir");
        let work_dir = tempdir.path().join("workspace");
        let moved_dir = tempdir.path().join("other-place");

        std::fs::create_dir_all(&work_dir).expect("create work dir");
        std::fs::create_dir_all(&moved_dir).expect("create moved dir");

        let bootstrapped_home = (|| -> Result<PathBuf, String> {
            env::set_current_dir(&work_dir).map_err(|error| error.to_string())?;

            crate::create_home_with_empty_config(Path::new(".selvedge"))
                .map_err(|error| error.to_string())
        })();

        env::set_current_dir(&original_dir).expect("restore current dir");
        let bootstrapped_home = bootstrapped_home.expect("bootstrap default home");
        let expected_home =
            std::fs::canonicalize(work_dir.join(".selvedge")).expect("canonicalize home");

        assert_eq!(bootstrapped_home, expected_home);
        assert!(!moved_dir.join(".selvedge").exists());
    }

    #[test]
    fn selvedge_home_requires_initialization() {
        let _guard = TEST_LOCK.lock().expect("test lock");
        reset_for_test();

        let error = crate::selvedge_home().expect_err("must fail before init");

        assert_eq!(error, ConfigError::NotInitialized);
    }

    #[test]
    fn selvedge_home_returns_selected_home_directory() {
        let _guard = TEST_LOCK.lock().expect("test lock");
        reset_for_test();
        let tempdir = tempfile::TempDir::new().expect("tempdir");
        let config_home = tempdir.path().join("config-home");
        let config_path = config_home.join("config.toml");

        std::fs::create_dir_all(&config_home).expect("create config home");
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

        crate::init_with_home(&config_home).expect("init config service");

        let selected_home = crate::selvedge_home().expect("read selected home");

        assert_eq!(
            selected_home,
            std::fs::canonicalize(&config_home).expect("canonicalize config home")
        );
    }
}
