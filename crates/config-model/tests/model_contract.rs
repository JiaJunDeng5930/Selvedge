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
    assert!(config.llm.providers.is_empty());
    assert_eq!(config.harness.max_children_per_fork, 5);
    assert_eq!(config.harness.max_descendants_per_task, 20);
    assert!(config.mcp.servers.is_empty());
}

#[test]
fn harness_limits_are_configurable_and_ordered() {
    let table = toml::toml! {
        [harness]
        max_children_per_fork = 8
        max_descendants_per_task = 30
    };
    let config = AppConfig::try_from(table).expect("materialize harness limits");

    assert_eq!(config.harness.max_children_per_fork, 8);
    assert_eq!(config.harness.max_descendants_per_task, 30);

    let invalid = toml::toml! {
        [harness]
        max_children_per_fork = 21
        max_descendants_per_task = 20
    };
    let error = AppConfig::try_from(invalid).expect_err("fork limit must fit descendant limit");
    assert_eq!(
        error.to_string(),
        "harness.max_children_per_fork must not exceed harness.max_descendants_per_task"
    );
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

    assert_eq!(
        provider.base_url.as_deref(),
        Some("https://example.com/backend-api/codex")
    );
    assert_eq!(provider.stream_completion_timeout_ms, Some(15_000));
    assert_eq!(provider.models, vec!["gpt-5", "gpt-5-codex"]);
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

    assert_eq!(
        missing_authority_error.to_string(),
        "llm.providers.chatgpt.base_url must be an absolute http or https URL"
    );
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

    assert_eq!(
        query_error.to_string(),
        "llm.providers.chatgpt.base_url must be a clean base URL"
    );
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

    assert_eq!(
        error.to_string(),
        "llm.providers contains invalid provider id \"bad/id\""
    );
}

#[test]
fn mcp_servers_materialize_with_defaults_and_explicit_process_settings() {
    let table = toml::toml! {
        [mcp.servers.filesystem]
        command = "npx"
        args = ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]

        [mcp.servers.filesystem.env]
        LOG_LEVEL = "warn"

        [mcp.servers."acme.tools"]
        command = "/opt/acme/mcp"
        timeout_ms = 2_500
    };

    let config = AppConfig::try_from(table).expect("materialize mcp config");
    let filesystem = config
        .mcp
        .servers
        .get("filesystem")
        .expect("filesystem server");
    let acme = config.mcp.servers.get("acme.tools").expect("acme server");

    assert_eq!(filesystem.command, "npx");
    assert_eq!(
        filesystem.args,
        ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
    );
    assert_eq!(
        filesystem.env.get("LOG_LEVEL").map(String::as_str),
        Some("warn")
    );
    assert_eq!(filesystem.timeout_ms, 60_000);
    assert_eq!(acme.timeout_ms, 2_500);
}

#[test]
fn mcp_server_rejects_invalid_id_blank_command_and_zero_timeout() {
    let invalid_id = toml::toml! {
        [mcp.servers."bad/id"]
        command = "mcp-server"
    };
    let blank_command = toml::toml! {
        [mcp.servers.valid]
        command = " \t "
    };
    let zero_timeout = toml::toml! {
        [mcp.servers.valid]
        command = "mcp-server"
        timeout_ms = 0
    };

    assert_eq!(
        AppConfig::try_from(invalid_id)
            .expect_err("invalid server id must fail")
            .to_string(),
        "mcp.servers contains invalid server id \"bad/id\""
    );
    assert_eq!(
        AppConfig::try_from(blank_command)
            .expect_err("blank command must fail")
            .to_string(),
        "mcp.servers.valid.command must not be blank"
    );
    assert_eq!(
        AppConfig::try_from(zero_timeout)
            .expect_err("zero timeout must fail")
            .to_string(),
        "mcp.servers.valid.timeout_ms must be greater than zero"
    );
}

#[test]
fn mcp_server_rejects_nul_in_arguments_and_environment() {
    let nul_argument = toml::toml! {
        [mcp.servers.valid]
        command = "mcp-server"
        args = ["ok", "bad\u{0}argument"]
    };
    let empty_env_key = toml::toml! {
        [mcp.servers.valid]
        command = "mcp-server"

        [mcp.servers.valid.env]
        "" = "value"
    };
    let nul_env_key = toml::toml! {
        [mcp.servers.valid]
        command = "mcp-server"

        [mcp.servers.valid.env]
        "BAD\u{0}KEY" = "value"
    };
    let nul_env_value = toml::toml! {
        [mcp.servers.valid]
        command = "mcp-server"

        [mcp.servers.valid.env]
        KEY = "bad\u{0}value"
    };

    assert_eq!(
        AppConfig::try_from(nul_argument)
            .expect_err("NUL argument must fail")
            .to_string(),
        "mcp.servers.valid.args[1] must not contain NUL"
    );
    assert_eq!(
        AppConfig::try_from(empty_env_key)
            .expect_err("empty environment key must fail")
            .to_string(),
        "mcp.servers.valid.env contains invalid key \"\""
    );
    assert_eq!(
        AppConfig::try_from(nul_env_key)
            .expect_err("NUL environment key must fail")
            .to_string(),
        "mcp.servers.valid.env contains invalid key \"BAD\\0KEY\""
    );
    assert_eq!(
        AppConfig::try_from(nul_env_value)
            .expect_err("NUL environment value must fail")
            .to_string(),
        "mcp.servers.valid.env.KEY must not contain NUL"
    );
}
