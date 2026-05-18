use std::convert::TryFrom;

use selvedge_config_model::{AppConfig, ValidationError};
use toml::Table;

#[test]
fn empty_table_materializes_to_valid_defaults() {
    let config = AppConfig::try_from(Table::new()).expect("materialize config");

    // @verifies selvedge.config.model
    assert!(config.validate().is_ok());
    // @verifies selvedge.config.model
    assert_eq!(config.network.connect_timeout_ms, None);
    // @verifies selvedge.config.model
    assert_eq!(config.network.request_timeout_ms, None);
    // @verifies selvedge.config.model
    assert_eq!(config.network.stream_idle_timeout_ms, None);
    // @verifies selvedge.config.model.llm.defaults
    assert!(config.llm.providers.is_empty());
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

    // @verifies selvedge.config.model
    assert!(error.to_string().contains("unknown field"));
}

#[test]
fn invalid_scalar_value_is_rejected() {
    let mut config = AppConfig::try_from(Table::new()).expect("materialize config");
    config.server.port = 0;

    // @verifies selvedge.config.model
    assert_eq!(config.validate(), Err(ValidationError::InvalidPort));
}

#[test]
fn cross_field_constraint_is_rejected() {
    let mut config = AppConfig::try_from(Table::new()).expect("materialize config");
    config.feature.enabled = true;
    config.feature.rollout_percentage = 0;

    // @verifies selvedge.config.model
    assert_eq!(
        config.validate(),
        Err(ValidationError::EnabledFeatureRequiresRollout)
    );
}

#[test]
fn zero_network_timeout_is_rejected() {
    let mut config = AppConfig::try_from(Table::new()).expect("materialize config");
    config.network.request_timeout_ms = Some(0);

    // @verifies selvedge.config.model
    assert_eq!(
        config.validate(),
        Err(ValidationError::InvalidNetworkRequestTimeout)
    );
}

#[test]
fn invalid_user_agent_is_rejected() {
    let mut config = AppConfig::try_from(Table::new()).expect("materialize config");
    config.network.user_agent = Some("bad\r\nvalue".to_owned());

    // @verifies selvedge.config.model
    assert_eq!(
        config.validate(),
        Err(ValidationError::InvalidUserAgent("bad\r\nvalue".to_owned()))
    );
}

#[test]
fn provider_map_accepts_non_sensitive_provider_settings() {
    let table = toml::toml! {
        [llm.providers.chatgpt]
        base_url = "https://example.com/backend-api/codex"
        stream_completion_timeout_ms = 15_000
        models = ["gpt-5", "gpt-5-codex"]

        [llm.providers.chatgpt.settings]
        issuer = "https://auth.example.com"
        client_id = "client-123"
        expected_workspace_id = "workspace-456"
    };

    let config = AppConfig::try_from(table).expect("materialize config");
    let provider = config
        .llm
        .providers
        .get("chatgpt")
        .expect("chatgpt provider config");

    // @verifies selvedge.config.model.llm.provider
    assert_eq!(
        provider.base_url.as_deref(),
        Some("https://example.com/backend-api/codex")
    );
    // @verifies selvedge.config.model.llm.provider
    assert_eq!(provider.stream_completion_timeout_ms, Some(15_000));
    // @verifies selvedge.config.model.llm.provider.models
    assert_eq!(provider.models, vec!["gpt-5", "gpt-5-codex"]);
    // @verifies selvedge.config.model.llm.provider.settings
    assert_eq!(
        provider
            .settings
            .get("client_id")
            .and_then(toml::Value::as_str),
        Some("client-123")
    );
}

#[test]
fn provider_base_url_accepts_uppercase_schemes() {
    let table = toml::toml! {
        [llm.providers.chatgpt]
        base_url = "HTTPS://chatgpt.com/backend-api/codex"
    };

    let config = AppConfig::try_from(table).expect("uppercase schemes should be accepted");
    let provider = config
        .llm
        .providers
        .get("chatgpt")
        .expect("chatgpt provider config");

    // @verifies selvedge.config.model.url.scheme
    assert_eq!(
        provider.base_url.as_deref(),
        Some("HTTPS://chatgpt.com/backend-api/codex")
    );
}

