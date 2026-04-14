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

#[test]
fn invalid_user_agent_is_rejected() {
    let mut config = AppConfig::try_from(Table::new()).expect("materialize config");
    config.network.user_agent = Some("bad\r\nvalue".to_owned());

    assert_eq!(
        config.validate(),
        Err(ValidationError::InvalidUserAgent("bad\r\nvalue".to_owned()))
    );
}

#[test]
fn chatgpt_auth_defaults_materialize_from_empty_config() {
    let config = AppConfig::try_from(Table::new()).expect("materialize config");

    assert_eq!(
        config.llm.providers.chatgpt.auth.issuer,
        "https://auth.openai.com"
    );
    assert_eq!(
        config.llm.providers.chatgpt.auth.client_id,
        "app_EMoamEEZ73f0CkXaXp7hrann"
    );
    assert_eq!(
        config.llm.providers.chatgpt.auth.expected_workspace_id,
        None
    );
}

#[test]
fn chatgpt_auth_accepts_explicit_values() {
    let table = toml::toml! {
        [llm.providers.chatgpt.auth]
        issuer = "https://example.com"
        client_id = "client-123"
        expected_workspace_id = "workspace-456"
    };

    let config = AppConfig::try_from(table).expect("materialize config");

    assert_eq!(
        config.llm.providers.chatgpt.auth.issuer,
        "https://example.com"
    );
    assert_eq!(config.llm.providers.chatgpt.auth.client_id, "client-123");
    assert_eq!(
        config
            .llm
            .providers
            .chatgpt
            .auth
            .expected_workspace_id
            .as_deref(),
        Some("workspace-456")
    );
}

#[test]
fn chatgpt_api_defaults_materialize_from_empty_config() {
    let config = AppConfig::try_from(Table::new()).expect("materialize config");

    assert_eq!(
        config.llm.providers.chatgpt.api.base_url,
        "https://chatgpt.com/backend-api/codex"
    );
    assert_eq!(
        config
            .llm
            .providers
            .chatgpt
            .api
            .stream_completion_timeout_ms,
        1_800_000
    );
}

#[test]
fn chatgpt_api_accepts_explicit_values() {
    let table = toml::toml! {
        [llm.providers.chatgpt.api]
        base_url = "https://example.com/backend-api/codex"
        stream_completion_timeout_ms = 15_000
    };

    let config = AppConfig::try_from(table).expect("materialize config");

    assert_eq!(
        config.llm.providers.chatgpt.api.base_url,
        "https://example.com/backend-api/codex"
    );
    assert_eq!(
        config
            .llm
            .providers
            .chatgpt
            .api
            .stream_completion_timeout_ms,
        15_000
    );
}

#[test]
fn chatgpt_api_rejects_non_absolute_base_url() {
    let table = toml::toml! {
        [llm.providers.chatgpt.api]
        base_url = "/backend-api/codex"
    };

    let error = AppConfig::try_from(table).expect_err("relative base url must fail");

    assert_eq!(
        error.to_string(),
        "llm.providers.chatgpt.api.base_url must be an absolute http or https URL"
    );
}

#[test]
fn chatgpt_api_rejects_non_loopback_http_base_url() {
    let table = toml::toml! {
        [llm.providers.chatgpt.api]
        base_url = "http://example.com/backend-api/codex"
    };

    let error = AppConfig::try_from(table).expect_err("non-loopback http base url must fail");

    assert_eq!(
        error.to_string(),
        "llm.providers.chatgpt.api.base_url must use https unless it targets a loopback host"
    );
}

#[test]
fn chatgpt_api_rejects_base_url_with_query_or_fragment() {
    let query_table = toml::toml! {
        [llm.providers.chatgpt.api]
        base_url = "https://chatgpt.com/backend-api/codex?x=1"
    };
    let fragment_table = toml::toml! {
        [llm.providers.chatgpt.api]
        base_url = "https://chatgpt.com/backend-api/codex#frag"
    };

    let query_error = AppConfig::try_from(query_table).expect_err("base url with query must fail");
    let fragment_error =
        AppConfig::try_from(fragment_table).expect_err("base url with fragment must fail");

    assert_eq!(
        query_error.to_string(),
        "llm.providers.chatgpt.api.base_url must be a clean base URL"
    );
    assert_eq!(
        fragment_error.to_string(),
        "llm.providers.chatgpt.api.base_url must be a clean base URL"
    );
}

