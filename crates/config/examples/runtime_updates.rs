use std::fs;

use selvedge_config::{init_with_home, read, update_runtime, update_runtime_and_persist};
use tempfile::TempDir;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let tempdir = TempDir::new()?;
    let config_home = tempdir.path().join(".selvedge");
    let config_path = config_home.join("config.toml");

    fs::create_dir_all(&config_home)?;

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

    init_with_home(config_home)?;

    update_runtime("feature.rollout_percentage", 100_u8)?;
    update_runtime("feature.enabled", true)?;
    update_runtime_and_persist("logging.level", "debug")?;

    let current = read(|config| {
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
