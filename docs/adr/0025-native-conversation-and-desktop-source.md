# 0025: Native conversation semantics and transplanted desktop components

## Why change both sides

ADR 0020 constrained the work to the browser. That left the native surface as a
collection of generic widgets and encouraged the adapter to infer their layout.
Copying the desktop's colors while replacing its interactions with short local
implementations did not retain the design. This decision supersedes that
restriction: the native conversation vocabulary and its browser implementation
change together.

The reference is the installed `openai-codex-electron` **26.917.71314**, extracted
from `ChatGPT.app/Contents/Resources/app.asar`. The Web GPT launcher is not this
reference. `host/public/vendor/desktop-source.json` records the exact input
members, hashes, decoded-source ranges and generated output hashes.

## Meaning belongs in the native surface

The reference's `split-items-into-render-groups` separates user input, ongoing
agent activity, the answer, and permission requests rather than presenting every
internal event as another chat message. The native `Thread` now names its
timeline, composer, details and action regions. `ThreadLink` separates request
title, identity and current status; status changes no longer rewrite the title.

`UI.messages` projects committed speech and execution activities. The original
hook decisions, execution receipts and approval records remain in a separate
audit view of the same history page. A completed tool's processed output does
not disappear when its raw receipt is moved out of the transcript. Result error
flags remain distinct from display state and are included in the observation.

`Composer` owns a native draft identity independently of the selected submission
form. Send and Steer retain their different native commands and resolver gates,
but selecting an intent does not replace the editor or lose its text. This is
not a frontend table deciding which task states permit an operation.

`conversation-spec.bend` observes exact ordered speech, audit JSON and result
value/error pairs independently of `UI.bend`. `architecture.UserSurface`, built
by `proofs/ui.bend` in the production harness, requires the four conversation
laws as well as the existing read-only projection and command correspondence.
The transcript proof uses the imported `Std.list_ind`; it does not introduce a
parallel list algebra. Shared provider-kind/text decoding is an explicit
interpretation boundary, not a claim to prove a provider protocol.

No Git panel, terminal, editing model switch, dictation or other unsupported
desktop capability is introduced as an empty native object.

## Reuse the implementation, not a sketch of it

The actual styled desktop `DropdownMenu`, `SearchInput`, `RadioGroup` and
`RadioItem`, with their React/ReactDOM implementation, are extracted from
`app-shared-7b9edc1bfb7f.js`. The bundler removes unrelated application code and
the final module has no external imports. Current DOM realization is in
[../../host/public/renderer.mjs](../../host/public/renderer.mjs); the pinned source
and reproduction record remain in `host/public/vendor/desktop-source.json`.

The scroll implementation uses **22 unchanged callback bodies and nine unchanged
helpers** from `thread-scroll-layout-27da424d79e0.js` and `app-initial`. The local
shell supplies DOM elements, stable refs and effect lifetime. It retains the
source's directional gestures, timing, rounding compensation, content-growth
and footer-resize handling, reduced-motion behavior and explicit scroll action.
The DOM retains the reverse-origin scroller, transcript, measured sticky footer
spacer, source gradient and overlaid composer. Replacing those boxes with an
independent footer grid row changes the algorithm's geometry.

The desktop stylesheet is scoped to transplanted components. Its actual theme
token rules supply the native shell's palette; the adapter does not keep a
second set of hand-picked light/dark values. Font faces are excluded. The
existing Markdown parser, incremental DOM sink, scheduler, worker and dependency
files are unchanged; desktop Markdown element rules do not style that renderer.

`scripts/import-desktop.mjs` reproduces all four desktop artifacts byte-for-byte
from the pinned archive and esbuild 0.25.10. Routine checks verify committed
artifact hashes without requiring a local application installation. Updating
the source requires reviewing the actual inputs and rerunning reproduction,
not editing the generated callbacks and adding another conditional.

## Evidence boundaries

The former fake `Element` test had no browser layout, real focus, IME or default
event behavior. It was deleted, not extended into a second browser. The old
scroll test also treated zero as the top even though the new origin is the
bottom; real wheel events and visible-row positions replace that assertion.

Conversation mutation tests require a successful operational type check before
the production proof rejects missing speech, corrupt audit data, changed error
flags, incorrect Steer binding or shared draft ownership. Provenance tests
challenge changed shipped code and an invalid artifact inventory.

The browser checks exercise actual Chrome, HTTP/SSE, native compilation and
SQLite: stable Markdown/editor identity, intent changes, mobile-size controls,
real approval clicks, menu focus, and row position during output/footer growth.
Board dialogs and revised Web API snapshots use the same transplanted controls.
These are external boundary checks, not Bend proofs of browser correctness or
evidence about live account availability.