#[test]
fn chatgpt_api_rejects_blank_or_zero_timeout() {
    let mut config = AppConfig::try_from(Table::new()).expect("materialize config");
    config
        .llm
        .providers
        .chatgpt
        .api
        .stream_completion_timeout_ms = 0;

    assert_eq!(
        config.validate(),
        Err(ValidationError::InvalidChatgptApiStreamCompletionTimeout)
    );
}

#[test]
fn chatgpt_auth_rejects_blank_expected_workspace_id() {
    let table = toml::toml! {
        [llm.providers.chatgpt.auth]
        expected_workspace_id = ""
    };

    let error = AppConfig::try_from(table).expect_err("blank workspace id must fail");

    assert_eq!(
        error.to_string(),
        "llm.providers.chatgpt.auth.expected_workspace_id must not be blank"
    );
}

#[test]
fn chatgpt_auth_rejects_whitespace_only_expected_workspace_id() {
    let table = toml::toml! {
        [llm.providers.chatgpt.auth]
        expected_workspace_id = "   "
    };

    let error = AppConfig::try_from(table).expect_err("whitespace-only workspace id must fail");

    assert_eq!(
        error.to_string(),
        "llm.providers.chatgpt.auth.expected_workspace_id must not be blank"
    );
}

#[test]
fn chatgpt_auth_rejects_invalid_issuer() {
    let table = toml::toml! {
        [llm.providers.chatgpt.auth]
        issuer = "auth.openai.com"
    };

    let error = AppConfig::try_from(table).expect_err("relative issuer must fail");

    assert_eq!(
        error.to_string(),
        "llm.providers.chatgpt.auth.issuer must be an absolute http or https URL"
    );
}

#[test]
fn chatgpt_auth_rejects_blank_client_id() {
    let table = toml::toml! {
        [llm.providers.chatgpt.auth]
        client_id = "   "
    };

    let error = AppConfig::try_from(table).expect_err("blank client id must fail");

    assert_eq!(
        error.to_string(),
        "llm.providers.chatgpt.auth.client_id must not be blank"
    );
}

#[test]
fn chatgpt_auth_rejects_issuer_with_query_or_path() {
    let query_table = toml::toml! {
        [llm.providers.chatgpt.auth]
        issuer = "https://auth.openai.com?x=1"
    };
    let path_table = toml::toml! {
        [llm.providers.chatgpt.auth]
        issuer = "https://auth.openai.com/codex/device"
    };

    let query_error = AppConfig::try_from(query_table).expect_err("issuer with query must fail");
    let path_error = AppConfig::try_from(path_table).expect_err("issuer with path must fail");

    assert_eq!(
        query_error.to_string(),
        "llm.providers.chatgpt.auth.issuer must be a clean base URL"
    );
    assert_eq!(
        path_error.to_string(),
        "llm.providers.chatgpt.auth.issuer must be a clean base URL"
    );
}

#[test]
fn chatgpt_auth_rejects_non_loopback_http_issuer() {
    let table = toml::toml! {
        [llm.providers.chatgpt.auth]
        issuer = "http://example.com"
    };

    let error = AppConfig::try_from(table).expect_err("non-loopback http issuer must fail");

    assert_eq!(
        error.to_string(),
        "llm.providers.chatgpt.auth.issuer must use https unless it targets a loopback host"
    );
}

#[test]
fn chatgpt_auth_rejects_issuer_with_userinfo() {
    let table = toml::toml! {
        [llm.providers.chatgpt.auth]
        issuer = "https://user:pass@example.com"
    };

    let error = AppConfig::try_from(table).expect_err("issuer with userinfo must fail");

    assert_eq!(
        error.to_string(),
        "llm.providers.chatgpt.auth.issuer must not contain userinfo"
    );
}
