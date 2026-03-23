use std::fs;

use selvedge_config::AppConfigStore;
use tempfile::TempDir;

#[test]
fn public_api_supports_load_read_runtime_update_and_persist() {
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

    let store = AppConfigStore::load_with_explicit_path(config_path.clone()).expect("load store");

    let before = store
        .read(|config| {
            (
                config.server.port,
                config.feature.enabled,
                config.logging.level.clone(),
            )
        })
        .expect("read before update");

    store
        .update_runtime("feature.rollout_percentage", 100_u8)
        .expect("set rollout");
    store
        .update_runtime("feature.enabled", true)
        .expect("enable feature");
    store
        .update_runtime_and_persist("logging.level", "debug")
        .expect("persist logging level");

    let after = store
        .read(|config| {
            (
                config.server.port,
                config.feature.enabled,
                config.logging.level.clone(),
            )
        })
        .expect("read after update");
    let persisted = fs::read_to_string(config_path).expect("read persisted file");

    assert_eq!(before, (8080, false, "info".to_owned()));
    assert_eq!(after, (8080, true, "debug".to_owned()));
    assert!(persisted.contains("level = \"debug\""));
    assert!(!persisted.contains("enabled = true"));
}
