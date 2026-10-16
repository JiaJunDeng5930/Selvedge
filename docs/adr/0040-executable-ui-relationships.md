# ADR 0040: executable UI relationships

## Context

The interface already had sections, fields, choices, typography tiers and surface
roles, yet shared constructors rendered different information relationships with
similar emphasis. Some compound fields lost their visible names, and accessible
name references did not have corresponding HTML identifiers. Treating these as
individual style defects would leave the same ambiguity in other forms.

The composer also mixed creation context with execution controls. Its model was
selected only in a creation draft, and the task contract froze both provenance
and execution parameters. Whole-contract retention and comparison with a live
parent consequently prevented a task from changing its own model or permission
policy without violating unrelated ancestry requirements.

## Decision

Semantic information roles and ownership are retained through the production
presentation and authored-source boundary. Shared constructors determine how an
owned title, label, value or explanation is rendered and associated with its
owner. A compound observation is projected by the field it represents; its
profile and reasoning values cannot share an unspecified string projection.
The existing section and choice structures remain authoritative; a second
form hierarchy is unnecessary. Browser JavaScript interprets authored documents
and focus policies rather than reconstructing these relationships from labels.

Creation provenance and current execution settings have different lifetimes.
Their state and guarantees are separate so that an intentional configuration
update can preserve the creation binding, ancestry and unrelated task state.
Historical inheritance belongs to the actual fork operation and the preserved
creation record, rather than an equality with a parent's subsequently modified
settings. Changes are resolved through a public operation and controlled at the
commit boundary; outstanding accepted work keeps its established meaning.
Provider continuations include committed settings in their instruction contract,
so changing permissions also invalidates that task's provider session. Limiting
invalidation to a different model would accept the new permissions and then
reject the next message against the stale contract.

Public policy observations include descriptive reviewer data. Command inputs
need only the reviewer identity resolved by the operation. Reusing the observation
encoder for a command violates its closed schema and would couple presentation
details to accepted authority. The command codec therefore owns that projection.

Permission summaries retain the same scope distinction. A creation editor observes
a prospective configuration, while a task editor observes its committed execution
context. Creation override resets have no operation in the task editor and are
therefore absent from its menu.

The user model preference is separate from each task's model. It seeds creation
and survives browser reload, while changing it does not rewrite existing tasks.
The browser stores preference data; Bend validates and resolves it against the
current catalog.

Creation-only context and continuing execution controls are distinct composer
parts. The composer owns its enclosure and embedded editor focus. Persistent
navigation consumes an allocation, while transient layers use their explicit
overlay role. Capacity for editing is separate from the preferred width for
reading prose, so a reading-width preference does not unnecessarily turn
desktop navigation into an overlay.

The previous positive-inset requirement assumed every editor was an independent
field enclosure. An editor embedded in a composer shares its block edge instead.
Named enclosure profiles retain this distinction in the geometry requirements;
anonymous spacing overrides would hide it from clients and proofs. Focus
ownership is declared by the same construction boundary instead of recovered by
traversing the completed source tree.

## Evidence boundaries

Executable requirements and their production proofs are the authority for these
relationships. This document records why the boundaries changed, not another
account of their transitions. Compiler, storage, provider continuation and DOM
behavior remain external boundaries. Their focused integration checks and actual
browser observations supplement the pure production evidence; structural laws
alone cannot establish the final visual result.
