From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson JsonObjects.
From Selvedge.Adapters Require Import Common EvaluatorBudget ProviderCatalog.
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
Fixpoint calls history index := match history with [] => [] | item::rest =>
  let tail := calls rest (index+1) in if String.eqb (str item "role") "function_call" then
    JObject [("history_index",number index);("call_id",get item "call_id");("name",get item "name");("arguments",get item "arguments")]::tail else tail end.
Fixpoint outputs history call index := match history with
  | item::rest => let tail := outputs rest call (index+1) in
    if String.eqb (str item "role") "function_output" && JsonObjects.equivalent (get item "call_id") (get call "call_id") && (num call "history_index" <? index) then
      JObject [("history_index",number index);("is_error",get item "is_error");("text",JString (TextJson.render_json (get item "content")))]::tail else tail
  | _ => [] end.
Fixpoint pair_calls values history := match values with [] => [] | call::rest =>
  JObject [("history_index",get call "history_index");("call_id",get call "call_id");("name",get call "name");("arguments",get call "arguments");
    ("outputs",JArray (if existsb (fun later => JsonObjects.equivalent (get later "call_id") (get call "call_id")) rest then [] else outputs history call 0))]::pair_calls rest history end.
Definition context_boundary := JString "Only public text and the last six paired tool calls are supplied. Each call shares a 1000 local o200k_base token output budget. Preview omissions are unknown. Private continuation and encrypted reasoning are never supplied.".
Module Type ConstructedContext.
 Parameter t : Set.
 Parameter encode : t -> json.
 Parameter select : json -> outcome t.
 Parameter finish : json -> list json -> outcome t.
End ConstructedContext.
Module PublicContext : ConstructedContext.
Record public_context := Context {
 context_fields : list (string * json); recent_calls : list json; omitted_calls : N
}.
Definition t := public_context.
Definition encode value := JObject (List.app (context_fields value)
 [("recent_tool_calls",JArray (recent_calls value));("omitted_older_tool_calls",number (omitted_calls value));
  ("context_boundary",context_boundary)]).
Definition context_raw effect :=
  let history := items (get effect "history") in
  let users := map (fun item => JString (public_content (get item "content"))) (filter (fun item => String.eqb (str item "role") "user") history) in
  let call_values := calls history 0 in let recent := skipn (List.length call_values - 6) call_values in
  let notes := map (fun pair => let '(index,item) := pair in JObject [("history_index",number (N.of_nat index));
    ("kind",get item "role");("text",JString (public_content (get item "content")))])
    (filter (fun pair => note_role (str (snd pair) "role")) (combine (seq 0 (List.length history)) history)) in
  Context [("schema",JString "selvedge-reasoning-context-1");("scope",JString "native_public_history");
    ("model",get (get effect "model") "name");("project_context",get effect "project_context");
    ("original_user_request",hd (JString "") users);("latest_user_request",last users (JString ""));
    ("prior_user_requests",JArray (firstn (List.length users - 2) (skipn 1 users)));("public_notes",JArray notes)]
    (pair_calls recent history) (N.of_nat (List.length call_values - List.length recent)).
Definition select effect : outcome t := let history := get effect "history" in
 if negb (String.eqb (str effect "kind") "reasoning" && is_array history)
 then Rejected "TypeError" "An evaluator requires a native reasoning effect" else
 let error := history_error (items history) in if negb (String.eqb error "") then Rejected "TypeError" error
 else Accepted (context_raw effect).
Definition context_output pair := let '(output,preview) := pair in JObject [
 ("history_index",get output "history_index");("is_error",get output "is_error");
 ("text",match Budgeted.text preview with Some value => JString value | None => JNull end);
 ("preview",Budgeted.metadata preview)].
Fixpoint finish_calls raw budgeted := match raw,budgeted with
 | [],[] => Some [] | call::rest,observations::budgeted =>
   let outputs := items (get call "outputs") in
   match Budgeted.finish (map (fun output => str output "text") outputs) observations,finish_calls rest budgeted with
   | Some previews,Some tail => Some (JObject [("history_index",get call "history_index");("call_id",get call "call_id");
       ("name",get call "name");("arguments",get call "arguments");
       ("outputs",JArray (map context_output (combine outputs previews)))]::tail)
   | _,_ => None end
 | _,_ => None end.
Definition finish effect budgeted : outcome t := bind (select effect) (fun raw =>
 match finish_calls (recent_calls raw) budgeted with
 | Some calls => Accepted (Context (context_fields raw) calls (omitted_calls raw))
 | None => Rejected "TypeError" "Invalid evaluator context observations" end).
End PublicContext.
Definition context_select source := render_outcome PublicContext.encode (PublicContext.select (get source "effect")).
