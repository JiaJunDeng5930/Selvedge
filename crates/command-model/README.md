# command-model

<!-- selvedge-package-readme
package: selvedge-command-model
freshness_fingerprint: 081b3aa9305f93209fdecb007690921c696a3c00
-->

This crate defines the Selvedge command model API slice used to dispatch model calls, return completed API and branched tool outputs to the router, and describe router-mediated client event ingress.

Use it to define model-call request correlation, dispatch request, output envelope, call error, router ingress message types, router commands, event ingress messages, client subscriptions, client snapshots, shared client events, and client outbound frames.

This crate is not for network access, database access, filesystem access, provider execution, or task runtime mutation.

`RuntimeReady` is only a readiness signal. The task runtime sender is returned by `selvedge-core::spawn_task_runtime` to the creator that owns router registration.
`TaskRuntimeControl` is the shared control block for one runtime. It notifies the actor after a durable status change and provides a synchronous actor-exit barrier. Process shutdown sets the shutdown request before waiting on that barrier; archive only notifies the actor and waits for the same barrier. The control block does not store task status.
`TaskRuntimeCommand` carries ordered actor work. `ModelCallNotStarted` is the typed result of a router dispatch gate rejecting a model request after the durable status stopped permitting model calls; it is distinct from a provider API failure. Lifecycle transitions remain outside the task mailbox so a frozen actor can still unfreeze or archive.
`RouterCommand::SendUserInput` and each lifecycle command carry typed responders. Input succeeds as `Committed` with its persisted history node id or as `Queued`; a lifecycle command succeeds with its committed `TaskStatus`. Dropping an unsettled responder returns `RuntimeUnavailable`, so mailbox replacement, cancellation, and shutdown cannot be mistaken for a committed SQLite transition.
`ToolExecutionResult` contains one or more ordered branches. A branch targets the calling task or a newly identified child task and carries JSON output, an error bit, and ordinary user messages to append after the output. `CoreOutputMessage::EnsureTaskRuntimes` asks the router to start runtimes for task ids that core has already committed.
`RouterIngressSender` is unbounded. Runtime, API, and tool outputs must be able to enqueue router ingress without awaiting router mailbox capacity, because archive and process shutdown can synchronously wait for runtime actors to finish.
`RouterIngressWeakSender` is for internal router producers. Internal producers upgrade it only while an external ingress owner keeps the router mailbox open.
`CoreOutputEnvelope` carries `task_id` for task-based router routing.
Function-call history projections and tool execution requests carry their arguments as one `JsonObject`; function-output projections carry one JSON value. Nested values, arrays, nulls, and exact JSON numbers therefore cross router and client boundaries without flat primitive or string conversion.
`ModelCallDispatchRequest` shares the immutable `TaskModelConfig` selected by the task and separately carries the resolved provider profile. It carries the complete frozen manifest and a provider-neutral `CallableTools` selection for the current turn. Validation requires every explicitly callable name to be unique and present in that manifest.

`EventIngressSender` is owned by the router. `ClientFrameSender` is supplied by the router for a single client session. Delivery sequencing and hydration buffering live in `selvedge-events`.
`RouterCommand::AttachClient` carries an admission responder. The router must answer it after events reserves the client session slot; server uses that response as the attach accepted boundary before starting client-sync hydration.
`DetachReason::ClientRequested` represents an explicit detach command. `DetachReason::ClientDisconnected` represents the server observing the attach stream close.

`ClientSessionIdentity` allocates a fresh process-local generation for each attach attempt. Control messages carry that identity even if a later attach reuses the same client and command IDs. `DeliverNotice` additionally carries the command correlation for the operation that produced the notice. `ClientEvent` is the shared representation from publication through hydration buffering to client delivery.

