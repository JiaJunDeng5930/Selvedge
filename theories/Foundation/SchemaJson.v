From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema JsonSchema Numbers.
Import ListNotations.
Open Scope string_scope.

Fixpoint kind_schema (kind : kind) : list (string * json) :=
  match kind with
  | KText => [("type",JString "string")]
  | KBool => [("type",JString "boolean")]
  | KNatural => [("type",JString "integer");("minimum",JNumber "0")]
  | KInteger => [("type",JString "integer")]
  | KDecimal => [("type",JString "number")]
  | KJson => []
  | KArray element => [("type",JString "array");("items",JObject (kind_schema element))]
  | KOptional element => [("anyOf",JArray [JObject (kind_schema element);JObject [("type",JString "null")]])]
  | KEnum first rest => [("type",JString "string");("enum",JArray (map JString (first::rest)))]
  end.
Definition optional_kind kind := match kind with KOptional _ => true | _ => false end.
Definition object_fields (properties : list (string * json)) (required : list string) :=
  [("type",JString "object");("additionalProperties",JBool false);
    ("properties",JObject properties);("required",JArray (map JString required))].
Definition object_schema properties required := JObject (object_fields properties required).
Definition present_kind (description : kind) := match description with
 | KOptional value => value | _ => description end.
Definition present_schema (description : kind) :=
 let description := present_kind description in
 match description with
 | KNatural => (kind_schema description ++
   [("maximum",JNumber (Numbers.show_natural JsonSchema.maximum_natural))])%list
 | _ => kind_schema description
 end.
Definition schema_fields_with (describe : kind -> list (string * json)) (declaration : schema) := object_fields
  (map (fun f => (f.(field_name),JObject (describe f.(field_kind)))) declaration)
  (map field_name (filter (fun f => negb (optional_kind f.(field_kind))) declaration)).
Definition schema_fields := schema_fields_with kind_schema.
Definition omittable_fields := schema_fields_with present_schema.
Definition schema_json declaration := JObject (schema_fields declaration).
