# 0033: Controlled icon-button construction

## Context

An icon-only action combines a button, its glyph and their alignment. Accepting
arbitrary source nodes or positioning fields would let callers break that
relationship, requiring each caller to establish it again. This experiment asks
whether one useful control family can carry that relationship through ordinary
construction and changes.

## Decision and reasons

Use `AuthoredControls.IconButton` as a dedicated Data syntax, interpreted by
`icon_button_source` in `browser/controls/CONTROLS.bend`. Its inputs retain action
metadata, appearance and size, but expose no arbitrary layout, alignment or
offset. One interpreter owns the source construction. Production icon-only
actions delegate to it; their adoption is an executable obligation.

Universal laws bound to the actual interpreter cover every permitted value.
Replacing its icon and resizing return values of the same family, so the same
law covers their interpretation without separate instance proofs. The contracts
and production providers own the precise requirements; this document records
the reason for choosing that boundary.

A recurring combination warrants a family only when its parts serve a common
purpose and its useful operations preserve that purpose. Mere visual proximity
or a common classification is insufficient. Icon replacement and resizing give
this experiment concrete preserving operations without introducing a general
hierarchy of control categories.

## Consequences

The experiment is limited to IconButton. It neither migrates all controls nor
makes every general `Source` button private.

Geometric centering uses natural-number coordinates: the offset is
`floor(remaining space / 2)`. Drawing positions include the content insets and
require the existing fit condition. Bounds that cannot accommodate the drawing
retain the existing diagnostic. Optical centering of a glyph's ink and actual
browser DOM bounds receive no new proof. Compiler rejection and proof mutation
checks belong to `tests-bend/icon-button-construction.test.mjs`; they do not
establish those external rendering properties.
