# 0066: Preserve frozen approval evidence

Date: 2026-10-21
Status: Accepted

## Context

An approval outcome without its reviewer cannot explain who authorized or
rejected an operation. Looking up the current profile also changes the apparent
author of an earlier decision when configuration is edited or the service is
restarted. The pending approval already captures the information needed to avoid
both errors.

## Decision

Record the reviewer selected by the actual pending approval alongside the
operation, original call and outcome. Use the same reviewer projection for
pending requests and completed audit entries, and display that recorded evidence
in the activity details. A model reviewer retains its captured profile rather
than a reference resolved against current configuration.

Keep the existing authority of each decision entry: a human decision does not
settle a pending model review. Prove evidence preservation for the actual human
and model completion operations, including their added history entries, rather
than for a receipt constructor in isolation.

## Limits

These guarantees identify the reviewer and preserve the evidence used by the
domain operation. They do not establish that an external model's judgment is
correct or that an approved physical operation succeeds. The single current
journal format remains the format described in [ADR 0065](0065-distinguish-speech-from-provider-activity.md);
this correction is part of the same unpublished reconstruction.
