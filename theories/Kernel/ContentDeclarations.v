From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema SchemaJson Arguments.
From Selvedge.Kernel Require Import Images.
Import ListNotations.
Open Scope string_scope.

(* The model sees the same field declarations and image bounds as the real
   content parser. Digest membership and the combined image count remain
   runtime admission rules; these schemas describe the structural contract. *)
Definition asset_arguments := map (fun field =>
 let argument := Arguments.from_field field in
 if String.eqb (field_name field) "bytes"
 then Arguments.with_bounds (1,Images.image_byte_limit) argument else argument) Images.asset_schema.
Definition stored_size_schema := [("anyOf",JArray
 [Arguments.argument_json (Argument "bytes" (Scalar KNatural) true "Stored image size"
   (Some (1,Images.image_byte_limit))); JObject (SchemaJson.kind_schema KText)])].
Definition reference_arguments := map (fun field =>
 let argument := Arguments.omittable_nonnull (Arguments.from_field field) in
 if String.eqb (field_name field) "bytes"
 then Arguments.with_structure stored_size_schema argument else argument) Images.reference_schema.
Definition reference_schema := Arguments.json_schema reference_arguments.
Definition part_schema := JObject [("anyOf",JArray
 [SchemaJson.schema_json Images.text_part_schema;
  Arguments.json_schema (Arguments.refine_fields
   [("image",Arguments.schema_fields asset_arguments)]
   (map (fun field => Arguments.omittable_nonnull (Arguments.from_field field)) Images.image_part_schema))])].
Definition content_schema := [("anyOf",JArray
 [JObject (SchemaJson.kind_schema KText);
  JObject [("type",JString "array");("items",part_schema)]])].
Definition images_schema := [("type",JString "array");("items",reference_schema)].
Definition native_argument_fields (command : string) :=
 if String.eqb command "create_work_task"
 then [("message",content_schema);("images",images_schema)] else [].
