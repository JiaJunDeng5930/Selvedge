# Adaptive reasoning

Three independent settings are involved: an evaluator connection, an endpoint's
adaptive policy, and the ordinary profile preset produced by ChatGPT login.
Selecting a profile without an adaptive policy never invokes Jev.

## Configure the evaluator

Add `reasoning_evaluators` to the service home's `config.json`. Keep the key in
the environment of the server, not in the file:

```json
{
  "reasoning_evaluators": {
    "jev": {
      "provider": "openrouter",
      "api_key_env": "JEV_API_KEY",
      "timeout_ms": 30000,
      "max_attempts": 3
    }
  }
}
```

This is a configuration fragment, not a replacement for the existing file.
Supported provider presets are `openrouter` (`typesafe/jev-1.13`), `vercel`
(`typesafe-ai/jev`) and `typesafe` (`jev-latest`). `model` and the complete
`endpoint` URL can be overridden independently. The connection is a typed Jev
decision API, not an ordinary chat-completions API. Plain HTTP is permitted only
on loopback. Restart the server after changing its configuration or environment.

The evaluator receives the original and current request, retained public notes,
the frozen project context, and the last six tool calls paired with their results.
Each call shares a 1,000-local-token result budget. Head/tail omissions are marked;
the complete request is bounded by 28,000 local tokens and the native frame limit.
The pinned `o200k_base` tokenizer is an estimate, not Jev's private tokenizer.
Private/encrypted model continuation is excluded by the native projection.
Public task and tool content still leaves this computer for the chosen evaluator.

## Use the login preset

Sign in with the existing `bun host/cli.mjs login` command. When the account
catalog advertises `gpt-6-astra`, discovery also materializes
`chatgpt/<account-namespace>/gpt-6-astra-auto`. It keeps the same account and
underlying model. Its only selectable reasoning setting is `auto`; the ordinary
Astra profile remains available independently.

The preset is ordinary profile data produced by `accountAutoPreset`, using the
account's advertised effort levels, its default baseline, evaluator name `jev`,
and `configuration_update` transport. It does not configure or authenticate Jev.
A manually configured profile under that auto key overrides the preset. Like
other discovered account profiles, the generated preset is materialized from the
authenticated catalog rather than written over the user's configuration file.
No Codex CLI patch, model proxy or provider-specific scheduler is involved.

## Enable another endpoint

An API-key endpoint can use the same feature without ChatGPT login. For example,
add this profile to `profiles`, supplying the actual provider/model and supported
reasoning levels for the endpoint being used:

```json
{
  "my-model-auto": {
    "provider": "responses",
    "model": "my-model",
    "endpoint": "https://my-provider.example/v1/responses",
    "api_key_env": "MY_MODEL_API_KEY",
    "adaptive_reasoning": {
      "evaluator": "jev",
      "efforts": ["low", "medium", "high"],
      "baseline": "medium",
      "transport": "request_effort",
      "max_lease": 10
    }
  }
}
```

`request_effort` places the chosen effort on each request. Use
`configuration_update` only with an endpoint that implements that Responses
item: it keeps the original request-level effort and records changes in the
conversation. Earlier input items remain unchanged. Cache eligibility, retention
and actual savings still depend on the service and workload; no savings have
been measured here. The literal value `auto` is never sent as an upstream effort.

The model endpoint's credentials and the evaluator credentials are separate.
An adaptive profile is a task-generation profile, not an independent approval
reviewer; use an ordinary profile for `approval-for-me` judgments.

## Failure and verification boundaries

Missing configuration, authentication failures, invalid choices and exhausted
same-provider retries stop visibly without substituting a provider, model or
guessed effort. Tool execution is not repeated when an evaluator request fails.
Restart reconstructs the committed native state. Finished observations are not
replayed. An unfinished evaluation is recovered through the native scheduler with
a fresh, committed ticket; the old callback can no longer authorize a generation.

`REASONING.bend` is the policy entry. `bendlib/reasoning-spec.bend` specifies
generation authorization and settlement independently of the production
implementation. `ReasoningBoundary` binds routing, tickets, revisions, lease
ownership, prefix updates and public projection to checked evidence in
`bendlib/proofs/reasoning.bend`. HTTP, tokenization, SQLite, browser rendering and
the quality of Jev's decisions remain external boundaries tested separately.
