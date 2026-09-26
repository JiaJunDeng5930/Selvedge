# ChatGPT account transport and model discovery

The external contract was checked against OpenAI Codex `rust-v0.157.1`, released
2026-09-26. These HTTP/OAuth assumptions are tested at the host boundary, not
claimed as Bend theorems. The application identifies itself as Selvedge.

Source anchors in https://github.com/openai/codex/tree/rust-v0.157.1/codex-rs:

- `login/src/device_code_auth.rs`, `login/src/server.rs::send_code_exchange_request`
  and `login/src/auth/manager.rs`: device requests use JSON; authorization-code
  exchange uses form encoding with the device callback and PKCE verifier;
  refresh uses JSON. Authorization codes are not automatically replayed.
- `codex-api/src/common.rs::ResponsesApiRequest` and `core/src/client.rs`:
  Responses streaming, `store: false`, encrypted reasoning, a string
  `tool_choice`, and a stable prompt-cache/session identity. ChatGPT gets only
  the native callable tools; the API-key provider retains its allowed-tools
  request. Full completed items, including message phase and encrypted state,
  remain replayable without also synthesizing a duplicate assistant message.
- `codex-api/src/endpoint/models.rs`: the account catalog is `GET models` with
  `client_version`, using the same bearer credential and account header.
  `protocol/src/openai_models.rs` defines `models`, visibility (`list`, `hide`,
  `none`), priorities and reasoning capabilities. Subscription models are not
  filtered by `supported_in_api`. `models-manager/src/manager.rs` sorts priorities
  ascending. The host keeps connection settings separate from discovered model
  descriptors and binds generated profile identities to both account and route.
- `core/src/compact_remote_v2_attempt.rs`, `compact_remote_v2.rs`, and
  `protocol/src/models.rs`: this release requests remote compaction on the
  Responses stream by appending `{"type":"compaction_trigger"}`. A successful
  compact request must contain exactly one encrypted `compaction` output item.
  It is not an ordinary text-summarization request or the older compact route.

Transport retries apply only before output is exposed, within the existing
native retry budget. One rejected-token refresh is allowed. Redirects are
refused, bodies are bounded, and upstream error text is not persisted as a task
diagnostic. A local fixture is evidence about this adapter, not a live account's
entitlements, remote availability, or the meaning of encrypted compaction.

The model cache contains no tokens. It is valid only for its original account,
connection and audited client version. A fresh cache lasts five minutes; a
transient upstream failure can use matching data up to 24 hours old. Malformed
catalogs, permanent errors and account changes do not authorize stale fallback.
An explicit login/refresh fails visibly instead of using stale data. Credential
refresh remains serialized separately from model discovery.
