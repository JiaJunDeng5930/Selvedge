From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
From Selvedge.Foundation Require Import SchemaJson.
From Selvedge.Programming Require Import Arguments.
From Selvedge.Foundation Require Import Numbers RemoteIdentity.
From Selvedge.Programming Require ArgumentDeclaration.
From Selvedge.Kernel Require Import Domain Codec ContentDeclarations ChatgptArguments.
From Selvedge.Features Require Import Titles BoardParameters TaskGraphDeclarations ConnectionGrants.
From Selvedge.Features Require Domain.
From Selvedge.Programming Require Import CommandFields.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module D := ArgumentDeclaration.

Definition identity := D.Natural 0 4294967295.
Definition workspace_declaration := Codec.workspace_declaration.
Definition sandbox_declaration := Codec.sandbox_declaration.
Definition sandbox_patch_declaration := Codec.sandbox_patch_declaration.
Definition approval_declaration := Codec.approval_declaration.
Definition guidance_declaration := Codec.guidance_declaration.
Definition binding_declaration := Codec.binding_declaration.
Definition settings_declaration := Codec.settings_declaration.
Definition content_declaration := ContentDeclarations.content_declaration.
Definition images_declaration := ContentDeclarations.images_declaration.
Definition attachments_declaration := BoardParameters.attachments_declaration.
Definition title_prompt_declaration := Titles.instruction_declaration.
Definition controller_id_declaration := RemoteIdentity.controller_declaration.
Definition permissions_declaration := D.of_schema Selvedge.Features.Domain.rights_fields.
Definition grants_declaration := ConnectionGrants.declaration.

Definition graph_node_declaration (observed : bool) :=
 TaskGraphDeclarations.node_declaration identity (settings_declaration observed).
Definition graph_rule_declaration := TaskGraphDeclarations.rule_declaration.
Definition graph_nodes_declaration observed := D.BoundedArray 0 32 (graph_node_declaration observed).
Definition graph_rules_declaration := D.BoundedArray 0 32 graph_rule_declaration.
Definition board_status := BoardParameters.stage_declaration.
Definition board_assignee := BoardParameters.owner_declaration.
Definition board_project := BoardParameters.project_declaration.
Definition board_clock := BoardParameters.clock_declaration.
Definition board_priority := BoardParameters.priority_declaration.

Definition u32 (field : field_declaration) := typed identity field.
Definition optional_identity_text (field : field_declaration) := typed board_project field.
