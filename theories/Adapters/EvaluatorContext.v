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
    if String.eqb (str item "role") "function_output" && JsonObjects.equivalent (get item "call_id") (get call "call_id") then
      JObject [("history_index",number index);("is_error",get item "is_error");("text",get item "content")]::tail else tail
  | _ => [] end.
Definition pair_calls values history := map (fun call =>
  JObject [("history_index",get call "history_index");("call_id",get call "call_id");("name",get call "name");("arguments",get call "arguments");
    ("outputs",JArray (outputs history call 0))]) values.
Definition context_boundary := JString "Only bounded public text previews and their paired tool calls are supplied. Preview omissions are unknown. Provider conversation previews omit opaque continuations; ordinary tool data keeps its fields.".
Definition context effect :=
  let history := items (get effect "history") in
  let users := map (fun item => get item "content") (filter (fun item => String.eqb (str item "role") "user") history) in
  let notes := map (fun pair => let '(index,item) := pair in JObject [("history_index",number (N.of_nat index));
    ("kind",get item "role");("text",get item "content")])
    (filter (fun pair => note_role (str (snd pair) "role")) (combine (seq 0 (List.length history)) history)) in
  JObject [("model",get (get effect "model") "name");("project_context",get effect "project_context");
    ("original_user_request",hd (JString "") users);("latest_user_request",last users (JString ""));
    ("prior_user_requests",JArray (firstn (List.length users - 2) (skipn 1 users)));("public_notes",JArray notes);
    ("recent_tool_calls",JArray (pair_calls (calls history 0) history));
    ("context_boundary",context_boundary)].
