From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema SchemaJson JsonSchema Arguments Numbers RemoteIdentity.
From Selvedge.Foundation Require ArgumentDeclaration.
From Selvedge.Kernel Require Import Domain Codec Commands ContentDeclarations ChatgptArguments ChatgptProtocol.
From Selvedge.Features Require Import Titles BoardParameters TaskGraphDeclarations.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Module D := ArgumentDeclaration.

Definition shape (source : json) :=
 match D.parse source with Some description => description | None => D.Reject end.
Definition from_fields (declaration : schema) := D.Object (map (fun field =>
 (field_name field,negb (field_omittable field || SchemaJson.optional_kind (field_kind field)),
 D.of_kind (SchemaJson.present_kind (field_kind field)))) declaration).
Definition natural := D.of_kind KNatural.
Definition identity := D.Natural 0 4294967295.
Definition enum (first : string) (rest : list string) := D.of_kind (KEnum first rest).
Definition workspace_declaration := D.Object [
 ("roots",true,D.BoundedArray 0 32 D.text);
 ("primary_root",false,D.nullable D.text)].
Definition sandbox_declaration := from_fields Codec.sandbox_schema.
Definition sandbox_patch_declaration := D.Object (map (fun field =>
 (field_name field,false,D.of_kind (field_kind field))) Codec.sandbox_schema).
Definition approval_declaration := from_fields Codec.approval_schema.
Definition guidance_declaration := D.nullable (from_fields Codec.guidance_schema).
(** Public requests cannot manufacture observations. The host admits their
    syntax first, then supplies guidance and resource evidence separately. *)
Definition settings_declaration (observed : bool) := D.Object
 ([ ("workspace",false,workspace_declaration);
    ("sandbox",false,sandbox_patch_declaration);
    ("approval",false,approval_declaration);
    ("project_id",false,natural)] ++
  if observed then [("guidance",false,guidance_declaration);
                    ("workspace_binding",false,D.Any)] else []).
Definition settings_arguments := map (fun field =>
 let argument := Arguments.omittable_nonnull (Arguments.from_field field) in
 if String.eqb (field_name field) "workspace" then Arguments.with_declaration workspace_declaration argument else
 if String.eqb (field_name field) "sandbox" then Arguments.with_declaration sandbox_patch_declaration argument else
 if String.eqb (field_name field) "approval" then Arguments.with_declaration approval_declaration argument else argument)
 (filter (fun field => negb (String.eqb (field_name field) "guidance" ||
 String.eqb (field_name field) "workspace_binding")) Codec.task_settings_schema).
Definition fields_of (source : json) := match source with JObject fields => fields | _ => [] end.
Definition settings_schema := fields_of (D.schema (settings_declaration false)).
Definition public_settings_schema := settings_schema.
Definition content_declaration := shape (JObject ContentDeclarations.content_schema).
Definition images_declaration := shape (JObject ContentDeclarations.images_schema).
Definition attachments_declaration := D.Array (from_fields BoardParameters.attachment_schema).
Definition title_prompt_declaration := Titles.instruction_declaration.
Definition controller_id_declaration := RemoteIdentity.controller_declaration.
Definition controller_id_schema := fields_of (D.schema controller_id_declaration).
Definition title_prompt_schema := fields_of (D.schema title_prompt_declaration).
Definition permission_names := ["read";"control";"configure";"approve"].
Definition permissions_declaration := D.Object (map (fun name => (name,true,D.Boolean)) permission_names).
Definition permissions_schema := fields_of (D.schema permissions_declaration).
Definition grants_declaration := D.Array (D.Object [
 ("connection_id",true,identity);("project_ids",true,D.Array identity);
 ("sandbox",true,sandbox_declaration)]).
Definition connection_grants_schema := fields_of (D.schema grants_declaration).

Fixpoint graph_message_declaration (depth : nat) : D.t := match depth with
 | O => D.Reject
 | S remaining => D.Union [from_fields TaskGraphDeclarations.output_fields;
   from_fields TaskGraphDeclarations.literal_fields;
   D.Object [("kind",true,enum "concat" []);
     ("parts",true,D.Array (graph_message_declaration remaining))]]
 end.
Definition graph_node_declaration (observed : bool) := D.Union [
 D.Object [("key",true,D.text);("task_id",true,identity)];
 D.Object [("key",true,D.text);("profile",false,D.text);
 ("reasoning",false,D.text);("message",false,D.text);
 ("settings",false,settings_declaration observed)]].
Definition graph_action_declaration := D.Object [("target",true,D.text);
 ("message",true,graph_message_declaration TaskGraphDeclarations.maximum_message_depth)].
Definition graph_rule_declaration := D.Object [("key",true,D.text);("source",true,D.text);
 ("actions",true,D.BoundedArray 0 8 graph_action_declaration)].
