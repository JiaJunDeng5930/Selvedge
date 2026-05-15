# api

<!-- selvedge-package-readme
package: selvedge-api
freshness_commit: 1c81a33f8a447fd4578da3e44db1393e6dff110e
-->

This crate executes one Selvedge model call and returns the completed result to the router mailbox.

Use it to dispatch a single provider call, normalize the provider response into a model reply, classify execution failures, and spawn short-lived Tokio tasks for model calls.

The public entry point is `execute_model_call(request, router_tx, config)`. Provider selection comes from `request.provider.provider_name`; `chatgpt` is dispatched directly to `chatgpt-api`.

For ChatGPT direct dispatch, `request.provider.model_name` becomes the ChatGPT model. `request.provider.max_output_tokens` is accepted by the Selvedge request contract and ignored by this path because `chatgpt-api` exposes no request field for that control; ChatGPT `response.incomplete` with reason `max_output_tokens` returns `ModelFinishReason::Length` with accumulated output. Direct dispatch pins ChatGPT capabilities to reasoning summaries enabled, text verbosity enabled, and default reasoning effort `medium` until Selvedge has a capability source.

This crate is not for database access, filesystem access, task creation, task runtime mutation, router registry mutation, retries, or persistence.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([execute_model_call or spawn_model_call_tokio_task])
  Validate[Validate dispatch request]
  SelectProvider{request.provider.provider_name}
  Chatgpt[Run chatgpt-api stream]
  Accumulate[Accumulate streamed output]
  Complete[Send completed ApiOutputEnvelope]
  Unsupported[Send ModelCallError UnsupportedProvider]
  ValidationError[Return validation ModelCallError]
  StreamError[Send provider ModelCallError]
  RouterClosed[Return RouterClosed terminal status]
  Spawned[Tokio task owns execution]

  Start -->|caller invokes execute_model_call| Validate
  Start -->|caller invokes spawn_model_call_tokio_task| Spawned
  Spawned -->|task starts| Validate
  Validate -->|required dispatch fields are present| SelectProvider
  Validate -->|validate_dispatch_request returns error| ValidationError
  SelectProvider -->|provider_name equals chatgpt| Chatgpt
  SelectProvider -->|provider_name has any other value| Unsupported
  Chatgpt -->|stream opens and yields response events| Accumulate
  Chatgpt -->|chatgpt-api returns endpoint, auth, transport, timeout, or validation error| StreamError
  Accumulate -->|stream yields completed event or closes after terminal response| Complete
  Accumulate -->|stream yields an error before completion| StreamError
  Complete -->|router ingress send succeeds| Complete
  Complete -->|router ingress send fails| RouterClosed
  Unsupported -->|router ingress send succeeds| Unsupported
  Unsupported -->|router ingress send fails| RouterClosed
  StreamError -->|router ingress send succeeds| StreamError
  StreamError -->|router ingress send fails| RouterClosed
```
