# ADR 0002: Retain the resource state needed for recovery

Date: 2026-11-01
Status: Accepted

## Context

Managed workspaces must preserve ownership, avoid repeated allocation after a lost
response, retain work on archive, and recover after a service process stops.
The implementation also flushed every initial checkout file and Git administration
file, retained a list of every destroyed cloud instance, and persisted a dispatch
counter that was always one. Those additions did not change the recovery decisions.

Cloud recovery also accumulated pages of candidate and failed instance identities.
The acceptance fixtures manufactured multiple instances from one request even
though the request fixes both `InstanceCount` and `MinCount` to one. Tencent's
[RunInstances contract](https://cloud.tencent.com/document/api/213/15730) bounds
the allocation by that requested count. The list-based state protected a different
resource model from the one Selvedge actually provisions.

The plugin also generated a manifest of source and artifact hashes and rechecked
it at startup. In a source checkout, launching an already built plugin invoked the
compiler version commands and read every extraction input. The manifest was stored
beside the executable assets and supplied no independently authenticated identity.

## Decision

Use Git and filesystem operation completion for managed checkout contents. Keep
atomic publication of ownership and recovery records, and keep path, inode and Git
registration checks before returning or removing an owned workspace. Remove the
extra whole-checkout synchronization phases and their physical-barrier theorems.
Git's own [core.fsync configuration](https://git-scm.com/docs/git-config#Documentation/git-config.txt-corefsync)
controls its repository durability policy; Selvedge does not add a separate
recursive flush of project files. Preservation across host power loss is outside
this checkout contract.

Represent cloud allocation as unknown or a known optional instance. Reconcile an
unknown result with a single tag query; only one matching identity may proceed to
cleanup. A conflicting observation retains the unresolved resource. A failed
termination retains that identity for a later explicit archive retry. Remove
pagination, candidate and failure lists, destroyed-instance history and the
constant dispatch counter. Provider calls and resulting resource state supply the
public acceptance observations. The cloud receipt format becomes
`selvedge-cloud-workspace-4`, with no legacy decoder.

Build the plugin's generated files from the ordinary host build before packaging.
Load those executable files through the standard module loader. Remove the runtime
manifest, source-root and compiler-version audit. The build command recreates its
owned generated directory; packaging copies the declared files. The existing
[`prepack` lifecycle](https://docs.npmjs.com/cli/v11/using-npm/scripts#prepack)
continues to invoke the model build.

## Consequences

A managed checkout no longer adds a second traversal and file-by-file flush after
copying project contents. Service restart still checks observed ownership and
never repeats an uncertain checkout, move, or cloud allocation. A plugin can run
from its built package without querying the toolchain or its original checkout.
Real provider, filesystem and MCP behavior remains covered through public-entry
acceptance tests; private receipt layouts and removed audit fields are not test
requirements.
