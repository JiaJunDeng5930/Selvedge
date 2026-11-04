From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonObjects.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition note_role role := existsb (String.eqb role) ["assistant";"reasoning_summary";"error"].
Fixpoint calls history index := match history with [] => [] | item::rest =>
  let tail := calls rest (index+1) in if String.eqb (str item "role") "function_call" then
    JObject [("history_index",number index);("call_id",get item "call_id");("name",get item "name");("arguments",get item "arguments")]::tail else tail end.
Fixpoint outputs history call index := match history with
  | item::rest => let tail := outputs rest call (index+1) in
    if String.eqb (str item "role") "function_output" && JsonObjects.equivalent (get item "call_id") (get call "call_id") && (num call "history_index" <? index) then
      JObject [("history_index",number index);("is_error",get item "is_error");("text",get item "content")]::tail else tail
  | _ => [] end.
Fixpoint pair_calls values history := match values with [] => [] | call::rest =>
  JObject [("history_index",get call "history_index");("call_id",get call "call_id");("name",get call "name");("arguments",get call "arguments");
    ("outputs",JArray (if existsb (fun later => JsonObjects.equivalent (get later "call_id") (get call "call_id")) rest then [] else outputs history call 0))]::pair_calls rest history end.
Definition context_boundary := JString "Only bounded public text previews and the last six paired tool calls are supplied. Preview omissions are unknown. Provider conversation previews omit opaque continuations; ordinary tool data keeps its fields.".
Definition context effect :=
  let history := items (get effect "history") in
  let users := map (fun item => get item "content") (filter (fun item => String.eqb (str item "role") "user") history) in
  let call_values := calls history 0 in let recent := skipn (List.length call_values - 6) call_values in
  let notes := map (fun pair => let '(index,item) := pair in JObject [("history_index",number (N.of_nat index));
    ("kind",get item "role");("text",get item "content")])
    (filter (fun pair => note_role (str (snd pair) "role")) (combine (seq 0 (List.length history)) history)) in
  JObject [("schema",JString "selvedge-reasoning-context-1");("scope",JString "native_public_history");
    ("model",get (get effect "model") "name");("project_context",get effect "project_context");
    ("original_user_request",hd (JString "") users);("latest_user_request",last users (JString ""));
    ("prior_user_requests",JArray (firstn (List.length users - 2) (skipn 1 users)));("public_notes",JArray notes);
    ("recent_tool_calls",JArray (pair_calls recent history));
    ("omitted_older_tool_calls",number (N.of_nat (List.length call_values - List.length recent)));
    ("context_boundary",context_boundary)].
