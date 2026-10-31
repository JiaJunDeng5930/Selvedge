From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema SchemaJson Arguments.
Import ListNotations.
Open Scope string_scope.

Module D := ArgumentDeclaration.
Definition image_byte_limit : N := 10485760.
Definition message_image_limit : nat := 4.
Definition detail_kind := KEnum "auto" ["low";"high"].
Definition mime_kind := KEnum "image/png" ["image/jpeg";"image/gif";"image/webp"].
Definition identifier_declaration := D.exact_lower_hex 64.
Definition asset_fields := [("id",true,identifier_declaration);("mime",true,D.Value mime_kind);
 ("bytes",true,D.Natural 1 image_byte_limit)].
Definition asset_declaration := D.Object asset_fields.
Definition reference_bytes := D.Union
 [D.Natural 1 image_byte_limit;D.NaturalText 1 (Some image_byte_limit)].
Definition reference_declaration := D.Object
 [("id",true,identifier_declaration);("mime",true,D.Value mime_kind);
  ("bytes",true,reference_bytes);("name",false,D.text);("path",false,D.text)].
Definition text_part_declaration := D.Object [("type",true,D.Const (JString "text"));("text",true,D.text)].
Definition image_part_declaration := D.Object [("type",true,D.Const (JString "image"));
 ("image",true,asset_declaration);("detail",false,D.Value detail_kind)].
Definition part_declaration := D.Union [text_part_declaration;image_part_declaration].
Definition content_declaration := D.Union [D.text;D.Array part_declaration].
Definition images_declaration := D.Array reference_declaration.
Definition fields_of source := match source with JObject fields => fields | _ => [] end.
Definition reference_schema := D.schema reference_declaration.
Definition content_schema := fields_of (D.schema content_declaration).
Definition images_schema := fields_of (D.schema images_declaration).
Definition native_argument_fields (command : string) :=
 if String.eqb command "create_work_task"
 then [("message",content_schema);("images",images_schema)] else [].
