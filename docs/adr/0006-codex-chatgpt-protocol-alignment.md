# ADR 0006: Align ChatGPT protocol without sharing Codex state

Status: Accepted

## Context

Selvedge's ChatGPT adapter follows the protocol used by Codex, but owns its own credentials, transport, and durable task history. The public Codex implementation at commit `e269f2164cbb9f499e4f22301c393500e2a831f3` requires updated request metadata and token-refresh behavior. Copying its auth storage or session client would introduce another owner for state already owned by Selvedge.

An access token's expiry is not always available. Relying exclusively on a decoded JWT expiry leaves opaque tokens without a proactive refresh criterion. The time of the last successful token refresh is therefore credential state, not an HTTP client's cache or a process-local timer.

## Decision

Keep the existing module ownership and adapt the wire protocol at its current boundaries. Store `last_refresh` in the ChatGPT credential payload and update it together with tokens under the existing credential lock. Use decoded access-token expiry when available, and the persisted refresh time otherwise. The credential envelope remains owned by `model-credentials`.

Treat the updated payload as the single current format. Missing or invalid refresh timestamps fail validation; no migration or alternate credential parser is added. Existing credentials in the superseded format require a new login.

Preserve provider replay metadata at the typed `chatgpt-api` boundary, where callers already own response items and turn state. Adding provider-specific fields to Selvedge's durable conversation model is a separate decision: adapter protocol alignment does not establish that those fields survive the provider-neutral persistence path.

## Consequences

Auth refresh behavior works across process restarts without a second state store. Protocol changes remain local to the auth, login, and Responses adapters, with provider-neutral mapping changes only where their public contracts require them. Mock HTTP and stream tests establish local protocol behavior; they do not establish acceptance by the live ChatGPT service.

Upstream evidence and the exact alignment scope are recorded in the affected package READMEs and tests. The reference revision is a reproducible baseline, not a promise of compatibility with future Codex releases.
