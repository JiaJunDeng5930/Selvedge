From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema JsonSchema Numbers.
Import ListNotations.
Open Scope string_scope.

Definition kind_schema := Schema.kind_schema.
Definition optional_kind := Schema.optional_kind.
Definition object_fields (properties : list (string * json)) (required : list string) :=
  [("type",JString "object");("additionalProperties",JBool false);
    ("properties",JObject properties);("required",JArray (map JString required))].
Definition object_schema properties required := JObject (object_fields properties required).
Definition present_kind := Schema.present_kind.
Definition present_schema (description : kind) :=
 let description := present_kind description in
 match description with
 | KNatural => (kind_schema description ++
   [("maximum",JNumber (Numbers.show_natural JsonSchema.maximum_natural))])%list
 | _ => kind_schema description
 end.
Definition schema_fields_with (describe : kind -> list (string * json)) (declaration : schema) := object_fields
  (map (fun f => (f.(field_name),JObject (describe f.(field_kind)))) declaration)
  (map field_name (filter (fun f => negb (f.(field_omittable) || optional_kind f.(field_kind))) declaration)).
Definition schema_fields := schema_fields_with kind_schema.
Definition omittable_fields := schema_fields_with present_schema.
Definition schema_json declaration := JObject (schema_fields declaration).
