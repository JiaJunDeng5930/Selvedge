# api

This crate executes one Selvedge model call and returns the completed result to the router mailbox.

Use it to dispatch a single provider call, normalize the provider response into a model reply, classify execution failures, and spawn short-lived Tokio tasks for model calls.

This crate is not for database access, filesystem access, task creation, task runtime mutation, router registry mutation, retries, or persistence.
