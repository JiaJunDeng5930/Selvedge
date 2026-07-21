# domain-model

<!-- selvedge-package-readme
package: selvedge-domain-model
freshness_fingerprint: ac25435e2d627b5cfbe10c5336897088147bcbf7
-->

This crate defines Selvedge's shared task lifecycle and model-call domain values.

Use it to define conversation, tool, provider, and normalized model reply data structures.

Tool input schemas and function-call arguments use `JsonObject`, backed by
`serde_json` with arbitrary-precision number decoding. `Conversation` stores one
ordered list of `ConversationMessage` values whose content is arbitrary JSON.
Text content is a JSON string. Function calls and outputs use typed JSON objects;
the message constructors and readers define their shared field contract without
adding another persisted content model.
`CallableTools` expresses either the complete manifest or an explicit
duplicate-free subset. It is provider-neutral selection state, not another tool
definition model.

`TaskStatus` is the durable task lifecycle. `TaskLifecycleEvent` defines its complete transition table. New tasks start active; archived tasks have no outgoing transition.

This crate is not for network access, database access, filesystem access, provider execution, or task runtime mutation.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([caller constructs domain value])
  Conversation[Conversation and history value]
  Tool[Tool manifest and argument value]
  Provider[Model provider profile]
  Reply[Normalized model reply]
  TaskActive[Task active]
  TaskFrozen[Task frozen]
  TaskStopped[Task stopped]
  TaskArchived[Task archived]
  Ready[Value ready for package boundary]
  Serialize[Serialize or clone for caller]

  Start -->|caller constructs conversation, JSON message, node id, or task id| Conversation
  Start -->|caller constructs tool name, full input schema, manifest, callable selection, call id, or object arguments| Tool
  Start -->|caller constructs provider profile or reasoning effort| Provider
  Start -->|caller constructs model reply content, tool call, usage, or finish reason| Reply
  Start -->|caller constructs task status| TaskActive
  Conversation -->|Rust type construction succeeds| Ready
  Tool -->|Rust type construction succeeds| Ready
  Provider -->|Rust type construction succeeds| Ready
  Reply -->|Rust type construction succeeds| Ready
  TaskActive -->|Freeze| TaskFrozen
  TaskFrozen -->|Unfreeze| TaskActive
  TaskActive -->|Stop| TaskStopped
  TaskStopped -->|UserInput| TaskActive
  TaskActive -->|Archive| TaskArchived
  TaskFrozen -->|Archive| TaskArchived
  TaskStopped -->|Archive| TaskArchived
  Ready -->|serde caller requests serialization| Serialize
  Serialize -->|serde succeeds for contained values| Ready
```
