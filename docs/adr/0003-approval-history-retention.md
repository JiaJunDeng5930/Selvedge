# Retain the approval explanation without a reviewer configuration snapshot

Status: accepted

## Context

Approval grants one captured operation. The pending operation needs its selected
reviewer and ticket to route the request and accept only that review's result.
Once the operation settles, its historical reviewer profile no longer participates
in authorization or request execution. Retaining and proving that extra snapshot
made configuration provenance a separate product requirement without a current
use that requires it.

The approved command and decision reason have a different purpose. A before-tool
hook can rewrite the model's original call. Users therefore need the effective
invocation and the approval result to understand what actually ran or why it was
refused.

## Decision

Retain the pending reviewer until the operation settles. Completed approval
history keeps the effective invocation, operation identity and decision, without
copying the reviewer's profile. Use the shared approval construction to preserve
that explanation, and exercise its HTTP projection through the existing public
history test.

## Consequences

Historical approval records no longer expose a `reviewer` field. They do not
serve as an archive of model configuration. The command, approval reason and
execution authority keep their existing meanings. No compatibility field or
replacement provenance structure is introduced.
