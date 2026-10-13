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
