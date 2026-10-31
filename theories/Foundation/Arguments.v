From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema SchemaJson JsonSchema.
From Selvedge.Foundation Require ArgumentDeclaration.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

(* Presence and nullability are independent JSON Schema facts. A primitive's
   optional text is omittable but non-null; a command's optional text retains
   its existing nullable value kind. *)
Inductive argument_type :=
| Scalar (value : kind)
| Structured (declaration : ArgumentDeclaration.t).
Record argument_spec := Argument {
  argument_name : string;
  argument_type_of : argument_type;
  argument_required : bool;
  argument_description : string
}.
Definition from_field (field : field_spec) := Argument
  (field_name field) (Scalar (field_kind field))
  (negb (field_omittable field || SchemaJson.optional_kind (field_kind field))) "".
Definition with_scalar (value : kind) (required : bool) (argument : argument_spec) := Argument
 (argument_name argument) (Scalar value) required (argument_description argument).
Definition with_description (description : string) (argument : argument_spec) := Argument
 (argument_name argument) (argument_type_of argument) (argument_required argument)
 description.
Definition omittable (argument : argument_spec) := Argument
 (argument_name argument) (argument_type_of argument) false
 (argument_description argument).
Definition omittable_nonnull (argument : argument_spec) :=
 match argument_type_of argument with
 | Scalar (KOptional value) => with_scalar value false argument
 | _ => argument
 end.
Definition with_declaration (declaration : ArgumentDeclaration.t) (argument : argument_spec) := Argument
 (argument_name argument) (Structured declaration) (argument_required argument)
 (argument_description argument).
Definition with_bounds (bounds : N * N) (argument : argument_spec) :=
 let bounded := ArgumentDeclaration.Natural (fst bounds) (snd bounds) in
 with_declaration (match argument_type_of argument with
 | Scalar (KOptional _) => ArgumentDeclaration.nullable bounded | _ => bounded end) argument.
Definition type_declaration (description : argument_type) := match description with
 | Scalar kind => ArgumentDeclaration.of_kind kind | Structured declaration => declaration end.
Definition type_valid (description : argument_type) :=
 ArgumentDeclaration.check (type_declaration description).
Definition argument_declaration (declaration : list argument_spec) := ArgumentDeclaration.Object
 (map (fun argument => (argument_name argument,argument_required argument,
   type_declaration (argument_type_of argument))) declaration).
Definition parsed_arguments (declaration : list argument_spec) :=
 ArgumentDeclaration.denote (argument_declaration declaration).
Definition decode_arguments (declaration : list argument_spec) :=
 ArgumentDeclaration.decode (argument_declaration declaration).
Definition encode_arguments (declaration : list argument_spec) :=
 ArgumentDeclaration.encode (argument_declaration declaration).
Definition valid (declaration : list argument_spec) (source : json) :=
 ArgumentDeclaration.present (decode_arguments declaration source).
Definition argument_json (argument : argument_spec) :=
 let source := match argument_type_of argument with
 | Scalar kind => JObject (SchemaJson.kind_schema kind)
 | Structured declaration => ArgumentDeclaration.schema declaration end in
 match source with
 | JObject original =>
 JObject (original ++ [("description",JString (argument_description argument))])%list
 | _ => source end.
Definition schema_fields (declaration : list argument_spec) := SchemaJson.object_fields
 (map (fun argument => (argument_name argument,argument_json argument)) declaration)
 (map argument_name (filter argument_required declaration)).

Definition json_schema declaration := JObject (schema_fields declaration).