`RouterCommand::SendTaskInput` and `ChangeTaskStatus` carry a trusted `CommandOperationContext` and a `CommandOperationResponder`. The context separates caller scope from optional durable operation identity; the responder returns the JSON business result saved with the database mutation, or a classified `TaskCommandError`. A replayed operation returns its recorded result. Self lifecycle changes can return `deferred: true` until the enclosing tool result commits. Dropping an unsettled responder reports `RuntimeUnavailable`. Existing client commands retain their unscoped response contracts.

`RouterCommand::RecoverCommandInvocation` and its runtime counterpart identify a specific admitted invocation by task and durable function-call node. They request completion of that admission, including when ordinary task status would prevent execution; they do not authorize a new model run. Command-model validates nonempty task identifiers and required message text. The router, runtime, and database own admission, scope, and lifecycle checks.

`ToolExecutionRequest.execution_mode` distinguishes ordinary dispatch from startup recovery. `ToolExecutionResult.prepared_environment` optionally carries a typed checkpoint commit and an owned environment mutex guard. Clones share the same guard, so the lease remains held until all prepared-result owners release it after the database transaction. Equality includes guard identity; checkpoint bytes alone do not imply the same lease.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([caller constructs command-model value])
  ValidateDispatch[Validate ModelCallDispatchRequest]
  ValidateApiOutput[Validate ApiOutputEnvelope]
  ValidateRouterCommand[Validate RouterCommand]
  ControlReady[TaskRuntimeControl ready]
  StatusChanged[Durable task status changed]
  ModelNotStarted[Model call not started]
  ShuttingDown[Runtime shutdown requested]
  ShutdownFinished[Shutdown result published]
  TaskResponsePending[Task command response pending]
  TaskResponseSettled[Task command response settled]
  ToolResult[Construct branched tool result]
  Valid[Return accepted value]
  Invalid[Return validation error]

  Start -->|caller validates dispatch request| ValidateDispatch
  Start -->|caller validates API output envelope| ValidateApiOutput
  Start -->|caller validates router command| ValidateRouterCommand
  Start -->|caller creates TaskRuntimeControl| ControlReady
  Start -->|caller creates a user-input, lifecycle, or command-operation response channel| TaskResponsePending
  Start -->|caller constructs recovery request for a durable invocation| ValidateRouterCommand
  Start -->|router status gate suppresses a model dispatch| ModelNotStarted
  Start -->|caller constructs a completed tool result| ToolResult
  ValidateDispatch -->|correlation, task, provider, profile, input, manifest, and callable subset satisfy contract| Valid
  ValidateDispatch -->|required dispatch field is empty or inconsistent| Invalid
  ValidateApiOutput -->|output envelope correlation and payload are consistent| Valid
  ValidateApiOutput -->|output envelope correlation or payload is inconsistent| Invalid
  ValidateRouterCommand -->|client session ids or task id and required message text are nonempty| Valid
  ValidateRouterCommand -->|required session ids, task id, or message text is empty| Invalid
  ControlReady -->|notify_status_changed is called| StatusChanged
  StatusChanged -->|actor wakes and reloads durable status| ControlReady
  ModelNotStarted -->|runtime correlates the undispatched model run| Valid
  ControlReady -->|shutdown is called| ShuttingDown
  StatusChanged -->|shutdown is called| ShuttingDown
  ShuttingDown -->|finish_shutdown stores result and notifies waiters| ShutdownFinished
  ShutdownFinished -->|later shutdown call observes stored result| ShutdownFinished
  TaskResponsePending -->|runtime reports a committed, replayed, or deferred operation result, or classified failure| TaskResponseSettled
  TaskResponsePending -->|unsettled responder is dropped| TaskResponseSettled
  PreparedEnvironment[Prepared checkpoint retains lease]
  ToolResult -->|result includes prepared environment| PreparedEnvironment
  PreparedEnvironment -->|outer checkpoint transaction commits and all prepared owners release| Valid
  ToolResult -->|every branch has a target, JSON output, error bit, and user messages| Valid
```
