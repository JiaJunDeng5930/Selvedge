# api

This crate executes one Selvedge model call and returns the completed result to the router mailbox.

Use it to dispatch a single provider call, normalize the provider response into a model reply, classify execution failures, and spawn short-lived Tokio tasks for model calls.

The public entry point is `execute_model_call(request, router_tx, config)`. Provider selection comes from `request.provider.provider_name`; `chatgpt` is dispatched directly to `chatgpt-api`.

This crate is not for database access, filesystem access, task creation, task runtime mutation, router registry mutation, retries, or persistence.
