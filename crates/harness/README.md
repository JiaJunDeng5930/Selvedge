# harness

<!-- selvedge-package-readme
package: selvedge-harness
freshness_fingerprint: 1111a356944d1d1cb3cc33dcb9e70a5f452060c4
-->

This crate defines the model-visible protocol for Selvedge task self-orchestration.

Use it for the four harness tool manifests, typed invocation parsing, argument validation, typed success projections, stable JSON output, and correlated `ToolExecutionResult` construction.

This crate does not execute tools, access storage, coordinate runtimes, or define task lifecycle states beyond `active` and `archived`. Calling task identity and function-call correlation come from `ToolExecutionRequest`, not model arguments.

When a fork transaction has already created a durable child but runtime startup fails, the typed error preserves that child as `task_id` with `task_created: true`. The protocol does not imply that the child was rolled back.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([caller supplies ToolExecutionRequest])
  Select{tool name}
  Validate[Validate flat primitive arguments]
  Invocation[Return typed harness invocation]
  Invalid[Return invalid_arguments]
  Unknown[Return unknown_tool]
  Outcome{caller supplies typed outcome}
  Success[Encode stable success JSON]
  Failure[Encode stable error envelope]
  PartialFailure[Encode runtime failure with durable child identity]
  Result[Return correlated ToolExecutionResult]

  Start -->|tool name is one of the four harness names| Validate
  Start -->|tool name is not a harness name| Unknown
  Validate -->|required, optional, type, uniqueness, and range rules hold| Invocation
  Validate -->|an argument rule fails| Invalid
  Invocation -->|an executor later supplies a success or error| Outcome
  Outcome -->|outcome is successful| Success
  Outcome -->|outcome is an error without a committed child| Failure
  Outcome -->|runtime startup failed after the child commit| PartialFailure
  Success -->|output_text is success JSON and is_error is false| Result
  Failure -->|output_text is the error envelope and is_error is true| Result
  PartialFailure -->|error also contains task_id and task_created true| Result
```
