#![doc = include_str!("../README.md")]

use std::{collections::BTreeMap, path::Path};

use selvedge_config_model::{LlmConfig, LlmProviderConfig};
use selvedge_model_credentials::{CredentialKind, ModelCredentialError, read_credential_from_home};
use thiserror::Error;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProviderDescriptor {
    pub provider_id: String,
    pub credential_kind: CredentialKind,
    pub model_source: ModelSource,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ModelSource {
    Discoverable,
    BuiltIn(Vec<String>),
    Configured,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ConfiguredModelListing {
    pub provider_id: String,
    pub models: Vec<String>,
    pub diagnostics: Vec<String>,
}

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

pub struct ProviderRegistry {
    pub(crate) descriptors: BTreeMap<String, ProviderDescriptor>,
}

impl ProviderRegistry {
    pub fn new(descriptors: Vec<ProviderDescriptor>) -> Result<Self, ProviderRegistryError> {
        let mut registry = BTreeMap::new();
        for descriptor in descriptors {
            if validate_provider_id(&descriptor.provider_id).is_err() {
                return Err(ProviderRegistryError::InvalidProviderDescriptor {
                    provider_id: descriptor.provider_id.clone(),
                });
            }
            validate_model_source(&descriptor)?;
            let provider_id = descriptor.provider_id.clone();
            if registry.insert(provider_id.clone(), descriptor).is_some() {
                return Err(ProviderRegistryError::DuplicateProviderDescriptor { provider_id });
            }
        }

        Ok(Self {
            descriptors: registry,
        })
    }

    pub fn descriptor(&self, provider_id: &str) -> Option<&ProviderDescriptor> {
        self.descriptors.get(provider_id)
    }

    pub async fn list_configured_models_from_home(
        &self,
        selvedge_home: &Path,
        llm_config: &LlmConfig,
    ) -> Result<Vec<ConfiguredModelListing>, ProviderRegistryError> {
        let mut listings = Vec::new();

        for descriptor in self.descriptors.values() {
            let credential = read_credential_from_home(selvedge_home, &descriptor.provider_id)
                .await
                .map_err(map_credential_error)?;
            let Some(credential) = credential else {
                continue;
            };
            if credential.credential_kind != descriptor.credential_kind {
                continue;
            }
            let provider_config = llm_config.providers.get(&descriptor.provider_id);
            match &descriptor.model_source {
                ModelSource::Configured => {
                    let Some(provider_config) = provider_config else {
                        continue;
                    };
                    if provider_config.models.is_empty() {
                        continue;
                    }
                    listings.push(ConfiguredModelListing {
                        provider_id: descriptor.provider_id.clone(),
                        models: provider_config.models.clone(),
                        diagnostics: Vec::new(),
                    });
                }
                ModelSource::BuiltIn(models) => {
                    listings.push(ConfiguredModelListing {
                        provider_id: descriptor.provider_id.clone(),
                        models: models.clone(),
                        diagnostics: Vec::new(),
                    });
                }
                ModelSource::Discoverable => {
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

    pub async fn validate_dispatch_target_from_home(
        &self,
        selvedge_home: &Path,
        llm_config: &LlmConfig,
        provider_id: &str,
        model_name: &str,
    ) -> Result<(), ProviderRegistryError> {
        if model_name.trim().is_empty() {
            return Err(ProviderRegistryError::ValidationError {
                provider_id: provider_id.to_owned(),
                model_name: model_name.to_owned(),
            });
        }
        let descriptor =
            self.descriptor(provider_id)
                .ok_or_else(|| ProviderRegistryError::UnknownProvider {
                    provider_id: provider_id.to_owned(),
                })?;
        let credential = read_credential_from_home(selvedge_home, provider_id)
            .await
            .map_err(map_credential_error)?;
        let Some(credential) = credential else {
            return Err(ProviderRegistryError::IncompleteProvider {
                provider_id: provider_id.to_owned(),
            });
        };
        if credential.credential_kind != descriptor.credential_kind {
            return Err(ProviderRegistryError::IncompleteProvider {
                provider_id: provider_id.to_owned(),
            });
        }
        let provider_config = llm_config.providers.get(provider_id);
        match &descriptor.model_source {
            ModelSource::Configured => {
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
                    Err(ProviderRegistryError::ValidationError {
                        provider_id: provider_id.to_owned(),
                        model_name: model_name.to_owned(),
                    })
                }
            }
            ModelSource::BuiltIn(models) => {
                if models.iter().any(|model| model == model_name) {
                    Ok(())
                } else {
                    Err(ProviderRegistryError::ValidationError {
                        provider_id: provider_id.to_owned(),
                        model_name: model_name.to_owned(),
                    })
                }
            }
            ModelSource::Discoverable => Ok(()),
        }
    }
}

impl Default for ProviderRegistry {
    fn default() -> Self {
        default_registry()
    }
}

pub fn default_registry() -> ProviderRegistry {
    ProviderRegistry::new(vec![ProviderDescriptor {
        provider_id: "chatgpt".to_owned(),
        credential_kind: CredentialKind::Login,
        model_source: ModelSource::BuiltIn(vec!["gpt-5".to_owned(), "gpt-5-codex".to_owned()]),
    }])
    .unwrap_or_else(|_| ProviderRegistry {
        descriptors: BTreeMap::new(),
    })
}

pub fn provider_config<'a>(
    llm_config: &'a LlmConfig,
    provider_id: &str,
) -> Option<&'a LlmProviderConfig> {
    llm_config.providers.get(provider_id)
}

fn validate_model_source(descriptor: &ProviderDescriptor) -> Result<(), ProviderRegistryError> {
    if let ModelSource::BuiltIn(models) = &descriptor.model_source
        && (models.is_empty() || models.iter().any(|model| model.trim().is_empty()))
    {
        return Err(ProviderRegistryError::ValidationError {
            provider_id: descriptor.provider_id.clone(),
            model_name: String::new(),
        });
    }
    Ok(())
}

fn validate_provider_id(provider_id: &str) -> Result<(), ()> {
    if provider_id.trim().is_empty() {
        return Err(());
    }
    for byte in provider_id.bytes() {
        let allowed = byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_');
        if !allowed {
            return Err(());
        }
    }
    Ok(())
}

fn map_credential_error(error: ModelCredentialError) -> ProviderRegistryError {
    ProviderRegistryError::Credential(error.to_string())
}
