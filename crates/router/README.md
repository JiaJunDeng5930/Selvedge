# router

<!-- selvedge-package-readme
package: selvedge-router
freshness_commit: fc2e3adc00d7d6076ee17f2b153d0b8fc8c312dd
-->

This crate owns the Selvedge router actor.

Use it to spawn the process-local mailbox that routes client commands, task runtime output, API output, tool output, factory-created task runtimes, and events ingress. The router owns the live task runtime registry, pending runtime effects, and deferred task-local commands.

This crate does not execute provider calls, tool calls, task-local state transitions, database writes, or client delivery directly. It delegates those effects to the API, configured tool executor, task-runtime factory, core runtime, database, and events crates.

`RouterStartArgs` passes API execution config to `selvedge-api`; provider selection stays in each model-call request.

Router ingress is unbounded. The router is the lifecycle coordinator for task runtimes, and runtime-to-router output must enqueue without waiting for router mailbox capacity while the router is synchronously stopping a runtime. The router handle owns the strong ingress sender; runtime, API, tool, and factory producers receive weak ingress senders so dropping external ingress owners closes the router mailbox.

Core output routing is task-id based. A runtime that enqueued core output before a synchronous stop still has that output routed normally; stop controls runtime registry ownership and future task command delivery.
Core output with an embedded task id must match the envelope task id before the router starts model calls, tool executions, or event publication.

Attach routing is an admission boundary. `RouterCommand::AttachClient` sends `ReserveClientSession` to events and answers the command's admission responder with the reservation result; snapshot hydration starts later through client-sync after server observes the accepted admission.

## Runtime Ownership Decision

The router's runtime uniqueness invariant is route ownership: for one `TaskId`, at most one `TaskRuntimeSender` in `task_runtime_registry` may receive router task commands at a time. Creation is also single-owned through `pending_effects_by_task`.

Stop is a synchronous barrier in the router actor. `StopTaskRuntime` calls `TaskRuntimeControl::stop().await` for the current runtime entry and does not drain the router mailbox while waiting. The stop request and completion result live in the runtime's shared control block, so stop does not use the runtime business mailbox or the router mailbox.

Runtime ownership flows as missing, pending create, live, stopping, then released. During stopping, the router actor is inside the stop call. After `TaskRuntimeStopResult` returns, the router removes the registry entry only if it is still the same control block.

TODO: Define client data synchronization outside this crate. The router forwards client session controls and runtime diagnostics; it does not produce client-visible task, history, parent-edge, snapshot, or subscription-filtered data views.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([spawn router])
  Loop[Router mailbox loop]
  Command[Handle RouterCommand]
  CoreOutput[Handle CoreOutputEnvelope]
  ApiOutput[Handle ApiOutputEnvelope]
  ToolOutput[Handle ToolExecutionResult]
  FactoryOutput[Handle FactoryOutputEnvelope]
  RuntimeLive[Runtime registered live]
  RuntimePending[Runtime creation pending]
  RuntimeStopping[Runtime stop barrier in progress]
  Events[Forward event control]
  ErrorNotice[Publish diagnostic notice]
  Shutdown[Exit when ingress closes]

  Start -->|router handle is created| Loop
  Loop -->|RouterCommand arrives| Command
  Loop -->|CoreOutputEnvelope arrives| CoreOutput
  Loop -->|ApiOutputEnvelope arrives| ApiOutput
  Loop -->|ToolExecutionResult arrives| ToolOutput
  Loop -->|FactoryOutputEnvelope arrives| FactoryOutput
  Command -->|AttachClient reservation send succeeds| Events
  Command -->|Start, create, scan, or child-task command needs runtime and registry lacks live entry| RuntimePending
  Command -->|task command targets live runtime| RuntimeLive
  Command -->|StopTaskRuntime targets live runtime| RuntimeStopping
  Command -->|validation, missing runtime, events, database, or factory dispatch fails| ErrorNotice
  RuntimePending -->|factory effect is started for task| Loop
  FactoryOutput -->|runtime created for pending task| RuntimeLive
  FactoryOutput -->|factory skipped or failed task| ErrorNotice
  RuntimeLive -->|runtime send succeeds| Loop
  RuntimeLive -->|runtime send fails| ErrorNotice
  RuntimeStopping -->|TaskRuntimeControl stop result resolves| Loop
  CoreOutput -->|task id matches envelope and action is model call, tool call, or event publish| Events
  CoreOutput -->|task id mismatch or downstream send fails| ErrorNotice
  ApiOutput -->|correlation matches waiting runtime| RuntimeLive
  ApiOutput -->|correlation is unknown or runtime send fails| ErrorNotice
  ToolOutput -->|run id matches waiting runtime| RuntimeLive
  ToolOutput -->|run id is unknown or runtime send fails| ErrorNotice
  Events -->|event ingress send succeeds| Loop
  Events -->|event ingress send fails| ErrorNotice
  ErrorNotice -->|diagnostic handling completes| Loop
  Loop -->|all router ingress senders are dropped| Shutdown
```
