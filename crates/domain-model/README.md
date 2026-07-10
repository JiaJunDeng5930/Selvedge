# domain-model

<!-- selvedge-package-readme
package: selvedge-domain-model
freshness_fingerprint: 9336643422056626ad58fe8d013127bcfc90aced
-->

This crate defines the Selvedge domain model API slice used by model-call packages.

Use it to define conversation, tool, provider, structured payload, and normalized model reply data structures.

This crate is not for network access, database access, filesystem access, provider execution, or task runtime mutation.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([caller constructs domain value])
  Conversation[Conversation and history value]
  Tool[Tool manifest and argument value]
  Provider[Model provider profile]
  Payload[Structured payload]
  Reply[Normalized model reply]
  Ready[Value ready for package boundary]
  Serialize[Serialize or clone for caller]

  Start -->|caller constructs conversation path, message, node id, or task id| Conversation
  Start -->|caller constructs tool name, parameter, manifest, call id, or argument value| Tool
  Start -->|caller constructs provider profile or reasoning effort| Provider
  Start -->|caller constructs JSON or typed structured payload| Payload
  Start -->|caller constructs model reply content, tool call, usage, or finish reason| Reply
  Conversation -->|Rust type construction succeeds| Ready
  Tool -->|Rust type construction succeeds| Ready
  Provider -->|Rust type construction succeeds| Ready
  Payload -->|Rust type construction succeeds| Ready
  Reply -->|Rust type construction succeeds| Ready
  Ready -->|serde caller requests serialization| Serialize
  Serialize -->|serde succeeds for contained values| Ready
```
