use std::fs;

use selvedge_config::{ConfigStore, LoadSpec, OverrideOp, PersistMode};
use serde::{Deserialize, Serialize};
use tempfile::TempDir;

#[derive(Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(default, deny_unknown_fields)]
struct TestConfig {
    server: ServerConfig,
    feature: FeatureConfig,
}

impl Default for TestConfig {
    fn default() -> Self {
        Self {
            server: ServerConfig {
                host: "127.0.0.1".to_owned(),
                port: 7000,
                tags: vec!["base".to_owned()],
            },
            feature: FeatureConfig {
                enabled: false,
                rollout_percentage: 0,
            },
        }
    }
}

#[derive(Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(default, deny_unknown_fields)]
struct ServerConfig {
    host: String,
    port: u16,
    tags: Vec<String>,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            host: "127.0.0.1".to_owned(),
            port: 7000,
            tags: vec!["base".to_owned()],
        }
    }
}

#[derive(Debug, Deserialize, Serialize, PartialEq, Eq, Default)]
#[serde(default, deny_unknown_fields)]
struct FeatureConfig {
    enabled: bool,
    rollout_percentage: u8,
}

#[test]
fn explicit_file_path_wins_over_candidates() {
    let tempdir = TempDir::new().expect("tempdir");
    let explicit_path = tempdir.path().join("explicit.toml");
    let candidate_path = tempdir.path().join("candidate.toml");

    fs::write(
        &explicit_path,
        r#"
        [server]
        host = "explicit"
        port = 7100
        tags = ["explicit"]
        "#,
    )
    .expect("write explicit config");
    fs::write(
        &candidate_path,
        r#"
        [server]
        host = "candidate"
        port = 7200
        tags = ["candidate"]
        "#,
    )
    .expect("write candidate config");

    let store = load_store(LoadSpec {
        explicit_file_path: Some(explicit_path),
        file_path_candidates: vec![candidate_path],
        env_prefix: "SELVEDGE_TEST".to_owned(),
        cli_overrides: Vec::new(),
    });

    let host = store
        .read(|config: &TestConfig| config.server.host.clone())
        .expect("read current host");

    assert_eq!(host, "explicit");
}

#[test]
fn no_existing_candidate_loads_without_file_layer() {
    let tempdir = TempDir::new().expect("tempdir");
    let missing_path = tempdir.path().join("missing.toml");

    let store = load_store(LoadSpec {
        explicit_file_path: None,
        file_path_candidates: vec![missing_path],
        env_prefix: "SELVEDGE_TEST".to_owned(),
        cli_overrides: Vec::new(),
    });

    let port = store
        .read(|config: &TestConfig| config.server.port)
        .expect("read current port");

    assert_eq!(port, TestConfig::default().server.port);
}

#[test]
fn cli_overrides_file() {
    let tempdir = TempDir::new().expect("tempdir");
    let config_path = tempdir.path().join("config.toml");

    fs::write(
        &config_path,
        r#"
        [server]
        port = 7100
        "#,
    )
    .expect("write config");

    let store = load_store(LoadSpec {
        explicit_file_path: Some(config_path),
        file_path_candidates: Vec::new(),
        env_prefix: "SELVEDGE_TEST".to_owned(),
        cli_overrides: vec![OverrideOp::new("server.port", 7200)],
    });

    let port = store
        .read(|config: &TestConfig| config.server.port)
        .expect("read current port");

    assert_eq!(port, 7200);
}

#[test]
fn runtime_only_overrides_base_config() {
    let tempdir = TempDir::new().expect("tempdir");
    let config_path = tempdir.path().join("config.toml");

    fs::write(
        &config_path,
        r#"
        [server]
        port = 7100
        "#,
    )
    .expect("write config");

    let store = load_store(LoadSpec {
        explicit_file_path: Some(config_path.clone()),
        file_path_candidates: Vec::new(),
        env_prefix: "SELVEDGE_TEST".to_owned(),
        cli_overrides: Vec::new(),
    });

    store
        .set(
            OverrideOp::new("server.port", 7400),
            PersistMode::RuntimeOnly,
        )
        .expect("set runtime only override");

    let port = store
        .read(|config: &TestConfig| config.server.port)
        .expect("read current port");
    let file_contents = fs::read_to_string(config_path).expect("read config file");

    assert_eq!(port, 7400);
    assert!(file_contents.contains("7100"));
}

