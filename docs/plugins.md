# Plugins and hooks

The extension entry is `HOOKS.bend`, bound by `CONCEPTS.Extensibility`. Plugins are
trusted local executables speaking newline-delimited UTF-8 JSON-RPC 2.0 over stdio.
They do not need to be JavaScript modules or share a runtime with the Bend binary.
The included Bun example only demonstrates that wire contract.

## Configure and run

Add an entry to the existing configuration's `plugins` object and restart:

```json
{
  "plugins": {
    "audit": {
      "command": "bun",
      "args": ["/absolute/path/to/Selvedge/examples/plugins/audit.mjs"],
      "env": {
        "SELVEDGE_BASH_DEADLINE_MS": "10000",
        "SELVEDGE_AUDIT_FILE": "/absolute/private/path/selvedge-events.jsonl"
      }
    }
  }
}
```

This is a configuration fragment; retain the existing model profiles and other
settings. The audit file's parent directory must already exist. Without an audit
file the example still registers `plugin__audit__text_metrics` and caps Bash
deadlines. It does not filter dangerous shell commands or sandbox processes.

Configuration object order defines hook order, regardless of which process starts
first. Names match `[A-Za-z][A-Za-z0-9_]{0,63}`. Optional `cwd`, `env`, `args` and
`timeout_ms` configure transport; `event_timeout_ms` and `event_queue` bound
observers separately. Default request and observer deadlines are 10 and 5 seconds,
with 128 queued observer events and at most 16 plugins. `/describe` exposes the
native protocol version, event vocabulary and limits. A plugin must advance its
revision when code, policy, capabilities or tool meanings change. Task contracts
freeze exact revisions and hook order; an unavailable revision fails closed.

## Initialization and new tools

The host sends an `initialize` request with `protocolVersion`, client identity,
workspace, native event names and transport limits. The result is:

```json
{
  "protocolVersion": "selvedge-plugin-2",
  "revision": "example-2",
  "beforeTool": true,
  "afterTool": true,
  "events": ["tool_completed", "task_created"],
  "tools": [{
    "name": "echo",
    "description": "Return a supplied string",
    "inputSchema": {
      "type": "object",
      "properties": {"text": {"type": "string"}},
      "required": ["text"],
      "additionalProperties": false
    }
  }]
}
```

The resulting public name is `plugin__<configured-name>__echo`. Duplicate names,
unknown manifest fields, unsupported event names and unsupported schemas reject
initialization. There is no runtime tool-registration mutation inside callbacks:
restart to install a changed manifest, and use a new revision for new meanings.
This keeps already frozen contracts unambiguous.

Both hook flags are required Booleans. This is the current protocol, not a
compatibility negotiation: old manifests without `afterTool` are rejected.

Extension schemas use the native decidable fragment: closed objects with explicit
`properties` and optional `required`; arrays with `items`; strings, Booleans,
nulls and natural-number integers up to `2^32 - 1` with optional minimum/maximum.
`title` and `description` are metadata. Objects may omit `additionalProperties`
or set it to `false`; both are closed. Keywords such as `$ref`, `anyOf`, `enum`,
open properties, negative integers and unrestricted numbers are rejected, not
silently ignored. Definition checking and value checking each have a 256-step
bound. MCP retains its own server-side schema contract; no claim is made that
this extension fragment implements arbitrary JSON Schema.

To execute an approved extension tool, the host sends `callTool` with its local
`name`, final `arguments` and a `context` containing `task_id`, `operation_id` and
`call_id`. The result must be exactly a JSON object containing `value` and Boolean
`error`. Its native completion and cancellation semantics are the same as Bash
and MCP. A timeout or restart does not automatically repeat an external tool whose
outcome may already have happened.

## One before-tool protocol

Every accepted model tool call passes through the same native chain, including
`bash`, `fork_task`, `read_task`, `send_message_to_task`, `archive_task`,
`cancel_operation`, MCP tools and plugin tools. Public user commands are a separate
authority boundary; a user pressing Fork is not a model tool call.

Before source classification or argument validation, Bend commits a `CheckTool`
effect and a task-local pending ticket. The host sends `beforeTool` with:

```json
{
  "task_id": 0,
  "ticket": 7,
  "plugin": {"name": "audit", "revision": "example-1"},
  "tool": {"name": "bash", "description": "...", "schema": {}, "source": "harness"},
  "call": {"id": "call-1", "name": "bash", "arguments": {"command": "printf hello"}}
}
```

The `tool` above abbreviates a real complete tool definition. Allowed results are
exactly `{"decision":"allow"}`, `{"decision":"rewrite","arguments":{...}}`, or
`{"decision":"deny","reason":"..."}`. A rewrite replaces the entire argument
object; it cannot rename the tool, retarget the task, change the call ID or grant a
different ticket. Each later plugin sees the preceding rewrite. Final arguments
are validated against the frozen tool contract and live route after the whole
chain succeeds. Exceptions, malformed replies, unavailable revisions and timeouts
become native `HookFailure` records and do not dispatch the tool.

The original function call remains immutable. The effective call is reconstructed
from ordered `HookRecord` certificates, each bound to the owning task. Pending
checked attempts and external operation rights must match that reconstruction.
Inheriting a parent's history therefore does not inherit its permission to act.
Denial is absorbing; subsequent records cannot revive a refused chain.

