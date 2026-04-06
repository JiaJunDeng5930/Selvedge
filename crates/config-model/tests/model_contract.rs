use std::convert::TryFrom;

use selvedge_config_model::{AppConfig, ValidationError};
use toml::Table;

#[test]
fn empty_table_materializes_to_valid_defaults() {
    let config = AppConfig::try_from(Table::new()).expect("materialize config");

    assert!(config.validate().is_ok());
    assert_eq!(config.network.connect_timeout_ms, None);
    assert_eq!(config.network.request_timeout_ms, None);
    assert_eq!(config.network.stream_idle_timeout_ms, None);
}

#[test]
fn unknown_fields_are_rejected() {
    let parsed = toml::from_str::<Table>(
        r#"
        [server]
        host = "127.0.0.1"
        port = 8080
        extra = true
        "#,
    )
    .expect("parse raw table");

    let error = AppConfig::try_from(parsed).expect_err("unknown field should fail");

    assert!(error.to_string().contains("unknown field"));
}

#[test]
fn invalid_scalar_value_is_rejected() {
    let mut config = AppConfig::try_from(Table::new()).expect("materialize config");
    config.server.port = 0;

    assert_eq!(config.validate(), Err(ValidationError::InvalidPort));
}

#[test]
fn cross_field_constraint_is_rejected() {
    let mut config = AppConfig::try_from(Table::new()).expect("materialize config");
    config.feature.enabled = true;
    config.feature.rollout_percentage = 0;

    assert_eq!(
        config.validate(),
        Err(ValidationError::EnabledFeatureRequiresRollout)
    );
}

#[test]
fn zero_network_timeout_is_rejected() {
    let mut config = AppConfig::try_from(Table::new()).expect("materialize config");
    config.network.request_timeout_ms = Some(0);

    assert_eq!(
        config.validate(),
        Err(ValidationError::InvalidNetworkRequestTimeout)
    );
}
