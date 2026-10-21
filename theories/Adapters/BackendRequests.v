From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Kernel Require Import NativeTools ModelCapabilities.
From Selvedge.Features Require Import Titles.
From Selvedge.Adapters Require Import Common ProviderCatalog BackendHistory ProviderCompaction.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition request_effort effect := default (get (get effect "sampling") "request_effort") (get (get effect "model") "reasoning").
Definition effective_effort effect := default (get (get effect "sampling") "effective_effort") (get (get effect "model") "reasoning").
Definition independent_task_text effect := set (set (set (set effect "instructions" (JString ""))
  "tools" (JArray [])) "callable" (JArray [])) "history"
  (JArray [message "user" (get effect "prompt")]).
Definition independent_effect effect :=
  let kind := str effect "kind" in
  if String.eqb kind "context_compaction" then set (set effect "output_mode" (JString "plain")) "history"
    (JArray (helper_history (items (get effect "history"))))
  else if existsb (String.eqb kind) ["task_title";"board_text"] then
    set (independent_task_text effect) "output_mode" (JString "plain")
  else if String.eqb kind "approval" then
    set (set (set (set effect "tools" (JArray [])) "callable" (JArray [])) "history"
      (JArray [message "user" (JString (TextJson.render_json (JObject [
        ("task_id",get effect "task_id");("request_id",get effect "ticket");("command",get effect "call");
        ("task_settings",get effect "settings");("recent_user_requests_newest_first",get effect "user_requests");
        ("context_boundary",JString "Only the latest four user requests, each limited to 4096 characters; older requests and other task data are omitted.")])))]))
      "output_mode" (JString "plain")
  else effect.
Definition prepare_effect value : outcome json :=
  let effect := independent_effect value in
  if negb (independent_kind (str effect "kind")) &&
     (String.eqb (text (request_effort effect)) "auto" || String.eqb (text (effective_effort effect)) "auto" ||
      (is_object (get (get effect "model") "adaptive_reasoning") && negb (has effect "sampling")))
  then reject "An automatic endpoint requires a committed native reasoning selection"
  else Accepted (set (set (set effect "requestEffort" (request_effort effect))
    "effectiveEffort" (effective_effort effect)) "history" (get effect "history")).
Definition prepare source := render_outcome (fun value => value) (prepare_effect source).
Definition allowed_tool name := JObject [("type",JString "function");("name",name)].
Definition allowed_tools effect := match items (get effect "callable") with
  | [] => JString "none" | names => JObject [("type",JString "allowed_tools");("mode",JString "auto");
      ("tools",JArray (map allowed_tool names))] end.
Definition request_base effect profile input := JObject [
  ("model",get (get effect "model") "name");("stream",JBool true);("store",JBool false);
  ("instructions",if independent_kind (str effect "kind") then get effect "instructions" else JString "");
  ("input",input);("reasoning",JObject [("effort",if account profile then effective_effort effect else request_effort effect)]);
  ("tools",JArray (map tool (NativeTools.presentation_catalog (items (get effect "tools")))));
  ("parallel_tool_calls",JBool true);("include",JArray [JString "reasoning.encrypted_content"]);
  ("tool_choice",allowed_tools effect)].
Definition account_tools body effect :=
  let selected := filter (fun item => contains (items (get effect "callable")) (get item "name"))
    (items (get body "tools")) in
  match selected with
  | [] => set (set body "tools" (JArray [])) "tool_choice" (JString "none")
  | _ => set (set body "tools" (JArray [JObject [("type",JString "namespace");
      ("name",JString local_tool_namespace);("description",JString "Local Selvedge tools");("tools",JArray selected)]]))
      "tool_choice" (JString "auto") end.
Definition request_account body effect profile : outcome json :=
  if account profile then
    let body := account_tools body effect in
    let observed_levels := get (get profile "model_info") "supported_reasoning_levels" in
    if is_array observed_levels then
      let levels := map (fun level => get level "effort") (items observed_levels) in
      if Nat.eqb (List.length levels) 0 && negb (is_object (get (get effect "model") "adaptive_reasoning"))
      then Accepted (without body "reasoning")
      else if independent_kind (str effect "kind") || contains levels (effective_effort effect) then Accepted body
      else reject ("This account model supports these reasoning levels: " ++ String.concat ", " (map text levels))
    else Accepted body
  else Accepted body.
Definition task_text_format effect := JObject [
  ("type",JString "json_schema");("name",get effect "kind");("strict",JBool true);
  ("schema",Titles.output_schema (String.eqb (str effect "kind") "board_text" && negb (boolean_field effect "retitle")))].
Definition structured_text body effect :=
  if existsb (String.eqb (str effect "kind")) ["task_title";"board_text"] then
    set body "text" (JObject [("format",task_text_format effect)]) else body.
Definition request_final body effect :=
  let body := if independent_kind (str effect "kind") && negb
    (String.eqb (str effect "kind") "approval" && (String.eqb (str (get effect "model") "provider") "chatgpt" &&
      String.eqb (str (get effect "model") "name") ModelCapabilities.codex_auto_review_model))
    then without body "reasoning" else body in
  let body := if String.eqb (str body "instructions") "" && negb (account (get effect "model"))
    then without body "instructions" else body in
  structured_text (if independent_kind (str effect "kind") then
    set (set body "tool_choice" (JString "none")) "tools" (JArray []) else body) effect.
Definition request_output_limit body effect :=
  if has effect "max_output_tokens" || (0 <? num effect "output_reserve_tokens") then
    set body "max_output_tokens" (if has effect "max_output_tokens" then get effect "max_output_tokens"
      else get effect "output_reserve_tokens") else body.
Definition effect_input (select_history : list json -> string -> list json) effect profile :=
  let history := items (get effect "history") in
  input_items (if boolean_field effect "context_selected" then history else
    if is_text (get profile "scope") then select_history history (str profile "scope") else history) profile.
Definition request (select_history : list json -> string -> list json) source :=
  render_outcome (fun body => body) (bind (prepare_effect (get source "effect")) (fun effect =>
    bind (effect_input select_history effect (get source "profile")) (fun input =>
      bind (request_account (request_base effect (get source "profile") (JArray input)) effect (get source "profile"))
        (fun body => Accepted (request_output_limit (request_final body effect) effect))))).
Definition measurement_request (select_history : list json -> string -> list json) source :=
  let effect := get source "effect" in let profile := get source "profile" in
  render_outcome (fun input => request_final
    (if account profile then account_tools (request_base effect profile (JArray input)) effect
      else request_base effect profile (JArray input)) effect) (effect_input select_history effect profile).
Definition input (select_history : list json -> string -> list json) source :=
  let profile := get source "profile" in let history := items (get source "history") in
  render_outcome JArray (input_items
    (if is_text (get profile "scope") then select_history history (str profile "scope") else history) profile).