A plugin only replies to the current committed ticket. Duplicate, stale,
interrupted and post-archive replies have no authority. Freeze can retain a
completed grant without advancing the remaining chain. Recovery retains committed
grants but fails a pending callback whose outcome is unknown; it does not call it
again or run the unapproved tool. Cancellation is advisory for the plugin process:
the callback may already have performed its own effects, which Selvedge cannot
roll back. Lifecycle controls still govern the core task independently.

## Result hooks

`afterTool` is a result-processing request, not an observation. It runs for
completed Bash, MCP, extension and model-invoked internal tools, including the
parent return of `fork_task`. Public user commands and inherited fork returns do
not manufacture another invocation. Calls refused before execution do not have
an execution result to process.

After the raw completion is committed, enabled plugins from the task's frozen
contract run in order. Each receives the preceding result value:

```json
{
  "task_id": 0,
  "operation_id": 17,
  "ticket": 19,
  "plugin": {"name": "audit", "revision": "example-2"},
  "call": {"id": "call-1", "name": "bash", "arguments": {"command": "printf hello"}},
  "value": {"stdout": "hello", "exit_code": 0},
  "error": false
}
```

`operation_id` is stable throughout execution and result processing. `ticket` is
the fresh, committed callback identity; it is not the old execution ticket.
The reply is exactly one of:

```json
{"decision": "allow"}
{"decision": "rewrite", "value": {"redacted": true}}
{"decision": "deny", "reason": "Do not deliver this result"}
```

A rewrite may supply any JSON value, including explicit `null`. It cannot change
the original call, the task, or the execution error flag. Extra `error`, `name`,
`arguments` or identity fields are rejected. Invalid replies, unavailable frozen
revisions, transport errors and timeouts become failed result records. Denial or
failure delivers an explicit error instead of the value; it does **not** undo the
tool's already completed external effects.

`ToolReceipt` retains the original call, result and error flag. `AfterRecord`
retains each decision. Both are visible in durable history and the UI but excluded
from the default model-context projection; only the processed result is delivered
there. This is not confidential erasure: authorized history reads, including
`read_task`, can expose audit records. A confidentiality policy must also govern
those reads and any external artifacts.

An operation owns its result callback independently of model/control work, so a
completion cannot replace an unrelated in-flight model request. Cancelling the
operation addresses the live callback ticket, and late replies have no authority.
Freeze suspends new task execution, not settlement of an already-owned result.
An invocation that archives its own task may finish its own result callback, but
cannot start new work. Older cancellation effects precede the new callback in
that commit.

After restart, interrupted result processing reports `after_hook_interrupted`:
execution is known from the retained receipt, while the callback outcome is
unknown. Neither the tool nor the callback is repeated. This differs from recovery
of an external operation whose execution outcome itself was never committed.

## Post-commit observations

Subscribe to native event kinds `task_created`, `task_changed`, `model_started`,
`model_completed`, `tool_requested`, `tool_dispatched`, `tool_completed`,
`hook_completed`, `recovered` and `configured`. These names derive from one native
`EventKind` type and its checked wire round-trip. The host sends an `event` request:

```json
{
  "sequence": 12,
  "ordinal": 0,
  "type": "tool_completed",
  "task_id": 0,
  "cursor": 9,
  "payload": {"call_id":"call-1","value":"hello","error":false},
  "payload_omitted": false
}
```

Payloads above are abbreviated. Ordinary completion payloads also identify the
original requested call and the authorized effective call when available. A child
fork return has `origin: "fork_return"`; it is not a second dispatch of its
parent's command. Birth markers prevent inherited history from being emitted as
new occurrences. Running-operation announcements are not final completions; a
real final value that happens to contain `status: "running"` still is one.

`tool_dispatched` reports actual surviving external dispatch. Internal tools have
request/authorization/completion events but no fictional process-start event.
`task_changed` reports the committed summary delta, not every intermediate
scheduler state. Model lifecycle events identify tickets and outcomes without
copying encrypted reasoning or project credentials. Summary requests are identified
by `kind: "summary"` in their lifecycle payloads.

The cursor is the exclusive history offset immediately after an occurrence. To
read that record, issue public `read` with `after = cursor - 1` and `limit = 1`.
Payloads above the 16 KiB projection budget are explicitly omitted (`null` plus
`payload_omitted: true`), retaining task/cursor identity. A JSON null result is not
confused with omission. Full-envelope pressure may omit an optional notification
batch rather than reject core work. Per-plugin queues additionally bound count
and retained bytes; overflow or observer failure produces host diagnostics.

Delivery is **best-effort, ordered per plugin, with no retry or restart replay**.
A timed-out handler may still run in its process. Sequence and ordinal identify an
event within a service journal; an external durable sink should also namespace the
service and use these IDs for deduplication. Exactly-once external side effects,
durable observer acknowledgments and reliable message delivery are not promised.
Observer replies cannot rewrite results, veto committed state or generate native
tool permissions. Plugins should handle requests concurrently so a slow observer
does not block their own transport handlers for `beforeTool` or `afterTool`.

## Trust and verification

Plugins execute with the user's OS permissions and inherited environment. Do not
install untrusted executables expecting a sandbox. The native proof boundary
establishes gate placement, call identity, ordered task-bound authorization,
absorption of denial, result-chain routing, immutable execution error flags,
receipt preservation, complete transition refinement and observer non-interference
with core state/replies/effects. It does not prove a callback's policy correct or
certify arbitrary external processes. Tests run real fixture processes and
loopback providers, check SQLite commit-before-callback, exercise denial/rewrite,
internal fork, MCP, extension tools, interruption/recovery, oversized payloads,
bounded observers and deliberately type-correct proof-breaking mutations.
