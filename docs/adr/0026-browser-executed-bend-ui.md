# ADR 0026: Execute the proved UI functions in the browser

## Status

Accepted.

## Context

A server-rendered presentation makes local navigation, editing and display changes
wait for a network round trip. Moving those decisions into an independent
JavaScript UI would introduce a second implementation of behavior already expressed
and proved in Bend. The application needs immediate local interaction while task
commands retain one authoritative committed state.

## Decision

Compile the production Bend UI functions with the official JavaScript library
backend and execute them in the browser. Interaction state, layout and document
construction therefore use the same functions bound to the production proofs.
JavaScript interprets their DOM, network and physical effects.

Keep local interaction separate from authoritative task commits. The server
accepts authenticated public commands and publishes snapshots after journal
commit. The browser correlates command completion with the submitted draft
revision so an older response cannot consume a newer draft.

## Consequences

Local interaction does not require a server presentation request, and changes to
UI policy have one Bend implementation. Compilation and browser execution remain
explicit external boundaries: proofs of the source functions do not establish
compiler correctness, DOM geometry, event delivery or network reliability.
