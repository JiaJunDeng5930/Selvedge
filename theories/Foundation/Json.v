From Stdlib Require Import String List Bool Ascii NArith.
Import ListNotations.
Open Scope string_scope.

(** Text is UTF-8 bytes. A number retains its exact JSON source spelling. *)
Inductive json : Type :=
| JNull
| JBool (value : bool)
| JNumber (decimal : string)
| JString (value : string)
| JArray (values : list json)
| JObject (fields : list (string * json)).

Fixpoint lookup (name : string) (fields : list (string * json)) : option json :=
  match fields with
  | [] => None
  | (key, value) :: rest =>
      if String.eqb name key then Some value else lookup name rest
  end.

Definition field (name : string) (source : json) : option json :=
  match source with JObject fields => lookup name fields | _ => None end.
Definition as_string (value : json) : option string :=
  match value with JString text => Some text | _ => None end.
Definition as_bool (value : json) : option bool :=
  match value with JBool boolean => Some boolean | _ => None end.
Definition as_number (value : json) : option string :=
  match value with JNumber decimal => Some decimal | _ => None end.
Definition as_array (value : json) : option (list json) :=
  match value with JArray values => Some values | _ => None end.
Definition as_object (value : json) : option (list (string * json)) :=
  match value with JObject fields => Some fields | _ => None end.
Definition string_field (name : string) (source : json) : option string :=
  match field name source with Some value => as_string value | None => None end.
Definition bool_field (name : string) (source : json) : option bool :=
  match field name source with Some value => as_bool value | None => None end.
Definition number_field (name : string) (source : json) : option string :=
  match field name source with Some value => as_number value | None => None end.
Definition array_field (name : string) (source : json) : option (list json) :=
  match field name source with Some value => as_array value | None => None end.

Definition success (value : json) : json :=
  JObject [("ok", JBool true); ("value", value)].
Definition failure (code message : string) : json :=
  JObject [("ok", JBool false); ("code", JString code); ("error", JString message)].

Fixpoint remove_field (name : string) (fields : list (string * json)) :=
  match fields with
  | [] => []
  | (key,value) :: rest =>
      if String.eqb name key then remove_field name rest
      else (key,value) :: remove_field name rest
  end.
Definition set_field (name : string) (value : json) (fields : list (string * json)) :=
  (name,value) :: remove_field name fields.

Definition has_field (name : string) (source : json) : bool :=
  match field name source with Some _ => true | None => false end.
Definition is_object (source : json) : bool := match source with JObject _ => true | _ => false end.
Definition is_array (source : json) : bool := match source with JArray _ => true | _ => false end.
Definition is_string (source : json) : bool := match source with JString _ => true | _ => false end.
Definition is_number (source : json) : bool := match source with JNumber _ => true | _ => false end.
Definition is_bool (source : json) : bool := match source with JBool _ => true | _ => false end.
Definition is_null (source : json) : bool := match source with JNull => true | _ => false end.
Definition starts_with (beginning text : string) : bool := String.prefix beginning text.
Definition substring (start length : nat) (text : string) := String.substring start length text.

Fixpoint equal (lhs rhs : json) : bool :=
  match lhs, rhs with
  | JNull, JNull => true
  | JBool lhs, JBool rhs => Bool.eqb lhs rhs
  | JNumber lhs, JNumber rhs | JString lhs, JString rhs => String.eqb lhs rhs
  | JArray lhs, JArray rhs =>
      (fix values_equal lhs rhs :=
        match lhs, rhs with
        | [], [] => true
        | x :: xs, y :: ys => equal x y && values_equal xs ys
        | _, _ => false end) lhs rhs
  | JObject lhs, JObject rhs =>
      (fix fields_equal lhs rhs :=
        match lhs, rhs with
        | [], [] => true
        | (k,x) :: xs, (l,y) :: ys => String.eqb k l && equal x y && fields_equal xs ys
        | _, _ => false end) lhs rhs
  | _, _ => false
  end.
