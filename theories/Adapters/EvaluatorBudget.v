From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson JsonObjects.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition checked (valid : bool) value code message := if valid then success value else failure code message.
Definition omission := String (Ascii.ascii_of_nat 10) "[Tool output preview: middle omitted]" ++ String (Ascii.ascii_of_nat 10) "".
Definition tool_output_tokens : N := 1000.
Definition response_bytes : N := 65536.
Definition request_bytes : N := 2100000.
Definition request_tokens : N := 28000.
Definition contract := JObject [("tool_output_tokens",number tool_output_tokens);("response_bytes",number response_bytes);
  ("request_bytes",number request_bytes);("request_tokens",number request_tokens);("omission",JString omission)].
Definition action name := JObject [("action",JString name)].
Definition ends source suffix := starts (substring (String.length source - String.length suffix) (String.length suffix) source) suffix &&
  Nat.leb (String.length suffix) (String.length source).
Definition bounded value maximum := canonical_natural value && (nat_value value <=? maximum).
Fixpoint entries_valid entries index := match entries with [] => true | entry::rest =>
  JsonObjects.equivalent (get entry "index") (number index) && bounded (get entry "cost") 9007199254740991 &&
  (boolean_field (get entry "text") "truthy" || JsonObjects.equivalent (get entry "cost") (number 0)) && entries_valid rest (index+1) end.
Definition cost_sum entries := fold_left (fun sum entry => sum + num entry "cost") entries 0.
Fixpoint insert_cost entry entries := match entries with [] => [entry] | first::rest =>
  if num entry "cost" <=? num first "cost" then entry::first::rest else first::insert_cost entry rest end.
Fixpoint positive_order entries := match entries with [] => [] | first::rest =>
  let tail := positive_order rest in if 0 <? num first "cost" then insert_cost first tail else tail end.
Fixpoint allocate entries remaining count := match entries with [] => [] | entry::rest =>
  let budget := N.min (num entry "cost") (remaining / count) in
  JObject [("index",get entry "index");("budget",number budget)]::allocate rest (remaining-budget) (count-1) end.
Definition allocation_for allocations index := match find (fun a => JsonObjects.equivalent (get a "index") index) allocations with Some a => get a "budget" | None => number 0 end.
Definition allocation_values entries maximum := if cost_sum entries <=? maximum then
  map (fun e => JObject [("index",get e "index");("budget",get e "cost")]) entries else
  let ordered := positive_order entries in let values := allocate ordered maximum (N.of_nat (List.length ordered)) in
  map (fun e => JObject [("index",get e "index");("budget",allocation_for values (get e "index"))]) entries.
Definition allocation_actions entries allocations := map (fun pair =>
  let '(entry,allocation) := pair in JObject [("index",get allocation "index");("budget",get allocation "budget");
    ("action",JString (if num entry "cost" <=? num allocation "budget" then "original" else "preview"))]) (combine entries allocations).
Definition budget_plan source := let entries := items (get source "entries") in
  checked (bounded (get source "maximum") tool_output_tokens && entries_valid entries 0)
  (JArray (allocation_actions entries (allocation_values entries (num source "maximum")))) "RangeError" "Invalid evaluator tool-output budget".
Definition preview_done name value := JObject [("action",JString "done");("text_action",JString name);("text",value)].
Definition preview_decode keep head tail := JObject [("action",JString "decode");("keep",number keep);("head_count",number head);("tail_count",number tail)].
Definition preview_keep keep := if keep =? 0 then preview_done "preview" (JString omission) else
  let head := (3*keep+3)/4 in preview_decode keep head (keep-head).
Definition preview_start source := let budget := num source "budget" in success (
  if num source "original_cost" <=? budget then preview_done "original" JNull else
  match get source "marker_cost" with JNull => JObject [("action",JString "marker");("text",JString omission)] | marker =>
    if budget <? nat_value marker then preview_done "null" JNull else
    match get source "token_count" with JNull => action "encode" | count => preview_keep (N.min (nat_value count) budget) end end).
Definition preview_state_valid source state := let keep := num state "keep" in
  (0 <? keep) && (keep <=? N.min (num source "budget") (num source "token_count")) &&
  if String.eqb (str state "action") "decode" then num state "head_count" + num state "tail_count" <=? keep else
    String.eqb (str state "action") "count" &&
    JsonObjects.equivalent (get state "text") (JString (str state "head" ++ omission ++ str state "tail")) &&
    starts (str source "text") (str state "head") && ends (str source "text") (str state "tail").
