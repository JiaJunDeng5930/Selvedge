# chatgpt-auth

<!-- selvedge-package-readme
package: chatgpt-auth
freshness_fingerprint: 6f755cdbf6cbcae521f2f453e555414671fa49fc
-->

This crate resolves ChatGPT auth state for request execution.

It exposes:

- `resolve_for_request()`
- `resolve_after_unauthorized()`
- `parse_auth_file(...)`
- `parse_chatgpt_jwt_claims(...)`
- `read_chatgpt_auth_config()`
- `chatgpt_auth_file_path(...)`
- `persist_chatgpt_auth_file(...)`

The crate reads ChatGPT provider settings fresh for every call through
`selvedge_config`, uses `selvedge_client` for refresh HTTP requests, and reads
or atomically updates the `chatgpt` login credential record at
`<selvedge_home>/auth/model-providers/chatgpt.json`.

`chatgpt-login` reuses the config, claims, and token validation APIs.
`model-credentials` owns envelope decoding, paths, locking, and atomic writes.
The token writer requires a `CredentialLockGuard`; callers retain that guard
across refresh so another writer cannot replace the credential mid-refresh.
Invalid tokens leave the existing file unchanged.

The current ChatGPT credential payload requires `tokens` and an RFC3339
`last_refresh` timestamp. Login and successful refresh writes record the current
UTC time. Records without a valid timestamp fail validation and require a new
login; the reader does not migrate older records.

Access tokens with a readable JWT expiry refresh within five minutes of expiry.
Tokens without an expiry, including opaque tokens, refresh when `last_refresh`
is more than eight days old. JWT expiry takes precedence over that age fallback.
Refresh uses a JSON request body. A refresh HTTP 401 response or a recognized
terminal provider code requires reauthentication; diagnostics support both OAuth
string errors and nested `error.code` / `error.message` responses.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([resolve_for_request or resolve_after_unauthorized])
  LoadConfig[Read ChatGPT provider settings]
  LoadHint[Read pre-lock credential snapshot for forced refresh]
  Lock[Acquire credential path lock]
  LoadFile[Load credential record]
  ParseClaims[Parse id and access token claims]
  Decide{refresh condition}
  ReturnLocal[Return local credentials]
  Refresh[POST refresh request]
  Merge[Validate and merge refresh response tokens]
  Persist[Atomically persist credential record]
  ReturnRefreshed[Return refreshed credentials]
  ConfigError[Return config error]
  FileError[Return auth file parse or IO error]
  LockError[Return lock error]
  WorkspaceError[Return workspace mismatch]
  RefreshError[Return refresh failed or reauthentication required]

  Start -->|request auth resolution starts| LoadConfig
  LoadConfig -->|config read succeeds| LoadHint
  LoadConfig -->|config read fails| ConfigError
  LoadHint -->|call is resolve_after_unauthorized| Lock
  LoadHint -->|call is resolve_for_request| Lock
  Lock -->|exclusive path lock acquired| LoadFile
  Lock -->|lock directory, open, or exclusive lock fails| LockError
  LoadFile -->|credential JSON exists and required tokens and last_refresh parse| ParseClaims
  LoadFile -->|file missing, malformed JSON, unsupported schema, or required token field invalid| FileError
  ParseClaims -->|workspace claim conflicts with expected_workspace_id| WorkspaceError
  ParseClaims -->|claims parse and workspace is accepted| Decide
  Decide -->|tokens are usable, proactive refresh is not due, and force refresh is absent| ReturnLocal
  Decide -->|access token is unusable, id token is malformed, proactive refresh is due, or forced refresh still requires new tokens| Refresh
  Decide -->|forced refresh sees another writer already changed usable tokens| ReturnLocal
  Refresh -->|provider returns 2xx JSON token response| Merge
  Refresh -->|provider returns reauthentication code, non-2xx response, invalid success body, unusable token, or transport error| RefreshError
  Merge -->|required replacement tokens are nonempty and usable| Persist
  Merge -->|required replacement token is missing, empty, or unusable| RefreshError
  Persist -->|directory create, temp write, encode, and rename succeed| ReturnRefreshed
  Persist -->|directory create, temp write, encode, or rename fails| FileError
```
