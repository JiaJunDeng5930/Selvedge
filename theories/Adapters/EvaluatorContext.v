From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson JsonObjects.
From Selvedge.Adapters Require Import Common EvaluatorBudget.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition note_role role := existsb (String.eqb role) ["assistant";"reasoning_summary";"error"].
Definition public_text value := match value with JString _ => true | JArray parts =>
  forallb (fun part => is_object part && is_text (get part "text")) parts | _ => false end.
Fixpoint join_parts parts := match parts with [] => "" | [part] => str part "text" | part::rest =>
  str part "text" ++ String (Ascii.ascii_of_nat 10) (join_parts rest) end.
Definition public_content value := match value with JString value => value | JArray parts => join_parts parts | _ => "" end.
Definition item_error item := let role := str item "role" in
  if String.eqb role "user" || note_role role then
    if public_text (get item "content") then "" else "The native evaluator context contains an invalid public text part"
  else if String.eqb role "function_call" || String.eqb role "function_output" then "" else "The native evaluator context contains an unsupported role".
Fixpoint history_error history := match history with [] => "" | item::rest =>
  let error := item_error item in if String.eqb error "" then history_error rest else error end.
Fixpoint observes history observations index := match history,observations with
  | [],[] => true | item::rest,observation::observations =>
    JsonObjects.equivalent (get observation "history_index") (number index) && JsonObjects.equivalent (get observation "content") (get item "content") &&
    is_text (get observation "text") && observes rest observations (index+1)
  | _,_ => false end.
Fixpoint calls history index := match history with [] => [] | item::rest =>
  let tail := calls rest (index+1) in if String.eqb (str item "role") "function_call" then
    JObject [("history_index",number index);("call_id",get item "call_id");("name",get item "name");("arguments",get item "arguments")]::tail else tail end.
Fixpoint outputs history observations call index := match history,observations with
  | item::rest,observed::observations => let tail := outputs rest observations call (index+1) in
    if String.eqb (str item "role") "function_output" && JsonObjects.equivalent (get item "call_id") (get call "call_id") && (num call "history_index" <? index) then
      JObject [("history_index",number index);("is_error",get item "is_error");("text",get observed "text")]::tail else tail
  | _,_ => [] end.
Fixpoint pair_calls values history observations := match values with [] => [] | call::rest =>
  JObject [("history_index",get call "history_index");("call_id",get call "call_id");("name",get call "name");("arguments",get call "arguments");
    ("outputs",JArray (if existsb (fun later => JsonObjects.equivalent (get later "call_id") (get call "call_id")) rest then [] else outputs history observations call 0))]::pair_calls rest history observations end.
Definition context_boundary := JString "Only public text and the last six paired tool calls are supplied. Each call shares a 1000 local o200k_base token output budget. Preview omissions are unknown. Private continuation and encrypted reasoning are never supplied.".
Definition context_calls raw calls omitted := JObject (object_fields raw ++
  [("recent_tool_calls",calls);("omitted_older_tool_calls",omitted);("context_boundary",context_boundary)]).
Definition context_raw effect observations :=
  let history := items (get effect "history") in
  let users := map (fun item => JString (public_content (get item "content"))) (filter (fun item => String.eqb (str item "role") "user") history) in
  let call_values := calls history 0 in let recent := skipn (List.length call_values - 6) call_values in
  let notes := map (fun pair => let '(index,item) := pair in JObject [("history_index",number (N.of_nat index));
    ("kind",get item "role");("text",JString (public_content (get item "content")))])
    (filter (fun pair => note_role (str (snd pair) "role")) (combine (seq 0 (List.length history)) history)) in
  context_calls (JObject [("schema",JString "selvedge-reasoning-context-1");("scope",JString "native_public_history");
    ("model",get (get effect "model") "name");("project_context",get effect "project_context");
    ("original_user_request",hd (JString "") users);("latest_user_request",last users (JString ""));
    ("prior_user_requests",JArray (firstn (List.length users - 2) (skipn 1 users)));("public_notes",JArray notes)])
    (JArray (pair_calls recent history observations)) (number (N.of_nat (List.length call_values - List.length recent))).
Definition context_select source := let effect := get source "effect" in let history := get effect "history" in
  if negb (String.eqb (str effect "kind") "reasoning" && is_array history) then type_error "An evaluator requires a native reasoning effect" else
  let error := history_error (items history) in if negb (String.eqb error "") then type_error error else
  if String.eqb (str source "phase") "shape" then success (action "observe_history") else
  checked (observes (items history) (items (get source "observations")) 0) (context_raw effect (items (get source "observations")))
    "TypeError" "Invalid evaluator history observation".
Fixpoint context_outputs raw entries plans observations index := match raw,entries,plans,observations with
  | [],[],[],[] => Some []
  | output::rest,entry::entries,plan::plans,observed::observations =>
    if JsonObjects.equivalent (get entry "index") (number index) && (String.eqb (str plan "text_action") "original" || JsonObjects.equivalent (get (get observed "source") "text") (get output "text")) then
      match context_outputs rest entries plans observations (index+1) with Some tail => Some (JObject [
        ("history_index",get output "history_index");("is_error",get output "is_error");
        ("text",if String.eqb (str plan "text_action") "original" then get output "text" else get plan "text");("preview",get plan "preview")]::tail) | None => None end else None
  | _,_,_,_ => None end.
Fixpoint finish_calls raw budgeted := match raw,budgeted with
  | [],[] => Some [] | call::rest,result::results =>
    let construction := get result "construction" in let finished := budget_finish construction in
    if boolean_field finished "ok" && JsonObjects.equivalent (get finished "value") (get result "plan") && JsonObjects.equivalent (get construction "maximum") (number tool_output_tokens) then
      match context_outputs (items (get call "outputs")) (items (get construction "entries")) (items (get finished "value")) (items (get construction "previews")) 0,
        finish_calls rest results with
      | Some outputs,Some tail => Some (JObject [("history_index",get call "history_index");("call_id",get call "call_id");
        ("name",get call "name");("arguments",get call "arguments");("outputs",JArray outputs)]::tail)
      | _,_ => None end else None
  | _,_ => None end.
Definition context_finish source := let selected := context_select source in let raw := get selected "value" in
  if negb (String.eqb (str source "phase") "shape") && boolean_field selected "ok" && JsonObjects.equivalent raw (get source "selected") then
    match finish_calls (items (get raw "recent_tool_calls")) (items (get source "budgeted")) with Some calls =>
      success (context_calls (JObject (map (fun key => (key,get raw key)) ["schema";"scope";"model";"project_context";"original_user_request";
        "latest_user_request";"prior_user_requests";"public_notes"])) (JArray calls) (get raw "omitted_older_tool_calls"))
    | None => type_error "Invalid evaluator context construction" end
  else type_error "Invalid evaluator context construction".
