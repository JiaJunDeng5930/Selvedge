# ChatGPT Web backend

`chatgpt-web` connects the ordinary Selvedge model interface to **ChatGPT Web API
v1**. It is separate from the `chatgpt` OAuth/Codex provider and the `responses`
API-key provider. Task creation, tools, approval reviews, board drafting,
summarization, cancellation and branching still use their existing interfaces.

## Configuration

Add a profile to the `profiles` object in the service's `config.json`:

```json
{
  "web-high": {
    "provider": "chatgpt-web",
    "model": "chatgpt-web/high",
    "endpoint": "http://127.0.0.1:8787/v1/responses",
    "api_key_env": "CHATGPT_WEB_TOKEN",
    "timeout_ms": 1800000
  }
}
```

Set `CHATGPT_WEB_TOKEN` to the API application's token before starting Selvedge.
The endpoint and variable name above are the defaults; the default timeout is
300,000 milliseconds. This backend does not read another application's browser
profile, credentials or database. It requires no Selvedge OAuth login. Set
`chatgpt: false` at the top level to disable unrelated default OAuth discovery.

Start the API service independently and enable its **full** mode to use Selvedge
tools. A tools-disabled service rejects a normal agent request rather than
silently switching to a browser-only task. Then select `web-high` in the ordinary
model picker, or run:

```bash
node host/cli.mjs create --profile web-high --message "Inspect the project."
```

Supported model IDs are `chatgpt-web/light`, `chatgpt-web/medium`,
`chatgpt-web/high`, `chatgpt-web/xhigh`, and `chatgpt-web/pro`. These names select
webpage effort controls. For this backend the **profile's model ID** selects
effort; the general native-provider reasoning field is not sent. Create a
separate profile for each desired effort. Adaptive per-turn reasoning is rejected
because the API freezes settings at the root. An unavailable webpage effort is
an error, never an implicit substitute.

## What callers see

The existing `requestModel(effect, config, home, limits, options)` returns the same
ordered text, function-call and opaque-context items as the other providers.
Callers do not supply response IDs, slice history, serialize protocol tool
results, or manage idempotency keys. `onDelta(text, outputIndex)` remains
append-only; the optional `onSnapshot(text, outputIndex)` replaces a provisional
preview. The service and web renderer support both. The committed terminal
resource, not its provisional previews, supplies durable output.

Ordinary messages continue the explicitly retained response with only new input.
Function-call arguments remain JSON objects. A complete result batch is sent
together, with results encoded as strings containing `{value, is_error}`. This
preserves arbitrary JSON values with a `content` member without accidentally
interpreting them as MCP rich results. Tools execute only through native
authorization, approval, hooks and sandboxing.

The root declares the task's frozen function catalog. The protocol cannot change
that catalog or send a per-turn `tool_choice`; native admission still rejects
calls outside the current allowed set. API-side exposure is not execution
authority. Selvedge currently models textual messages and JSON-object function
tools. The protocol's image inputs, custom string tools and output-format
selection are not new Selvedge input types in this change. Undeclared custom
calls and opaque foreign-provider context are rejected rather than coerced or
silently dropped.

Messages arriving alongside tool results cannot be mixed into the protocol's
result batch. The adapter retains them in the continuation receipt. If the batch
finishes the turn, it sends those messages as one explicit successor; if another
tool round is required, it carries them forward. Both steps keep distinct
durable request keys. Async results that arrive while HTTP is pending are also
retained: each receipt records its exact committed input span, so a result
appended before that receipt cannot be skipped on the next call.

Local receipts are never forwarded as input items to a different provider;
ordinary text and function history remain available to that provider.
Forks start fresh pages with explicit inherited context. A text checkpoint starts
a fresh root with replacement context. A requested summary is a separate,
tool-free text request; there is no remote compaction endpoint. Approval reviews
and board drafts are also independent tool-free roots, with the existing strict
JSON decision parsers. Oversized requests fail explicitly; the server does not
split them or secretly synthesize summaries.

## Retained requests and cancellation

`HOME/providers/chatgpt-web/requests.sqlite` stores the original request body,
UUID key, connection binding and observed response resource. It is private
external-effect metadata, not a second task journal. The bearer token is never
stored there. Keep it with the service home when backing up or restoring tasks;
do not copy it into a new home with unrelated task identities.

Only declared header/connection retries occur automatically, using the same
original body and key. A stream that was already exposed is not silently
restarted. A cached committed result can be observed again with that same
effect identity. A changed body or connection cannot reuse its identity.

Timeout, disconnect and service shutdown only detach observation. On restart,
native journal replay does not resend prompts or execute tools. An unknown
request blocks a replacement request and reports its retained key and, when
known, response ID. This prevents an ordinary retry from creating duplicate
webpage work.

An explicit task interruption or steering command records cancellation of the
original request and calls its `/cancel` endpoint. A later native model effect
can then start a new root with the task's explicit context. The new effect does
not reuse a consumed predecessor. Remote Stop can fail or remain unconfirmed;
the diagnostic preserves the original identity, and native cancellation still
retires local execution authority. Shutdown never issues this explicit Stop.

To abandon an uncertain turn and continue normally:

```bash
node host/cli.mjs interrupt --task-id 0
node host/cli.mjs send --task-id 0 --message "Continue using the recorded results; do not repeat uncertain effects."
```

Alternatively, inspect the original webpage and response first. The exported
`chatgptWebRequestAction(key, action, config, home, limits, options)` supports
`inspect`, `resume`, and `cancel` against that exact response. Only an explicitly
supplied `confirm: true` accompanies resume confirmation. These actions never
allocate a page, submit a new prompt or execute a caller tool. Resuming remote
observation does not resurrect a native ticket already failed or cancelled;
settlement still requires the original live effect, otherwise use an explicit
interruption/new task or supplied checkpoint. When admission's response ID was
not observed, keep the original key/body for same-key observation rather than
guessing an ID or a new key.

## Evidence

The audited input is `codex-chatgpt-web/docs/protocol.md` at source revision
`627e4f4720cd61c0cd7bc6e75b3bafd125deb217`, SHA-256
`bd38e5df4a9ef16662627f71bd62749f7f883cd42b694dbba571c8531db204b6`,
and its `runtime/response-resource.schema.json`. ADR 0024 describes the boundary.

`tests-bend/chatgpt-web.test.mjs` uses a strict independent loopback protocol
fixture, actual SQLite, native effects, process sandboxes, restart, cancellation
and concurrent tool completion. `web-streaming.test.mjs` checks snapshot
replacement and preview ownership. After building, run
`node scripts/chatgpt-web-browser-check.mjs` for the real Chrome/SSE snapshot,
draft-preservation and terminal-output check; captures go to
`.workpad/chatgpt-web-backend/`. These checks do not access a commercial
account or claim that browser behavior, the remote service, HTTP, SQLite or the
OS is proved by Bend.
