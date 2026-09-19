# ADR 0008: Script command environments and durable execution

Status: Accepted

## Context

Registering every extension function as a model tool couples application scripting to the model protocol. Selvedge needs ordinary functions and modules behind one `exec_cmd` tool, while keeping the existing independent tools available. An environment can be shared by unrelated invocations, so its state and authority cannot both belong to the task that originally created it.

The existing open-call recovery policy requires retry-safe tools to avoid duplicate observable effects. Marking arbitrary scripts retry-safe without additional persistence would repeat variable mutations, messages, and child creation. A tool attempt identifier changes across recovery and cannot identify a previously applied script operation. Returning from the executor also precedes the core's history transaction, leaving a gap if the next shared user is admitted immediately.

## Decision

Represent script environments separately from tasks, and keep caller authority on each invocation. Fork shares the environment by default; copy preserves an evaluated environment as independent state, while new starts from the base environment. Serializing execution at the environment boundary makes a copy consistent across every sharing task.

Use owned V8 150.4 snapshots for evaluated JavaScript state. The executable probe demonstrated persistent lexical declarations, closures, modules, top-level await, and repeated independent restore/snapshot cycles. The direct V8 interface accepts owned snapshot bytes; the evaluated `deno_core` interface instead required a static byte slice, which would prevent normal reclamation without modifying its ownership model. The runtime remains a separate adapter that has no database or task authority.

Use one process-level worker queue for the V8 isolate lifecycle. Default-parallel integration tests exposed crashes in concurrent `SnapshotCreator::CreateBlob` calls; debugger stacks identified read-only heap serialization and promotion. Serializing only test execution would leave the production failure intact. The worker serializes real initialization, evaluation, and snapshot disposal while callers retain asynchronous request/response interfaces. Independent environments do not currently execute JavaScript in parallel.

Keep initialization in the existing log/cursor flow. An ordinary initial `exec_cmd` function call is dispatched during startup and produces an ordinary tool output. Explicit startup execution mode reaches every script host operation. JavaScript has no ambient filesystem-write or process capability; a shell/write host command returns a normal startup-denial diagnostic instead of performing the operation.

Startup does not prohibit scoped kernel mutations. Initialization can create children or append messages through their journaled kernel operations. A normal attempt becoming a startup recovery attempt preserves the same durable invocation identity.

Persist nested operation identity and results using the calling task, durable outer function-call node, and operation ordinal. Mutation authorization and effect/result recording occur at the actual kernel mutation transaction. Replays must validate the command and arguments before reusing a result. A different operation at a recorded position fails safely; this is not a claim that arbitrary nondeterministic JavaScript will reproduce the same computation.

Commit the next environment state with the enclosing tool output. Retain exclusive environment admission until that commit settles. A script-created child is readable before the enclosing command finishes, but cannot start until its output and environment assignment are finalized. This permits commands after fork in the same script while retaining the requested copy boundary.

Defer self-directed lifecycle changes until that enclosing commit, so stopping or archiving the caller cannot cancel its own unfinished checkpoint. A later externally committed lifecycle change takes precedence over the deferred request; finishing old work must never revive an archived task. Task-originated message sends must also pass scope checks before runtime creation, because starting an unauthorized target can itself execute durable work.

An unfinished invocation can outlive the task actor that admitted it. Recovery of that specific invocation must be possible without resuming the task's model loop, including when that task has since stopped or archived. Otherwise a surviving child that shares the environment could remain blocked forever. This adds a completion-only exception to [ADR 0003](0003-persisted-task-lifecycle.md)'s rejection of archived task runtime creation; it does not resume the model loop or introduce another initialization mechanism.

## Consequences

Adding a composed script function does not add a model tool definition. Host command documentation and extension source remain discoverable from the environment. Sharing state does not grant parent authority to a child's invocation, including after asynchronous continuations.

Snapshot creation and persistence add work at command boundaries. The design does not claim measured latency or memory overhead. Extension data remains ordinary files written through the explicit host capabilities; there is no extension data-model registry.

The persistence format changes without migration or fallback readers, following repository policy. Engine checkpoints are current-format data, rather than a portable interchange format across arbitrary V8 versions.