Definition graph_command (name : string) := String.eqb name "create_task_graph" || String.eqb name "update_task_graph".
Definition board_metadata (name : string) := existsb (String.eqb name) ["create_card";"update_card"].
Definition board_status := enum "backlog" ["todo";"in_progress";"in_review";"done";"blocked"].
Definition board_assignee := D.Union [enum "none" ["self"];
 D.PrefixedText "profile/" (D.bounded_text 1016);
 D.PrefixedText "agent/" (D.NaturalText 0 None)].
Definition board_project := D.Union [enum "" [];D.NaturalText 0 None].
Definition board_clock := D.NaturalText 0 (Some 4294967295).
Definition board_priority := enum "none" ["low";"medium";"high";"urgent"].

Definition refined_type (observed : bool) (command name : string) : option D.t :=
 if String.eqb name "settings" then Some (settings_declaration observed) else
 if String.eqb name "workspace" then Some (if String.eqb command "resolve_workspace" then D.nullable workspace_declaration else workspace_declaration) else
 if String.eqb name "guidance" then Some (if observed then guidance_declaration else from_fields Codec.guidance_schema) else
 if String.eqb name "sandbox" then Some sandbox_patch_declaration else
 if String.eqb name "approval" then Some approval_declaration else
 if String.eqb name "message" then Some content_declaration else
 if String.eqb name "images" then Some images_declaration else
 if String.eqb name "messages" then Some (D.Array content_declaration) else
 if String.eqb name "attachments" then Some attachments_declaration else
 if String.eqb name "observed_at" then Some board_clock else
 if graph_command command then
   if String.eqb name "nodes" then Some (D.BoundedArray 0 32 (graph_node_declaration observed)) else
   if String.eqb name "rules" then Some (D.BoundedArray 0 32 graph_rule_declaration) else
   if String.eqb name "work_id" || String.eqb name "graph_id" then Some identity else None
 else if String.eqb command "configure_chatgpt_connections" && String.eqb name "connections" then Some grants_declaration else
 if String.eqb command "chatgpt_exec" && String.eqb name "arguments" then Some (shape ChatgptArguments.args_schema) else
 if existsb (String.eqb command) ["chatgpt_exec";"chatgpt_cancel";"chatgpt_forget";"chatgpt_projects";
 "chatgpt_project";"chatgpt_operation";"chatgpt_operations"] &&
 existsb (String.eqb name) ["connection_id";"project_id";"operation_id"] then Some identity else
 if board_metadata command then
   if String.eqb name "status" then Some board_status else
   if String.eqb name "priority" then Some board_priority else
   if String.eqb name "assignee" then Some board_assignee else
   if String.eqb name "project" then Some board_project else None
 else if String.eqb command "move_card" && String.eqb name "status" then Some board_status else
 if String.eqb command "remote_grant" && String.eqb name "permissions" then Some permissions_declaration else
 if String.eqb name "controller_id" then Some controller_id_declaration else
 if String.eqb command "configure_title_settings" && existsb (String.eqb name) ["task_prompt";"agent_prompt"]
 then Some title_prompt_declaration else None.
Definition required_by_operation (command field : string) :=
 (String.eqb command "move_card" && String.eqb field "status") ||
 (String.eqb command "link_card" && String.eqb field "task_id") ||
 (String.eqb command "pin_card" && String.eqb field "pinned").
Definition refine_argument (observed : bool) (name : string) (argument : argument_spec) :=
 let argument := if required_by_operation name (argument_name argument) then
  Argument (argument_name argument) (argument_type_of argument) true
   (argument_description argument) (argument_bounds argument) else argument in
 match refined_type observed name (argument_name argument) with
 | Some description => Arguments.with_declaration description argument
 | None => argument end.
Definition command_arguments_with (observed : bool) (specification : command_spec) :=
 map (refine_argument observed (command_name specification))
 (map (Commands.command_argument (command_name specification))
  (Field "op" (KEnum (command_name specification) []) ::
   filter (fun field => observed || negb (String.eqb (field_name field) "workspace_binding"))
     (command_fields specification))).
Definition command_arguments := command_arguments_with false.
Definition command_schema (specification : command_spec) := Arguments.json_schema (command_arguments specification).
Definition valid (observed : bool) (source : json) :=
 match string_field "op" source with
 | Some name => match find (fun specification => String.eqb name (command_name specification)) Commands.command_specs with
   | Some specification => Arguments.valid (command_arguments_with observed specification) source
   | None => false end
 | None => false end.
Record public_raw_command := PublicRawCommand {
 public_raw_source : json;
 public_raw_admitted : valid false public_raw_source = true
}.
Record observed_command := ObservedCommand {
 observed_source : json;
 observed_admitted : valid true observed_source = true
}.
Definition admit_public (source : json) : option public_raw_command :=
 match Bool.bool_dec (valid false source) true with
 | left proof => Some (PublicRawCommand source proof) | right _ => None end.
Definition admit_observed (source : json) : option observed_command :=
 match Bool.bool_dec (valid true source) true with
 | left proof => Some (ObservedCommand source proof) | right _ => None end.
