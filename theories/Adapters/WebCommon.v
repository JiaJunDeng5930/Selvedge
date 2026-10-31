From Stdlib Require Import String List Bool NArith Ascii.
From Selvedge.Foundation Require Import Json JsonObjects TextJson Utf8 CallWire.
From Selvedge.Programming Require ArgumentDeclaration DeclarationFields ObjectMethod.
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
Module D := ArgumentDeclaration.
Module O := ObjectMethod.
Definition missing (value : option json) := match value with Some value => value | None => JNull end.
Definition member fields name := missing (Json.lookup name fields).
Definition member_text fields name := text (member fields name).
Definition member_subset fields keys := fold_right (fun key rest =>
  match Json.lookup key fields with Some value => (key,value)::rest | None => rest end) [] keys.
Definition required := DeclarationFields.required.
Definition raw (name : string) := DeclarationFields.optional name D.Any.
Definition safe_natural := D.Natural 0 9007199254740991.
Definition project fields {result : Set} (handler : O.arguments fields result)
 (values : D.denote (D.OpenObject fields)) := O.apply fields handler (proj1_sig values).
Inductive retirement := Active | Cancelled | ConfigurationChanged.
Definition retirement_code reason := number (match reason with Active => 0 | Cancelled => 1 | ConfigurationChanged => 2 end).
Definition retirement_declaration := D.Union (map (fun reason => D.Const (retirement_code reason))
  [Active;Cancelled;ConfigurationChanged]).
Definition retirement_value (value : D.denote retirement_declaration) : retirement :=
 match value with inl _ => Active | inr (inl _) => Cancelled | inr (inr (inl _)) => ConfigurationChanged
 | inr (inr (inr impossible)) => match impossible with end end.
Record stored_request := StoredRequest { stored_fields : list (string * json); stored_retirement : retirement }.
Definition stored_json value := JObject (("retired",retirement_code value.(stored_retirement))::
  Json.remove_field "retired" value.(stored_fields)).
(** Persisted retirement is decoded only where it determines request reuse.
    The encoder derives its wire value from that same state. *)
Definition read_stored value : option stored_request := match value with
 | JObject fields => option_map (StoredRequest (Json.remove_field "retired" fields))
     (option_map retirement_value (D.decode retirement_declaration (member fields "retired")))
 | _ => None end.
Definition optional_stored value : option (option stored_request) := match value with
 | JNull => Some None | _ => option_map Some (read_stored value) end.
Definition stored_as reason value := match reason,value.(stored_retirement) with
 | Active,Active | Cancelled,Cancelled | ConfigurationChanged,ConfigurationChanged => true | _,_ => false end.
Definition stored_member value name := member value.(stored_fields) name.
Definition owner_parts kind task card ticket := JString (if String.eqb kind "model"
  then "task:" ++ name_or_number task
  else kind ++ ":" ++ name_or_number (if is_null task then card else task) ++ ":" ++ name_or_number ticket).
Definition owner_value effect := owner_parts (member_text effect "kind") (member effect "task_id")
  (member effect "card_id") (member effect "ticket").
Definition owner effect := success (owner_value effect).
Definition receipt_tag value := eq value "type" "provider_receipt" && eq value "provider" "chatgpt-web".
Fixpoint receipt_index history offset latest := match history with [] => latest | item::rest =>
  receipt_index rest (offset+1) (if eq item "role" "model_context" && receipt_tag (get item "content")
    then number offset else latest) end.
Definition cursor kind history := if String.eqb kind "model" then receipt_index history 0 JNull else JNull.
Definition position kind history :=
  let index := cursor kind history in
  success (JObject [("position",if is_null index then JNumber "-1" else index);
    ("input_count",if is_null index then JNull else get (get
      (nth_history history (nat_value index)) "content") "input_count")]).
Definition replacement_suffix kind replacement := if String.eqb kind "model" then
  match Common.natural replacement with
  | Some index => ":context:" ++ decimal index | None => "" end else "".
Definition successor_body id input := JObject [("previous_response_id",id);("input",JArray input);("stream",JBool true)].
(* DEFENSE: Protocol JSON may contain duplicate members or unpaired Unicode
   escapes. These violate the domain contract even when JSON syntax parses. *)
Definition domain_json_failure_at nesting source :=
  match TextJson.json_value_at true (S (String.length source)) nesting source with
  | TextJson.Invalid reason => existsb (String.eqb reason)
      ["Duplicate object key";"Unpaired Unicode surrogate";"Invalid Unicode scalar"]
  | _ => false
  end.
Definition domain_json_failure source :=
  domain_json_failure_at (S (String.length source)) source.
Definition decode_text source := match TextJson.parse_json source with
  | Some value => success value
  | None => if domain_json_failure source
      then err "Invalid ChatGPT Web JSON: duplicate object field or malformed Unicode"
      else failure "SyntaxError" "Invalid ChatGPT Web JSON" end.

(* Provider arguments are the only protocol subtree whose member occurrences
   belong to the tool admission. Encode them before the host sees an object. *)
Definition provider_arguments_valid resource := forallb (fun call =>
  if eq call "type" "function_call" then
    is_object (get call "arguments") && negb (has call "arguments_json")
  else true) (items (get resource "output")).
Definition provider_call_wire call :=
  if eq call "type" "function_call" then JObject (map (fun field =>
    if String.eqb (fst field) "arguments" then
      ("arguments_json",JString (TextJson.render_json (snd field))) else field)
    (object_fields call)) else call.
Definition provider_resource_wire resource := JObject (map (fun field =>
  if String.eqb (fst field) "output" then
    (match snd field with JArray values => (fst field,JArray (map provider_call_wire values))
      | _ => field end) else field)
  (object_fields resource)).
Definition provider_json_wire value :=
  if eq value "object" "web.response" then
    if provider_arguments_valid value then Some (provider_resource_wire value) else None
  else if is_object (get value "response") then
    if provider_arguments_valid (get value "response") then Some (JObject (map (fun field =>
      if String.eqb (fst field) "response" then (fst field,provider_resource_wire (snd field)) else field)
      (object_fields value))) else None
  else Some value.
(* SSE wraps the response in one additional object. The bounded raw parse
   allows that envelope; tool admission applies the callback argument budget. *)
Definition parse_provider_json source :=
  match TextJson.parse_json_members_at (S TextJson.input_nesting) source with
  | Some value => match provider_json_wire value with
    | Some encoded => TextJson.parse_json (TextJson.render_json encoded)
    | None => None end
  | None => None end.
Definition decode_provider_text source := match parse_provider_json source with
  | Some value => success value
  | None => if domain_json_failure_at (S TextJson.input_nesting) source
      then err "Invalid ChatGPT Web JSON: duplicate object field or malformed Unicode"
      else failure "SyntaxError" "Invalid ChatGPT Web JSON" end.
