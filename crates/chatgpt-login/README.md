# chatgpt-login

## This crate is for

This crate implements the ChatGPT device-code login flow.

Use it to:

- start a device-code login challenge
- poll the provider for authorization state
- exchange the authorization grant for tokens
- persist the ChatGPT auth file after a successful login

## This crate is not for

This crate is not for:

- exposing a reusable login client
- caching config or process-local login state across calls
- validating JWT signatures or fetching JWKS documents
- supporting providers other than ChatGPT

## Public API

Callers use three async functions:

- `start_device_code_login()`
- `poll_device_code_login(...)`
- `complete_device_code_login(...)`

The crate reads ChatGPT auth config fresh for every call through `selvedge_config`
and executes every HTTP request through `selvedge_client`.

## Runtime behavior

- `start_device_code_login()` reads the current `issuer` and `client_id`, then
  requests a new device-code challenge
- `poll_device_code_login(...)` performs exactly one poll and never loops
  internally
- `complete_device_code_login(...)` exchanges the authorization grant, parses
  claims from `id_token`, checks `expected_workspace_id` when configured, and
  writes `<selvedge_home>/auth/chatgpt-auth.json` atomically before returning

## Challenge lifetime contract

`DeviceCodeChallenge::expires_at` is an API contract, not a reflection of any
provider-specific TTL field. This crate always sets `expires_at` to
`issued_at + 15 minutes`.

This behavior is intentional. It matches the repository-level public contract
for this crate, and callers may rely on that fixed lifetime when they interpret
`DeviceCodePollOutcome::Expired` or `ChatgptLoginError::ChallengeExpired`.

If the provider returns a different lifetime value, this crate does not surface
that value through the public API.

## Config

This crate reads:

```toml
[llm.providers.chatgpt.auth]
issuer = "https://auth.openai.com"
client_id = "app_EMoamEEZ73f0CkXaXp7hrann"
expected_workspace_id = "optional string"
```
