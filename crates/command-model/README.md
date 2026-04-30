# command-model

This crate defines the Selvedge command model API slice used to dispatch model calls, return completed API outputs to the router, and describe router-mediated client event ingress.

Use it to define model-call request correlation, dispatch request, output envelope, call error, router ingress API message types, factory output and runtime inventory messages, event ingress messages, client subscriptions, client snapshots, raw events, and client outbound frames.

This crate is not for network access, database access, filesystem access, provider execution, or task runtime mutation.

`RuntimeReady` is only a readiness signal. The task runtime sender is returned by `selvedge-core::spawn_task_runtime` to the creator that owns router registration.

`EventIngressSender` is owned by the router. `ClientFrameSender` is supplied by the router for a single client session. Delivery sequencing and hydration buffering live in `selvedge-events`.

Client commands, factory outputs, API outputs, tool outputs, runtime exits, runtime inventory queries, and shutdown all enter through `RouterIngressMessage`.

Factory effects report through `RouterIngressMessage::Factory`. Runtime inventory requests use `RouterIngressMessage::RuntimeInventoryQuery` and return live plus pending task runtime task ids through a oneshot response. A factory effect may include its own effect id so the router excludes that effect from the pending set returned to the requester.
