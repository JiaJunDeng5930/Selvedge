# Web presentation adapter

`UI.bend` still owns the entire task presentation: which content and controls
exist, their labels, events, field bindings and enabled flags. The browser never
reads a task snapshot or reconstructs lifecycle, provider-message or command
tables. Changes to task behavior and available actions belong in that native
definition, not in a browser-side state machine.

`widgets.mjs` renders the supplied roles as task navigation, a focused conversation,
a docked send/steer composer and an optional details panel. Task controls, live
operations, ancestry, branching, context controls and the frozen tool contract
are existing native widgets, not independently implemented features. The initial
native form supplies the model choices discovered by account login. There is no
fabricated Git panel, terminal, file browser or model-switch action.

The presentation follows the installed Codex Desktop's neutral sidebar,
conversation column, compact composer, action menu and right-hand details panel.
The reference version and inspected assets are recorded in ADR 0020. The adapter
does not ship the application's code, branding or fonts. New-task model/reasoning
fields sit in the composer toolbar; the existing JSON settings field is available
from its settings disclosure. Its value and binding still come from Bend.

Pending permission requests are native operation widgets in the conversation,
with the exact command, justification, working directory and scope. Only human
review requests have Approve once and Deny actions; model-reviewed requests show
their independent reviewer and retain cancellation. Commands and justification
are rendered literally, never as HTML or assistant Markdown. The New task and
Fork forms use the existing JSON widget for optional context overrides.

An HTTP 200 from `/api/ui` can still carry a refused command in `result.receipt`:
the outer success also delivers the updated native screen and its error notice.
The adapter must not confuse that wrapper with an approval. The scroll-to-latest
control lives in the header so it cannot cover permission buttons on a narrow
screen. Browser checks verify hit-testing and actual pointer clicks, not only
programmatic event dispatch.

`renderer.mjs` fills only declared field bindings. `app.mjs` serializes native
presentation events, stores unsubmitted drafts and reconnects the authenticated
event stream. Keyed DOM reconciliation retains field elements, caret/selection,
disclosures and unchanged messages. A successful request clears only the draft
values actually submitted, not text typed while the request was pending.
Enter submits the active composer; Shift+Enter inserts a new line. Ctrl/Cmd+Enter
also submits forms. None of these shortcuts submits during IME composition. The
send/steer menu retains each native form and its draft, rather than rewriting a
command based on a browser-side task status. Scrolling follows
new output only while the reader remains near the bottom. Explicit history
navigation suppresses previews until the reader selects Follow latest.

On narrow screens the task sidebar has an outside-click scrim, keyboard focus
containment and an inert conversation behind it. The access-token form is a native
modal dialog. These controls change browser focus and disclosure state only.

## Incremental Markdown

`markdown.mjs` keeps the incoming target string separate from its visible cursor
and the incremental parser's open-node stack. Input arrivals only append and
schedule work. Visible text advances at most once per 32 ms, with a backlog-based
step and a 4,096-character maximum batch. All instances share an approximately
6 ms frame budget; a single parser call still has to finish before yielding.
Completed output is also processed in bounded batches rather than one large
synchronous parse. Surrogate pairs are not split across visible updates.

The pinned `streaming-markdown` parser consumes new characters incrementally. The
DOM sink appends into the pending structure and its last text node instead of
rebuilding paragraphs. Closed nodes keep their identities. Unclosed emphasis,
links, lists and code retain optimistic, continuous structures. This is the
parser's streaming Markdown dialect, not a claim of complete CommonMark support;
setext headings and reference-style link definitions are not resolved.

Highlighting and formula parsing run in `markdown-worker.mjs` only after a token
closes. Libraries load lazily from this server. Code uses a declared supported
language, not expensive language guessing; math produces native MathML with
untrusted commands disabled. Formatter inputs, pending work and output sizes are
bounded, and a stuck worker is reset. Oversized, unknown-language or failed jobs
retain plain text. Formatting does not replace a selected code/math node's text.

Model text never enters `innerHTML`. HTML-like input is text. Links accept only
HTTP(S), mail and local fragments; images are explicit links, not automatic
network requests. Formatter-generated markup passes a second element/attribute
allowlist before entering the document. The static server serves only declared
assets under a self-only content policy.

## Transient previews and authority

`streams.mjs` consumes host-authored `stream_start`, text `delta`, `stream_cancel`
and `stream_end` notices, correlated by task, ticket and output index. A preview
is not a native message, command, tool result or checkpoint. It is labelled as a
preview, has bounded storage, and cannot change any enabled flag. Cancellation
removes it immediately. A connection loss discards it; without a new observed
start, later deltas are ignored rather than shown with a missing prefix. The
eventual committed native snapshot remains available.

The host emits end only after settlement and includes that exact durable
revision. An unrelated earlier commit cannot retire a preview. A native message
may adopt its already-rendered Markdown only after settlement and an exact text
match in the native presentation; otherwise the native text is rendered normally.
No live delta can subsequently append into an adopted, committed message.
Compaction streams are never shown as assistant output.

## Evidence

`board.mjs` and `board.css` render the native board composition. `picker.mjs`
enhances native choices with searchable keyboard menus; `collection-fields.mjs`
retains tags, upload/preview state and workspace input. Drag insertion fills
native target bindings with the revision captured at pointer-down. Continuous
creation retains only native-declared parameters. There is no browser scheduler
or optimistic card store. `npm run test:board-browser` exercises this surface and
writes screenshots/results to `.workpad/board-webui/`.

`tests-bend/web-streaming.test.mjs` probes the scheduler, Unicode boundary, link
policy, SSE framing, draft acknowledgement and preview correlation.
`npm run test:browser` uses an isolated Chrome profile, a real loopback ChatGPT
fixture, the native kernel and SQLite. Set `CHROME_BIN` when Chrome is not in a
standard location. It fails explicitly when a browser is unavailable. Screenshots
and measured batch/DOM results go to `.workpad/chatgpt-webui/`.
Browser and transport tests are not Bend proofs or evidence about live account
entitlements. Package provenance and licenses are in `vendor/`.