#[test]
fn runtime_and_persist_writes_merged_current_config_to_file() {
    let tempdir = TempDir::new().expect("tempdir");
    let config_path = tempdir.path().join("config.toml");

    fs::write(
        &config_path,
        r#"
        [server]
        port = 7100
        tags = ["file"]
        "#,
    )
    .expect("write config");

    let store = load_store(LoadSpec {
        explicit_file_path: Some(config_path.clone()),
        file_path_candidates: Vec::new(),
        env_prefix: "SELVEDGE_TEST".to_owned(),
        cli_overrides: Vec::new(),
    });

    store
        .set(
            OverrideOp::new("server.port", 7500),
            PersistMode::RuntimeAndPersist,
        )
        .expect("persist override");

    let port = store
        .read(|config: &TestConfig| config.server.port)
        .expect("read current port");
    let persisted = fs::read_to_string(config_path).expect("read persisted file");

    assert_eq!(port, 7500);
    assert!(persisted.contains("7500"));
    assert!(persisted.contains("\"file\""));
    assert!(!persisted.contains("127.0.0.1"));
}

#[test]
fn runtime_only_override_is_not_persisted_by_later_persist() {
    let tempdir = TempDir::new().expect("tempdir");
    let config_path = tempdir.path().join("config.toml");

    fs::write(
        &config_path,
        r#"
        [server]
        host = "file-host"
        port = 7100
        tags = ["file"]
        "#,
    )
    .expect("write config");

    let store = load_store(LoadSpec {
        explicit_file_path: Some(config_path.clone()),
        file_path_candidates: Vec::new(),
        env_prefix: "SELVEDGE_TEST".to_owned(),
        cli_overrides: Vec::new(),
    });

    store
        .set(
            OverrideOp::new("server.host", "runtime-only-host"),
            PersistMode::RuntimeOnly,
        )
        .expect("set runtime-only override");
    store
        .set(
            OverrideOp::new("server.port", 7600),
            PersistMode::RuntimeAndPersist,
        )
        .expect("persist port override");

    let current = store
        .read(|config: &TestConfig| (config.server.host.clone(), config.server.port))
        .expect("read current config");
    let persisted = fs::read_to_string(config_path).expect("read persisted file");

    assert_eq!(current, ("runtime-only-host".to_owned(), 7600));
    assert!(persisted.contains("7600"));
    assert!(persisted.contains("file-host"));
    assert!(!persisted.contains("runtime-only-host"));
}

#[test]
fn runtime_and_persist_without_selected_file_returns_error() {
    let store = load_store(LoadSpec {
        explicit_file_path: None,
        file_path_candidates: Vec::new(),
        env_prefix: "SELVEDGE_TEST".to_owned(),
        cli_overrides: Vec::new(),
    });

    let error = store
        .set(
            OverrideOp::new("server.port", 7600),
            PersistMode::RuntimeAndPersist,
        )
        .expect_err("persist without file should fail");

    assert!(error.to_string().contains("persist"));
}

#[test]
fn invalid_business_value_fails_without_state_change() {
    let store = load_store(LoadSpec {
        explicit_file_path: None,
        file_path_candidates: Vec::new(),
        env_prefix: "SELVEDGE_TEST".to_owned(),
        cli_overrides: Vec::new(),
    });

    let error = store
        .set(
            OverrideOp::new("feature.enabled", true),
            PersistMode::RuntimeOnly,
        )
        .expect_err("invalid config should fail");

    let feature = store
        .read(|config: &TestConfig| (config.feature.enabled, config.feature.rollout_percentage))
        .expect("read feature config");

    assert!(error.to_string().contains("rollout"));
    assert_eq!(feature, (false, 0));
}

#[test]
fn read_recomputes_base_plus_patch_each_time() {
    let store = load_store(LoadSpec {
        explicit_file_path: None,
        file_path_candidates: Vec::new(),
        env_prefix: "SELVEDGE_TEST".to_owned(),
        cli_overrides: Vec::new(),
    });

    let before = store
        .read(|config: &TestConfig| config.server.port)
        .expect("read before update");

    store
        .set(
            OverrideOp::new("server.port", 7700),
            PersistMode::RuntimeOnly,
        )
        .expect("set runtime override");

    let after = store
        .read(|config: &TestConfig| config.server.port)
        .expect("read after update");

    assert_eq!(before, 7000);
    assert_eq!(after, 7700);
}

fn load_store(spec: LoadSpec) -> ConfigStore<TestConfig> {
    ConfigStore::load(spec, TestConfig::default, validate_config).expect("load config store")
}

fn validate_config(config: &TestConfig) -> Result<(), String> {
    if config.server.port == 0 {
        return Err("server.port must be greater than zero".to_owned());
    }

    if config.feature.enabled && config.feature.rollout_percentage == 0 {
        return Err("feature.rollout_percentage must be greater than zero when enabled".to_owned());
    }

    Ok(())
}
