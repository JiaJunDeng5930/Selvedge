From Selvedge.Kernel Require Import ModelResultDeclarations.
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
Definition task_id_field (request : json) :=
  optional (has request "task_id") "task_id" (get request "task_id").
Definition observation_kind (request : json) := str request "kind".
Definition empty_requested_path (request : json) :=
  match field "path" request with Some (JString "") => true | _ => false end.

Definition request_plan (source : json) : json :=
  let request := get source "observation" in
  if negb (is_object request) then type_error "Expected an observation request"
  else if String.eqb (observation_kind request) "streams" && field_count_is 1 request then
    success (JObject [ModelResultDeclarations.tag ModelResultDeclarations.browser_streams])
  else if String.eqb (observation_kind request) "workspace-git" &&
      request_count_is 2 request && is_text (get request "primary") then
    success (JObject ([ModelResultDeclarations.tag ModelResultDeclarations.browser_workspace_git;
      ("primary",if String.eqb (str request "primary") "" then get source "cwd" else get request "primary") ] ++
      task_id_field request))
  else if String.eqb (observation_kind request) "browse-directories" && request_count_is 2 request then
    success (JObject ([ModelResultDeclarations.tag ModelResultDeclarations.browser_browse_directories;
      ("path",get request "path");
      ("default_path",JBool (empty_requested_path request));
      ("project_root",get source "project_root") ] ++ task_id_field request))
  else if String.eqb (observation_kind request) "directories" && request_count_is 2 request && truthy (get request "workspace") then
    success (JObject ([ModelResultDeclarations.tag ModelResultDeclarations.browser_directories;("workspace",get request "workspace") ] ++ task_id_field request))
  else if String.eqb (observation_kind request) "skill-catalog" && request_count_is 2 request && truthy (get request "workspace") then
    success (JObject ([ModelResultDeclarations.tag ModelResultDeclarations.browser_skill_catalog;("workspace",get request "workspace") ] ++ task_id_field request))
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

Theorem workspace_git_plan_defaults_to_cwd : forall observation cwd,
  observation = JObject [ModelResultDeclarations.tag ModelResultDeclarations.browser_workspace_git;("primary",JString "")] ->
  request_plan (JObject [("observation",observation);("cwd",cwd)]) =
    success (JObject [ModelResultDeclarations.tag ModelResultDeclarations.browser_workspace_git;("primary",cwd)]).
Proof. intros observation cwd equal;subst observation;reflexivity. Qed.

Theorem browse_empty_path_selects_default : forall observation,
  observation = JObject [ModelResultDeclarations.tag ModelResultDeclarations.browser_browse_directories;("path",JString "")] ->
  request_plan (JObject [("observation",observation)]) =
    success (JObject [ModelResultDeclarations.tag ModelResultDeclarations.browser_browse_directories;("path",JString "");
      ("default_path",JBool true);("project_root",JNull)]).
Proof. intros observation equal;subst observation;reflexivity. Qed.

Theorem browse_default_prefers_an_observed_task_root : forall task_root project_root,
  resolve_browse_path (JObject [("plan",JObject [ModelResultDeclarations.tag ModelResultDeclarations.browser_browse_directories;("path",JString "");
    ("default_path",JBool true);("project_root",project_root)]);
    ("task_environment_present",JBool true);("task_root",task_root)]) =
    success (JObject [("path",task_root);("canonicalize",JBool false)]).
Proof. reflexivity. Qed.

Theorem browse_default_uses_canonical_project_root_without_task_environment : forall project_root,
  resolve_browse_path (JObject [("plan",JObject [ModelResultDeclarations.tag ModelResultDeclarations.browser_browse_directories;("path",JString "");
    ("default_path",JBool true);("project_root",project_root)]);
    ("task_environment_present",JBool false)]) =
    success (JObject [("path",project_root);("canonicalize",JBool true)]).
Proof. reflexivity. Qed.

Theorem browse_failure_has_the_public_error_shape : forall message,
  completion (JObject [ModelResultDeclarations.tag ModelResultDeclarations.browser_browse_directories;("ok",JBool false);("error",JString message)]) =
    success (JObject [("ok",JBool false);("error",JString message)]).
Proof. intros;reflexivity. Qed.

Theorem skill_catalog_failure_has_the_public_error_shape : forall message,
  completion (JObject [ModelResultDeclarations.tag ModelResultDeclarations.browser_skill_catalog;("ok",JBool false);("error",JString message)]) =
    success (JObject [ModelResultDeclarations.tag ModelResultDeclarations.browser_skill_catalog;("ok",JBool false);("error",JString message)]).
Proof. intros;reflexivity. Qed.
