# ADR 0059: Extend managed workspaces with a cloud execution binding

## Context

Upstream commit `acfbe86` adds Tencent CVM task environments to the local worktree
lifecycle. A remote path alone does not identify an execution environment. Forks
can inherit a workspace without owning its resource, and an execution request can
remain active after the task configuration changes. Resolving those requests from
current host state or the first matching path would lose their original authority.

The Rocq replacement already owns workspace transitions, command admission and
context-measurement scheduling. A second cloud lifecycle or a JavaScript copy of
task inheritance would separate these rules from the definitions being proved
and extracted.

## Decision

Extend the existing managed-resource representation with a typed backend. The
shared backend declaration supplies external names and command field metadata;
commands, retained resources and creation/archive effects use the same cases.
Keep the existing lifecycle phases because local and cloud resources wait for
the same kinds of setup and archive observations.

Keep a controlled resource-owner reference in the existing frozen task settings.
Ordinary task creation can inherit a caller's environment without inheriting its
fork lineage, so lineage and path alone cannot recover that authority. Cloud
forks retain the binding; an explicitly permitted local workspace selection
clears it. External settings cannot assign the reference. Require a ready resource
for every task inheriting that binding, not only its owner; otherwise a fork of
a failed setup could resume model execution in an unavailable environment.

Freeze resource identity in the actual execution effect. The IO host resolves
that identity to a physical receipt; it does not reproduce ownership rules or
infer a cloud environment from a path. Project and browser observations without
a task binding remain local.

Keep SDK calls, SSH, process transport, receipts and filesystem operations in the
Bun host. Provider receipts survive interrupted setup and enable reclamation;
they identify physical resources and do not replace the kernel's lifecycle.
Cloud setup clones the pushed GitHub commit and runs the project's
`.selvedge/env.sh` before returning a successful binding. Failed setup retains its
log and reclaims the instance. A missing cloud binding fails explicitly.

Cloud Bash uses Full Access inside the bound environment. The same binding
serves process input, file observations and image reads. Existing commit-before-
dispatch order, real process-group cleanup and archive barriers continue to apply.
Provider credentials remain host environment bindings, outside domain history.
Persisting the environment notice in domain history makes replay and token
accounting use the same content as provider requests.

Retain the existing `ReadyForModel` representation across context remeasurement;
measurement temporarily blocks scheduling without consuming the model request.
No notification flag is needed. The shared typed native catalog already avoids
the Bend-specific repeated construction addressed by upstream ADR 0055.

Journal rows persist inputs and compare their replayed decisions. Backend and
resource-binding fields change those decisions. Advance the single current
journal format to `selvedge-rocq-journal-2` and reject earlier formats before
replay rather than introducing compatibility defaults or a second execution path.

## Evidence and trust

Kernel checking covers the stated properties of the definitions used by the
production extraction entries. Independent complete-Service tests exercise the
official SDK against a controlled API and SSH fixture, including setup failure,
resource inheritance and interactive process feedback. They do not establish
Tencent availability or the behavior of arbitrary project setup scripts.

## Related decisions

- [Upstream cloud task workspaces](0054-cloud-task-workspaces.md) is preserved
  verbatim as the source decision for this incremental migration.
- [Upstream native catalog construction](0055-native-catalog-construction.md)
  records a Bend compilation concern already addressed by the Rocq design.
- [The shared Rocq semantic source](0054-rocq-semantic-source-and-extracted-runtime.md)
  defines the extraction and host boundary used here.
