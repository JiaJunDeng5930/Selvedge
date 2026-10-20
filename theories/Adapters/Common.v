From Stdlib Require Import String List Bool NArith Ascii DecimalString.
From Selvedge.Foundation Require Export Json Numbers.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

(** Absent optional JSON fields are represented by null at the external boundary. *)
Definition get (source : json) (name : string) : json :=
  match field name source with Some value => value | None => JNull end.
Definition text (value : json) : string :=
  match value with JString value => value | _ => "" end.
Definition flag (value : json) : bool :=
  match value with JBool value => value | _ => false end.
Definition items (value : json) : list json :=
  match value with JArray values => values | _ => [] end.
Definition object_fields (value : json) : list (string * json) :=
  match value with JObject fields => fields | _ => [] end.
Definition has (source : json) (name : string) : bool :=
  match field name source with Some _ => true | None => false end.
Definition is_object := Json.is_object.
Definition is_text := Json.is_string.
Definition is_array := Json.is_array.
Definition set (source : json) (name : string) (value : json) : json :=
  JObject (set_field name value (object_fields source)).
Definition without (source : json) (name : string) : json :=
  JObject (remove_field name (object_fields source)).
Definition err (message : string) := failure "Error" message.
Definition type_error (message : string) := failure "TypeError" message.
Definition range_error (message : string) := failure "RangeError" message.

Definition natural (value : json) : option N :=
  match value with JNumber source => parse_natural source | _ => None end.
Definition decimal := show_natural.
Definition number (value : N) := JNumber (decimal value).
Definition nat_value (value : json) : N := match natural value with Some n => n | None => 0 end.
Definition num (source : json) (name : string) := nat_value (get source name).
Definition str (source : json) (name : string) := text (get source name).
Definition boolean_field (source : json) (name : string) := flag (get source name).
Definition canonical_natural (value : json) : bool :=
  match natural value, value with
  | Some n, JNumber source => String.eqb source (decimal n) && (n <=? 9007199254740991)
  | _, _ => false
  end.
Definition starts (source prefix : string) := starts_with prefix source.
Definition truthy (value : json) : bool :=
  match value with
  | JNull => false
  | JBool value => value
  | JString value => negb (String.eqb value "")
  | JNumber value => negb (String.eqb value "0" || String.eqb value "-0")
  | _ => true
  end.
Definition diagnostic (value : json) : string :=
  match value with
  | JNull => "null"
  | JBool true => "true"
  | JBool false => "false"
  | JString value | JNumber value => value
  | JObject _ => "[object Object]"
  | JArray _ => "[invalid diagnostic observation]"
  end.
Definition optional (present : bool) (key : string) (value : json) :=
  if present then [(key,value)] else [].
