From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema Utf8.
Import ListNotations.
Open Scope string_scope.

(** The external-tool protocol accepts a closed, bounded JSON Schema fragment.
    Unsupported keywords are rejected when the schema is registered. *)
Definition member (name : string) (names : list string) := existsb (String.eqb name) names.
Definition object_keys (source : json) (names : list string) :=
 match source with
 | JObject fields => unique_names (map fst fields) && forallb (fun field => member (fst field) names) fields
 | _ => false end.
Definition natural (value : json) := match value with
 | JNumber source => match Numbers.parse_natural source with
   | Some value => if N.leb value 4294967295 then Some value else None
   | None => None end
 | _ => None end.
Definition optional_text (value : option json) := match value with
 | None | Some (JString _) => true | _ => false end.
Definition optional_bound (value : option json) := match value with
 | None => true | Some value => match natural value with Some _ => true | _ => false end end.
Definition bound_or (value : option json) (fallback : N) :=
 match value with Some value => match natural value with Some value => value | None => fallback end | None => fallback end.
Definition bound_matches (schema : json) (value : N) :=
 N.leb (bound_or (field "minimum" schema) 0) value &&
 N.leb value (bound_or (field "maximum" schema) 4294967295).
Fixpoint strings (values : list json) : option (list string) :=
 match values with [] => Some [] | JString text :: rest => option_map (cons text) (strings rest) | _ => None end.
Definition enum_definition (source : option json) :=
 match source with
 | None => true
 | Some (JArray (_ :: _ as values)) => match strings values with
   | Some names => unique_names names && Nat.leb (List.length names) 256
   | None => false end
 | _ => false end.
Definition enum_accepts (schema : json) (value : json) :=
 match field "enum" schema with
 | None => true
 | Some (JArray values) => existsb (Json.equal value) values
 | _ => false end.
Definition required_valid (properties : list (string * json)) (source : option json) :=
 match source with None => true | Some (JArray values) =>
 match strings values with Some names => unique_names names &&
   forallb (fun name => member name (map fst properties)) names | None => false end
 | _ => false end.
Definition required_present (schema : json) (source : list (string * json)) :=
 match field "required" schema with
 | None => true
 | Some (JArray values) => forallb (fun value => match value with JString name =>
   match lookup name source with Some _ => true | None => false end | _ => false end) values
 | _ => false end.
Fixpoint definition_fuel (fuel : nat) (schema : json) : bool :=
 match fuel with O => false | S fuel =>
 match schema with
 | JObject fields =>
   optional_text (lookup "description" fields) && optional_text (lookup "title" fields) &&
   match lookup "anyOf" fields with
   | Some (JArray (_ :: _ as alternatives)) =>
     object_keys schema ["anyOf"; "description"; "title"] && forallb (definition_fuel fuel) alternatives
   | Some _ => false
   | None => match string_field "type" schema with
     | Some "object" =>
       object_keys schema ["type"; "description"; "title"; "properties"; "required"; "additionalProperties"] &&
       (match field "additionalProperties" schema with None | Some (JBool false) => true | _ => false end) &&
       match field "properties" schema with
       | Some (JObject properties) => unique_names (map fst properties) &&
         required_valid properties (field "required" schema) && forallb (fun property => definition_fuel fuel (snd property)) properties
       | _ => false end
     | Some "array" => object_keys schema ["type"; "description"; "title"; "items"] &&
       match field "items" schema with Some item => definition_fuel fuel item | None => false end
     | Some "string" => object_keys schema ["type"; "description"; "title"; "enum"] && enum_definition (field "enum" schema)
     | Some "integer" => object_keys schema ["type"; "description"; "title"; "minimum"; "maximum"] &&
       optional_bound (field "minimum" schema) && optional_bound (field "maximum" schema) &&
       N.leb (bound_or (field "minimum" schema) 0) (bound_or (field "maximum" schema) 4294967295)
     | Some "boolean" | Some "null" => object_keys schema ["type"; "description"; "title"]
     | _ => false end
   end
 | _ => false end end.
Fixpoint check_fuel (fuel : nat) (schema value : json) : bool :=
 match fuel with O => false | S fuel =>
 match field "anyOf" schema with
 | Some (JArray alternatives) => existsb (fun alternative => check_fuel fuel alternative value) alternatives
 | Some _ => false
 | None => match value with
   | JNull => match string_field "type" schema with Some "null" => true | _ => false end
   | JBool _ => match string_field "type" schema with Some "boolean" => true | _ => false end
   | JString text => match string_field "type" schema with Some "string" => Utf8.well_formed text && enum_accepts schema value | _ => false end
   | JNumber _ => match string_field "type" schema, natural value with
     | Some "integer", Some number => bound_matches schema number | _,_ => false end
   | JArray values => match string_field "type" schema, field "items" schema with
     | Some "array", Some item => forallb (check_fuel fuel item) values | _,_ => false end
   | JObject values => match string_field "type" schema, field "properties" schema with
     | Some "object", Some (JObject properties) => unique_names (map fst values) && required_present schema values &&
       forallb (fun value => match lookup (fst value) properties with
         | Some description => check_fuel fuel description (snd value) | None => false end) values
     | _,_ => false end
   end
 end end.
Definition definition := definition_fuel 256.
Definition valid (schema value : json) := definition schema && check_fuel 256 schema value.
