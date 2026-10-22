From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema Utf8.
From Selvedge.Kernel Require Import Numbers Codec ContextTypes Context ContextUpdates.
Import ListNotations.
Open Scope string_scope.
Definition parse_scope (source : json) := match source with
 | JString "global" => Some Global | JString "primary_workspace" => Some PrimaryWorkspace
 | JString "workspace" => Some EveryWorkspace | _ => None end.
Definition parse_policy (source : json) :=
 match Schema.decode [Field "files" (KArray KText);Field "directories" (KArray KText);
  Field "repository_markers" (KArray KText);Field "excluded" (KArray KText);
  Field "max_directories" KNatural;Field "max_entries" KNatural;Field "max_sources" KNatural;Field "max_bytes" KNatural] source with
 | None => None | Some values =>
 let files:=head values in let values:=tail values in let dirs:=head values in let values:=tail values in
 let markers:=head values in let values:=tail values in let excluded:=head values in let values:=tail values in
 let directories:=head values in let values:=tail values in let entries:=head values in let values:=tail values in
 Some (DiscoveryPolicy files dirs markers excluded directories entries (head values) (head (tail values))) end.
Definition text_observer (field : string) (make : string -> observer) (source : json) :=
 option_map make (string_field field source).
Definition policy_observer (make : discovery_policy -> observer) (source : json) :=
 option_map make (parse_policy (value_or_null "policy" source)).
Definition observer_readers : list (string * (json -> option observer)) :=
 [("native_state",fun _ => Some NativeState);
  ("native_text",fun source => match string_field "revision" source,string_field "content" source with
    Some revision,Some content => Some (NativeText revision content) | _,_ => None end);
  ("config_text",text_observer "setting" ConfigText);("config_files",text_observer "setting" ConfigFiles);
  ("home_file",text_observer "relative" HomeFile);("workspace_file",text_observer "relative" WorkspaceFile);
  ("home_guidance",policy_observer HomeGuidance);("primary_guidance",policy_observer PrimaryGuidance);
  ("workspace_guidance",policy_observer WorkspaceGuidance);("home_skills",policy_observer HomeSkills);
  ("workspace_skills",policy_observer WorkspaceSkills)].
Definition parse_observer (source : json) :=
 match string_field "type" source with Some name =>
  match find (fun entry => String.eqb name (fst entry)) observer_readers with
  | Some (_,read) => read source | None => None end
 | None => None end.
Definition parse_identity_source (source : json) := match string_field "type" source with
 | Some "constant" => option_map Constant (string_field "value" source)
 | Some "source_path" => Some SourcePath | Some "workspace_root" => Some WorkspaceRoot
 | Some "home_root" => Some HomeRoot | _ => None end.
Definition parse_identity_field (source : json) :=
 match string_field "name" source,parse_identity_source (value_or_null "source" source),bool_field "required" source with
 | Some name,Some from,Some required => Some (IdentityField name from required) | _,_,_ => None end.
Definition parse_value_source (source : json) := match string_field "type" source with
 | Some "body" => Some Body | Some "metadata" => option_map Metadata (string_field "field" source)
 | Some "observation_field" => option_map ObservationField (string_field "field" source)
 | Some "identity" => option_map IdentityValue (string_field "field" source) | _ => None end.
Definition parse_value_field (source : json) :=
 match string_field "name" source,parse_value_source (value_or_null "source" source) with
 | Some name,Some from => match from with
   | IdentityValue _ => Some (ValueField name from true)
   | _ => option_map (ValueField name from) (bool_field "required" source) end
 | _,_ => None end.
Definition parse_definition (source : json) :=
 match string_field "kind" source,string_field "semantics" source,parse_scope (value_or_null "scope" source),
  parse_observer (value_or_null "observer" source),array_field "identity" source,array_field "fields" source with
 | Some kind,Some semantics,Some scope,Some observer,Some identity,Some fields =>
   match Codec.traverse parse_identity_field identity,Codec.traverse parse_value_field fields with
   | Some identity,Some fields => let definition:=ContextDefinition kind semantics scope observer identity fields in
     if ContextUpdates.valid_definition definition then Some definition else None
   | _,_ => None end
 | _,_,_,_,_,_ => None end.
Definition self_key (source : json) :=
 match string_field "type" source,parse_definition (value_or_null "definition" source),ContextUpdates.parse_fields (value_or_null "identity" source) with
 | Some kind,Some definition,Some identity =>
   if String.eqb kind (definition_kind definition) && ContextUpdates.valid_identity definition identity
   then Some (ContextKey definition identity) else None
 | _,_,_ => None end.
Definition self_snapshot (source : json) :=
 match self_key (value_or_null "key" source),string_field "revision" source,
  ContextUpdates.parse_fields (value_or_null "fields" (value_or_null "value" source)) with
 | Some key,Some revision,Some fields =>
   if String.eqb (definition_kind (key_definition key)) (text_default "type" (value_or_null "value" source) "")
   then ContextUpdates.construct_snapshot (key_definition key) (key_identity key) revision fields else None
 | _,_,_ => None end.
Definition patch := ContextUpdates.parse_patch.
Definition ordered_edits := ContextUpdates.ordered_edits.
Definition valid_patch := ContextUpdates.valid_patch.
