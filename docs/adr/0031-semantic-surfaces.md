# ADR 0031: Resolve surface colors from their purpose and interaction

## Decision

Bend owns surface purpose, persistent selection and pointer phase separately.
Appearance and generated document nodes use the same surface resolver; the browser
adapter serializes its result and interprets the modeled interaction variables.
Desktop theme tokens continue to supply light and dark colors.

## Reason

A selected row retains its selection when the pointer leaves. Editing a field
must not borrow a button hover tint, and an embedded editor takes its background
from its container. Treating these meanings as local token choices let the
Appearance model and specialized renderer paths assign different backgrounds to
the same selection, and left status blends outside the typed paint model.

Surfaces pair foreground with background. Raw app button tokens had incompatible
dark values, so buttons use primary text and the semantic primary-solid group.

Keeping this decision in a shared production resolver lets the proof obligations
refer to the same values consumed by both rendering paths. The small CSS adapter
interprets the resolved phases without defining another palette. The guarantees
cover document and CSS property semantics; they do not assert contrast for every
browser-resolved theme color.
