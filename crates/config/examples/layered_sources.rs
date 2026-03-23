use std::fs;

use selvedge_config::{ConfigStore, LoadSpec, OverrideOp};
use selvedge_config_model::{AppConfig, default_app_config, validate_app_config};
use tempfile::TempDir;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let tempdir = TempDir::new()?;
    let candidate_path = tempdir.path().join("selvedge.toml");

    fs::write(
        &candidate_path,
        r#"
[server]
host = "0.0.0.0"
port = 8088
request_timeout_ms = 8000

[logging]
level = "info"
format = "text"
"#,
    )?;

    let store = ConfigStore::load(
        LoadSpec {
            explicit_file_path: None,
            file_path_candidates: vec![candidate_path],
            env_prefix: "SELVEDGE_APP".to_owned(),
            cli_overrides: vec![
                OverrideOp::new("server.port", 9090_u16),
                OverrideOp::new("logging.level", "debug"),
            ],
        },
        default_app_config,
        validate_app_config,
    )?;

    let summary = store.read(|config: &AppConfig| {
        format!(
            "host={} port={} timeout={}ms log_level={}",
            config.server.host,
            config.server.port,
            config.server.request_timeout_ms,
            config.logging.level,
        )
    })?;

    println!("{summary}");
    println!("Environment overrides would use keys like SELVEDGE_APP_SERVER__PORT=7001");

    Ok(())
}
