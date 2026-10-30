From Selvedge.Kernel Require Import ModelResultDeclarations.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Utf8 Schema.
From Selvedge.Kernel Require Import Commands Workspace CommandDeclarations.
From Selvedge.Adapters Require Import Common Observation.
From Selvedge.Host Require Import LocalResources.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition type_admit (accepted : bool) (value : json) (message : string) :=
  if accepted then success value else type_error message.
Definition path_valid (value : json) := is_text value && Utf8.well_formed (text value) && Utf8.no_nul (text value).
Definition workspace_valid value := ArgumentDeclaration.present
 (ArgumentDeclaration.decode Codec.workspace_declaration value).
Definition workspace_admit value := match ArgumentDeclaration.decode Codec.workspace_declaration value with
 | Some fields => success (ArgumentDeclaration.encode Codec.workspace_declaration fields)
 | None => type_error "A workspace requires at most 32 roots and an optional primary_root" end.
Definition root_admit (source : json) :=
 match ArgumentDeclaration.decode Workspace.path_declaration (get source "root") with
 | Some root => type_admit (boolean_field source "absolute") (JString (proj1_sig root))
     "Workspace roots must be bounded absolute directory paths"
 | None => type_error "Workspace roots must be bounded absolute directory paths" end.
Fixpoint distinct (seen roots : list json) :=
  match roots with [] => true | root::rest =>
    negb (existsb (equal root) seen) && distinct (root::seen) rest end.
Definition workspace_distinct (source : json) := type_admit (distinct [] (items (get source "roots"))) JNull
  "Workspace roots must be distinct after resolving symbolic links".
Definition workspace_selected (source : json) :=
  let primary := get source "primary" in
  type_admit (is_null primary || existsb (fun root => String.eqb (text root) (text primary)) (items (get source "roots")))
    (JObject [("roots",get source "roots");("primary_root",primary)]) "The primary root must be one of the workspace roots".
Definition selection_value (source : json) :=
  let value := get (get source "value") "primary_root" in
  let default := is_null value || equal value (JString "") in
  JObject [("canonicalize",JBool (negb default));
    ("root",if default then hd JNull (items (get source "roots")) else value)].
Definition workspace_selection (source : json) := success (selection_value source).
Definition workspace_bound (source : json) :=
  let workspace := get source "workspace" in let plan := get source "plan" in let committed := get plan "workspace" in
  if has committed "primary_root" && equal (get workspace "roots") (get committed "roots") &&
    equal (get workspace "primary_root") (get committed "primary_root") then
    let project := String.eqb (str plan "scope") "project" in
    let primary := get workspace "primary_root" in
    if project && (is_null primary || equal primary (JString ""))
    then err "Project execution requires a primary Workspace root"
    else success (JObject [("cwd",if is_null primary then JString "/" else primary);
      ("projectOnly",JBool project);("unrestricted",JBool (String.eqb (str plan "access") "unrestricted"));
      ("writableRoots",if String.eqb (str (get plan "sandbox") "mode") "workspace-write" then get workspace "roots" else JArray [])])
  else err "A workspace root changed after it was committed; reselect the workspace before executing".

Inductive selection_path := CommandWorkspace | TaskWorkspace | NodeWorkspace (index : nat).
Record selection := Selection { selected_path : selection_path; selected_value : json; resolve_project : bool }.
Record workspace_plan := WorkspacePlan { root_task : bool; worktree : bool; selections : list selection }.
Definition select_settings (path : selection_path) (resolve : bool) (value : json) :=
  if is_object value then [Selection path value resolve] else [].
Fixpoint graph_selections (index : nat) (nodes : list json) : list selection :=
  match nodes with [] => [] | node::rest =>
    (if is_object node && negb (has node "task_id")
     then select_settings (NodeWorkspace index) true (get node "settings") else []) ++
    graph_selections (S index) rest end.
Definition known_command (operation : string) :=
  existsb (fun spec => String.eqb operation spec.(command_name)) Commands.command_specs.
