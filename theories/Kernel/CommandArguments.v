From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema SchemaJson Arguments Numbers RemoteIdentity.
From Selvedge.Foundation Require ArgumentDeclaration.
From Selvedge.Kernel Require Import Domain Codec ContentDeclarations ChatgptArguments.
From Selvedge.Features Require Import Titles BoardParameters TaskGraphDeclarations.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module D := ArgumentDeclaration.

Definition from_fields := D.of_schema.
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
    ("project_id",false,identity)] ++
  if observed then [("guidance",false,guidance_declaration);
                    ("workspace_binding",false,D.Any)] else []).
Definition settings_arguments := map (fun field =>
 let argument := Arguments.omittable_nonnull (Arguments.from_field field) in
 if String.eqb (field_name field) "workspace" then Arguments.with_declaration workspace_declaration argument else
 if String.eqb (field_name field) "sandbox" then Arguments.with_declaration sandbox_patch_declaration argument else
 if String.eqb (field_name field) "approval" then Arguments.with_declaration approval_declaration argument else
 if String.eqb (field_name field) "project_id" then Arguments.with_declaration identity argument else argument)
 (filter (fun field => negb (String.eqb (field_name field) "guidance" ||
 String.eqb (field_name field) "workspace_binding")) Codec.task_settings_schema).
Definition fields_of (source : json) := match source with JObject fields => fields | _ => [] end.
Definition settings_schema := fields_of (D.schema (settings_declaration false)).
Definition public_settings_schema := settings_schema.
Definition content_declaration := ContentDeclarations.content_declaration.
Definition images_declaration := ContentDeclarations.images_declaration.
Definition attachments_declaration (observed : bool) := D.Array
 (from_fields (if observed then BoardParameters.attachment_schema
               else BoardParameters.attachment_reference_schema)).
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

Definition graph_node_declaration (observed : bool) := D.Union [
 D.Object [("key",true,D.text);("task_id",true,identity)];
 D.Object [("key",true,D.text);("profile",false,D.text);
 ("reasoning",false,D.text);("message",false,D.text);
 ("settings",false,settings_declaration observed)]].
Definition graph_rule_declaration := TaskGraphDeclarations.rule_declaration.
Definition graph_command (name : string) := String.eqb name "create_task_graph" || String.eqb name "update_task_graph".
Definition board_metadata (name : string) := existsb (String.eqb name) ["create_card";"update_card"].
Definition board_status := enum "backlog" ["todo";"in_progress";"in_review";"done";"blocked"].
Definition board_assignee := D.Union [enum "none" ["self"];
 D.PrefixedText "profile/" (D.bounded_text 1016);
 D.PrefixedText "agent/" (D.NaturalText 0 (Some 4294967295))].
Definition board_project := D.Union [enum "" [];D.NaturalText 0 (Some 4294967295)].
Definition board_clock := D.NaturalText 0 (Some 4294967295).
Definition board_priority := enum "none" ["low";"medium";"high";"urgent"].


(** A field declares its internal representation and its external admission in
    one place. The observed interpretation differs only for host-owned evidence.
    Generated internal messages retain ordinary naturals; admitted messages
    carry the complete external judgment instead of pretending every internal
    identifier or counter belongs to the public U32 wire protocol. *)
Record field_declaration := DeclareField {
 field_shape : field_spec;
 field_wire_type : bool -> option D.t;
 field_force_required : bool
}.
Definition plain (field : field_spec) := DeclareField field (fun _ => None) false.
Definition req (name : string) (kind : kind) := plain (Field name kind).
Definition opt (name : string) (kind : kind) := plain (OmittableField name kind).
Definition nullable (name : string) (kind : kind) := plain (Field name (KOptional kind)).
Definition typed (description : D.t) (field : field_declaration) := DeclareField
 (field_shape field) (fun _ => Some description) (field_force_required field).
Definition staged (description : bool -> D.t) (field : field_declaration) := DeclareField
 (field_shape field) (fun observed => Some (description observed)) (field_force_required field).
Definition required (field : field_declaration) := DeclareField
 (field_shape field) (field_wire_type field) true.
Definition u32 (field : field_declaration) := typed identity field.
Definition optional_identity_text (field : field_declaration) := typed board_project field.
Definition bounded (minimum maximum : N) (field : field_declaration) := typed (D.Natural minimum maximum) field.
Record wire_command := WireCommand {
 wire_name : string;
 wire_fields : list field_declaration
}.
Definition command_shape (declaration : wire_command) :=
 Command (wire_name declaration) (map field_shape (wire_fields declaration)).
Definition field_argument (observed : bool) (declaration : field_declaration)
 (base : argument_spec) :=
 let argument := Argument (argument_name base) (argument_type_of base)
   (field_force_required declaration || argument_required base) (argument_description base) (argument_bounds base) in
 match field_wire_type declaration observed with
 | Some description => Arguments.with_declaration description argument
 | None => argument end.
