From Stdlib Require Import String List Bool NArith Ascii.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

(** Plans refer to opaque host values by coordinates; Unicode code units and
    numeric observations are the only information used for admission. *)
Definition kind (value : json) (expected : string) := String.eqb (str value "kind") expected.
Fixpoint units_equal (units : list json) (expected : string) :=
  match units, expected with
  | [], EmptyString => true
  | JNumber code :: rest, String character tail =>
      String.eqb code (decimal (N.of_nat (nat_of_ascii character))) && units_equal rest tail
  | _, _ => false
  end.
Definition equal_text (value : json) (expected : string) :=
  kind value "string" && units_equal (items (get value "units")) expected.
Fixpoint find_field (entries : list json) (name : string) :=
  match entries with
  | [] => JNull
  | entry::rest => if equal_text (get entry "key") name then get entry "value" else find_field rest name
  end.
Definition observed_field (value : json) (name : string) := find_field (items (get value "fields")) name.
Definition present (value : json) := negb (is_null value).
Definition defined (value : json) := present value && negb (kind value "undefined").
Definition nullish (value : json) := negb (defined value) || kind value "null".
Definition reference (value : json) := JObject [("ref",get value "ref")].
Definition literal (value : json) := JObject [("literal",value)].
Definition selected (value fallback : json) := if present value then reference value else literal fallback.
Definition plan_field (name : string) (value : json) := JObject [("key",JString name);("value",value)].
Definition plan_object (base : option json) (fields : list json) :=
  JObject (optional (match base with Some _ => true | None => false end) "base"
    (match base with Some value => value | None => JNull end) ++ [("fields",JArray fields)]).
Definition plan_error (code : string) (parts : list json) :=
  JObject [("error",JArray parts);("code",JString code)].
Definition invalid (message : string) := plan_error "TypeError" [literal (JString message)].
Definition has_error (plan : json) := has plan "error".
Definition bound (value : json) (lower upper : N) :=
  match natural value with Some n => (lower <=? n) && (n <=? upper) | None => false end.
Definition observed_bound (value : json) (lower upper : N) :=
  kind value "number" && bound (get value "number") lower upper.
Definition optional_bound (value : json) (lower upper : N) :=
  negb (defined value) || observed_bound value lower upper.
Definition code_range (value : json) (lower upper : N) := bound value lower upper.
Definition alpha (value : json) := code_range value 65 90 || code_range value 97 122.
Definition digit (value : json) := code_range value 48 57.
Definition code (value : json) (expected : N) :=
  match natural value with Some n => N.eqb n expected | None => false end.
Definition whitespace (value : json) :=
  code_range value 9 13 || code value 32 || code value 160 || code value 5760 ||
  code_range value 8192 8202 || code value 8232 || code value 8233 || code value 8239 ||
  code value 8287 || code value 12288 || code value 65279.
Definition nonempty (value : json) := kind value "string" && existsb (fun u => negb (whitespace u)) (items (get value "units")).
Definition identifier_tail (u : json) := alpha u || digit u || code u 46 || code u 95 || code u 47 || code u 45.
Definition variable_tail (u : json) := alpha u || digit u || code u 95.
Definition identifier (value : json) :=
  kind value "string" && match items (get value "units") with
  | [] => false
  | head::rest => (alpha head || digit head) && forallb identifier_tail rest && (N.of_nat (List.length rest) <=? 127)
  end.
Definition variable (value : json) :=
  kind value "string" && match items (get value "units") with
  | [] => false
  | head::rest => (alpha head || code head 95) && forallb variable_tail rest
  end.
Definition plugin_name (value : json) :=
  kind value "string" && match items (get value "units") with
  | [] => false
  | head::rest => alpha head && forallb variable_tail rest && (N.of_nat (List.length rest) <=? 63)
  end.
Definition allowed (names : list string) (value : json) := existsb (equal_text value) names.
Fixpoint unknown (names : list string) (fields : list json) :=
  match fields with [] => JNull | entry::rest =>
    if allowed names (get entry "key") then unknown names rest else get entry "key" end.
Definition fields_only (names : list string) (value : json) :=
  kind value "object" && is_null (unknown names (items (get value "fields"))).
Definition plain_fields_only (names : list string) (value : json) :=
  is_object value && forallb (fun entry => existsb (String.eqb (fst entry)) names) (object_fields value).
Definition observed_strings (value : json) :=
  kind value "array" && forallb (fun x => kind x "string") (items (get value "items")).
Definition optional_text (value : json) := negb (defined value) || nonempty value.
Definition optional_strings (value : json) := negb (defined value) || observed_strings value.
Definition environment (value : json) :=
  negb (defined value) || (kind value "object" && forallb (fun entry =>
    variable (get entry "key") && kind (get entry "value") "string") (items (get value "fields"))).
Definition same_units (left right : json) :=
  kind left "string" && kind right "string" &&
    let a := items (get left "units") in let b := items (get right "units") in
    Nat.eqb (List.length a) (List.length b) &&
    forallb (fun pair => N.eqb (nat_value (fst pair)) (nat_value (snd pair))) (combine a b).
Definition member_text (values : list json) (value : json) := existsb (fun x => same_units x value) values.

Definition exact_fields (names : list string) (value : json) :=
  match value with
  | JObject fields => Nat.eqb (List.length names) (List.length fields) &&
      forallb (fun name => has value name) names && plain_fields_only names value
  | _ => false
  end.
