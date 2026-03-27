use std::fs;

use selvedge_config::{init_with_cli, read, update_runtime};
use tempfile::TempDir;

#[test]
fn singleton_config_service_and_model_work_together() {
    let tempdir = TempDir::new().expect("tempdir");
    let config_home = tempdir.path().join(".selvedge");
    let config_path = config_home.join("config.toml");

    fs::create_dir_all(&config_home).expect("create config home");

    fs::write(
        &config_path,
        r#"
[server]
host = "127.0.0.1"
port = 9000
request_timeout_ms = 5000

[logging]
level = "info"
"#,
    )
    .expect("write config");

    init_with_cli(
        Some(config_home),
        vec![("server.port".to_owned(), "9000".to_owned())],
    )
    .expect("init config");

    let before = read(|config| config.server.port).expect("read initial config");

    update_runtime("feature.rollout_percentage", 100_u8).expect("set rollout percentage");
    update_runtime("feature.enabled", true).expect("enable feature");
    update_runtime("server.request_timeout_ms", 10_000_u64).expect("set request timeout");

    let after = read(|config| {
        (
            config.server.port,
            config.server.request_timeout_ms,
            config.feature.enabled,
            config.feature.rollout_percentage,
        )
    })
    .expect("read updated config");

    assert_eq!(before, 9000);
    assert_eq!(after, (9000, 10_000, true, 100));
}
