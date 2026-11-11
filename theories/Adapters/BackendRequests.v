From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson CallWire.
From Selvedge.Kernel Require RealtimeContext.
From Selvedge.Kernel Require Import NativeTools ModelCapabilities ContextSelection.
From Selvedge.Features Require Import Titles.
From Selvedge.Adapters Require Import Common ProviderCatalog BackendHistory.
From Selvedge.Programming Require Import AdapterResult.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition request_effort effect := default (get (get effect "sampling") "request_effort") (get (get effect "model") "reasoning").
Definition effective_effort effect := default (get (get effect "sampling") "effective_effort") (get (get effect "model") "reasoning").
Definition independent_task_text effect := set (set effect "instructions" (JString "")) "history"
  (JArray [message "user" (get effect "prompt")]).
Definition independent_effect effect :=
  let kind := str effect "kind" in
  if existsb (String.eqb kind) ["task_title";"board_text"] then
    independent_task_text effect
  else if String.eqb kind "approval" then
    set effect "history"
      (JArray [message "user" (JString (TextJson.render_json (JObject [
        ("task_id",get effect "task_id");("request_id",get effect "ticket");("command",CallWire.external (get effect "call"));
        ("task_settings",get effect "settings");("recent_user_requests_newest_first",get effect "user_requests");
        ("context_boundary",JString "Only the latest four user requests, each limited to 4096 characters; older requests and other task data are omitted.")])))])
  else effect.
Definition prepare_effect value : outcome json :=
  let effect := independent_effect value in
  if negb (independent_kind (str effect "kind")) &&
     (String.eqb (text (request_effort effect)) "auto" || String.eqb (text (effective_effort effect)) "auto" ||
      (is_object (get (get effect "model") "adaptive_reasoning") && negb (has effect "sampling")))
  then reject "An automatic endpoint requires a committed native reasoning selection"
  else Accepted effect.
Definition prepare source := render_outcome (fun value => value) (prepare_effect source).
Definition allowed_tool name := JObject [("type",JString "function");("name",name)].
(** A callable name is derived from its registered tool. Backends cannot
    supply an independent allowlist that names undeclared capabilities. *)
Definition tool_authority := list (json * bool).
Definition authority_tools (authority : tool_authority) := map fst authority.
Definition callable_tools (authority : tool_authority) := map fst (filter snd authority).
Definition authority_names authority := map (fun tool => get tool "name") (callable_tools authority).
Definition request_authority (independent : bool) := if independent then unit else tool_authority.
Definition construct_authority (independent : bool) effect : request_authority independent :=
 match independent as independent return request_authority independent with
 | true => tt
 | false => let names := items (get effect "callable") in
     map (fun entry => (entry,contains names (get entry "name")))
       (NativeTools.presentation_catalog (items (get effect "tools"))) end.

(** Independent text requests cannot contain tool authority. Every Responses
    backend uses this constructor and encoder, including account transports. *)
Record response_request (independent : bool) := ResponseRequest {
  response_model : json;
  response_input : list json;
  response_instructions : option json;
  response_reasoning : option json;
  response_authority : request_authority independent;
  response_format : option json;
  response_limit : option json
}.
Arguments ResponseRequest {independent} _ _ _ _ _ _ _.
Arguments response_model {independent} _.
Arguments response_input {independent} _.
Arguments response_instructions {independent} _.
Arguments response_reasoning {independent} _.
Arguments response_authority {independent} _.
Arguments response_format {independent} _.
Arguments response_limit {independent} _.
Definition encode_authority (independent : bool) (account : bool) : request_authority independent -> list json * json :=
 match independent as independent return request_authority independent -> list json * json with
 | true => fun _ => ([],JString (if account then "auto" else "none"))
 | false => fun authority =>
   let tools := map tool (authority_tools authority) in
   if account then
     match map tool (callable_tools authority) with
     | [] => ([],JString "auto")
     | selected => ([JObject [("type",JString "namespace");("name",JString local_tool_namespace);
         ("description",JString "Local Selvedge tools");("tools",JArray selected)]],JString "auto") end
   else (tools,match authority_names authority with [] => JString "none" | names => JObject [
     ("type",JString "allowed_tools");("mode",JString "auto");("tools",JArray (map allowed_tool names))] end)
 end.
Definition optional_field (name : string) (value : option json) :=
 match value with Some value => [(name,value)] | None => [] end.
Definition responses_lite profile := account profile && boolean_field (get profile "model_info") "use_responses_lite".
Definition codex_message item :=
 if negb (has item "type") && is_text (get item "role") then
   let content := get item "content" in
   set (set item "type" (JString "message")) "content"
     (if is_text content then
        JArray [JObject [("type",JString (if String.eqb (str item "role") "assistant" then "output_text" else "input_text"));
          ("text",content)]]
      else content)
 else item.
Definition codex_reasoning_effort profile value :=
 let info := get profile "model_info" in
 let levels := map (fun level => get level "effort") (items (get info "supported_reasoning_levels")) in
 if String.eqb (text value) "ultra" then
   let hint := get info "multi_agent_reasoning_effort" in
   if is_text hint && negb (String.eqb (text hint) "ultra") && contains levels hint then hint
   else if contains levels (JString "max") then JString "max"
   else match find (fun level => negb (String.eqb (text level) "ultra")) (rev levels) with
     | Some effort => effort | None => JString "medium" end
 else if String.eqb (text value) "persistent" then JString "disabled"
 else value.
Definition codex_reasoning_fields profile value :=
 set value "effort" (codex_reasoning_effort profile (get value "effort")).
Definition codex_input_item profile item :=
 if String.eqb (str item "type") "configuration_update" then
   set item "reasoning" (codex_reasoning_fields profile (get item "reasoning"))
 else codex_message item.
