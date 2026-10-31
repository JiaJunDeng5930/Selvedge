# Plugins and hooks

Plugins are trusted local executables speaking newline-delimited UTF-8 JSON-RPC 2.0 over stdio.
They do not need to be JavaScript modules or share a runtime with the extracted kernel.
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
or set it to `false`; both are closed. Finite string `enum` values and bounded
`anyOf` alternatives are supported. Keywords such as `$ref`, open properties,
negative integers and unrestricted numbers are rejected, not
silently ignored. Definition checking and value checking each limit recursive
nesting to 256 levels; this is not a limit on the total number of sibling fields.
MCP retains its own server-side schema contract; no claim is made that
this extension fragment implements arbitrary JSON Schema.

MCP `inputSchema` is retained as an object and passed unchanged to model tool
discovery. Its dialect and keywords (including `number`, `$ref` and `anyOf`) do
not pass through the extension interpreter. Model calls and hook rewrites must
still supply an argument object; the MCP server validates that object against
its advertised schema before execution, as required by the
[MCP tools specification](https://modelcontextprotocol.io/specification/2025-11-25/server/tools).
The kernel's local argument check therefore establishes the call envelope, not
arbitrary MCP-schema satisfaction or the correctness of the external server.

To execute an approved extension tool, the host sends `callTool` with its local
`name`, final `arguments` and a `context` containing `task_id`, `operation_id` and
`call_id`. The result must be exactly a JSON object containing `value` and Boolean
`error`. Its native completion and cancellation semantics are the same as Bash
and MCP. A timeout or restart does not automatically repeat an external tool whose
outcome may already have happened.

## One before-tool protocol

A model call first passes envelope and frozen tool identity admission. The kernel
then records the call and runs before-tool hooks in order. Allow preserves the
original ordered argument members; rewrite replaces the arguments while retaining
the call identity. Final per-tool argument admission runs after those hooks and
before authorization or execution. The host sends
`beforeTool` with:

```json
{
  "task_id": 0,
  "ticket": 7,
  "plugin": {"name": "audit", "revision": "example-1"},
  "tool": {"name": "bash", "description": "...", "parameters": {},
    "source": {"kind": "native", "program": {"kind": "Process"}}},
  "call": {"id": "call-1", "name": "bash", "arguments": {"command": "printf hello"}}
}
```

A model reply containing an invalid call is rejected before that call becomes a
tool invocation. The `tool` above abbreviates the real complete definition; its
`parameters` contains the advertised schema. Allowed results are
exactly `{"decision":"allow"}`, `{"decision":"rewrite","arguments":{...}}`, or
`{"decision":"deny","reason":"..."}`. A rewrite replaces the entire argument
object. The host can report exceptions, malformed replies, unavailable revisions
and timeouts.

The [kernel definitions](../theories/Kernel/) own authorization-record semantics.

Cancellation is advisory for the plugin process: the callback may already have
performed its own effects, which Selvedge cannot roll back.

## Result hooks

`afterTool` is a result-processing request, not an observation. It runs for
completed Bash, MCP, extension and model-invoked internal tools, including the
parent return of `fork_task`. Public user commands and inherited fork returns do
not manufacture another invocation. Calls refused before execution do not have
an execution result to process.

After the raw completion is committed, the host sends:

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

A rewrite may supply any JSON value, including explicit `null`.

Extra `error`, `name`, `arguments` or identity fields are rejected. Invalid replies,
unavailable frozen revisions, transport errors and timeouts can fail result
processing. Result processing does not undo the tool's already completed external
effects.

Excluding audit records from model context does not provide confidential erasure:
authorized history reads, including `read_task`, can expose audit records.
A confidentiality policy must also govern those reads and any external artifacts.

The [kernel definitions](../theories/Kernel/) own result processing and completion admission.

## Post-commit observations

Subscribe to native event kinds `task_created`, `task_changed`, `model_started`,
`model_completed`, `tool_requested`, `tool_dispatched`, `tool_completed`,
`hook_completed`, `recovered` and `configured`. Configuration admission checks
subscriptions against the native `Limits.plugin_events` vocabulary. Notification
producers use those event names as strings. The host sends an `event` request:

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
install untrusted executables expecting a sandbox. Kernel theorems constrain
particular authorization, callback and history operations under their stated
premises; [the task requirements](../requirements/Tasks.v) select those contracts. Plugin policy,
physical process behavior and observer delivery remain external obligations.
Public end-to-end tests use fixture processes and loopback providers to exercise
commit-before-callback, denial/rewrite, internal fork, MCP, extension tools,
interruption/recovery, oversized payloads and bounded observers.
