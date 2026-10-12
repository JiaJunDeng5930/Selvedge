# User work and property operations

Start with [MODEL.bend](MODEL.bend) for semantic subjects, alternatives and work
identities. [PROGRAM.bend](PROGRAM.bend) constructs decisions, workspace
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
