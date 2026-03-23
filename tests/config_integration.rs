use selvedge_config::{ConfigStore, LoadSpec, OverrideOp, PersistMode};
use selvedge_config_model::{AppConfig, default_app_config, validate_app_config};

#[test]
fn model_and_store_work_together() {
    let store = ConfigStore::load(
        LoadSpec {
            explicit_file_path: None,
            file_path_candidates: Vec::new(),
            env_prefix: "SELVEDGE_APP".to_owned(),
            cli_overrides: vec![OverrideOp::new("server.port", 9000)],
        },
        default_app_config,
        validate_app_config,
    )
    .expect("load config store");

    let before = store
        .read(|config: &AppConfig| config.server.port)
        .expect("read initial config");

    store
        .set(
            OverrideOp::new("feature.rollout_percentage", 100),
            PersistMode::RuntimeOnly,
        )
        .expect("set rollout percentage");

    store
        .set(
            OverrideOp::new("feature.enabled", true),
            PersistMode::RuntimeOnly,
        )
        .expect("enable feature");

    let after = store
        .read(|config: &AppConfig| {
            (
                config.server.port,
                config.feature.enabled,
                config.feature.rollout_percentage,
            )
        })
        .expect("read updated config");

    assert_eq!(before, 9000);
    assert_eq!(after, (9000, true, 100));
}
