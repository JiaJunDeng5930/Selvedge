# router

This crate owns the in-memory Selvedge router actor.

Use it to spawn the router mailbox, register task runtime handles returned by the factory, route task-local commands to live runtimes, coordinate runtime lifecycle effects, answer runtime inventory queries, project domain events into typed raw events, and forward router-mediated event ingress.

The router keeps runtime registry, lifecycle effect registry, and waiting task commands in memory. Factory, API, tool execution, events, and task runtimes interact with the router through command-model messages and executor traits.

Core output is accepted only when the envelope runtime token matches the registered live runtime for that task. Model-call and tool-execution requests are additionally discarded while the runtime is in removal.
