# harness

<!-- selvedge-package-readme
package: selvedge-harness
freshness_fingerprint: 0eb5153539e33f1b94d782b598eeec21612e36d1
-->

This crate implements Selvedge task self-orchestration and bounded Bash command execution for model tool calls.

Use it for the five harness tool manifests, complete JSON input schemas, typed invocation parsing from JSON objects, argument validation, SQLite-backed task reads, router-mediated task mutations, non-interactive Bash commands, stable JSON output, and the production `ToolExecutionSpawner`.

Calling task identity and complete function-call correlation come from `ToolExecutionRequest`, not model arguments. SQLite reads run on Tokio's blocking pool. Send and archive wait for typed router responders, so enqueueing a command is never reported as business success.

`fork_task` accepts a positive `child_count` and an optional `messages` string array of the same length. It creates one calling-task branch with JSON number `0` and one new-child branch per requested child with JSON numbers `1` through `child_count`; each aligned initial message is attached to its child branch and is not part of the branch output. The executor generates child task ids only. Core owns the later transactional branch commit and runtime startup.

Every built-in schema is a closed object with typed, described properties and an explicit required set. Runtime parsing still owns semantic checks such as non-whitespace strings and numeric ranges. Task history projects function-call arguments as their original JSON object, including nested objects, arrays, and nulls.

`bash` runs `/bin/bash -lc` with null stdin and inherits the server process working directory and environment. Its timeout defaults to 30 seconds and accepts 100 through 120000 milliseconds. Stdout and stderr are drained concurrently, each retains at most 65536 bytes, and the result reports truncation separately. Zero and nonzero exits are successful tool executions; signal termination is represented by a null `exit_code`.

Each Bash invocation owns a process group. A timeout sends `SIGKILL` to that group, waits for the shell and pipe readers to settle, and returns `command_timed_out`; the same group guard prevents a cancelled or panicking invocation from leaving command processes behind. Background sessions, PTYs, stdin writes, policy, approval, and sandboxing are outside this crate.

The executor supervises each request in an inner Tokio task and attempts exactly one terminal `ToolExecutionResult` delivery. The result copies the request's task, run, function-call node, function-call id, and tool name unchanged. Ordinary tools and terminal executor failures produce one calling-task branch. A panic or cancelled inner task becomes a correlated error branch instead of leaving the calling runtime waiting forever.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([caller supplies ToolExecutionRequest])
  Supervise[Start supervised execution]
  Select{tool name}
  Validate[Validate the JSON argument object]
  Invocation[Build typed harness invocation]
  Fork[Generate child ids and numbered branches]
  Read[Read SQLite snapshot on blocking pool]
  Mutate[Send router mutation and wait for responder]
  Bash[Run Bash login command in a process group and drain both output pipes]
  BashTimeout[Kill the process group and reap the shell]
  Invalid[Return invalid_arguments]
  Unknown[Return unknown_tool]
  Panic[Map panic or cancellation]
  Outcome{execution outcome}
  Success[Encode stable success JSON]
  Failure[Encode stable error envelope]
  Result[Send one correlated ToolExecutionResult]

  Start -->|Tokio runtime accepts the supervisor| Supervise
  Supervise -->|tool name is one of the five harness names| Validate
  Supervise -->|tool name is not a harness name| Unknown
  Supervise -->|inner execution panics or is cancelled| Panic
  Validate -->|allowed keys, required values, types, and semantic ranges hold| Invocation
  Validate -->|an argument rule fails| Invalid
  Invocation -->|invocation is read_task| Read
  Invocation -->|invocation is fork| Fork
  Invocation -->|invocation is send or archive| Mutate
  Invocation -->|invocation is bash| Bash
  Read -->|SQLite read completes| Outcome
  Mutate -->|router responder settles| Outcome
  Bash -->|shell and both pipes reach a terminal state| Outcome
  Bash -->|deadline expires| BashTimeout
  Bash -->|spawn, pipe read, or wait fails| Failure
  BashTimeout -->|process group termination and shell reap complete| Failure
  BashTimeout -->|termination or reap fails| Failure
  Panic -->|supervisor classifies the JoinError| Failure
  Fork -->|calling branch and all requested child branches are built| Result
  Invalid -->|validation error is terminal| Failure
  Unknown -->|unknown tool error is terminal| Failure
  Outcome -->|outcome is successful| Success
  Outcome -->|outcome is an error| Failure
  Success -->|one calling-task branch carries success JSON| Result
  Failure -->|one calling-task branch carries the error envelope| Result
```
