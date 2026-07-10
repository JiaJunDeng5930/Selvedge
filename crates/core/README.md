# core

<!-- selvedge-package-readme
package: selvedge-core
freshness_commit: 592f95539c225023a2f2d66f8096a3f85ac304ee
-->

This crate runs one task runtime actor per active task.

Use it to spawn a task-local runtime that loads SQLite state through `selvedge-db`, queues input while busy, requests model calls through the router, requests tool execution through the router, and exits on archive or database errors.

This crate only talks to the router mailbox and the database package. Provider calls, tool execution, event fanout, runtime registry ownership, and direct client delivery live in other crates.

On `Start`, the runtime reads the active task snapshot and classifies the concrete cursor tail. User/system/function-output tails request a model call; function-call tails request tool execution; assistant/developer tails await user input with an empty queue. The runtime keeps only in-flight correlation ids and pending tool-call identity in memory; the task cursor lives in SQLite.

The actor checks `TaskRuntimeControl` before receiving each business mailbox command. A stop request makes the actor return from its loop at that safety point. The mailbox receive branch is behind the control branch and the actor rechecks stop after receiving a command, so a stop bit observed at the event boundary prevents the next business command from starting. The runtime writes `TaskRuntimeStopResult` from the actor's unified exit path, so a later stop call also completes after archive, database error, router shutdown, or dropped runtime mailbox.

Runtime output to the router uses the unbounded router ingress sender. Event handlers can enqueue router output synchronously and return to the control check without waiting for router mailbox capacity.

`TaskRuntimeSpawnDeps` wraps the runtime config and a `TaskRuntimeSpawner` implementation. Use `TaskRuntimeSpawnDeps::new` for the default Tokio-backed spawner and `with_spawner` for boundary tests.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([spawn_task_runtime])
  LoadSnapshot[Read active task snapshot]
  ClassifyTail{cursor tail}
  AwaitInput[Await user input]
  RequestModel[Send model call request to router]
  AwaitModel[Await matching API output]
  RequestTool[Send tool execution request to router]
  AwaitTool[Await matching tool output]
  QueueInput[Queue or append user input]
  Archive[Archive task]
  Stop[Exit after stop control]
  Exit[Publish TaskRuntimeExitNotice]
  DbError[Exit on database error]
  RouterClosed[Exit on router ingress closure]

  Start -->|task runtime actor starts| LoadSnapshot
  LoadSnapshot -->|active task snapshot read succeeds| ClassifyTail
  LoadSnapshot -->|database read fails or task is inactive| DbError
  ClassifyTail -->|tail is user, system, or function output| RequestModel
  ClassifyTail -->|tail is function call| RequestTool
  ClassifyTail -->|tail is assistant or developer and queued input is empty| AwaitInput
  ClassifyTail -->|tail is assistant or developer and queued input exists| QueueInput
  RequestModel -->|router ingress send succeeds| AwaitModel
  RequestModel -->|router ingress send fails| RouterClosed
  AwaitModel -->|matching completed API output arrives| ClassifyTail
  AwaitModel -->|matching failed API output arrives| AwaitInput
  AwaitModel -->|user input arrives while model is in flight| QueueInput
  RequestTool -->|router ingress send succeeds| AwaitTool
  RequestTool -->|router ingress send fails| RouterClosed
  AwaitTool -->|matching tool result arrives| ClassifyTail
  AwaitTool -->|user input arrives while tool is in flight| QueueInput
  AwaitInput -->|user input command arrives| QueueInput
  QueueInput -->|database transition succeeds| ClassifyTail
  QueueInput -->|database transition fails| DbError
  AwaitInput -->|archive command arrives| Archive
  Archive -->|database archive succeeds| Exit
  Archive -->|database archive fails| DbError
  AwaitInput -->|stop control observed before business command starts| Stop
  AwaitModel -->|stop control observed at command boundary| Stop
  AwaitTool -->|stop control observed at command boundary| Stop
  Stop -->|actor writes stop result| Exit
```
