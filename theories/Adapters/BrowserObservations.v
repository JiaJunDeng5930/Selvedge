From Selvedge.Kernel Require Import ModelResultDeclarations.
From Selvedge.Programming Require Import Schema.
From Selvedge.Kernel Require ModelDeclarations.
From Stdlib Require Import String List Bool Arith.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.

Definition field_count_is (count : nat) (source : json) : bool :=
  match source with
  | JObject fields => Nat.eqb (List.length fields) count
  | _ => false
  end.
Definition request_count_is (count : nat) (request : json) :=
  field_count_is (count + if has request "task_id" then 1 else 0) request.
Definition observation_kind (request : json) := str request "kind".
Definition empty_requested_path (request : json) :=
  match field "path" request with Some (JString "") => true | _ => false end.

Definition request_plan (source : json) : json :=
  let request := get source "observation" in
  if negb (is_object request) then type_error "Expected an observation request"
  else if String.eqb (observation_kind request) "streams" && field_count_is 1 request then
    success (ModelDeclarations.encode_packet (ModelDeclarations.pack ModelResultDeclarations.browser_streams [!!]))
  else if String.eqb (observation_kind request) "workspace-git" &&
      request_count_is 2 request then
    match (match string_field "primary" request with Some "" => string_field "cwd" source | selected => selected end) with
    | Some primary => success (ModelDeclarations.encode_packet
        (ModelDeclarations.pack ModelResultDeclarations.browser_workspace_git [!primary;field "task_id" request!]))
    (* DEFENSE: A non-text primary, or an empty primary without a text cwd,
       cannot supply the declared workspace root. *)
    | None => type_error "Expected a workspace root" end
  else if String.eqb (observation_kind request) "browse-directories" && request_count_is 2 request then
    success (ModelDeclarations.encode_packet (ModelDeclarations.pack ModelResultDeclarations.browser_browse_directories
      [!get request "path";empty_requested_path request;get source "project_root";field "task_id" request!]))
  else if String.eqb (observation_kind request) "directories" && request_count_is 2 request && truthy (get request "workspace") then
    success (ModelDeclarations.encode_packet (ModelDeclarations.pack ModelResultDeclarations.browser_directories
      [!get request "workspace";field "task_id" request!]))
  else if String.eqb (observation_kind request) "skill-catalog" && request_count_is 2 request && truthy (get request "workspace") then
    success (ModelDeclarations.encode_packet (ModelDeclarations.pack ModelResultDeclarations.browser_skill_catalog
      [!get request "workspace";field "task_id" request!]))
  else type_error "Unknown browser observation".

Definition resolve_browse_path (source : json) : json :=
  let plan := get source "plan" in
  if boolean_field plan "default_path" then
    if boolean_field source "task_environment_present" then
      success (JObject [("path",get source "task_root");("canonicalize",JBool false)])
    else success (JObject [("path",get plan "project_root");("canonicalize",JBool true)])
  else success (JObject [("path",get plan "path");("canonicalize",JBool false)]).

Definition completion (source : json) : json :=
  let kind := str source "kind" in
  let value := get source "value" in
  if String.eqb kind "workspace-git" then
    success (JObject [ModelResultDeclarations.tag ModelResultDeclarations.browser_workspace_git;("available",get source "available")])
  else if String.eqb kind "browse-directories" then
    if boolean_field source "ok" then success value
    else success (JObject [("ok",JBool false);("error",get source "error")])
  else if String.eqb kind "directories" then
    success (JObject [ModelResultDeclarations.tag ModelResultDeclarations.browser_directories;("workspace",get value "workspace");("guidance",get value "guidance")])
  else if String.eqb kind "skill-catalog" then
    if boolean_field source "ok" then
      success (JObject [ModelResultDeclarations.tag ModelResultDeclarations.browser_skill_catalog;("ok",JBool true);("skills",value)])
    else success (JObject [ModelResultDeclarations.tag ModelResultDeclarations.browser_skill_catalog;("ok",JBool false);("error",get source "error")])
  else type_error "Unknown browser observation result".

Definition call (operation : string) (source : json) : json :=
  if String.eqb operation "browser.observation" then
    if String.eqb (str source "phase") "plan" then request_plan source
    else if String.eqb (str source "phase") "resolve" then resolve_browse_path source
    else if String.eqb (str source "phase") "complete" then completion source
    else type_error "Unknown browser observation phase"
  else err ("Unknown browser observation operation: " ++ operation).
