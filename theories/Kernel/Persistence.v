From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import ChatgptArguments Codec ContextTypes Numbers RealtimeContext.
From Selvedge.Features Require BoardClock ConnectionGrants Titles.
From Selvedge.Programming Require ArgumentDeclaration.
Import ListNotations.
Open Scope string_scope.
Module D := ArgumentDeclaration.

(** These projections keep the declarations needed to reconstruct dependent
    values after extraction has erased their indices. *)
Definition encode_context_key (key : context_key) :=
 (key_definition key,
  D.encode (D.Object (identity_properties (definition_identity (key_definition key))))
    (key_values key)).

Definition decode_context_key (image : definition * json) : option context_key :=
 let '(definition, values) := image in
 option_map (ContextKey definition)
   (D.decode (D.Object (identity_properties (definition_identity definition))) values).

Definition encode_revision (value : revision) : string + N :=
 match value with
 | inl text => inl (proj1_sig text)
 | inr (inl counter) => inr (proj1_sig counter)
 | inr (inr impossible) => match impossible with end
 end.

Definition decode_revision (image : string + N) : option revision :=
 match image with
 | inl text => option_map inl (D.decode required_text (JString text))
 | inr counter => Some (counter_revision counter)
 end.

Definition encode_context_snapshot (snapshot : snapshot) :=
 let key := snapshot_key snapshot in
 (key, encode_revision (snapshot_version snapshot),
  D.encode (D.Object (value_properties key (definition_fields (key_definition key))))
    (snapshot_values snapshot)).

Definition decode_context_snapshot (image : context_key * (string + N) * json) : option snapshot :=
 let '(key, revision, values) := image in
 match decode_revision revision,
   D.decode (D.Object (value_properties key (definition_fields (key_definition key)))) values with
 | Some version, Some values => Some (Snapshot key version values)
 | _, _ => None
 end.

Definition encode_board_clock := D.encode BoardClock.declaration.
Definition decode_board_clock := D.decode BoardClock.declaration.

Definition decode_chatgpt_arguments := D.decode ChatgptArguments.declaration.

Definition encode_title_instruction := D.encode Titles.instruction_declaration.
Definition decode_title_instruction := D.decode Titles.instruction_declaration.

Definition encode_settings_request (value : settings_request) :=
 (option_map (D.encode workspace_declaration) (workspace_override value),
  option_map (D.encode sandbox_patch_declaration) (sandbox_override value),
  option_map (D.encode approval_declaration) (approval_override value),
  project_override value,
  option_map (D.encode RealtimeContext.declaration) (realtime_context_override value),
  option_map (D.encode guidance_declaration) (guidance_observation value),
  binding_observation value).

Definition decode_optional declaration (image : option json) :=
 match image with
 | None => Some None
 | Some value => option_map Some (D.decode declaration value)
 end.

Definition decode_settings_request image : option settings_request :=
 let '(workspace, sandbox, approval, project, realtime, guidance, binding) := image in
 match decode_optional workspace_declaration workspace,
       decode_optional sandbox_patch_declaration sandbox,
       decode_optional approval_declaration approval,
       decode_optional RealtimeContext.declaration realtime,
       decode_optional guidance_declaration guidance with
 | Some workspace, Some sandbox, Some approval, Some realtime, Some guidance =>
   Some (SettingsRequest workspace sandbox approval project realtime guidance binding)
 | _, _, _, _, _ => None
 end.

Definition encode_connection_grants (value : ConnectionGrants.Grants.t) :=
 JArray (map (fun grant => JObject [
   ("connection_id", number (ConnectionGrants.identity grant));
   ("project_ids", ConnectionGrants.projects_json (ConnectionGrants.grant_projects grant));
   ("sandbox", sandbox_json (ConnectionGrants.grant_sandbox grant))])
   (ConnectionGrants.Grants.values value)).

Definition decode_connection_grants (value : json) :=
 match D.decode ConnectionGrants.declaration value with
 | Some values => ConnectionGrants.admit_grants values
 | None => None
 end.
