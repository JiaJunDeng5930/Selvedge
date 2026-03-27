use std::fs;

use selvedge_config::{init_with_cli, read};
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
host = "0.0.0.0"
port = 8088
request_timeout_ms = 8000

[logging]
level = "info"
format = "text"
"#,
    )?;

    init_with_cli(
        Some(config_home),
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
    println!(
        "If no explicit home is given, load() falls back to env home and fixed home search order."
    );

    Ok(())
}
