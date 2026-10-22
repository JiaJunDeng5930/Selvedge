From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema SchemaJson JsonSchema.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

(* Presence and nullability are independent JSON Schema facts. A primitive's
   optional text is omittable but non-null; a command's optional text retains
   its existing nullable value kind. *)
Inductive argument_type :=
| Scalar (value : kind)
| Structured (fields : list (string * json)).
Record argument_spec := Argument {
  argument_name : string;
  argument_type_of : argument_type;
  argument_required : bool;
  argument_description : string;
  argument_bounds : option (N * N)
}.
Definition from_field (field : field_spec) := Argument
  (field_name field) (Scalar (field_kind field)) (negb (SchemaJson.optional_kind (field_kind field))) "" None.
Definition with_scalar (value : kind) (required : bool) (argument : argument_spec) := Argument
 (argument_name argument) (Scalar value) required (argument_description argument) (argument_bounds argument).
Definition with_description (description : string) (argument : argument_spec) := Argument
 (argument_name argument) (argument_type_of argument) (argument_required argument)
 description (argument_bounds argument).
Definition omittable (argument : argument_spec) := Argument
 (argument_name argument) (argument_type_of argument) false
 (argument_description argument) (argument_bounds argument).
Definition omittable_nonnull (argument : argument_spec) :=
 match argument_type_of argument with
 | Scalar (KOptional value) => with_scalar value false argument
 | _ => argument
 end.
Definition with_bounds (bounds : N * N) (argument : argument_spec) := Argument
  (argument_name argument) (argument_type_of argument) (argument_required argument)
  (argument_description argument) (Some bounds).
Definition with_structure (description : list (string * json)) (argument : argument_spec) := Argument
 (argument_name argument) (Structured description) (argument_required argument)
 (argument_description argument) (argument_bounds argument).
Definition refine_fields (overrides : list (string * list (string * json)))
 (declaration : list argument_spec) := map (fun argument =>
 match find (fun entry => String.eqb (argument_name argument) (fst entry)) overrides with
 | Some (_,fields) => with_structure fields argument | None => argument end) declaration.
Definition type_valid (description : argument_type) (value : json) := match description with
 | Scalar kind => match Schema.decode_value kind value with Some _ => true | None => false end
 | Structured fields => JsonSchema.valid (JObject fields) value
 end.
Definition type_schema (description : argument_type) := match description with
 | Scalar kind => SchemaJson.kind_schema kind
 | Structured fields => fields
 end.
Definition shape_kind (description : argument_type) := match description with
 | Scalar kind => kind | Structured _ => KJson end.
Definition argument_schema (declaration : list argument_spec) : schema :=
 map (fun argument => Field (argument_name argument)
   (if argument_required argument then shape_kind (argument_type_of argument) else KOptional (shape_kind (argument_type_of argument)))) declaration.
Definition numeric_bounds (value : json) (bounds : N * N) :=
 match as_number value with Some text => match parse_natural text with
 | Some n => (fst bounds <=? n) && (n <=? snd bounds) | None => false end | None => false end.
Definition argument_valid (source : json) (argument : argument_spec) :=
 match field (argument_name argument) source with
 | None => negb (argument_required argument)
 | Some value => if type_valid (argument_type_of argument) value then match value, argument_bounds argument with
     | JNull,_ | _,None => true
     | _,Some bounds => numeric_bounds value bounds
     end else false
 end.
Definition valid (declaration : list argument_spec) (source : json) :=
 match Schema.decode (argument_schema declaration) source with
 | None => false
 | Some _ => forallb (argument_valid source) declaration
 end.
Definition argument_json (argument : argument_spec) :=
 let fields := (type_schema (argument_type_of argument) ++
   [("description",JString (argument_description argument))])%list in
 JObject (match argument_bounds argument with
 | None => fields
 | Some (minimum,maximum) => set_field "minimum" (JNumber (show_natural minimum))
     (set_field "maximum" (JNumber (show_natural maximum)) fields)
 end).
Definition schema_fields (declaration : list argument_spec) := SchemaJson.object_fields
 (map (fun argument => (argument_name argument,argument_json argument)) declaration)
 (map argument_name (filter argument_required declaration)).

Definition json_schema declaration := JObject (schema_fields declaration).
