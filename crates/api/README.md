# api

<!-- selvedge-package-readme
package: selvedge-api
freshness_commit: 4df7c938dc791ae919322681e4c3b366888c755d
-->

This crate executes one Selvedge model call and returns the completed result to the router mailbox.

Use it to dispatch a single provider call, normalize the provider response into a model reply, classify execution failures, and spawn short-lived Tokio tasks for model calls.

The public entry point is `execute_model_call(request, router_tx, config)`. Provider selection comes from `request.provider.provider_name`; the provider registry validates the configured provider and selected model before the ChatGPT adapter executes ChatGPT requests.

For ChatGPT adapter dispatch, `request.provider.model_name` becomes the ChatGPT model. `request.provider.max_output_tokens` is accepted by the Selvedge request contract and ignored by this path because `chatgpt-api` exposes no request field for that control; ChatGPT `response.incomplete` with reason `max_output_tokens` returns `ModelFinishReason::Length` with accumulated output. ChatGPT dispatch pins ChatGPT capabilities to reasoning summaries enabled, text verbosity enabled, and default reasoning effort `medium` until Selvedge has a capability source.

This crate is not for database access, filesystem access, task creation, task runtime mutation, router registry mutation, retries, or persistence.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([execute_model_call or spawn_model_call_tokio_task])
  Validate[Validate dispatch request]
  ResolveProvider[Resolve provider through registry]
  Chatgpt[Run chatgpt-api stream]
  Accumulate[Accumulate streamed output]
  Complete[Send completed ApiOutputEnvelope]
  UnknownProvider[Send ModelCallError for unknown provider]
  IncompleteProvider[Send ModelCallError for incomplete provider or unavailable model]
  ValidationError[Return validation ModelCallError]
  StreamError[Send provider ModelCallError]
  RouterClosed[Return RouterClosed terminal status]
  Spawned[Tokio task owns execution]

  Start -->|caller invokes execute_model_call| Validate
  Start -->|caller invokes spawn_model_call_tokio_task| Spawned
  Spawned -->|task starts| Validate
  Validate -->|required dispatch fields are present| ResolveProvider
  Validate -->|validate_dispatch_request returns error| ValidationError
  ResolveProvider -->|registry accepts chatgpt and selected model| Chatgpt
  ResolveProvider -->|provider id is absent from registry| UnknownProvider
  ResolveProvider -->|credential or model-source rule is unsatisfied| IncompleteProvider
  Chatgpt -->|stream opens and yields response events| Accumulate
  Chatgpt -->|chatgpt-api returns endpoint, auth, transport, timeout, or validation error| StreamError
  Accumulate -->|stream yields completed event or closes after terminal response| Complete
  Accumulate -->|stream yields an error before completion| StreamError
  Complete -->|router ingress send succeeds| Complete
  Complete -->|router ingress send fails| RouterClosed
  UnknownProvider -->|router ingress send succeeds| UnknownProvider
  UnknownProvider -->|router ingress send fails| RouterClosed
  IncompleteProvider -->|router ingress send succeeds| IncompleteProvider
  IncompleteProvider -->|router ingress send fails| RouterClosed
  StreamError -->|router ingress send succeeds| StreamError
  StreamError -->|router ingress send fails| RouterClosed
```
