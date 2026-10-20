# 0056: Document lifetimes and parser observations

Status: Accepted

## Context

A live Markdown prefix, a completed history item and a retained interruption have different publication rights. A fork may display another Task's output, and a delayed physical parser callback can arrive after replacement or eviction. A reusable display key alone cannot identify the lifetime that authorized that callback.

The former Documents contract largely mirrored its implementation in a second interpreter. Equality to that interpreter did not independently establish current source authority, monotone parser progress or preservation of local component state.

## Decision

Separate stable source identity from an allocated lifetime epoch. Completion does not change source identity, so finishing a live output can retain local state. Replacement, deletion and namespace reset must still prevent an old callback from becoming current again; preserving the allocator across resets provides that distinction without a second source registry.

Treat physical Markdown parsing as an observation of an authoritative source prefix. Admit and register that observation before publishing its source change. A callback's provenance fields cannot create source authority, and an incomplete parse cannot publish final components merely because the producer has finished. This places external parser trust at an explicit boundary instead of assuming that matching strings establish ownership.

Keep the viewing Task distinct from the producer. A fork can show inherited content without acquiring permission to execute it as its own completed output. Shared Work interfaces use their committed revision for the same reason. Effect admission also depends on the current mounted occurrence and display policy; source association alone is insufficient.

Keep interrupted-source retention bounded and separate from durable completed history. Older retained sources become literal archives rather than remounted interfaces, preserving readable evidence while withdrawing stale component authority. Restored public state passes runtime admission; typed internal values do not establish the authenticity of external snapshots.

State the required source, lifetime and publication properties directly about the production entries. A duplicate document interpreter would add another representation to maintain without strengthening those independent requirements.

## Consequences and trust

This restores meaningful source-ownership and lifecycle requirements while replacing implementation-to-itself equalities. The executable definitions remain the authority for concrete limits and transitions.

Rocq checks the stated implications about pure entries. Extraction, OCaml and JavaScript execution, the physical Markdown parser and actual IO remain distinct trust boundaries. Callback checks establish association and monotonicity; the caller must still supply the authenticated World and preserve the accepted publication ordering.

References: [Rocq 9.2 String library](https://rocq-prover.org/doc/v9.2/stdlib/Stdlib.Strings.String.html), [Rocq extraction reference](https://rocq-prover.org/doc/v9.2/refman/addendum/extraction.html).
