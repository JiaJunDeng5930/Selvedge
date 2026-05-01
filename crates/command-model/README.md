# command-model

This crate defines the Selvedge command model API slice used to dispatch model calls, return completed API outputs to the router, and describe router-mediated client event ingress.

Use it to define model-call request correlation, dispatch request, output envelope, call error, router ingress message types, router commands, factory output messages, event ingress messages, client subscriptions, client snapshots, raw events, and client outbound frames.

This crate is not for network access, database access, filesystem access, provider execution, or task runtime mutation.

`RuntimeReady` is only a readiness signal. The task runtime sender is returned by `selvedge-core::spawn_task_runtime` to the creator that owns router registration.
`TaskRuntimeInstanceId` identifies one spawned runtime instance so the router can ignore stale exits from replaced runtimes.
`TaskRuntimeCommand::Stop` carries a one-shot acknowledgement sender. A runtime sends the acknowledgement only after it has processed all commands that were ahead of `Stop` in its mailbox and is ready to exit.

`EventIngressSender` is owned by the router. `ClientFrameSender` is supplied by the router for a single client session. Delivery sequencing and hydration buffering live in `selvedge-events`.

Factory output envelopes are returned by synchronous factory calls. Runtime inventory is supplied to the factory by the router from router-owned live and pending task runtime state.
