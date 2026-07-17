# domain-model

<!-- selvedge-package-readme
package: selvedge-domain-model
freshness_fingerprint: babd97983f5cec64b996241879634dc187cea019
-->

This crate defines the Selvedge domain model API slice used by model-call packages.

Use it to define conversation, tool, provider, and normalized model reply data structures.

Tool input schemas and function-call arguments use `JsonObject`, backed by
`serde_json` with arbitrary-precision number decoding. Conversation replay has
explicit function-call and function-output content variants, so callers do not
encode tool history as generic structured messages.

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
  Ready[Value ready for package boundary]
  Serialize[Serialize or clone for caller]

  Start -->|caller constructs conversation path, message, node id, or task id| Conversation
  Start -->|caller constructs tool name, full input schema, manifest, call id, or object arguments| Tool
  Start -->|caller constructs provider profile or reasoning effort| Provider
  Start -->|caller constructs model reply content, tool call, usage, or finish reason| Reply
  Conversation -->|Rust type construction succeeds| Ready
  Tool -->|Rust type construction succeeds| Ready
  Provider -->|Rust type construction succeeds| Ready
  Reply -->|Rust type construction succeeds| Ready
  Ready -->|serde caller requests serialization| Serialize
  Serialize -->|serde succeeds for contained values| Ready
```
