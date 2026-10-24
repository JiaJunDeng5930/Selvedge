# Runtime acceptance

The runtime suite exercises physical behavior through public service, HTTP,
CLI, plugin and relay entry points. The automated suite uses local
model/MCP/network peers and isolated temporary homes without a live account.
This does not discharge the live-account voice acceptance below.

The retained responsibilities include commit-before-effect ordering, replay
without repeated external calls, SQLite ownership, credentials, filesystem
integrity, process cleanup, network framing/backpressure and browser streaming.
Gallina domain rules and structural guarantees belong to their executable
constructions and checked proofs. Tests of the removed Bend compiler, runtime
intrinsics and source-scanning gates are not part of this suite.

Run `bun run build` before `bun run test`. Browser acceptance uses a real
Chromium instance through Playwright and the application's HTTP entry. A passed
Rocq proof or successful module build does not report a physical scenario as
having passed; run the corresponding public entry before recording that result.

`browser-workflows.test.mjs` uses the pinned `playwright-core` dependency with
a system Chromium executable. Install Chromium, or set
`SELVEDGE_CHROMIUM_EXECUTABLE_PATH` to its executable, before running the suite;
missing browser setup fails explicitly. To run these workflows alone, use
`bun test tests/browser-workflows.test.mjs --timeout 30000` after the build.
They cover Project workspace inheritance versus an explicitly empty selection,
ordered image content and responsive keyboard navigation, and actual graph
node actions with owner-local persistence and atomic rejection of invalid
stored state. The graph workflow has its own 60-second budget because it opens,
edits and reloads multiple real Tasks through the complete service.

The existing Python browser drivers additionally require Python Playwright and
accept `--chromium /path/to/chromium` and `--artifacts /path/to/results`.
`test-interactive-markdown-browser.py --mode all`, `test-images-browser.py`,
and `test-history-search-browser.py` retain streaming/IME, side conversation,
image recovery and original-message navigation acceptance. They launch isolated
local peers and real services; their fixture controls do not replace product
modules or browser reducers.

`mcp-schema-contract.test.mjs` distinguishes the two external tool contracts:
an official MCP SDK stdio server accepts signed decimals and nested JSON Schema
through real task execution, and rejects invalid arguments itself. An extension
offering that same schema must still fail initialization because its documented
schema language is smaller. This local fixture requires no model account.

## Live-account voice acceptance

Before reporting dictation or live voice as accepted, also run the application
with a real ChatGPT voice account through its public HTTP and browser interface.
The local `audioFactory` session tests establish ownership and reconnect behavior;
they do not exercise ChatGPT authorization, transcription, WebRTC or playback.

Run `bun run start`, open the reported loopback address in a microphone-capable
browser, and use **Sign in for voice**. The Responses account has a separate scope
and does not substitute for voice authorization. Exercise these physical paths:

- Dictate into an existing draft, finish recording, and send the recognized text
  through the ordinary composer. Cancel a second recording and check that it is
  discarded. Edit the draft while transcription is pending and check that the
  returned text remains available for explicit insertion.
- Start live voice from a new Task and from an existing Task. Check microphone
  input, received audio, independent microphone/playback mute controls, and the
  spoken conversation in that Task's history.
- Ask voice to delegate actual task work, stop voice while that work is accepted,
  and check that the task continues. Restart the service and check the committed
  conversation and work history through the same browser interface.

Record the source revision, account-login availability and observed results in
ignored `.workpad/`. A missing voice login leaves this physical acceptance
outstanding; a passing build or injected local audio peer is not a pass.
