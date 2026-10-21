From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common Observation Workspaces SandboxPolicy Seatbelt.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition next (previous continuation : json) :=
  if boolean_field previous "ok" then continuation else previous.
Definition admit (valid : bool) (message : string) := if valid then success JNull else err message.
Definition plan_admission (source : json) :=
  let options := get source "options" in
  if has options "managedWorktreeRoot" && negb (paths_valid [get options "managedWorktreeRoot"])
  then type_error "Invalid managed Worktree root"
  else if negb (existsb (String.eqb (str options "platform")) ["linux";"darwin"])
  then err "Selvedge supports Linux and macOS only"
  else match decode_plan (get source "plan") with
    | Some _ => success (get source "plan")
    | None => type_error "Malformed committed sandbox execution plan"
    end.
Definition root_observation (root observation : json) :=
  next (admit (is_object observation && plain_fields_only ["root";"absolute"] observation && has observation "root" &&
    is_bool (get observation "absolute") && equal observation (JObject [("root",root);("absolute",get observation "absolute")]))
    "Workspace path observation does not match its source") (root_admit observation).
Fixpoint roots_observed (roots observations : list json) :=
  match roots,observations with
  | [],[] => success JNull
  | root::rest,observation::tail => next (root_observation root observation) (roots_observed rest tail)
  | _,_ => err "Workspace path observations must cover every root in order"
  end.
Definition workspace_selected (source : json) :=
  let workspace := get source "workspace" in let committed := get (get source "plan") "workspace" in
  let selection := Workspaces.selection_value (JObject [("value",committed);("roots",get workspace "roots")]) in
  let primary := if boolean_field selection "canonicalize" then
    next (root_observation (get selection "root") (get (get source "root_observations") "primary"))
      (root_observation (get workspace "primary_root") (get (get source "root_observations") "canonical_primary"))
    else admit (equal (get workspace "primary_root") (get selection "root")) "Workspace primary observation does not match its selection" in
  let selected := Workspaces.workspace_selected (JObject [("roots",get workspace "roots");("primary",get workspace "primary_root")]) in
  next primary (next selected (next
    (admit (equal (get selected "value") workspace) "Workspace observation does not match its selected value")
    (Workspaces.workspace_bound source))).
Definition workspace_roots (source : json) :=
  let workspace := get source "workspace" in let committed := get (get source "plan") "workspace" in
  let observations := get source "root_observations" in
  next (admit (is_object observations && plain_fields_only ["original";"canonical";"primary";"canonical_primary"] observations &&
    is_array (get observations "original") && is_array (get observations "canonical")) "Workspace requires tagged path observations")
  (next (roots_observed (items (get committed "roots")) (items (get observations "original")))
  (next (roots_observed (items (get workspace "roots")) (items (get observations "canonical")))
  (next (admit (Nat.eqb (List.length (items (get committed "roots"))) (List.length (items (get workspace "roots")))) "Workspace root observation count changed")
  (next (Workspaces.workspace_distinct (JObject [("roots",get workspace "roots")])) (workspace_selected source))))).
Definition workspace_admission (source : json) :=
  next (Workspaces.workspace_admit (get (get source "plan") "workspace"))
    (next (Workspaces.workspace_admit (get source "workspace")) (workspace_roots source)).
Definition launch_context (source : json) :=
  let bound := get (Workspaces.workspace_bound source) "value" in
  JObject [("plan",get source "plan");("options",get source "options");("workspace",get source "workspace");
    ("cwd",get bound "cwd");("projectOnly",get bound "projectOnly");("writableRoots",get bound "writableRoots");
    ("scratch",get source "scratch");("protectedRoots",get source "protectedRoots");
    ("managedWorktreeRoot",get source "managedWorktreeRoot");("separator",get source "separator");("runtimeReads",get source "runtimeReads")].
Definition optional_coordinate (source context : json) (key : string) :=
  negb (has source key) || equal (get source key) (get context key).
Definition resources_admission (source : json) :=
  let context := launch_context source in
  admit (forallb (optional_coordinate source context) ["cwd";"projectOnly";"writableRoots"] &&
    (negb (has source "networkAccess") || equal (get source "networkAccess") (get (get (get source "plan") "sandbox") "network_access")) &&
    (negb (has source "platform") || equal (get source "platform") (get (get source "options") "platform")) &&
    is_text (get source "separator") && String.eqb (str source "separator") "/" &&
    paths_valid [get source "scratch"] && is_array (get source "protectedRoots") && paths_valid (items (get source "protectedRoots")) &&
    is_array (get (get source "options") "readOnlyPaths") &&
    Nat.eqb (List.length (items (get source "protectedRoots"))) (List.length (items (get (get source "options") "readOnlyPaths"))))
    "Sandbox observations do not match the admitted security context".
