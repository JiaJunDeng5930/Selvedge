# User work and property operations

Start with [MODEL.bend](MODEL.bend) for semantic subjects, alternatives and work
identities, immutable property observations and submission assessments. [PROGRAM.bend](PROGRAM.bend) constructs decisions, workspace
collections and action units from their actual observations. Read their properties
through its getters; clients do not construct their private representations.

[CONTRACT.bend](CONTRACT.bend) binds admission, observation and generated commands
to production operations; [PROOF.bend](PROOF.bend) supplies the evidence. Actual
application acceptance remains the responsibility of the interaction command
resolver. Browser interpretation consumes these constructions and owns their
physical presentation.

`object_key`, `subject_key` and `action_key` expose canonical semantic identities.
`group_owner(editor, fields)` finds the common property owner of an actual form
section; an empty section or mixed ownership uses that editor's root object.

The property factories consume context observations and world resource lookups.
Their getters expose the current value, provenance, owner and field identities;
`property_support` applies the actual action scope to those identities.

`property_summary` derives the compact current choice. `property_source_description`
provides readable provenance; `property_help` retains full accessible help.
`attention_obstruction` selects the next repair from the complete assessment, and
`property_obstruction` correlates it with the actual property fields and editor.

`draft_requirements` and `draft_can_prepare` share the production command guards
and revision-correlated workspace failures with presentation and admission.
Assessment getters retain individual obstructions and the original action identity.
Directory observation is an explicit next step in the assessment, before actual
command resolution. The complete observation and guard equations are assembled
by the owning production evidence in [PROOF.bend](PROOF.bend).

Permission observations track filesystem/network and approval provenance separately.
Project selection changes directory provenance; permissions inherit environment
defaults or the parent task unless that individual permission choice is overridden.

The session owns source intent in its actual open layer; presentation consumes
that intent together with these observations through `property_source_nodes`.

[ACTIVITY.bend](ACTIVITY.bend) constructs comparison, explanation and object-editing
activities from the owning observations. Start at `comparison`, `explanation` or
`editing`, then read `scope`, `object`, `relations`, `required_evidence`,
`support_evidence`, `catalog` and `reading_units`. A dependent decision is admitted
by its actual parent's selected prerequisite and common ownership; a workspace
relation reads members from the retained collection. `ActivityRequirements` binds
these producers and their necessary observations to the concept's production proof.

`project_edit` retains the original resource, complete draft, pending submission,
change observation and action assessment. `draft_requirements` also consumes
unadded directory input and project changes, so every submission caller must pass
the complete draft instead of replacing this operation with `can_prepare(body, ...)`.

`candidate` observes each actual alternative through the existing canonical input,
single-candidate decision admission and choose operations. Read its identity,
selected state, availability, original rejection reason and selection input through
`candidate_*` getters. Activities derive these observations from their complete
catalogue; search projects observations and never reinterprets admission.

`ACTIVITY.view(activity, focus, inspection)` admits the requested subject against
that activity's retained root, selected-parent dependencies and selected-profile
fields. Initial root decisions expose candidates. Comparison activities expose compact
owned parameter entries; effect-explanation activities reserve configuration
dependencies for requested inspection and express actual access consequences
with the principal candidates. Requested parameter and inspection views retain their exact
subject. `completion` supplies the common apply/dismiss, apply/return,
inspection-return and compound commit/discard boundary; consumers must use it
without changing the domain's draft-versus-immediate configuration semantics.
An inspection with a requested retained subject exposes that exact root or child
selection and completes back to inspection; an inspection without a requested
selection returns to its owner. A different child request never expands the root.

`relation_exposure` is the production projection policy for the existing relation
fold. Required facts remain requirements, but `coverage` supplies their actual
expression witness instead of requiring a duplicate paragraph. Read
`information_expressions(activity, current, coverage)` for every applicable required subject: a selected candidate, admitted
parameter, actual permission consequence, owner context, original identity,
requested inspection or necessary inline value. The complete property observation
and applied/draft/original reference remain in `FactIdentity`. Project name input
uses `draft_field_identity`, retaining the full draft separately from the saved
object identity. Equal display labels do not establish coverage.

Model search is requested only for an initial model comparison with more than
eight catalogue entries. Filtering preserves the actual selected candidate,
including unavailable selection observations, rather than redoing admission.
Open and automatic reasoning fields retain their actual SingleLine or DisplayOnly
entry; finite options remain owned dependent decisions. The Ask consequence names
the existing explicit Bash escalation request rather than claiming automatic
approval-need detection. `ViewConstructionRequirements` binds these operations and
expression witnesses to the owner-local production evidence.

Property summaries always retain their actual principal identity. Permission
summary modes come from the observed execution strategy for both draft and
committed contexts: Ask, Automatic review or Full access. Compact summaries omit
secondary access details while preserving that mode; they never reduce ordinary
permissions to an unnamed shield. Full summaries add the observed consequences.
The standalone permission consequence operation remains unchanged.

Consumers read model profile/effort through `property_model_context`, which returns
the shared `Forms.ModelValue` observation, and permission state through
`property_permission_context`, which returns the real context observation. Other
property kinds return None. These read-only getters are bound to the owning
`model_property` and `permissions_property` producers; clients do not match the
private Property representation. Human-readable model identity remains available
through `property_value`.

`property_recognition_summary` is the entry for inline recognition. It retains the
complete Property observation, the principal subject/value, and an optional
subject/value that depends on that selection. Model identity owns its effort
explanation; execution strategy owns the relevant sandbox explanation. Effective
Full access has no active sandbox limit to summarize. `summary_projection`
removes dependent information for a compact group without changing the owner or
principal value. `RecognitionSummaryRequirements` binds these relationships to
the production factory. The complete `property_summary` remains available for
semantic descriptions and help, rather than determining the inline visual roles.


`MODEL.InformationStatus` separates applicability from presence.
`PROGRAM.property_information` reads typed property observations at their owner;
`ACTIVITY.information_status` combines that public observation with the current
activity's dependency and assessment evidence. The original
parent/selection/child dependencies remain in the relation tree even while
inactive; they retain observation evidence without admitting a choice or edit.
`subject_dependency` reads those same conditions, including owner and editor
checks, rather than reconstructing applicability from field captions. The
existing `dependency_applies`, retained-decision and exposure checks continue to
control all actionable dependencies.

Applicable observations distinguish present information, optional absence,
required absence and unavailable information. Project selection uses its typed
optional reference, model and reviewer presence use the actual catalog lookup,
and project editing uses the production assessment's field obstructions.
`information_expressions` filters the existing subject witnesses through that
classification. Inactive information is omitted unless its exact subject was
explicitly requested for inspection; a required or unavailable observation remains
visible so that missing information cannot disappear as if it were irrelevant.
`InformationRequirements` binds retained conditions, classification and complete
expression traversal to these production operations.
