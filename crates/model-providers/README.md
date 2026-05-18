# model-providers

<!-- selvedge-package-readme
package: selvedge-model-providers
freshness_commit: 636fd61c9fc62b053c401426481a47ea5f0c066b
-->

This crate owns the model provider registry and the shared configured-provider rules.

Use it to resolve provider descriptors, check whether a provider is configured, validate dispatch targets, and build the configured provider/model listing for local operations.

Provider adapters own provider-specific request execution and discovery. This crate keeps provider id, credential kind, model source, and completion rules in one place.

## Package State Machine

```mermaid
flowchart TD
  Start([list or dispatch validation request])
  LoadConfig[Load provider config]
  LoadCredential[Load credential state]
  Descriptor[Resolve descriptor]
  Check[Check configured state]
  Configured[Use configured models]
  BuiltIn[Use built-in models]
  Discover[Discover provider models]
  Validate[Validate dispatch target]
  Success[Return listing or accepted target]
  ConfigError[Return config error]
  CredentialError[Return credential error]
  UnknownProvider[Return unknown provider]
  Incomplete[Return incomplete provider]
  DiscoveryError[Return discovery error]
  ValidationError[Return validation error]

  Start -->|caller supplies config or a model request| LoadConfig
  LoadConfig -->|config model is valid| LoadCredential
  LoadConfig -->|config load fails| ConfigError
  LoadCredential -->|credential store read succeeds| Descriptor
  LoadCredential -->|credential store fails| CredentialError
  Descriptor -->|provider id exists in registry| Check
  Descriptor -->|provider id is absent from registry| UnknownProvider
  Check -->|credential is missing or wrong kind| Incomplete
  Check -->|configured-source list request has models| Configured
  Check -->|built-in-source list request has models| BuiltIn
  Check -->|discoverable-source list request has credentials| Discover
  Check -->|dispatch request has configured provider| Validate
  Configured -->|model names validate| Success
  BuiltIn -->|built-in names validate| Success
  Discover -->|discovery returns models| Success
  Discover -->|discovery fails| DiscoveryError
  Validate -->|model name satisfies source rule| Success
  Validate -->|model name violates source rule| ValidationError
```
