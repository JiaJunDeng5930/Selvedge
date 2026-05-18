#![doc = include_str!("../README.md")]

use std::{collections::BTreeMap, path::Path};

use selvedge_config_model::{LlmConfig, LlmProviderConfig};
use selvedge_model_credentials::{CredentialKind, ModelCredentialError, read_credential_from_home};
use thiserror::Error;

/// @behavior selvedge.model.providers Model provider registry centralizes provider descriptors, credential completion rules, model listing, and dispatch validation.
/// @behavior selvedge.model.providers.descriptor Provider descriptors expose provider id, credential kind, and model source for shared provider completion rules.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProviderDescriptor {
    /// @behavior selvedge.model.providers.descriptor.provider_id Provider descriptors expose the id used in configuration, credentials, and dispatch requests.
    pub provider_id: String,
    /// @behavior selvedge.model.providers.descriptor.credential_kind Provider descriptors expose the credential kind required before provider dispatch.
    pub credential_kind: CredentialKind,
    /// @behavior selvedge.model.providers.descriptor.model_source Provider descriptors expose the model source used for listing and dispatch validation.
    pub model_source: ModelSource,
}

/// @behavior selvedge.model.providers.model_source Model sources distinguish discoverable, built-in, and user-configured provider model lists.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ModelSource {
    Discoverable,
    BuiltIn(Vec<String>),
    Configured,
}

/// @behavior selvedge.model.providers.listing Configured model listings expose provider ids and the model names available for local selection.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ConfiguredModelListing {
    /// @behavior selvedge.model.providers.listing.provider_id Configured model listings expose the provider id for a listed provider.
    pub provider_id: String,
    /// @behavior selvedge.model.providers.listing.models Configured model listings expose model names available for local selection.
    pub models: Vec<String>,
    /// @behavior selvedge.model.providers.listing.diagnostics Configured model listings expose provider diagnostics produced while listing models.
    pub diagnostics: Vec<String>,
}

/// @behavior selvedge.model.providers.error Provider registry errors report duplicate descriptors, credential failures, incomplete providers, discovery failures, and dispatch validation failures.
#[derive(Debug, Error, PartialEq, Eq)]
pub enum ProviderRegistryError {
    #[error("provider descriptor id {provider_id:?} is invalid")]
    InvalidProviderDescriptor { provider_id: String },
    #[error("provider descriptor id {provider_id:?} is duplicated")]
    DuplicateProviderDescriptor { provider_id: String },
    #[error("credential store failed: {0}")]
    Credential(String),
    #[error("provider {provider_id:?} is unknown")]
    UnknownProvider { provider_id: String },
    #[error("provider {provider_id:?} is incomplete")]
    IncompleteProvider { provider_id: String },
    #[error("provider {provider_id:?} discovery failed: {reason}")]
    DiscoveryError { provider_id: String, reason: String },
    #[error("provider {provider_id:?} model {model_name:?} is invalid")]
    ValidationError {
        provider_id: String,
        model_name: String,
    },
}

/// @constraint selvedge.model.providers.registry The provider registry maps provider ids to descriptors used by listing and dispatch validation.
pub struct ProviderRegistry {
    /// @constraint selvedge.model.providers.registry.descriptors Provider registries store descriptors keyed by provider id for lookup, listing, and dispatch validation.
    pub(crate) descriptors: BTreeMap<String, ProviderDescriptor>,
}

impl ProviderRegistry {
    /// @constraint selvedge.model.providers.registry.new Registry construction accepts unique path-safe provider descriptors with valid model sources.
    pub fn new(descriptors: Vec<ProviderDescriptor>) -> Result<Self, ProviderRegistryError> {
        let mut registry = BTreeMap::new();
        for descriptor in descriptors {
            if validate_provider_id(&descriptor.provider_id).is_err() {
                // @constraint selvedge.model.providers.registry.new.provider_id Registry construction rejects descriptors whose provider id is invalid.
                return Err(ProviderRegistryError::InvalidProviderDescriptor {
                    provider_id: descriptor.provider_id.clone(),
                });
            }
            validate_model_source(&descriptor)?;
            let provider_id = descriptor.provider_id.clone();
            if registry.insert(provider_id.clone(), descriptor).is_some() {
                // @constraint selvedge.model.providers.registry.new.unique Registry construction rejects duplicate provider descriptor ids.
                return Err(ProviderRegistryError::DuplicateProviderDescriptor { provider_id });
            }
        }

        Ok(Self {
            descriptors: registry,
        })
    }

    /// @behavior selvedge.model.providers.registry.descriptor Registry descriptor lookup returns the descriptor for a provider id when it is registered.
    pub fn descriptor(&self, provider_id: &str) -> Option<&ProviderDescriptor> {
        self.descriptors.get(provider_id)
    }

