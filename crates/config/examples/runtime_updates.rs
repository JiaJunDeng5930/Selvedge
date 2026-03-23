use std::fs;

use selvedge_config::{ConfigStore, LoadSpec, OverrideOp, PersistMode};
use selvedge_config_model::{AppConfig, default_app_config, validate_app_config};
use tempfile::TempDir;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let tempdir = TempDir::new()?;
    let config_path = tempdir.path().join("selvedge.toml");

    fs::write(
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
    )?;

    let store = ConfigStore::load(
        LoadSpec {
            explicit_file_path: Some(config_path.clone()),
            file_path_candidates: Vec::new(),
            env_prefix: "SELVEDGE_APP".to_owned(),
            cli_overrides: Vec::new(),
        },
        default_app_config,
        validate_app_config,
    )?;

    store.set(
        OverrideOp::new("feature.rollout_percentage", 100_u8),
        PersistMode::RuntimeOnly,
    )?;
    store.set(
        OverrideOp::new("feature.enabled", true),
        PersistMode::RuntimeOnly,
    )?;
    store.set(
        OverrideOp::new("logging.level", "debug"),
        PersistMode::RuntimeAndPersist,
    )?;

    let current = store.read(|config: &AppConfig| {
        format!(
            "feature_enabled={} rollout={} log_level={}",
            config.feature.enabled, config.feature.rollout_percentage, config.logging.level,
        )
    })?;
    let persisted = fs::read_to_string(config_path)?;

    println!("Current view: {current}");
    println!("Persisted file:\n{persisted}");
    println!("`RuntimeOnly` changes affect reads immediately but are not written to disk.");

    Ok(())
}
