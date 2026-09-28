# 0024: Explicit ChatGPT Web transport receipts

## Context

ChatGPT Web API v1 resembles Responses JSON but implements a different boundary:
one retained page, immutable root settings, single-use response predecessors,
complete tool-result batches and provisional text snapshots. Treating it as a
different URL for the Responses provider would resend history, misparse object
arguments and append revised text as if it were a delta. Browser subscriber
disconnection also does not mean task cancellation.

The supported change is a new interpreter for the existing model-effect
contract. It does not change task ownership, queues, tool execution, permissions,
recovery projection, native scheduling, or application state representation.

## Decision

`model-request.mjs` owns the shared frozen project/settings preparation and
bounded pre-stream retry implementation. `providers.mjs` dispatches the new
`chatgpt-web` profile without adding a provider wire type to any caller. The
ordinary output remains `Say`, `Invoke`, or opaque `Context` at the native
boundary. Approval parsing now accepts the already existing normalized text
item, as board drafting did, instead of depending on a Responses message wrapper.

`chatgpt-web.mjs` interprets the v1 request and response vocabulary. A locally
authored `provider_receipt` is an opaque `Context` value, not a model-authored
instruction or invocation. It binds a response to its service-home identity,
task, connection, root contract and precise input/output spans. The task's
immutable input sequence supplies an explicit coverage boundary. Newly committed
async results can precede a late model reply in native history, so using only
the suffix after a response ID is insufficient. Coverage hashing checks that
the referenced input was retained; it never searches text to choose a page.

The existing history action and context projection carry this data unchanged.
Their generic `ModelContext` case needs no provider-specific constructors or new
list theory. A branch's distinct native task ID selects a new root rather than
sharing a predecessor. A native text checkpoint removes the old receipt through
the existing context cut. No task lifecycle is reconstructed in the adapter.

The external receipt database commits each UUID and original body before HTTP.
One native model ticket has at most two protocol requests: its tool-result batch
and, only if that batch completes, a successor delivering already committed
deferred messages. Other cases issue one request. This is protocol framing, not
an extra tool executor, polling loop, retry scheduler or agent turn. Both
requests retain independent idempotency identities and their complete output.

Native cancellation is distinguished from observer lifetime. A committed cancel
records which external request it retires before asynchronous work can select a
later response, then attempts Stop against that original ID. It does not prove
physical cancellation. A newly authorized native effect after interruption or
steering may start a replacement root; transport uncertainty alone cannot grant
that permission. Service shutdown only detaches existing observations.

The generic observer gains `onSnapshot` alongside append-only `onDelta`. Named
SSE events retain their names through `network.mjs`; existing data-only consumers
keep the old interface. Revision or shrinkage discards only the disposable
preview's incremental Markdown parser. Final output remains native state.

## Evidence and limits

The production Bend definitions, specifications and proofs require no edits for
this backend. The existing complete-decision, opaque-context, call-admission,
history, checkpoint, interruption and stale-ticket guarantees are reused. They
do **not** prove the JavaScript interpreter's history projection, SQLite receipt
durability, digest collision resistance, network framing, remote idempotency,
page retention or browser observations. Those are explicit external boundaries.

The independent v1 fixture validates wire fields and predecessor/batch rules.
Tests cross real native/SQLite/process boundaries and exercise concurrent
completion between request and receipt, replay without dispatch, exact-key
retry, explicit cancellation versus shutdown, invalid responses, independent
review/drafting and UI snapshot replacement. No parallel native transition
truth table or new general theorem library was added. The standard whole-program
proof and mutation gates remain the evidence for the unchanged native semantics.

The profile's model ID selects webpage effort. Per-turn adaptive reasoning,
native encrypted compaction, image input and custom-string tool contracts are
not mapped into features the present unified model vocabulary does not provide.
The fixed root tool catalog cannot track the dynamic native callable subset;
native admission remains authoritative. Missing pages, changed connections,
oversized requests and unresolved external outcomes fail explicitly instead of
quietly starting a different conversation.