Definition preview_step source := let state := get source "state" in let observed := get source "observation" in
  let valid := JsonObjects.equivalent (get observed "state") state && preview_state_valid source state in
  let decoding := String.eqb (str state "action") "decode" in
  let observed_valid := if decoding then
    ((0 <? num state "head_count") || String.eqb (str observed "head") "") &&
    ((0 <? num state "tail_count") || String.eqb (str observed "tail") "")
    else String.eqb (str state "action") "count" && JsonObjects.equivalent (get observed "text") (get state "text") in
  let result := if decoding then
    let head := num state "head_count" in let tail := num state "tail_count" in
    if (0 <? head) && negb (starts (str source "text") (str observed "head")) then preview_decode (num state "keep") (head-1) tail
    else if (0 <? tail) && negb (ends (str source "text") (str observed "tail")) then preview_decode (num state "keep") head (tail-1)
    else JObject [("action",JString "count");("keep",get state "keep");("text",JString (str observed "head" ++ omission ++ str observed "tail"));
      ("head",get observed "head");("tail",get observed "tail")]
  else if num observed "cost" <=? num source "budget" then preview_done "preview" (get state "text")
    else preview_keep (num state "keep" - (num observed "cost" - num source "budget")) in
  checked (valid && observed_valid) result "TypeError" "Invalid evaluator preview observation".
Definition parsed_text_bound encoded value := match parse_json (text encoded) with Some parsed => JsonObjects.equivalent parsed value | None => false end.
Definition preview_completion observed := if String.eqb (str observed "completion_kind") "start" then preview_start (get observed "completion") else preview_step (get observed "completion").
Definition preview_bound entry allocation observed :=
  if String.eqb (str allocation "action") "original" then String.eqb (str (get observed "result") "text_action") "original" else
  let initial := get observed "source" in let completion := get observed "completion" in let result := get observed "result" in
  JsonObjects.equivalent (get (preview_completion observed) "value") result && String.eqb (str result "action") "done" &&
  (if String.eqb (str result "text_action") "preview" then parsed_text_bound (get observed "selected_encoded") (get result "text")
    else JsonObjects.equivalent (get result "text") JNull) &&
  parsed_text_bound (get (get entry "text") "encoded") (get initial "text") &&
  JsonObjects.equivalent (get initial "budget") (get allocation "budget") && JsonObjects.equivalent (get initial "original_cost") (get entry "cost") &&
  forallb (fun key => JsonObjects.equivalent (get initial key) (get completion key)) ["text";"budget";"original_cost";"marker_cost";"token_count"].
Definition preview_metadata entry allocation observed := JObject [
  ("truncated",JBool (negb ((String.eqb (str allocation "action") "original" && negb (String.eqb (str (get entry "text") "type") "nan")) ||
    (String.eqb (str (get entry "text") "type") "string" && JsonObjects.equivalent (get (get entry "text") "encoded") (get observed "selected_encoded")))));
  ("original_tokens",get entry "cost");("sent_tokens",get observed "sent_tokens");("budget_tokens",get allocation "budget");("tokenizer",JString "o200k_base")].
Fixpoint finish_entries entries allocations observations := match entries,allocations,observations with
  | [],[],[] => Some []
  | entry::rest,allocation::allocated,observed::observations =>
    if JsonObjects.equivalent (get entry "index") (get observed "index") && JsonObjects.equivalent (get entry "index") (get allocation "index") &&
      JsonObjects.equivalent (get entry "cost") (get observed "original_cost") && JsonObjects.equivalent (get allocation "budget") (get observed "budget") && preview_bound entry allocation observed then
      match finish_entries rest allocated observations with Some rest => Some (JObject [
        ("index",get entry "index");("text_action",if num entry "cost" <=? num allocation "budget" then JString "original" else get (get observed "result") "text_action");
        ("text",get (get observed "result") "text");("preview",preview_metadata entry allocation observed)]::rest) | None => None end else None
  | _,_,_ => None end.
Definition budget_finish source := let plan := budget_plan source in
  if boolean_field plan "ok" && JsonObjects.equivalent (get plan "value") (get source "allocation") then
    match finish_entries (items (get source "entries")) (items (get plan "value")) (items (get source "previews")) with
    | Some result => success (JArray result) | None => type_error "Invalid evaluator output-budget construction" end
  else type_error "Invalid evaluator output-budget construction".