Definition plan (command : json) : workspace_plan :=
  let op := str command "op" in
  (* DEFENSE: Commands are observed before native admission; unknown operations must not trigger filesystem reads. *)
  if negb (known_command op) then WorkspacePlan false false []
  else if existsb (String.eqb op) ["create";"create_idle";"fork";"create_work_task";"create_worktree_task";"create_workspace_task";"save_board_agent"] then
    WorkspacePlan (Commands.root_task_creation command)
      (String.eqb op "create_worktree_task" || String.eqb op "create_workspace_task" ||
        (existsb (String.eqb op) ["create_idle";"create_work_task"] && boolean_field command "create_worktree"))
      (select_settings TaskWorkspace true (get command "settings"))
  else if existsb (String.eqb op) ["create_project";"update_project"] then
    WorkspacePlan false false (select_settings CommandWorkspace false command)
  else if existsb (String.eqb op) ["create_task_graph";"update_task_graph"] then
    let selected := graph_selections 0%nat (items (get command "nodes")) in
    WorkspacePlan (Commands.root_task_creation command) false selected
  else WorkspacePlan false false [].
Definition selection_json (selection : selection) :=
 Schema.encode ModelResultDeclarations.workspace_selection_fields
   (Schema.of_tuple ModelResultDeclarations.workspace_selection_fields
     [! selection.(selected_value); selection.(resolve_project) !]).
Definition plan_json (plan : workspace_plan) :=
 Schema.encode ModelResultDeclarations.workspace_command_fields
   (Schema.of_tuple ModelResultDeclarations.workspace_command_fields
     [! plan.(root_task); plan.(worktree); map selection_json plan.(selections) !]).
Definition workspace_selection_plan (source : json) :=
 let value := get source "value" in
 (* DEFENSE: An explicitly supplied invalid workspace must not select project defaults. *)
 let project := if boolean_field source "resolve_project" && negb (has value "workspace") &&
   bound (get value "project_id") 0 9007199254740991 then natural (get value "project_id") else None in
 success (Schema.encode ModelResultDeclarations.workspace_settings_fields
   (Schema.of_tuple ModelResultDeclarations.workspace_settings_fields [! project; has value "workspace" !])).
Definition observed_settings (selected observation : json) :=
  let workspace := if has observation "workspace" then set selected "workspace" (get observation "workspace") else selected in
  let selected := if has observation "workspace_binding" then set workspace "workspace_binding" (get observation "workspace_binding") else workspace in
  if has observation "guidance" then set selected "guidance" (get observation "guidance") else selected.
Fixpoint observed_nodes (index : nat) (nodes : list json) (settings : json) :=
  match index,nodes with
  | O,node::rest => set node "settings" settings :: rest
  | S index,node::rest => node::observed_nodes index rest settings
  | _,[] => []
  end.
Definition apply_observation (command : json) (entry : selection * json) :=
  let settings := observed_settings (fst entry).(selected_value) (snd entry) in
  match (fst entry).(selected_path) with
  | CommandWorkspace => settings
  | TaskWorkspace => set command "settings" settings
  | NodeWorkspace index => set command "nodes" (JArray (observed_nodes index (items (get command "nodes")) settings))
  end.
Definition workspace_command_observed (source : json) :=
  let command := get source "command" in
  success (fold_left apply_observation (combine (plan command).(selections) (items (get source "observations"))) command).

(* Raw command admission precedes every observation, including cloud and unknown-task paths.
   Service-owned observations have no constructors in this public declaration. *)
Definition workspace_command_raw (source : json) :=
 match CommandDeclarations.admit_public (get source "command") with
 | None => type_error "Command fields do not match their declared presence, shape or bounds"
 | Some admitted => success (CommandDeclarations.public_json admitted)
 end.

Definition child (parent leaf : string) :=
  if String.eqb (String.substring (Nat.pred (String.length parent)) 1 parent) "/"
  then parent ++ leaf else parent ++ "/" ++ leaf.
Definition contains_path (root parent : string) := String.eqb root parent || starts root (child parent "").
Definition worktree_locations (source : json) :=
  let home := str source "home" in let storage := child home "worktrees" in
  let name := "task-" ++ decimal (num source "task_id") in
  type_admit (is_text (get source "home") && starts home "/" && bound (get source "task_id") 0 9007199254740991)
    (JObject [("home",JString home);("storage",JString storage);("active",JString (child storage name));
      ("archived",JString (child (child storage "archived") name));
      ("receipt",JString (child (child storage "receipts") (name ++ ".json")))])
    "Invalid managed worktree task identity or service home".
