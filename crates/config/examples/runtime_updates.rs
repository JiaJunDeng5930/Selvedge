use std::fs;

use selvedge_config::AppConfigStore;
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

    let store = AppConfigStore::load_with_explicit_path(config_path.clone())?;

    store.update_runtime("feature.rollout_percentage", 100_u8)?;
    store.update_runtime("feature.enabled", true)?;
    store.update_runtime_and_persist("logging.level", "debug")?;

    let current = store.read(|config| {
        format!(
            "feature_enabled={} rollout={} log_level={}",
            config.feature.enabled, config.feature.rollout_percentage, config.logging.level,
        )
    })?;
    let persisted = fs::read_to_string(config_path)?;

    println!("Current view: {current}");
    println!("Persisted file:\n{persisted}");
    println!("Runtime-only changes affect reads immediately but are not written to disk.");

    Ok(())
}