    /// @behavior selvedge.model.providers.list Configured model listing returns only providers whose credential state and model source satisfy completion rules.
    pub async fn list_configured_models_from_home(
        &self,
        selvedge_home: &Path,
        llm_config: &LlmConfig,
    ) -> Result<Vec<ConfiguredModelListing>, ProviderRegistryError> {
        let mut listings = Vec::new();

        for descriptor in self.descriptors.values() {
            let credential = read_credential_from_home(selvedge_home, &descriptor.provider_id)
                .await
                // @behavior selvedge.model.providers.list.credential_error Configured model listing surfaces credential-store failures as registry credential errors.
                .map_err(map_credential_error)?;
            // @behavior selvedge.model.providers.list.missing_credential Configured model listing skips providers with no credential record.
            let Some(credential) = credential else {
                continue;
            };
            // @behavior selvedge.model.providers.list.kind_mismatch Configured model listing skips providers whose credential kind differs from the descriptor.
            if credential.credential_kind != descriptor.credential_kind {
                continue;
            }
            let provider_config = llm_config.providers.get(&descriptor.provider_id);
            match &descriptor.model_source {
                ModelSource::Configured => {
                    // @behavior selvedge.model.providers.list.configured Configured-source model listing uses provider config model lists after credential completion.
                    // @behavior selvedge.model.providers.list.configured.missing_config Configured model listing skips configured-source providers with no provider config entry.
                    let Some(provider_config) = provider_config else {
                        continue;
                    };
                    // @behavior selvedge.model.providers.list.configured.empty_models Configured model listing skips configured-source providers with empty model lists.
                    if provider_config.models.is_empty() {
                        continue;
                    }
                    // @behavior selvedge.model.providers.list.configured.models Configured model listing returns configured-source model names from provider config.
                    listings.push(ConfiguredModelListing {
                        provider_id: descriptor.provider_id.clone(),
                        models: provider_config.models.clone(),
                        diagnostics: Vec::new(),
                    });
                }
                ModelSource::BuiltIn(models) => {
                    // @behavior selvedge.model.providers.list.built_in Built-in model listing uses descriptor model lists after credential completion.
                    // @behavior selvedge.model.providers.list.built_in.models Configured model listing returns built-in model names from provider descriptors.
                    listings.push(ConfiguredModelListing {
                        provider_id: descriptor.provider_id.clone(),
                        models: models.clone(),
                        diagnostics: Vec::new(),
                    });
                }
                ModelSource::Discoverable => {
                    // @behavior selvedge.model.providers.list.discoverable Discoverable model listing reports provider diagnostics after credential completion.
                    // @behavior selvedge.model.providers.list.discoverable.diagnostic Configured model listing returns discoverable providers with a discovery diagnostic when model discovery is unavailable.
                    listings.push(ConfiguredModelListing {
                        provider_id: descriptor.provider_id.clone(),
                        models: Vec::new(),
                        diagnostics: vec![
                            "model discovery is unavailable in this adapter".to_owned(),
                        ],
                    });
                }
            }
        }

        Ok(listings)
    }

    /// @behavior selvedge.model.providers.dispatch_model Dispatch validation accepts only configured providers and model names allowed by their model source.
    pub async fn validate_dispatch_target_from_home(
        &self,
        selvedge_home: &Path,
        llm_config: &LlmConfig,
        provider_id: &str,
        model_name: &str,
    ) -> Result<(), ProviderRegistryError> {
        if model_name.trim().is_empty() {
            // @constraint selvedge.model.providers.dispatch_model.nonblank Dispatch validation rejects blank model names.
            return Err(ProviderRegistryError::ValidationError {
                provider_id: provider_id.to_owned(),
                model_name: model_name.to_owned(),
            });
        }
        let descriptor = self
            .descriptor(provider_id)
            // @behavior selvedge.model.providers.dispatch_model.unknown Dispatch validation returns unknown-provider errors for unregistered provider ids.
            .ok_or_else(|| ProviderRegistryError::UnknownProvider {
                provider_id: provider_id.to_owned(),
            })?;
        let credential = read_credential_from_home(selvedge_home, provider_id)
            .await
            // @behavior selvedge.model.providers.dispatch_model.credential_error Dispatch validation surfaces credential-store failures as registry credential errors.
            .map_err(map_credential_error)?;
        let Some(credential) = credential else {
            // @behavior selvedge.model.providers.dispatch_model.missing_credential Dispatch validation returns incomplete-provider errors when the provider credential is absent.
            return Err(ProviderRegistryError::IncompleteProvider {
                provider_id: provider_id.to_owned(),
            });
        };
        if credential.credential_kind != descriptor.credential_kind {
            // @behavior selvedge.model.providers.dispatch_model.kind_mismatch Dispatch validation returns incomplete-provider errors when credential kind differs from the descriptor.
            return Err(ProviderRegistryError::IncompleteProvider {
                provider_id: provider_id.to_owned(),
            });
        }
        let provider_config = llm_config.providers.get(provider_id);
        match &descriptor.model_source {
            ModelSource::Configured => {
                // @behavior selvedge.model.providers.dispatch_model.configured Configured-source dispatch validation checks provider config model names after credential completion.
                // @behavior selvedge.model.providers.dispatch_model.configured.missing_config Dispatch validation returns incomplete-provider errors when configured-source providers have no config entry.
                let Some(provider_config) = provider_config else {
                    return Err(ProviderRegistryError::IncompleteProvider {
                        provider_id: provider_id.to_owned(),
                    });
                };
                if provider_config
                    .models
                    .iter()
                    .any(|model| model == model_name)
                {
                    Ok(())
                } else {
                    // @behavior selvedge.model.providers.dispatch_model.configured.invalid_model Dispatch validation returns validation errors when configured-source models are absent from provider config.
                    Err(ProviderRegistryError::ValidationError {
                        provider_id: provider_id.to_owned(),
                        model_name: model_name.to_owned(),
                    })
                }
            }
            ModelSource::BuiltIn(models) => {
                // @behavior selvedge.model.providers.dispatch_model.built_in Built-in dispatch validation checks descriptor model names after credential completion.
                if models.iter().any(|model| model == model_name) {
                    Ok(())
                } else {
                    // @behavior selvedge.model.providers.dispatch_model.built_in.invalid_model Dispatch validation returns validation errors when built-in models are absent from the descriptor.
                    Err(ProviderRegistryError::ValidationError {
                        provider_id: provider_id.to_owned(),
                        model_name: model_name.to_owned(),
                    })
                }
            }
            ModelSource::Discoverable => {
                // @behavior selvedge.model.providers.dispatch_model.discoverable Discoverable-source dispatch validation accepts model names after credential completion.
                // @behavior selvedge.model.providers.dispatch_model.discoverable.accept Dispatch validation accepts discoverable-source model names after the provider credential is complete.
                Ok(())
            }
        }
    }
}