Definition security_admission (source : json) :=
  next (admit (String.eqb (str (get source "plan") "access") "sandboxed") "Malformed committed sandbox execution plan")
    (next (resources_admission source) (next (managed_worktree_admission (launch_context source))
      (protected_workspace (launch_context source)))).
Fixpoint runtime_observed (candidates : list json) (seen : list string) (entries : list json) :=
  match entries with [] => true | entry::rest =>
    plain_fields_only ["root";"canonical"] entry && paths_valid [get entry "root";get entry "canonical"] &&
    existsb (equal (get entry "root")) candidates && negb (existsb (String.eqb (str entry "root")) seen) &&
    runtime_observed candidates (str entry "root"::seen) rest end.
Definition runtime_admission (source : json) :=
  admit (is_array (get source "runtimeReads") && runtime_observed
    (items (runtime_candidates (str (get source "options") "platform"))) [] (items (get source "runtimeReads")) &&
    (boolean_field (launch_context source) "projectOnly" || equal (get source "runtimeReads") (JArray [])))
    "Sandbox runtime observations do not match the selected platform".
Fixpoint numbered_bindings (descriptor : N) (entries : list json) :=
  match entries with [] => [] | entry::rest =>
    JObject [("root",get entry "root");("readonly",get entry "readonly");("descriptor",number descriptor)] :: numbered_bindings (N.succ descriptor) rest end.
Definition expected_bindings (source : json) := JArray (numbered_bindings 4 (items (bindings (launch_context source)))).
Definition linux_launch (source : json) :=
  let context := launch_context source in let expected := expected_bindings source in
  next (admit (equal (get source "bindings") expected) "Sandbox descriptor observations do not match their admitted bindings")
    (success (JObject [("prefix",linux_prefix (set context "bindings" expected));("cwd",get context "cwd")])).
Fixpoint ancestor_rows (rows roots : list json) :=
  match rows,roots with [] ,[] => true | row::rest,_::tail => is_array row && paths_valid (items row) && ancestor_rows rest tail | _,_ => false end.
Definition seatbelt_source (source : json) :=
  set (set (Seatbelt.seatbelt_input (launch_context source)) "protectedAncestors" (get source "protectedAncestors")) "readAncestors" (get source "readAncestors").
Definition darwin_launch (source : json) :=
  let context := launch_context source in
  let profile := Seatbelt.seatbelt (seatbelt_source source) in
  next (admit (is_array (get source "protectedAncestors") && is_array (get source "readAncestors") &&
    ancestor_rows (items (get source "protectedAncestors")) (items (get source "protectedRoots")) &&
    (if boolean_field context "projectOnly" then ancestor_rows (items (get source "readAncestors"))
      (items (get (Seatbelt.seatbelt_input context) "readableRoots") ++ [get source "scratch"])
     else equal (get source "readAncestors") (JArray []))) "Sandbox ancestor observations do not match their source paths")
    (next profile (next (admit (negb (has source "profile") || equal (get source "profile") (get profile "value"))
      "Sandbox profile does not match the admitted security context")
      (success (JObject [("prefix",darwin_prefix (JObject [("profile",get profile "value")]));("cwd",get context "cwd")])))).
Definition sandbox_prepare (source : json) :=
  next (plan_admission source) (next (workspace_admission source) (next (security_admission source)
    (let context := launch_context source in success (JObject [("cwd",get context "cwd");("projectOnly",get context "projectOnly");
      ("bindings",bindings context);("writableRoots",get context "writableRoots");("seatbeltInput",Seatbelt.seatbelt_input context)])))).
Definition sandbox_launch (source : json) :=
  next (plan_admission source) (next (workspace_admission source) (next (security_admission source)
    (next (runtime_admission source)
      (if String.eqb (str (get source "options") "platform") "darwin" then darwin_launch source else linux_launch source)))).
Definition unrestricted_launch (source : json) :=
  let cwd := get (get (Workspaces.workspace_bound source) "value") "cwd" in
  next (plan_admission source) (next (workspace_admission source)
    (next (admit (String.eqb (str (get source "plan") "access") "unrestricted" && negb (String.eqb (str (get source "plan") "scope") "project"))
      "Unrestricted execution is unavailable for this committed plan")
      (next (admit (optional_coordinate source (JObject [("cwd",cwd)]) "cwd") "Unrestricted execution cwd does not match the admitted Workspace")
        (success (JObject [("file",JString "/bin/bash");("prefix",JArray [JString "--noprofile";JString "--norc"]);("cwd",cwd)]))))).
