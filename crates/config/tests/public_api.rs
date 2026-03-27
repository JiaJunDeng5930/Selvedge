use std::fs;

use selvedge_config::{
    init_with_cli, read, selvedge_home, update_runtime, update_runtime_and_persist,
};
use selvedge_config_model::LogFilter;
use tempfile::TempDir;

#[test]
fn public_api_supports_singleton_read_runtime_update_persist_and_cli_precedence() {
    let tempdir = TempDir::new().expect("tempdir");
    let config_home = tempdir.path().join(".selvedge");
    let config_path = config_home.join("config.toml");

    fs::create_dir_all(&config_home).expect("create config home");

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
        Some(config_home.clone()),
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
            config.logging.level,
        )
    })
    .expect("read before update");

    assert_eq!(before, (9100, false, LogFilter::Info));

    update_runtime("feature.rollout_percentage", 100_u8).expect("set rollout");
    update_runtime("feature.enabled", true).expect("enable feature");
    update_runtime_and_persist("logging.level", "debug").expect("persist logging level");

    let after = read(|config| {
        (
            config.server.port,
            config.feature.enabled,
            config.logging.level,
        )
    })
    .expect("read after update");
    let persisted = fs::read_to_string(config_path).expect("read persisted file");
    let selected_home = selvedge_home().expect("read selected home");

    assert_eq!(after, (9100, true, LogFilter::Debug));
    assert_eq!(
        selected_home,
        fs::canonicalize(config_home).expect("canonicalize config home")
    );
    assert!(persisted.contains("level = \"debug\""));
    assert!(!persisted.contains("enabled = true"));
    let loaded = read(|config| (config.server.port, config.server.request_timeout_ms))
        .expect("read config with cli overrides");

    assert_eq!(loaded, (9100, 10_000));
}
