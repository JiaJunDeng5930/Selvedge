From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Utf8 TextJson.
From Selvedge.Kernel Require Import Conversation.
From Selvedge.Features Require Import Titles.
From Selvedge.Adapters Require Import Common Observation.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Inductive response_piece := Captured (text : json) | Skipped.
Definition extract (item : json) : option response_piece :=
  if String.eqb (str item "type") "text" then
    if is_text (get item "text") then Some (Captured (get item "text")) else None
  else if String.eqb (str item "type") "context" then
    let value := Conversation.provider_value (get item "value") in
    if String.eqb (str value "type") "reasoning" then Some Skipped
    else if String.eqb (str value "type") "message" && String.eqb (str value "role") "assistant" then
      match items (get value "content") with
      | [content] => if String.eqb (str content "type") "output_text"
                     then Some (Captured (get content "text")) else None
      | _ => None
      end
    else None
  else None.
Fixpoint extract_all (items : list json) : option (list json) :=
  match items with [] => Some [] | item::rest =>
    match extract item,extract_all rest with
    | Some Skipped,Some rest => Some rest
    | Some (Captured text),Some rest => Some (text::rest)
    | _,_ => None
    end
  end.
Definition response_text (approval : bool) (source : json) :=
  let limit := get source "limit" in
  if negb (bound limit 1 9007199254740991) then type_error
    (if approval then "Missing approval reason byte bound" else "Missing board response byte bound")
  else if negb (is_array (get source "items")) then type_error
    (if approval then "The approval reviewer returned no output" else "The drafting endpoint returned no output")
  else match extract_all (items (get source "items")) with
    | None => type_error (if approval then "The approval reviewer must return text without tool calls"
                         else "The drafting endpoint must return text without tool calls")
    | Some [JString text] =>
      if Utf8.well_formed text &&
        (N.of_nat (String.length text) <=? nat_value limit + if approval then 256 else 0)
      then success (JString text)
      else type_error (if approval then "The approval reviewer exceeded its response bound"
                       else "The drafting endpoint must return one bounded JSON response")
    | Some _ => type_error (if approval then "The approval reviewer must return exactly one decision"
                           else "The drafting endpoint must return one bounded JSON response")
    end.
Definition approval_outcome (source : json) :=
  match TextJson.parse_json (str source "text") with
  | Some (JObject [(_,JString _);(_,JString _)] as value) =>
    if exact_fields ["decision";"reason"] value &&
      existsb (String.eqb (str value "decision")) ["allow";"deny"] &&
      is_text (get value "reason") && Utf8.nonblank (str value "reason") &&
      Utf8.well_formed (str value "reason") && Utf8.no_nul (str value "reason") &&
      bound (get source "limit") (N.of_nat (String.length (str value "reason"))) 9007199254740991
    then success value
    else type_error "The approval reviewer returned a malformed decision"
  | _ => type_error "The approval reviewer must return exactly two string fields"
  end.
Definition task_text_outcome (source : json) :=
  match TextJson.parse_json (str source "text") with
  | None => type_error "The task text endpoint must return one JSON object"
  | Some value =>
    let capture := negb (String.eqb (str (get source "context") "kind") "task_title" ||
      boolean_field (get source "context") "retitle") in
    let fields := if capture then ["title";"description"] else ["title"] in
    if exact_fields fields value && is_text (get value "title") &&
      (negb capture || is_text (get value "description")) &&
      (N.of_nat (String.length (str value "title")) <=? Titles.response_title_bytes) &&
      Utf8.well_formed (str value "title") && Utf8.no_nul (str value "title") &&
      Utf8.well_formed (str value "description") && Utf8.no_nul (str value "description")
    then let title := Titles.normalize (str value "title") in
      if String.eqb title "" then type_error "The task text endpoint returned an empty title"
      else success (JObject [("title",JString title);("description",JString (str value "description"))])
    else type_error "The task text endpoint returned invalid title or description fields"
  end.
Definition request_task_text (source : json) :=
  let effect := get source "effect" in
  if existsb (String.eqb (str effect "kind")) ["board_text";"task_title"] && is_text (get effect "prompt") then
    if truthy (get (get effect "model") "adaptive_reasoning")
    then type_error "Task text generation requires an ordinary model profile" else success JNull
  else type_error "Expected a committed task text effect".
