# 0024: Official Sign in with ChatGPT

## Context

Selvedge previously derived its ChatGPT account adapter from Codex's private
transport, as recorded in [ADR 0017](0017-chatgpt-account-contract.md). OpenAI's
September 29, 2026 release documents a public Sign in with ChatGPT path for
open-source and local applications. Eligible Plus and Pro users can authorize
requests against their ChatGPT plan without supplying an API key. Identity scopes
do not grant access to ChatGPT conversations or authorize inference by themselves.

The official contract provides dynamic client registration, OIDC identity
validation and public model/inference endpoints. Retaining the previous fixed
Codex client, private account claims or backend routes would defeat the purpose
of adopting that contract.

## Decision

Use the documented local public-client flow: browser authorization with PKCE and
a loopback callback, issuer discovery and signed ID-token verification. Persist
the issued client registration separately from rotating credentials, and retain a
stable installation host ID. This permits a failed exchange to reuse its issued
registration without accepting an unverified identity. Bind account identity to
the issuer, issued client ID and verified subject because registration belongs to
the selected account and workspace; equal email addresses do not establish equal
registrations. Serialize refresh and atomically replace credentials to avoid
refresh-token rotation races.

Use OAuth Bearer credentials at the public `/v1/models` and `/v1/responses`
endpoints. Keep account discovery and frozen task contracts at the existing host
boundary. Preserve the model catalog's server order and group local tools in the
`selvedge` namespace, as required by the documented inference contract. Local tool
execution remains governed by the native committed invocation and approval rules.

Use ordinary bounded text summaries for ChatGPT checkpoints. The Sign in with
ChatGPT documentation establishes Responses inference but does not establish
support for the former Codex `compaction_trigger` request or the remote compact
route. A text request uses the documented inference operation and the existing
native summary-admission contract. Retain complete response items and encrypted
reasoning in ordinary model history; this choice does not claim equivalence
between text summaries and encrypted provider checkpoints.

The credential store has one current format. Reject former credentials rather
than adding a compatibility parser; users must run `login` again and remove old
fixed-client or backend-endpoint configuration. Newly registered identity must
not silently substitute for an old task's frozen account identity.

## Consequences and evidence boundary

Users manage participating-app access and usage through
[ChatGPT usage settings](https://chatgpt.com/settings/usage). Plus usage is shared
across participating apps rather than allocated separately to each installation.
The local open-source contract does not establish approval for a paid or remotely
hosted deployment.

Signed loopback OAuth/OIDC and HTTP/SSE fixtures exercise registration, identity,
refresh, model discovery, tools and native summary integration. These tests do
not establish real-account authorization, plan eligibility, remote availability,
or semantic quality of generated summaries. No live account authorization was
performed for this change. Bend proofs continue to describe native admission,
committed effects and history preservation, not the external OAuth service.

## Sources

Contract checked on October 2, 2026:

- [DevDay announcement](https://learn.chatgpt.com/docs/whats-new/devday-2026#sign-in-with-chatgpt)
  and [local/open-source applicability](https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt).
- [Sign-in and dynamic registration](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
  and [OIDC discovery and validation](https://developers.openai.com/siwc/website).
- [Token reference](https://developers.openai.com/siwc/token-sharing-open-source/token-reference)
  and [profiles, sessions and usage](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions).
- [Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
  and [preview request limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations).
- [Official DevKit](https://github.com/openai/sign-in-with-chatgpt-devkit), whose
  local OAuth implementation supplies the reference verification behavior.