#[test]
fn provider_base_url_rejects_non_absolute_base_url() {
    let table = toml::toml! {
        [llm.providers.chatgpt]
        base_url = "/backend-api/codex"
    };

    let error = AppConfig::try_from(table).expect_err("relative base url must fail");

    // @verifies selvedge.config.model.llm.provider.base_url
    assert_eq!(
        error.to_string(),
        "llm.providers.chatgpt.base_url must be an absolute http or https URL"
    );
}

#[test]
fn provider_base_url_rejects_non_loopback_http_base_url() {
    let table = toml::toml! {
        [llm.providers.chatgpt]
        base_url = "http://example.com/backend-api/codex"
    };

    let error = AppConfig::try_from(table).expect_err("non-loopback http base url must fail");

    // @verifies selvedge.config.model.url.scheme
    assert_eq!(
        error.to_string(),
        "llm.providers.chatgpt.base_url must use https unless it targets a loopback host"
    );
}

#[test]
fn provider_base_url_rejects_base_url_without_authority() {
    let missing_authority_table = toml::toml! {
        [llm.providers.chatgpt]
        base_url = "https:///backend-api/codex"
    };
    let relative_authority_table = toml::toml! {
        [llm.providers.chatgpt]
        base_url = "https:backend-api/codex"
    };

    let missing_authority_error = AppConfig::try_from(missing_authority_table)
        .expect_err("base url without authority must fail");
    let relative_authority_error = AppConfig::try_from(relative_authority_table)
        .expect_err("base url with relative authority must fail");

    // @verifies selvedge.config.model.llm.provider.base_url
    assert_eq!(
        missing_authority_error.to_string(),
        "llm.providers.chatgpt.base_url must be an absolute http or https URL"
    );
    // @verifies selvedge.config.model.llm.provider.base_url
    assert_eq!(
        relative_authority_error.to_string(),
        "llm.providers.chatgpt.base_url must be an absolute http or https URL"
    );
}

#[test]
fn provider_base_url_rejects_base_url_with_query_or_fragment() {
    let query_table = toml::toml! {
        [llm.providers.chatgpt]
        base_url = "https://chatgpt.com/backend-api/codex?x=1"
    };
    let fragment_table = toml::toml! {
        [llm.providers.chatgpt]
        base_url = "https://chatgpt.com/backend-api/codex#frag"
    };

    let query_error = AppConfig::try_from(query_table).expect_err("base url with query must fail");
    let fragment_error =
        AppConfig::try_from(fragment_table).expect_err("base url with fragment must fail");

    // @verifies selvedge.config.model.llm.provider.base_url
    assert_eq!(
        query_error.to_string(),
        "llm.providers.chatgpt.base_url must be a clean base URL"
    );
    // @verifies selvedge.config.model.llm.provider.base_url
    assert_eq!(
        fragment_error.to_string(),
        "llm.providers.chatgpt.base_url must be a clean base URL"
    );
}

#[test]
fn provider_rejects_zero_timeout() {
    let table = toml::toml! {
        [llm.providers.chatgpt]
        stream_completion_timeout_ms = 0
    };

    let error = AppConfig::try_from(table).expect_err("zero timeout must fail");

    // @verifies selvedge.config.model.llm.provider.timeout
    assert_eq!(
        error.to_string(),
        "llm.providers.chatgpt.stream_completion_timeout_ms must be greater than zero"
    );
}

#[test]
fn provider_rejects_blank_model_name() {
    let table = toml::toml! {
        [llm.providers.manual]
        models = ["claude", "  "]
    };

    let error = AppConfig::try_from(table).expect_err("blank model must fail");

    // @verifies selvedge.config.model.llm.provider.models
    assert_eq!(
        error.to_string(),
        "llm.providers.manual.models must not contain blank model names"
    );
}

#[test]
fn provider_rejects_duplicate_model_name() {
    let table = toml::toml! {
        [llm.providers.manual]
        models = ["claude", "claude"]
    };

    let error = AppConfig::try_from(table).expect_err("duplicate model must fail");

    // @verifies selvedge.config.model.llm.provider.models
    assert_eq!(
        error.to_string(),
        "llm.providers.manual.models contains duplicate model \"claude\""
    );
}

#[test]
fn provider_rejects_invalid_provider_id() {
    let table = toml::toml! {
        [llm.providers."bad/id"]
        models = ["model"]
    };

    let error = AppConfig::try_from(table).expect_err("invalid provider id must fail");

    // @verifies selvedge.config.model.llm.provider
    assert_eq!(
        error.to_string(),
        "llm.providers contains invalid provider id \"bad/id\""
    );
}
