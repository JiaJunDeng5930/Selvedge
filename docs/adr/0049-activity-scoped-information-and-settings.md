# 0049: Derive expanded settings from activity information requirements

Date: 2026-10-16

Status: Accepted

## Context

Conditional decisions already prevented editing inactive dependencies, but the
information fallback could restore those dependencies as ordinary facts. An
inactive reviewing model therefore appeared as missing configuration under a
different approval strategy. Information coverage accounted for property
membership without consistently accounting for the current activity.

Expanded settings also flattened field identity, current value and navigation
into a caption. The activity and completion observations remained available, but
did not consistently determine the panel identity and return affordance.

## Decision and reasons

Retain dependency conditions for information reasoning while preserving the
existing admission boundary for actions. Derive information requirements from
the current activity and its typed observations, so inapplicable information is
distinct from an applicable missing value. Explicit inspection may explain an
inactive condition without admitting an inactive operation.

Carry setting identity, current value and the canonical interaction separately
to the shared constructor. Derive the visible panel identity and its accessible
name from the same activity observation. This prevents each settings panel from
reconstructing ownership, navigation and applicability from labels.

Use the existing panel stack for a requested source inspection. The existing
settings-inspection flag cannot also identify a second request for provenance.
A source subactivity preserves its originating panel and returns to it without
adding a second flag to every layer or using an unrelated field as a sentinel.

The design follows the distinction between conditional follow-up controls and
supporting information that people request when needed, as illustrated by the
[GOV.UK conditional reveal guidance](https://design-system.service.gov.uk/components/radios/)
and [details guidance](https://design-system.service.gov.uk/components/details/).
The relevant principle is to preserve the dependency and purpose of information;
the application retains its own settings interactions and visual grammar.

## Assurance boundary

Production obligations bind applicability, information coverage and the shared
constructors. Native interaction regressions exercise emitted controls and their
actual commands; page inspection checks that the resulting hierarchy is readable.
These forms of evidence remain separate from the underlying execution policy.