Definition worktree_path (source : json) :=
  let op := str source "operation" in let root := get source "root" in
  if (String.eqb op "source" && contains_path (str source "primary") (str source "repository") &&
       negb (contains_path (str source "home") (str source "repository"))) ||
     (String.eqb op "archive" && (equal root (get (get source "files") "active") || equal root (get (get source "files") "archived"))) ||
     (String.eqb op "copy" && contains_path (str source "source") (str source "repository") &&
       contains_path (str source "destination") (text root) && negb (equal (get source "destination") root))
  then success JNull else err "Managed worktree path must remain in its admitted repository or owned storage; service home must stay outside the source repository".
Definition reservation_valid (value : json) (files : json) :=
  plain_fields_only ["id";"canonical_root";"dev";"ino";"repository"] value &&
  forallb (fun key => is_text (get value key) && negb (String.eqb (str value key) ""))
    ["id";"dev";"ino";"repository"] &&
  equal (get value "canonical_root") (get files "active") && path_valid (get value "repository").
Definition worktree_receipt_format := "selvedge-local-workspace-2".
Definition worktree_receipt_fields := ["format";"task_id";"source_root";"root";"workspace";"status";"local_phase";"reservation"].
Definition worktree_receipt_encode (source : json) :=
  let state := get source "state" in
  success (JObject (map (fun key => (key,if String.eqb key "format" then JString worktree_receipt_format else get state key)) worktree_receipt_fields)).
Definition worktree_receipt (source : json) :=
  let value := get source "value" in let workspace := get value "workspace" in let root := get value "root" in
  let files := get source "files" in
  let unreserved := String.eqb (str value "local_phase") "unreserved" && is_null (get value "reservation") in
  type_admit (plain_fields_only worktree_receipt_fields value && String.eqb (str value "format") worktree_receipt_format &&
    LocalResources.receipt_stage_valid value &&
    equal (get value "task_id") (get source "task_id") && equal (get value "source_root") (get source "source_root") &&
    (unreserved || reservation_valid (get value "reservation") files) &&
    ((existsb (String.eqb (str value "status")) ["creating";"ready";"archiving";"released";"needs_resolution";"destroy_pending"] && equal root (get files "active")) ||
     (String.eqb (str value "status") "archived" && equal root (get files "archived"))) &&
    workspace_valid workspace &&
    existsb (fun root => String.eqb (text root) (str workspace "primary_root")) (items (get workspace "roots")) &&
    contains_path (str workspace "primary_root") (text root)) value "Invalid managed worktree receipt".
Definition relocated (value : json) (previous next : string) (descendants : bool) :=
  JString (if String.eqb (text value) previous || (descendants && contains_path (text value) previous)
    then next ++ String.substring (String.length previous) (String.length (text value)) (text value) else text value).
Definition worktree_workspace (source : json) :=
  let workspace := get source "workspace" in let previous := str source "previous" in let next := str source "next" in
  let relocate := fun value => relocated value previous next (boolean_field source "descendants") in
  success (JObject [("roots",JArray (map relocate (items (get workspace "roots"))));
    ("primary_root",relocate (get workspace "primary_root"))]).
Definition worktree_recovery_effect (source : json) :=
  let entry := get source "entry" in
  success (JObject [("kind",JString (if existsb (String.eqb (str entry "status")) ["creating";"creating_archived"] then "worktree_create" else "worktree_archive"));
    ("task_id",get entry "task_id");("source_root",get entry "source_root");("root",get entry "root")]).

(* DEFENSE: A selected cloud root can resolve through a symlink or '..' into
   another environment. Canonical paths must still belong to the selected root. *)
Definition workspace_environment_bound (source : json) :=
  type_admit (is_text (get source "root") &&
    forallb (fun root => is_text root && Workspace.root_within (text root) (str source "root"))
      (items (get (get source "workspace") "roots"))) JNull
    "A cloud workspace must stay within its task repository".
