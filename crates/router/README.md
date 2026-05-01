# router

This crate owns the Selvedge router actor.

Use it to spawn the process-local mailbox that routes client commands, task runtime output, API output, tool output, factory-created task runtimes, and events ingress. The router owns the live task runtime registry, pending runtime effects, and deferred task-local commands.

This crate does not execute provider calls, tool calls, task-local state transitions, database writes, or client delivery directly. It delegates those effects to the API, configured tool executor, task-runtime factory, core runtime, database, and events crates.

TODO: Define client data synchronization outside this crate. The router forwards client session controls and runtime diagnostics; it does not produce client-visible task, history, parent-edge, snapshot, or subscription-filtered data views.
