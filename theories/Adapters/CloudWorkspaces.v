From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Kernel Require Import WorkspaceBackend.
From Selvedge.Adapters Require Import Common Workspaces CloudConfiguration.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition component_character (character : ascii) :=
  let n := N.of_nat (nat_of_ascii character) in
  ((65 <=? n) && (n <=? 90)) || ((97 <=? n) && (n <=? 122)) ||
  ((48 <=? n) && (n <=? 57)) || existsb (Ascii.eqb character) ["_"%char;"."%char;"-"%char].
Fixpoint component_characters (source : string) :=
  match source with EmptyString => true
  | String character rest => component_character character && component_characters rest end.
Definition component (source : string) := negb (String.eqb source "") && component_characters source.
Fixpoint slash_index (source : string) (position : nat) : option nat :=
  match source with EmptyString => None
  | String character rest => if Ascii.eqb character "/"%char then Some position
    else slash_index rest (S position) end.
Definition strip_suffix (suffix source : string) :=
  if String.eqb (String.substring (Nat.sub (String.length source) (String.length suffix)) (String.length suffix) source) suffix
  then String.substring 0 (Nat.sub (String.length source) (String.length suffix)) source else source.
Definition github_remote (source : string) : option string :=
  match find (fun prefix => starts source prefix)
    ["https://github.com/";"git@github.com:";"ssh://git@github.com/"] with
  | None => None
  | Some prefix =>
    let path := strip_suffix "/" (String.substring (String.length prefix) (String.length source) source) in
    match slash_index path 0 with
    | None => None
    | Some index =>
      let owner := String.substring 0 index path in
      let repository := strip_suffix ".git" (String.substring (S index) (String.length path) path) in
      if component owner && component repository then
        Some ("https://github.com/" ++ owner ++ "/" ++ repository ++ ".git") else None
    end
  end.
Definition repository (source : json) := success
  (match github_remote (str source "remote") with Some url => JString url | None => JNull end).
Definition remote_names (source : json) :=
  let names := items (get source "names") in
  let origin := fun value => equal value (JString "origin") in
  success (JArray (filter origin names ++ filter (fun value => negb (origin value)) names)).
Definition contained_workspace (selected : json) (root : string) :=
  Workspaces.workspace_valid selected && Workspaces.path_valid (get selected "primary_root") &&
  existsb (fun member => equal member (get selected "primary_root")) (items (get selected "roots")) &&
  forallb (fun member => Workspaces.path_valid member && Workspaces.contains_path (text member) root)
    (items (get selected "roots")).
Definition receipt_keys := ["format";"namespace";"task_id";"source_root";"root";"token";"backend"].
Definition receipt_statuses := ["persist_pending";"allocation_unknown";"allocated";"preparing";"ready";
  "destroy_pending";"destroy_failed";"needs_credential";"needs_reconcile";"needs_resolution";"destroyed"].
Definition recovery_authority (value : json) :=
  let scope := get value "scope" in
  is_object scope && is_text (get scope "account_id") && negb (String.eqb (str scope "account_id") "") &&
  String.eqb (str scope "provider") "tencent_cvm" &&
  equal (get scope "region") (get (get value "settings") "region") &&
  is_text (get scope "endpoint") && negb (String.eqb (str scope "endpoint") "") &&
  String.eqb (str scope "credential_reference") "service-environment:TENCENTCLOUD" &&
  equal (get (get value "request") "ClientToken") (get value "token") &&
  equal (get value "dispatch_count") (number 1) &&
  existsb (String.eqb (str value "status")) receipt_statuses &&
  is_array (get value "instance_ids") && is_array (get value "candidate_ids").
Definition receipt_matches (source : json) :=
  let expected := get source "expected" in let value := get source "value" in
  is_object value && forallb (fun name => equal (get value name) (get expected name)) receipt_keys &&
  CloudConfiguration.valid (JObject [("backend",get value "backend");
    (WorkspaceBackend.name WorkspaceBackend.TencentCvm,get value "settings")]) &&
  (is_null (get source "bound_root") || equal (get value "root") (get source "bound_root")) &&
  contained_workspace (get value "workspace") (str value "root") && recovery_authority value.
Definition receipt (source : json) :=
  if receipt_matches source then success (get source "value")
  else type_error "Cloud workspace receipt does not match its task".
Definition workspace (source : json) :=
  let selected := get source "workspace" in
  let repository := str source "repository" in
  if contained_workspace selected repository
  then Workspaces.worktree_workspace (JObject [("workspace",selected);("previous",JString repository);
    ("next",get source "root");("descendants",JBool true)])
  else type_error "Cloud workspace roots must belong to the project GitHub repository".
