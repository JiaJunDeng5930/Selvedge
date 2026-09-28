# 0022: Native task board and reference-compatible interactions

The design reference is Better Codex, commit
`f973870ef3fddd29f1c616eef8c3ad194d301018`, Apache-2.0:
<https://github.com/Ericwong5021/better-codex>. Its board screenshot and
`src/ui/injected-entry.ts` supply the column/card layout, toolbar, compact
creation dialog, property menus, continuous creation, drag insertion, context
actions and attachment interaction. Its task scheduler and mutable browser issue
store are not incorporated into Selvedge.

## Representation and execution

A card captures intended work; an ordinary task owns its execution and
conversation. `BOARD.bend` records drafts, stages, priorities, assignments,
projects, attachments, archive/pin state and revision-correlated drafting
requests. `MODEL.World` contains the board as an independent product component.
Existing tasks and frozen contracts remain the execution objects.

The finite association list also records manual order. Ordinary updates replace
their existing slot. `Move` removes its source and inserts before an observed
target, or appends it. The source revision must match; the target must still be
in the destination stage and the same pin group. Stable list filtering places
pinned cards first; automatic dispatch further groups by priority while retaining
manual order within each group. There is no second rank table or browser-owned
order to synchronize.

`board-resolution.bend` decides admission and resolves a command to a registry
change or ordinary task launch. `board.bend` interprets that change;
`board-spec.bend` independently specifies the complete decision, including reply
and effects. Relocation's specification describes the retained prefix and suffix
without calling the implementation's relocation helper. Existing atomic command,
protocol, scheduling and journal composition bind these operations to production.

`board-scheduling.bend` uses the ordinary task-creation boundary; its independent
specification is `board-scheduling-spec.bend`. Automatic dispatch respects
assignment and per-agent concurrency and links a conversation once. Card stages
can follow the linked task, while metadata edits never rewrite frozen execution
inputs. Archive interrupts active execution; restore does not replay external
effects. A browser refresh is not a second scheduler.

Assistance is a separate committed, tool-free `RequestBoardText` effect using an
ordinary configured endpoint, independently of the execution assignee and
adaptive reasoning. A ticket, revision and retitle flag govern settlement.
Title-only results retain the original description. Restart records an interrupted
drafting request as failed instead of automatically issuing another paid request.

## UI and external boundaries

`board-navigation.bend` and `board-view.bend` produce the cursor, read-only
filters, visible cards, enabled actions, fields and drop bindings. The command
codecs supply the same vocabulary to API callers and form bindings. Navigation
does not become a durable task command.

The browser owns keyed DOM, focus, unsent input, popovers and pointer geometry.
It fills only native-provided bindings. Drag retains the source revision from
pointer-down and takes its insertion binding from the native target descriptor.
The ghost and insertion marker are temporary visuals, not optimistic state.
Native forms declare which parameters survive continuous creation. Submitted
content clears only when it still equals the submitted snapshot; input typed
while a request is in flight is retained.

The file boundary authenticates uploads/reads, hashes actual content, uses
bounded regular files in a non-symlink vault, and rechecks stored metadata.
Clipboard/drop and picker uploads share this path. Only sniffed PNG/JPEG/GIF/WebP
content is offered inline; other bytes are downloads. Submission waits for
pending uploads. Native attachment validation remains required: a browser path
is not filesystem authority.

## Evidence and limits

`board-architecture.bend` and `proofs/board.bend` assemble complete-change,
task-birth, drafting-settlement, callback-correlation and navigation evidence.
The public harness carries this evidence with the existing command, execution,
invariant, recovery and trace laws. `board-proof.test.mjs` mutates type-correct
production expressions and requires the assembled proof to reject ignored
insertion positions, lost suffixes, missing effects, stale tickets, replaced
descriptions and incorrect dialog transitions.

`board-service.test.mjs` exercises the compiled kernel with real SQLite, HTTP
streams, authenticated attachments, cancellation and restart. Manual order is
checked across replay and metadata edits. File/text component tests cover bytes
and provider decoding. `scripts/board-browser-check.mjs` drives isolated Chrome
via CDP: actual pointer insertion, edits across SSE refresh, searchable choices,
continuous creation, pasted files, previews and narrow/dark layouts. Results and
screenshots are under `.workpad/board-webui/`.

Proofs do not establish DOM/file/HTTP correctness, compiler correctness, model
quality or account availability. Boundary tests use local fixtures, not a paid
account. Selvedge remains a single-user local service; the reference's multi-user
identity and deployment system are not imported as a second authorization layer.
