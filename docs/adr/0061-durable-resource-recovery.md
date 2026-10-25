# 0061: Preserve resource recovery authority before physical allocation

Status: accepted.

A paid allocation can succeed after its caller loses the response. A synced file
without a synced directory entry does not establish recovery authority after a
crash. Reissuing an allocation to recover its identifier also assumes provider
idempotency outlives every service restart, which the provider contract does not
establish.

The extracted resource controller therefore owns allocation, preparation,
reconciliation and destruction transitions. The host interprets its primitive
operations. A complete request, token and verified provider scope must reach a
durable control record before the controller emits its single allocation. The
scope fixes the owning account, region, endpoint and credential reference. The
identity observation and allocation use one captured credential; secrets are
never persisted. Recovery verifies the current credential against that scope and
emits read-only observations rather than another allocation.

Unknown allocations are reconciled through every page of the request's management
tag. Candidates remain recorded, and only identifiers matching the saved request
and tag enter the destruction set. The service reserves the `selvedge-task` tag
namespace: operators must not copy or modify these tags while a recovery intent
is open. This is an operational assumption about mutable provider metadata, not
an unforgeable ownership claim. Ambiguous matches require resolution; an empty,
interrupted or unauthorized scan preserves an unresolved allocation.

Recording a discovered identity is attempted before destruction. If storage is
full, confirmed in-memory identifiers still authorize cleanup, using an
independent cleanup deadline. The previous durable unknown intent remains a
recovery obligation; a failed write never becomes a durable success. A pinned SDK
transport patch rejects redirects, so the transport cannot silently dispatch the
allocation to a second endpoint.

The same controller grants local checkout and move operations after durable
intent records. Restart recovery observes Git registration and existing paths;
it does not replay a checkout or move. File publication uses exclusive,
no-follow temporary files, file synchronization, same-directory rename and parent
synchronization. Newly created service directories are established and synced
from their stable ancestors before any resource intent is published.

The current cloud receipt format includes this recovery authority. Older
receipts lack account and single-dispatch evidence, remain untouched external
material, and require explicit reconciliation rather than synthesized authority
or automatic format conversion.
