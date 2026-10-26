From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema SchemaJson Arguments.
From Selvedge.Kernel Require Import Images.
Import ListNotations.
Open Scope string_scope.

Module D := ArgumentDeclaration.
Definition asset_declaration := D.refine_object [("bytes",D.Natural 1 Images.image_byte_limit)]
 (D.of_schema Images.asset_schema).
Definition reference_declaration := D.refine_object
 [("bytes",D.Union [D.Natural 1 Images.image_byte_limit;D.text])]
 (D.of_schema Images.reference_schema).
Definition part_declaration := D.Union [D.of_schema Images.text_part_schema;
 D.refine_object [("image",asset_declaration)] (D.of_schema Images.image_part_schema)].
Definition content_declaration := D.Union [D.text;D.Array part_declaration].
Definition images_declaration := D.Array reference_declaration.
Definition fields_of source := match source with JObject fields => fields | _ => [] end.
Definition reference_schema := D.schema reference_declaration.
Definition content_schema := fields_of (D.schema content_declaration).
Definition images_schema := fields_of (D.schema images_declaration).
Definition native_argument_fields (command : string) :=
 if String.eqb command "create_work_task"
 then [("message",content_schema);("images",images_schema)] else [].
