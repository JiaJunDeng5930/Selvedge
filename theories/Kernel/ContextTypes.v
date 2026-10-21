From Stdlib Require Import String List Bool NArith.
Inductive scope := Global | PrimaryWorkspace | EveryWorkspace.
Record discovery_policy := DiscoveryPolicy {
  discovery_files : list string;
  discovery_directories : list string;
  discovery_markers : list string;
  discovery_excluded : list string;
  discovery_max_directories : N;
  discovery_max_entries : N;
  discovery_max_sources : N;
  discovery_max_bytes : N
}.
Inductive observer := NativeState | NativeText (revision content : string)
 | ConfigText (setting : string) | ConfigFiles (setting : string)
 | HomeFile (relative : string) | WorkspaceFile (relative : string)
 | HomeGuidance (policy : discovery_policy) | PrimaryGuidance (policy : discovery_policy)
 | WorkspaceGuidance (policy : discovery_policy) | HomeSkills (policy : discovery_policy)
 | WorkspaceSkills (policy : discovery_policy).
Inductive identity_source := Constant (value : string) | SourcePath | WorkspaceRoot | HomeRoot.
Record identity_field := IdentityField { identity_name : string; identity_from : identity_source; identity_required : bool }.
Inductive value_source := Body | Metadata (field : string) | ObservationField (field : string) | IdentityValue (field : string).
Record value_field := ValueField { value_name : string; value_from : value_source; value_required : bool }.
Record definition := ContextDefinition { definition_kind : string; definition_semantics : string;
 definition_scope : scope; definition_observer : observer;
 definition_identity : list identity_field; definition_fields : list value_field }.

Record context_key := ContextKey { key_definition : definition; key_identity : list (string * string) }.
Record snapshot := Snapshot { snapshot_key : context_key; snapshot_revision : string; snapshot_fields : list (string * string) }.
Record text_edit := TextEdit { edit_start : N; edit_removed : string; edit_inserted : string }.
Record field_patch := FieldPatch { patch_field : string; patch_edits : list text_edit }.
Inductive context_change := Introduce (value : snapshot)
 | Amend (key : context_key) (base revision : string) (patches : list field_patch)
 | Remove (key : context_key) (base : string).
Inductive context_observation := Present (value : snapshot) (patches : list field_patch)
 | Absent (key : context_key) | ObservationFailure (key : context_key) (message : string).
