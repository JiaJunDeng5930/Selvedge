# router

This crate owns the in-memory Selvedge router actor.

Use it to spawn the router mailbox, register task runtime handles returned by the factory, route task-local commands to live runtimes, coordinate runtime lifecycle effects, answer runtime inventory queries, and forward router-mediated event ingress.

The router keeps runtime registry, lifecycle effect registry, and waiting task commands in memory. Factory, API, tool execution, events, and task runtimes interact with the router through command-model messages and executor traits.
