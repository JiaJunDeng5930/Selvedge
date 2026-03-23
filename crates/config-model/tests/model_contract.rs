use selvedge_config_model::{AppConfig, default_app_config, validate_app_config};

#[test]
fn defaults_are_valid() {
    let config = default_app_config();

    assert!(validate_app_config(&config).is_ok());
}

#[test]
fn unknown_fields_are_rejected() {
    let parsed = toml::from_str::<AppConfig>(
        r#"
        [server]
        host = "127.0.0.1"
        port = 8080
        extra = true

        [logging]
        level = "info"
        format = "text"

        [feature]
        enabled = false
        rollout_percentage = 0
        "#,
    );

    assert!(parsed.is_err());
}

#[test]
fn invalid_scalar_value_is_rejected() {
    let mut config = default_app_config();
    config.server.port = 0;

    assert!(validate_app_config(&config).is_err());
}

#[test]
fn cross_field_constraint_is_rejected() {
    let mut config = default_app_config();
    config.feature.enabled = true;
    config.feature.rollout_percentage = 0;

    assert!(validate_app_config(&config).is_err());
}
