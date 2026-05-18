# model-credentials

<!-- selvedge-package-readme
package: selvedge-model-credentials
freshness_commit: dd00f09a3e7a07a6d96617e202b202598f4404ba
-->

This crate owns persisted model-provider credentials under the selected Selvedge Home.

Use it to read, check, list, and atomically write provider credential records at `<selvedge_home>/auth/model-providers/<provider_id>.json`.

This crate validates only the shared credential envelope: schema version, provider id, credential kind, and minimum payload shape. Provider-specific payload semantics belong to each provider adapter.

## Package State Machine

```mermaid
flowchart TD
  Start([credential operation])
  ResolveHome[Resolve Selvedge Home]
  Path[Build provider credential path]
  Lock[Acquire provider credential lock]
  Read[Read credential file]
  Decode[Decode credential record]
  Present[Return credential record]
  Absent[Return absent credential]
  Encode[Encode credential record]
  Write[Write temporary file]
  Replace[Atomically replace credential file]
  Persisted[Return persisted path]
  ConfigError[Return config error]
  LockError[Return lock error]
  CredentialError[Return credential error]

  Start -->|read, exists, list, or write is requested| ResolveHome
  ResolveHome -->|selected home is available| Path
  ResolveHome -->|selected home is unavailable| ConfigError
  Path -->|provider id is path-safe| Lock
  Path -->|provider id is invalid| CredentialError
  Lock -->|exclusive lock succeeds| Read
  Lock -->|exclusive lock fails| LockError
  Read -->|file exists| Decode
  Read -->|file is missing| Absent
  Read -->|file read or directory listing fails| CredentialError
  Decode -->|envelope is valid| Present
  Decode -->|JSON or envelope is invalid| CredentialError
  Lock -->|write operation holds lock| Encode
  Encode -->|record envelope is valid| Write
  Encode -->|record envelope is invalid| CredentialError
  Write -->|parent directory and temp file write succeed| Replace
  Write -->|directory or temp write fails| CredentialError
  Replace -->|rename succeeds| Persisted
  Replace -->|rename fails| CredentialError
```
