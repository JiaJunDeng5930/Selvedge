# ADR 0028: Populated page regions

## Decision

Carry page regions and their contents together in the production Interface tree.
Core's composition evidence binds their order to the page requirements; Web
realization evidence binds preservation to the actual `main_children` function.
Keep these obligations in the existing core and Web proof aggregates.

## Reason

The former `Structure` labels described intended organization without constraining
the emitted tree. Recursive role and key extraction reconstructed region membership
in the renderer, while fixed overview title boxes assumed a height that wrapped
controls could exceed. Explicit populated regions let rendering preserve content
instead of rediscovering its ownership. Intrinsic headers and the remaining body
space let real content determine the page split. The conversation body owns the
reading scroller, so the timeline and streaming output share that physical region.

Content presence alone does not preserve independent owners. Generated titles,
summaries and task facts must retain the identity of their owning node; empty or
shared helper keys can make document execution reuse one node for distinct
content even when the region contains every required child.

## Boundary

Remove recursive role extraction and fixed overview title boxes rather than keep
parallel organization paths. Bend proves production region order and document
preservation. Actual browser layout, scrolling and event delivery remain external
boundaries; these proofs do not establish physical browser correctness.
