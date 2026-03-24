use std::fs;

use selvedge_config::{init_with_cli, read};
use tempfile::TempDir;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let tempdir = TempDir::new()?;
    let config_path = tempdir.path().join("selvedge.toml");

    fs::write(
        &config_path,
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

    init_with_cli(
        Some(config_path),
        vec![
            ("server.port".to_owned(), "9090".to_owned()),
            ("logging.level".to_owned(), "debug".to_owned()),
        ],
    )?;

    let summary = read(|config| {
        format!(
            "host={} port={} timeout={}ms log_level={}",
            config.server.host,
            config.server.port,
            config.server.request_timeout_ms,
            config.logging.level,
        )
    })?;

    println!("{summary}");
    println!("If no explicit path is given, load() falls back to env path and fixed search paths.");

    Ok(())
}