Definition inline_tool_declaration item := String.eqb (str item "type") "additional_tools".
Definition codex_input profile input instructions (lite : bool) tools :=
 let prefix := match tools with [] => [] | _ => if lite then
   [JObject [("type",JString "additional_tools");("role",JString "developer");("tools",JArray tools)]] else [] end in
 let input := match instructions with
   | Some (JString (String head tail)) => message "developer" (JString (String head tail)) :: input
   | _ => input end in
 List.app prefix (filter (fun item => negb (inline_tool_declaration item)) (map (codex_input_item profile) input)).
Definition codex_reasoning profile (lite : bool) reasoning :=
 let fields := match reasoning with
   | Some value => codex_reasoning_fields profile value
   | None => JObject [] end in
 if lite then set fields "context" (JString "all_turns") else fields.
Definition encode_request {independent} (profile : json) (request : response_request independent) :=
 let account := account profile in
 let lite := responses_lite profile in
 let '(tools,choice) := encode_authority independent account (response_authority request) in
 let input := if account then codex_input profile (response_input request) (response_instructions request) lite tools
   else response_input request in
 JObject ([("model",response_model request);("stream",JBool true);("store",JBool false);
   ("input",JArray input);("tool_choice",choice);
   ("parallel_tool_calls",JBool (negb lite));("include",JArray [JString "reasoning.encrypted_content"])] ++
   optional (negb lite) "tools" (JArray tools) ++
   (if account then [("reasoning",codex_reasoning profile lite (response_reasoning request))]
    else optional_field "instructions" (response_instructions request) ++
      optional_field "reasoning" (response_reasoning request) ++
      optional_field "max_output_tokens" (response_limit request)) ++
   optional_field "text" (response_format request)).
Definition task_text_format_fields (kind : string) (retitle : bool) := JObject [
  ("type",JString "json_schema");("name",JString kind);("strict",JBool true);
  ("schema",Titles.output_schema (String.eqb kind "board_text" && negb retitle))].
Definition text_format_fields kind retitle :=
 if existsb (String.eqb kind) ["task_title";"board_text"]
 then Some (JObject [("format",task_text_format_fields kind retitle)]) else None.
Definition text_format effect := text_format_fields (str effect "kind") (boolean_field effect "retitle").
Definition structured_text_fields body kind retitle := match text_format_fields kind retitle with
 | Some format => set body "text" format | None => body end.
Definition reasoning_value effect := JObject [("effort",request_effort effect)].
Definition admit_reasoning effect profile : outcome (option json) :=
 let value := Some (reasoning_value effect) in
 let observed := get (get profile "model_info") "supported_reasoning_levels" in
 if account profile && is_array observed then
   let levels := map (fun level => get level "effort") (items observed) in
   if Nat.eqb (List.length levels) 0 && negb (is_object (get (get effect "model") "adaptive_reasoning"))
   then Accepted None
   (* DEFENSE: A refreshed account catalog can remove an effort retained by a
      Task's frozen policy; both the wire baseline and selected effort must fit. *)
   else if independent_kind (str effect "kind") ||
     (contains levels (request_effort effect) && contains levels (effective_effort effect)) then Accepted value
   else reject ("This account model supports these reasoning levels: " ++ String.concat ", " (map text levels))
 else Accepted value.
Definition output_limit effect :=
 if has effect "max_output_tokens" then Some (get effect "max_output_tokens")
 else if 0 <? num effect "output_reserve_tokens" then Some (get effect "output_reserve_tokens") else None.
Definition construct_request effect input reasoning limit
 : response_request (independent_kind (str effect "kind")) :=
 let independent := independent_kind (str effect "kind") in
 let instructions := if independent then get effect "instructions" else JString "" in
 let keep_reasoning := negb independent ||
   (String.eqb (str effect "kind") "approval" &&
     account (get effect "model") &&
     String.eqb (str (get effect "model") "name") ModelCapabilities.codex_auto_review_model) in
 ResponseRequest (get (get effect "model") "name") input
   (if String.eqb (text instructions) "" && negb (account (get effect "model")) then None else Some instructions)
   (if keep_reasoning then reasoning else None)
   (construct_authority independent effect)
   (text_format effect) limit.
Definition configuration_updates effect :=
  String.eqb (str (get (get effect "model") "adaptive_reasoning") "transport") "configuration_update".
Definition effect_input (select_history : list json -> string -> list json) effect profile :=
  let history := items (get effect "history") in
  let selected := if boolean_field effect "context_selected" then history else
    if is_text (get profile "scope") then select_history history (str profile "scope") else history in
  input_items (if configuration_updates effect then selected else
    filter (fun message => negb (reasoning_configuration message)) selected) profile.
Definition realtime_items effect observation :=
 if String.eqb (str effect "kind") "model" then
   match RealtimeContext.observed_text (get effect "realtime_context") observation with
   | Some contents => [message "developer" (JString contents)]
   | None => [] end
 else [].
Definition request (select_history : list json -> string -> list json) source :=
  render_outcome (fun body => body) (bind (prepare_effect (get source "effect")) (fun effect =>
    bind (effect_input select_history effect (get source "profile")) (fun input =>
      bind (admit_reasoning effect (get source "profile")) (fun reasoning =>
        Accepted (encode_request (get source "profile")
          (construct_request effect (input ++ realtime_items effect (get source "realtime")) reasoning (output_limit effect))))))).
Definition measurement_request (select_history : list json -> string -> list json) source :=
  let effect := get source "effect" in let profile := get source "profile" in
  render_outcome (fun input => encode_request profile
    (construct_request effect input (Some (reasoning_value effect)) None))
    (effect_input select_history effect profile).
