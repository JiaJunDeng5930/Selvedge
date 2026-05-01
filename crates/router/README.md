# router

This crate owns the Selvedge router actor.

Use it to spawn the process-local mailbox that routes client commands, task runtime output, API output, tool output, factory-created task runtimes, and events ingress. The router owns the live task runtime registry, pending runtime effects, and deferred task-local commands.

This crate does not execute provider calls, tool calls, task-local state transitions, database writes, or client delivery directly. It delegates those effects to the API, configured tool executor, task-runtime factory, core runtime, database, and events crates.

## Runtime Ownership Decision

The router's runtime uniqueness invariant is route ownership: for one `TaskId`, at most one `TaskRuntimeSender` in `task_runtime_registry` may receive router task commands at a time. Creation is also single-owned through `pending_effects_by_task`.

Stop is a synchronous barrier in the router actor. `StopTaskRuntime` calls `TaskRuntimeControl::stop().await` for the current runtime entry and does not drain the router mailbox while waiting. The stop request and completion result live in the runtime's shared control block, so stop does not use the runtime business mailbox or the router mailbox.

Runtime ownership flows as missing, pending create, live, stopping, then released. During stopping, the router actor is inside the stop call. After `TaskRuntimeStopResult` returns, the router removes the registry entry only if it is still the same control block.

TODO: Define client data synchronization outside this crate. The router forwards client session controls and runtime diagnostics; it does not produce client-visible task, history, parent-edge, snapshot, or subscription-filtered data views.
