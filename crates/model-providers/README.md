# model-providers

<!-- selvedge-package-readme
package: selvedge-model-providers
freshness_fingerprint: eea2ad559099655a32cf5f56a9f56ad2c648749e
-->

This crate owns the model provider registry and the shared configured-provider rules.

Use it to resolve provider descriptors, check whether a provider is configured, validate dispatch targets, and build the configured provider/model listing for local operations.

`ExecutableProvider` is the authoritative executable identity and supplies its canonical provider id. A descriptor selects an executable provider, its credential requirement, and either configured or built-in model names. Successful dispatch validation returns the executable identity for the API adapter's exhaustive match. Adding an enum variant requires adding its adapter branch.

The default registry exposes ChatGPT. Its fixed descriptors must validate; invalid built-in descriptors fail loudly rather than silently producing an empty registry.

## Package State Machine

```mermaid
flowchart TD
  Start([list or dispatch validation request])
  Descriptor[Resolve executable provider descriptor]
  Credential[Read credential state]
  Source[Check model source]
  Success[Return configured listing or executable provider]
  Unknown[Return unknown provider]
  Missing[Omit from listing or reject incomplete dispatch]
  Failure[Return credential error]
  Invalid[Return model validation error]

  Start -->|dispatch model name is empty| Invalid
  Start -->|dispatch model name is nonempty or caller requests a listing| Descriptor
  Descriptor -->|dispatch provider id is absent| Unknown
  Descriptor -->|dispatch descriptor exists or listing visits next descriptor| Credential
  Credential -->|credential read fails| Failure
  Credential -->|credential is absent or wrong kind| Missing
  Credential -->|credential kind matches| Source
  Source -->|configured source has no config or listing models are empty| Missing
  Source -->|listing has configured or built-in models| Success
  Source -->|dispatch model belongs to configured or built-in model list| Success
  Source -->|dispatch model is absent from the model list| Invalid
```
