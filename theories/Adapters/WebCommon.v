From Stdlib Require Import String List Bool NArith Ascii.
From Selvedge.Foundation Require Import Json JsonObjects TextJson Utf8.
From Selvedge.Adapters Require Export Common.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition eq source key value := String.eqb (str source key) value.
Definition same := JsonObjects.equivalent.
Definition nonempty value := is_text value && negb (String.eqb (text value) "").
Definition natural := canonical_natural.
Definition check (accepted : bool) value message := if accepted then success value else err message.
Definition name_or_number value := if is_text value then text value else TextJson.render_json value.
Definition array_count source := N.of_nat (List.length (items source)).
Definition subset value keys := fold_right (fun key rest =>
  if has value key then (key,get value key)::rest else rest) [] keys.
Definition contains_name values key value := existsb (fun item => same (get item key) value) values.
Definition first_item values := match values with [] => JNull | item::_ => item end.
Definition nth_history values index := nth (N.to_nat index) values JNull.
Fixpoint wire value := match value with
  | JString source => Utf8.well_formed source
  | JArray values => forallb wire values
  | JObject fields => forallb (fun pair => Utf8.well_formed (fst pair) && wire (snd pair)) fields
  | _ => true end.
Inductive retirement := Active | Cancelled | ConfigurationChanged.
Definition retirement_code reason := number (match reason with Active => 0 | Cancelled => 1 | ConfigurationChanged => 2 end).
Definition retired_as reason record := same (retirement_code reason) (get record "retired").
Definition retirement_valid record := retired_as Active record || retired_as Cancelled record || retired_as ConfigurationChanged record.
Definition retirement_optional record := is_null record || retirement_valid record.
Definition base_source source := is_object source && wire source &&
  retirement_optional (get source "record") && retirement_optional (get source "previous") &&
  retirement_optional (get source "current").
Definition owner_value effect := JString (if eq effect "kind" "model"
  then "task:" ++ name_or_number (get effect "task_id")
  else str effect "kind" ++ ":" ++ name_or_number (if is_null (get effect "task_id")
    then get effect "card_id" else get effect "task_id") ++ ":" ++ name_or_number (get effect "ticket")).
Definition owner source := success (owner_value (get source "effect")).
Definition receipt_tag value := eq value "type" "provider_receipt" && eq value "provider" "chatgpt-web".
Fixpoint receipt_index history offset latest := match history with [] => latest | item::rest =>
  receipt_index rest (offset+1) (if eq item "role" "model_context" && receipt_tag (get item "content")
    then number offset else latest) end.
Definition position source :=
  let effect := get source "effect" in
  let index := if eq effect "kind" "model" then receipt_index (items (get effect "history")) 0 JNull else JNull in
  success (JObject [("position",if is_null index then JNumber "-1" else index);
    ("input_count",if is_null index then JNull else get (get
      (nth_history (items (get effect "history")) (nat_value index)) "content") "input_count")]).
Definition replacement_suffix effect := if eq effect "kind" "model" then
  match Common.natural (get effect "context_replacement_source") with
  | Some index => ":context:" ++ decimal index | None => "" end else "".
Definition successor_body id input := JObject [("previous_response_id",id);("input",JArray input);("stream",JBool true)].
(* DEFENSE: Protocol JSON may contain duplicate members or unpaired Unicode
   escapes. These violate the domain contract even when JSON syntax parses. *)
Definition domain_json_failure source :=
  match TextJson.json_value (S (String.length source)) source with
  | TextJson.Invalid reason => existsb (String.eqb reason)
      ["Duplicate object key";"Unpaired Unicode surrogate";"Invalid Unicode scalar"]
  | _ => false
  end.
Definition decode_text source := match TextJson.parse_json source with
  | Some value => success value
  | None => if domain_json_failure source
      then err "Invalid ChatGPT Web JSON: duplicate object field or malformed Unicode"
      else failure "SyntaxError" "Invalid ChatGPT Web JSON" end.
