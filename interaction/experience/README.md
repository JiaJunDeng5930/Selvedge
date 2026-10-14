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
