# api

This crate executes one Selvedge model call and returns the completed result to the router mailbox.

Use it to dispatch a single provider call, normalize the provider response into a model reply, classify execution failures, and spawn short-lived Tokio tasks for model calls.

The public entry point is `execute_model_call(request, router_tx, config)`. Provider selection comes from `request.provider.provider_name`; `chatgpt` is dispatched directly to `chatgpt-api`.

For ChatGPT direct dispatch, `request.provider.model_name` becomes the ChatGPT model. `request.provider.max_output_tokens` is accepted by the Selvedge request contract and ignored by this path because `chatgpt-api` exposes no request field for that control; ChatGPT `response.incomplete` with reason `max_output_tokens` returns `ModelFinishReason::Length` with accumulated output. Direct dispatch pins ChatGPT capabilities to reasoning summaries enabled, text verbosity enabled, and default reasoning effort `medium` until Selvedge has a capability source.

This crate is not for database access, filesystem access, task creation, task runtime mutation, router registry mutation, retries, or persistence.