impl Default for ProviderRegistry {
    // @behavior selvedge.model.providers.registry.default Default registry construction returns the built-in Selvedge provider registry.
    fn default() -> Self {
        default_registry()
    }
}

/// @behavior selvedge.model.providers.default_registry The default provider registry contains ChatGPT login, Anthropic API-key, and OpenAI API-key provider descriptors.
pub fn default_registry() -> ProviderRegistry {
    ProviderRegistry::new(vec![
        ProviderDescriptor {
            provider_id: "chatgpt".to_owned(),
            credential_kind: CredentialKind::Login,
            model_source: ModelSource::BuiltIn(vec!["gpt-5".to_owned(), "gpt-5-codex".to_owned()]),
        },
        ProviderDescriptor {
            provider_id: "anthropic".to_owned(),
            credential_kind: CredentialKind::ApiKey,
            model_source: ModelSource::Configured,
        },
        ProviderDescriptor {
            provider_id: "openai".to_owned(),
            credential_kind: CredentialKind::ApiKey,
            model_source: ModelSource::Discoverable,
        },
    ])
    .unwrap_or_else(|_| ProviderRegistry {
        descriptors: BTreeMap::new(),
    })
}

/// @behavior selvedge.model.providers.provider_config Provider config lookup returns a provider config entry from an LLM config by provider id.
pub fn provider_config<'a>(
    llm_config: &'a LlmConfig,
    provider_id: &str,
) -> Option<&'a LlmProviderConfig> {
    llm_config.providers.get(provider_id)
}

// @constraint selvedge.model.providers.model_source.valid Built-in model source validation requires at least one nonblank built-in model name.
fn validate_model_source(descriptor: &ProviderDescriptor) -> Result<(), ProviderRegistryError> {
    if let ModelSource::BuiltIn(models) = &descriptor.model_source
        && (models.is_empty() || models.iter().any(|model| model.trim().is_empty()))
    {
        // @constraint selvedge.model.providers.model_source.valid.built_in Built-in model source validation rejects empty or blank built-in model lists.
        return Err(ProviderRegistryError::ValidationError {
            provider_id: descriptor.provider_id.clone(),
            model_name: String::new(),
        });
    }
    Ok(())
}

// @constraint selvedge.model.providers.provider_id Provider registry provider ids use nonblank path-safe spelling for shared config and credential lookup.
fn validate_provider_id(provider_id: &str) -> Result<(), ()> {
    if provider_id.trim().is_empty() {
        // @constraint selvedge.model.providers.provider_id.nonblank Provider registry id validation rejects blank ids.
        return Err(());
    }
    for byte in provider_id.bytes() {
        let allowed = byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_');
        if !allowed {
            // @constraint selvedge.model.providers.provider_id.path_safe Provider registry id validation rejects characters outside ASCII alphanumeric, dot, hyphen, and underscore.
            return Err(());
        }
    }
    Ok(())
}

// @behavior selvedge.model.providers.credential_error Credential-store errors are mapped into provider registry credential errors.
fn map_credential_error(error: ModelCredentialError) -> ProviderRegistryError {
    ProviderRegistryError::Credential(error.to_string())
}
