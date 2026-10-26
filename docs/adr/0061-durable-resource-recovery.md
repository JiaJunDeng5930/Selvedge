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

Resource phases now carry their applicable evidence in closed Gallina
constructors. Allocation uncertainty and a confirmed allocation are distinct
values; preparation, successful readiness and readiness revalidation carry the
instance and connection facts they actually require. Durable phase fields are
projections of those constructors, rather than independently mutable flags.
This prevents a host status update from accidentally granting allocation or
cleanup authority. Recovery consumes observations and cannot regain allocation
authority along a subsequent controller trace. The current receipt format is
advanced together with this representation; accepting an earlier format would
reintroduce an independent interpretation of those facts.

The production resource and SSH readiness interpreters consume generated action
unions under strict TypeScript checking. SSH exit 255 is an observed temporary
transport failure during image startup; the extracted controller owns its bounded
retry and deadline. Missing image programs remain a definite preparation failure.
Neither a timer nor a transport adapter selects a resource continuation.

Exclusive directory creation establishes a local reservation, not Git
registration. The reservation records its canonical path, device, inode and
fresh identity before the controller permits Git registration. A separately
persisted registration acknowledgement permits preparation. Canonical roots and
Git backlinks are physical observations admitted by the same extracted owner.

Failed creation and archival share ownership evidence but retain distinct
intents. Archival moves registered worktrees to preserve tracked and untracked
changes. An owned, empty, unregistered reservation can instead be released with
nonrecursive `rmdir`. Release synchronizes the parent directory and persists a
terminal receipt before its callback can settle the resource as having no archive
path. Recovery may acknowledge that a durable reservation is already absent; it
never repeats a release or Git move. A crash before reservation identity reaches
disk leaves an explicit ownership resolution requirement rather than authorizing
a deletion from the directory name alone.

Git command completion is an observation of a mutation, not its durability
acknowledgement. `LocalResources.RegistrationSyncing` and
`LocalResources.TerminalSyncing` select the corresponding barrier before a
registration, ready, archive or release receipt can be published. The checked
`resource-runtime.ts` interpreter emits `local_synchronized` only after the
physical operation has completed. `worktrees.mjs` owns the write sets:

- Registration synchronizes the checkout's `.git` file, its Git administrative
  directory and files, the checkout directory, and the repository's `worktrees`
  administrative parent and common directory.
- Initial readiness also synchronizes the prepared initial checkout files and
  directories, including the checkout's parent entry.
- Archive synchronizes the relocated Git links and administrative files plus
  both the active and archive parent directories.
- Release synchronizes both managed path parents and the repository's Git
  administrative parent after removal.

These barriers cover the service's managed registration, path and initial
snapshot operations. Later arbitrary commands do not acquire an implicit
whole-filesystem durability guarantee. Symlink targets outside a managed tree
are not followed by synchronization. Recovery can finish a barrier on observed
owned facts but still cannot repeat checkout, move or removal. A failed barrier
preserves uncertainty instead of publishing a stable terminal fact. The single
current local receipt format is `selvedge-local-workspace-2`; earlier receipts
do not establish the new acknowledgement contract and are rejected.

Git supports both absolute and relative worktree linking files. Backlink
observations resolve relative paths against their canonical Git administrative
directory before the model compares them with the owned checkout's `.git` path.
The same observation validates creation, archive and recovery, including the
reservation's device/inode and repository common directory. New managed Git
operations request absolute links explicitly, without changing repository
configuration or narrowing admission of already valid relative links.
