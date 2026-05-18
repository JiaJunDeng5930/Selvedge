use selvedge_config_model::{LlmConfig, LlmProviderConfig};
use selvedge_model_credentials::{CredentialKind, ModelCredentialRecord, write_credential_to_home};
use selvedge_model_providers::{
    ModelSource, ProviderDescriptor, ProviderRegistry, default_registry,
};
use std::collections::BTreeMap;

#[tokio::test]
// @verifies selvedge.model.providers.list.built_in.models
async fn built_in_provider_is_configured_when_matching_credential_exists() {
    let tempdir = tempfile::TempDir::new().expect("tempdir");
    let registry = ProviderRegistry::new(vec![ProviderDescriptor {
        provider_id: "chatgpt".to_owned(),
        credential_kind: CredentialKind::Login,
        model_source: ModelSource::BuiltIn(vec!["gpt-5".to_owned(), "gpt-5-codex".to_owned()]),
    }])
    .expect("registry");
    write_credential_to_home(
        tempdir.path(),
        &ModelCredentialRecord {
            schema_version: 1,
            provider: "chatgpt".to_owned(),
            credential_kind: CredentialKind::Login,
            payload: serde_json::json!({ "tokens": { "access_token": "a" } }),
        },
    )
    .await
    .expect("write credential");

    let listings = registry
        .list_configured_models_from_home(tempdir.path(), &empty_llm_config())
        .await
        .expect("list models");

    // @verifies selvedge.model.providers.list.built_in.models
    assert_eq!(listings.len(), 1);
    // @verifies selvedge.model.providers.list.built_in.models
    assert_eq!(listings[0].provider_id, "chatgpt");
    // @verifies selvedge.model.providers.list.built_in.models
    assert_eq!(listings[0].models, vec!["gpt-5", "gpt-5-codex"]);
}

#[tokio::test]
// @verifies selvedge.model.providers.list.configured.models
async fn configured_provider_requires_matching_credential_and_config_models() {
    let tempdir = tempfile::TempDir::new().expect("tempdir");
    let registry = ProviderRegistry::new(vec![ProviderDescriptor {
        provider_id: "anthropic".to_owned(),
        credential_kind: CredentialKind::ApiKey,
        model_source: ModelSource::Configured,
    }])
    .expect("registry");
    write_credential_to_home(
        tempdir.path(),
        &ModelCredentialRecord {
            schema_version: 1,
            provider: "anthropic".to_owned(),
            credential_kind: CredentialKind::ApiKey,
            payload: serde_json::json!({ "api_key": "key" }),
        },
    )
    .await
    .expect("write credential");
    let llm_config = LlmConfig {
        providers: BTreeMap::from([(
            "anthropic".to_owned(),
            LlmProviderConfig {
                base_url: None,
                stream_completion_timeout_ms: None,
                models: vec!["claude-sonnet-4".to_owned()],
                settings: BTreeMap::new(),
            },
        )]),
    };

    let listings = registry
        .list_configured_models_from_home(tempdir.path(), &llm_config)
        .await
        .expect("list models");

    // @verifies selvedge.model.providers.list.configured.models
    assert_eq!(listings.len(), 1);
    // @verifies selvedge.model.providers.list.configured.models
    assert_eq!(listings[0].provider_id, "anthropic");
    // @verifies selvedge.model.providers.list.configured.models
    assert_eq!(listings[0].models, vec!["claude-sonnet-4"]);
}

#[test]
// @verifies selvedge.model.providers.default_registry.executable
fn default_registry_exposes_only_executable_providers() {
    let registry = default_registry();

    // @verifies selvedge.model.providers.default_registry.executable
    assert!(registry.descriptor("chatgpt").is_some());
    // @verifies selvedge.model.providers.default_registry.executable
    assert!(registry.descriptor("anthropic").is_none());
    // @verifies selvedge.model.providers.default_registry.executable
    assert!(registry.descriptor("openai").is_none());
}

fn empty_llm_config() -> LlmConfig {
    LlmConfig {
        providers: BTreeMap::new(),
    }
}
