# 0070: Share context source admission

Date: 2026-10-22
Status: Accepted

## Context

The context definition language supplies the same source contract to native
construction and wire observations. Separate partial checks let a constructor
skip definition validity while the wire interpreter applied a different schema.
Rejecting a present observation during wire decoding also prevented the ordinary
context callback from recording a source diagnostic and settling its lease.
An observation batch collects independent sources, so one rejected observation
must not discard accepted updates from the other sources.

## Decision

Keep definition and snapshot admission with the shared context operations.
Checked construction and the generic wire interpreter use those same predicates.
Present observations retain their decoded candidate until semantic observation
resolution; absent and failed observations still require an admitted source key.
This preserves the original distinction between a malformed protocol message and
a source observation that fails its declared contract.

Required text rejects an empty string rather than whitespace. A value borrowed
from an identity must equal that identity, including an optional empty identity;
it does not acquire an independent text requirement. These are properties of the
existing definition language rather than additional policies for installed kinds.

Use the existing JSON object equivalence operation for registered descriptors so
object member order cannot change source identity. Keep the actual construction,
patch, history reconstruction and callback functions as the subjects of the
proofs; an independent reference interpreter would recreate the disagreement.
