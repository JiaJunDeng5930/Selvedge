use std::{
    env, fmt,
    fs::{self, File},
    io::Write,
    marker::PhantomData,
    path::{Path, PathBuf},
    sync::{Arc, RwLock},
    time::{SystemTime, UNIX_EPOCH},
};

use serde::{Serialize, de::DeserializeOwned};
use thiserror::Error;
use toml::{Table, Value};

#[derive(Debug, Clone)]
pub struct LoadSpec {
    pub explicit_file_path: Option<PathBuf>,
    pub file_path_candidates: Vec<PathBuf>,
    pub env_prefix: String,
    pub cli_overrides: Vec<OverrideOp>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct OverrideOp {
    path: String,
    value: OverrideValue,
}

impl OverrideOp {
    pub fn new<P, V>(path: P, value: V) -> Self
    where
        P: Into<String>,
        V: Into<OverrideValue>,
    {
        Self {
            path: path.into(),
            value: value.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct OverrideValue(Value);

impl OverrideValue {
    fn into_inner(self) -> Value {
        self.0
    }
}

impl From<Value> for OverrideValue {
    fn from(value: Value) -> Self {
        Self(value)
    }
}

impl From<bool> for OverrideValue {
    fn from(value: bool) -> Self {
        Self(Value::Boolean(value))
    }
}

impl From<i32> for OverrideValue {
    fn from(value: i32) -> Self {
        Self(Value::Integer(i64::from(value)))
    }
}

impl From<u8> for OverrideValue {
    fn from(value: u8) -> Self {
        Self(Value::Integer(i64::from(value)))
    }
}

impl From<u16> for OverrideValue {
    fn from(value: u16) -> Self {
        Self(Value::Integer(i64::from(value)))
    }
}

impl From<u32> for OverrideValue {
    fn from(value: u32) -> Self {
        Self(Value::Integer(i64::from(value)))
    }
}

impl From<String> for OverrideValue {
    fn from(value: String) -> Self {
        Self(Value::String(value))
    }
}

impl From<&str> for OverrideValue {
    fn from(value: &str) -> Self {
        Self(Value::String(value.to_owned()))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PersistMode {
    RuntimeOnly,
    RuntimeAndPersist,
}

pub struct ConfigStore<T> {
    immutable: ImmutableState,
    runtime_patch: RwLock<Table>,
    validate_fn: Arc<ValidateFn<T>>,
    _marker: PhantomData<fn() -> T>,
}

impl<T> fmt::Debug for ConfigStore<T> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ConfigStore")
            .field("immutable", &self.immutable)
            .finish_non_exhaustive()
    }
}

impl<T> ConfigStore<T>
where
    T: DeserializeOwned + Serialize,
{
    pub fn load<DF, VF, E>(
        spec: LoadSpec,
        defaults_fn: DF,
        validate_fn: VF,
    ) -> Result<Self, ConfigError>
    where
        DF: FnOnce() -> T,
        VF: Fn(&T) -> Result<(), E> + Send + Sync + 'static,
        E: fmt::Display,
    {
        let immutable = ImmutableState::load(spec, defaults_fn)?;
        let validate_fn =
            Arc::new(move |config: &T| validate_fn(config).map_err(|error| error.to_string()));

        let store = Self {
            immutable,
            runtime_patch: RwLock::new(Table::new()),
            validate_fn,
            _marker: PhantomData,
        };

        store.validate_current_table(&Table::new())?;

        Ok(store)
    }

    pub fn read<R, F>(&self, reader: F) -> Result<R, ConfigError>
    where
        F: FnOnce(&T) -> R,
    {
        let runtime_patch = self
            .runtime_patch
            .read()
            .map_err(|_| ConfigError::LockPoisoned)?;
        let config = self.materialize_config(&runtime_patch)?;

        Ok(reader(&config))
    }

    pub fn set(&self, operation: OverrideOp, mode: PersistMode) -> Result<(), ConfigError> {
        let mut runtime_patch = self
            .runtime_patch
            .write()
            .map_err(|_| ConfigError::LockPoisoned)?;
        let mut candidate_patch = runtime_patch.clone();

        apply_override(&mut candidate_patch, operation.clone())?;
        let merged_table = self.current_table(&candidate_patch);
        let config = deserialize_table::<T>(&merged_table)?;
        self.validate_config(&config)?;

        if mode == PersistMode::RuntimeAndPersist {
            let path = self
                .immutable
                .resolved_file_path
                .as_ref()
                .ok_or(ConfigError::PersistPathUnavailable)?;
            persist_override(path, operation)?;
        }

        *runtime_patch = candidate_patch;

        Ok(())
    }

    fn current_table(&self, runtime_patch: &Table) -> Table {
        let mut merged = self.immutable.base_config.clone();
        merge_tables(&mut merged, runtime_patch);
        merged
    }

    fn materialize_config(&self, runtime_patch: &Table) -> Result<T, ConfigError> {
        let merged = self.current_table(runtime_patch);
        let config = deserialize_table::<T>(&merged)?;

        self.validate_config(&config)?;

        Ok(config)
    }

    fn validate_current_table(&self, runtime_patch: &Table) -> Result<(), ConfigError> {
        let config = self.materialize_config(runtime_patch)?;

        self.validate_config(&config)
    }

    fn validate_config(&self, config: &T) -> Result<(), ConfigError> {
        (self.validate_fn)(config).map_err(ConfigError::Validation)
    }
}

#[derive(Debug)]
struct ImmutableState {
    base_config: Table,
    resolved_file_path: Option<PathBuf>,
    _file_path_candidates: Vec<PathBuf>,
}

impl ImmutableState {
    fn load<T, DF>(spec: LoadSpec, defaults_fn: DF) -> Result<Self, ConfigError>
    where
        T: Serialize,
        DF: FnOnce() -> T,
    {
        let resolved_file_path = resolve_file_path(&spec)?;
        let defaults = serialize_to_table(defaults_fn())?;
        let file = load_file_table(resolved_file_path.as_deref())?;
        let env = load_env_table(&spec.env_prefix)?;
        let cli = build_override_table(spec.cli_overrides)?;
        let mut base_config = defaults;

        merge_tables(&mut base_config, &file);
        merge_tables(&mut base_config, &env);
        merge_tables(&mut base_config, &cli);

        Ok(Self {
            base_config,
            resolved_file_path,
            _file_path_candidates: spec.file_path_candidates,
        })
    }
}

type ValidateFn<T> = dyn Fn(&T) -> Result<(), String> + Send + Sync;

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("explicit config file does not exist: {0}")]
    ExplicitFileNotFound(PathBuf),
    #[error("failed to read config file at {path}: {source}")]
    FileRead {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse config file at {path}: {source}")]
    FileParse {
        path: PathBuf,
        #[source]
        source: toml::de::Error,
    },
    #[error("failed to serialize config value: {0}")]
    Serialize(#[from] toml::ser::Error),
    #[error("failed to deserialize config value: {0}")]
    Deserialize(#[from] toml::de::Error),
    #[error("invalid override path: {0}")]
    InvalidOverridePath(String),
    #[error("config validation failed: {0}")]
    Validation(String),
    #[error("persist requested but no config file is selected")]
    PersistPathUnavailable,
    #[error("failed to write config file at {path}: {source}")]
    FileWrite {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("config store lock is poisoned")]
    LockPoisoned,
}

fn resolve_file_path(spec: &LoadSpec) -> Result<Option<PathBuf>, ConfigError> {
    if let Some(explicit_path) = &spec.explicit_file_path {
        if explicit_path.is_file() {
            return Ok(Some(explicit_path.clone()));
        }

        return Err(ConfigError::ExplicitFileNotFound(explicit_path.clone()));
    }

    Ok(spec
        .file_path_candidates
        .iter()
        .find(|path| path.is_file())
        .cloned())
}

fn load_file_table(path: Option<&Path>) -> Result<Table, ConfigError> {
    let Some(path) = path else {
        return Ok(Table::new());
    };
    let contents = fs::read_to_string(path).map_err(|source| ConfigError::FileRead {
        path: path.to_path_buf(),
        source,
    })?;

    toml::from_str::<Table>(&contents).map_err(|source| ConfigError::FileParse {
        path: path.to_path_buf(),
        source,
    })
}

fn load_env_table(prefix: &str) -> Result<Table, ConfigError> {
    load_env_table_from_entries(prefix, env::vars())
}

fn load_env_table_from_entries<I>(prefix: &str, entries: I) -> Result<Table, ConfigError>
where
    I: IntoIterator<Item = (String, String)>,
{
    if prefix.is_empty() {
        return Ok(Table::new());
    }

    let normalized_prefix = format!("{}_", prefix.to_ascii_uppercase());
    let mut table = Table::new();

    for (key, raw_value) in entries {
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
        let value = parse_env_value(&raw_value)?;

        apply_override(&mut table, OverrideOp::new(path, value))?;
    }

    Ok(table)
}

fn build_override_table(overrides: Vec<OverrideOp>) -> Result<Table, ConfigError> {
    let mut table = Table::new();

    for operation in overrides {
        apply_override(&mut table, operation)?;
    }

    Ok(table)
}

fn apply_override(table: &mut Table, operation: OverrideOp) -> Result<(), ConfigError> {
    let segments = operation
        .path
        .split('.')
        .filter(|segment| !segment.is_empty())
        .collect::<Vec<_>>();

    if segments.is_empty() {
        return Err(ConfigError::InvalidOverridePath(operation.path));
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

    current.insert(
        segments[segments.len() - 1].to_owned(),
        operation.value.into_inner(),
    );

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

fn parse_env_value(raw: &str) -> Result<Value, ConfigError> {
    let wrapped = format!("value = {raw}");
    match toml::from_str::<Table>(&wrapped) {
        Ok(mut table) => Ok(table
            .remove("value")
            .expect("wrapped TOML value must contain key")),
        Err(_) => Ok(Value::String(raw.to_owned())),
    }
}

fn serialize_to_table<T>(value: T) -> Result<Table, ConfigError>
where
    T: Serialize,
{
    let value = Value::try_from(value)?;
    value_to_table(value)
}

fn value_to_table(value: Value) -> Result<Table, ConfigError> {
    match value {
        Value::Table(table) => Ok(table),
        _ => Err(ConfigError::InvalidOverridePath(
            "top-level config must serialize to a table".to_owned(),
        )),
    }
}

fn deserialize_table<T>(table: &Table) -> Result<T, ConfigError>
where
    T: DeserializeOwned,
{
    Value::Table(table.clone())
        .try_into()
        .map_err(ConfigError::Deserialize)
}

fn write_config_file(path: &Path, table: &Table) -> Result<(), ConfigError> {
    let rendered = toml::to_string_pretty(table)?;
    let temp_path = build_temp_path(path);

    write_all(&temp_path, rendered.as_bytes())?;
    fs::rename(&temp_path, path).map_err(|source| ConfigError::FileWrite {
        path: path.to_path_buf(),
        source,
    })?;

    Ok(())
}

fn persist_override(path: &Path, operation: OverrideOp) -> Result<(), ConfigError> {
    let mut persisted_table = load_file_table(Some(path))?;

    apply_override(&mut persisted_table, operation)?;
    write_config_file(path, &persisted_table)
}

fn write_all(path: &Path, bytes: &[u8]) -> Result<(), ConfigError> {
    let mut file = File::create(path).map_err(|source| ConfigError::FileWrite {
        path: path.to_path_buf(),
        source,
    })?;

    file.write_all(bytes)
        .map_err(|source| ConfigError::FileWrite {
            path: path.to_path_buf(),
            source,
        })?;
    file.sync_all().map_err(|source| ConfigError::FileWrite {
        path: path.to_path_buf(),
        source,
    })
}

fn build_temp_path(path: &Path) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or_default();
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("config.toml");

    path.with_file_name(format!("{file_name}.{nanos}.tmp"))
}

#[cfg(test)]
mod tests {
    use super::load_env_table_from_entries;

    #[test]
    fn env_entries_build_nested_override_table() {
        let table = load_env_table_from_entries(
            "selvedge_test",
            vec![
                ("SELVEDGE_TEST_SERVER__PORT".to_owned(), "7200".to_owned()),
                (
                    "SELVEDGE_TEST_SERVER__HOST".to_owned(),
                    "api.internal".to_owned(),
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
}
