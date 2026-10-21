From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json Schema.
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
Definition object_schema (properties : list (string * json)) (required : list string) :=
  JObject [("type",JString "object");("additionalProperties",JBool false);
    ("properties",JObject properties);("required",JArray (map JString required))].
Definition schema_json (declaration : schema) := object_schema
  (map (fun f => (f.(field_name),JObject (kind_schema f.(field_kind)))) declaration)
  (map field_name (filter (fun f => negb (optional_kind f.(field_kind))) declaration)).
