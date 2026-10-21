# 0058: Native browser layout with one semantic scene

Date: 2026-10-20
Status: Accepted

## Context

The old presentation engine maintained several node representations, physical
measurement jobs and a pure pixel-allocation model before rendering. Retaining
that machinery would duplicate the browser's font shaping, intrinsic sizing
and layout algorithms while preserving constraints of the former compiler.

The product needs consistent labels, actions, ownership, accessible controls
and usable reading space. Proofs about a parallel geometry engine cannot
establish that the actual browser lays out or focuses those controls correctly.

## Decision

Keep one typed semantic scene and interpret it into a closed native DOM/SVG
vocabulary. Gallina retains product labels, actions, availability and layout
intent; CSS handles physical geometry. A semantic heading remains distinct from
a header container and uses a native heading element, preserving heading
navigation without conflating those roles.

Use shared ordinary declarations for the small styling and control vocabularies.
Another generator for a small finite role enumeration would add more machinery
than maintenance it removes. Reuse the existing CSS and Markdown interpreters
instead of creating another styling or measurement protocol.

Let intrinsic sizing and fractional CSS dimensions replace saturated integral
pixel allocation. A bounded reading scrollport and reachable composer preserve
conversation access across wide and narrow windows. Narrow navigation retains
access to the same commands through native scrolling rather than the old
compact-menu geometry. Retire the unused measurement jobs, probe trees and
allocation algebra together with proofs specific to that removed engine.

Charts retain source values and row order in an accessible table. Require
coherent numeric or categorical axes instead of silently combining incompatible
coordinate interpretations.

## Consequences and trust

The executable definitions own concrete limits and transitions. Their checked
attribute and disabled-control properties constrain the actual keyed control,
rather than only an outer wrapper's empty event list.

CSS containment, font shaping, DOM focus, Markdown parsing, browser storage and
physical event delivery remain external responsibilities. Actual Chromium
scenarios exercise selected reading, control, focus and integration behavior;
they do not turn the browser into a kernel-verified implementation. Standard
extraction and JavaScript compilation retain their separate trust boundaries.

References: [CSS intrinsic sizing](https://www.w3.org/TR/css-sizing-3/#intrinsic-sizes),
[ARIA in HTML](https://www.w3.org/TR/html-aria/), and
[the semantic proof boundary](../proofs.md).
