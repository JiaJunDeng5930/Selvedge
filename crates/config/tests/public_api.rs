use std::fs;

use selvedge_config::{init_with_cli, read, update_runtime, update_runtime_and_persist};
use tempfile::TempDir;

#[test]
fn public_api_supports_singleton_read_runtime_update_persist_and_cli_precedence() {
    let tempdir = TempDir::new().expect("tempdir");
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
    )
    .expect("write config file");

    init_with_cli(
        Some(config_path.clone()),
        vec![
            ("server.port".to_owned(), "9100".to_owned()),
            ("server.request_timeout_ms".to_owned(), "10000".to_owned()),
        ],
    )
    .expect("init config");

    let before = read(|config| {
        (
            config.server.port,
            config.feature.enabled,
            config.logging.level.clone(),
        )
    })
    .expect("read before update");

    assert_eq!(before, (9100, false, "info".to_owned()));

    update_runtime("feature.rollout_percentage", 100_u8).expect("set rollout");
    update_runtime("feature.enabled", true).expect("enable feature");
    update_runtime_and_persist("logging.level", "debug").expect("persist logging level");

    let after = read(|config| {
        (
            config.server.port,
            config.feature.enabled,
            config.logging.level.clone(),
        )
    })
    .expect("read after update");
    let persisted = fs::read_to_string(config_path).expect("read persisted file");

    assert_eq!(after, (9100, true, "debug".to_owned()));
    assert!(persisted.contains("level = \"debug\""));
    assert!(!persisted.contains("enabled = true"));
    let loaded = read(|config| (config.server.port, config.server.request_timeout_ms))
        .expect("read config with cli overrides");

    assert_eq!(loaded, (9100, 10_000));
}
