From Stdlib Require Import String List.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
Import ListNotations.
Open Scope string_scope.
Definition reference_schema := [Field "name" KText; Field "revision" KText].
Definition reference_json (source : json) := JObject (map (fun name =>
 (name, match field name source with Some value => value | None => JNull end))
 (declared_names reference_schema)).
Definition same_reference (left right : json) :=
 Json.equal (reference_json left) (reference_json right).
