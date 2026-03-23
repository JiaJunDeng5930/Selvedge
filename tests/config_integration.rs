use std::fs;

use selvedge_config::AppConfigStore;
use tempfile::TempDir;

#[test]
fn app_config_store_and_model_work_together() {
    let tempdir = TempDir::new().expect("tempdir");
    let config_path = tempdir.path().join("selvedge.toml");

    fs::write(
        &config_path,
        r#"
[server]
host = "127.0.0.1"
port = 9000
request_timeout_ms = 5000

[logging]
level = "info"
format = "text"
"#,
    )
    .expect("write config");

    let store = AppConfigStore::load_with_explicit_path(config_path).expect("load store");

    let before = store
        .read(|config| config.server.port)
        .expect("read initial config");

    store
        .update_runtime("feature.rollout_percentage", 100_u8)
        .expect("set rollout percentage");
    store
        .update_runtime("feature.enabled", true)
        .expect("enable feature");
    store
        .update_runtime("server.request_timeout_ms", 10_000_u64)
        .expect("set request timeout");

    let after = store
        .read(|config| {
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
