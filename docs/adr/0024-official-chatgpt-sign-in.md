# 0024: Official Sign in with ChatGPT

## Context

Selvedge's former Codex-derived account transport, recorded in [ADR 0017](0017-chatgpt-account-contract.md),
is replaced by the public [Sign in with ChatGPT contract](https://developers.openai.com/siwc/token-sharing-open-source).
Private Codex clients and routes cannot establish conformance to that contract.

## Decision and reasons

Use the published MIT `openid-client` 6.8.8 standards library. The official
[DevKit](https://github.com/openai/sign-in-with-chatgpt-devkit/tree/f723814abdccec135b519c451fb6e1992ee5e933)
was evaluated, but its local package is an unpublished workspace, its facade lacks
raw Responses tools and access tokens, and its Noncommercial License restricts
business use. Vendoring its internals would retain those constraints while bypassing
its public interface. A standards library supports the required host integration.

Explicitly enable `enableNonRepudiationChecks`: the library's default token-endpoint
validation does not verify ID-token signatures at the application level. The
[signature-validation API](https://github.com/panva/openid-client/blob/v6.8.8/docs/functions/enableNonRepudiationChecks.md)
provides the required check alongside standard OIDC claim validation.

Keep account configuration, identity, login and credentials in `chatgpt-account.mjs`.
These rules must have one owner so configuration and transport clients cannot
interpret the same account differently. Expose account-bound authorization and a
controlled refresh operation, rather than persisted credential records; consumers
need permission to make requests, not refresh tokens or registration internals.

Bind identity to issuer, issued client and verified subject: equal email addresses
do not establish equal registrations. Persist registration separately from rotating
credentials so a failed exchange can reuse its issued client without accepting an
unverified identity. Serialize refresh and replace credentials atomically to avoid
rotation races. Reject the former credential format rather than maintain two formats.

Use public Responses inference and bounded text summaries because the official
contract does not establish the former Codex compaction operation. Preserve complete
response items and encrypted reasoning in history; text summaries do not claim
provider-checkpoint equivalence.

Account authorization remains a Host responsibility. Bend receives ordinary
Configure inputs and emits committed model effects, preserving task/account binding
without introducing a second account lifecycle. Native proofs establish admission
and history preservation; loopback tests cannot establish live-account eligibility
or generated summary quality. Users manage access through
[ChatGPT usage settings](https://chatgpt.com/settings/usage).
