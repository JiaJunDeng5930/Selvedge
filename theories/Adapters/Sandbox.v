From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common Workspaces SandboxPolicy Seatbelt.
From Selvedge.Programming Require Import AdapterResult.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition launch_context (source : json) :=
  let bound := get (Workspaces.workspace_bound source) "value" in
  JObject [("plan",get source "plan");("options",get source "options");("workspace",get source "workspace");
    ("cwd",get bound "cwd");("projectOnly",get bound "projectOnly");("writableRoots",get bound "writableRoots");
    ("scratch",get source "scratch");("protectedRoots",get source "protectedRoots");
    ("managedWorktreeRoot",get source "managedWorktreeRoot");("runtimeReads",get source "runtimeReads")].
Definition security_admission (source : json) :=
  next (managed_worktree_admission (launch_context source))
    (protected_workspace (launch_context source)).
Fixpoint numbered_bindings (descriptor : N) (entries : list json) :=
  match entries with [] => [] | entry::rest =>
    JObject [("root",get entry "root");("readonly",get entry "readonly");("descriptor",number descriptor)] :: numbered_bindings (N.succ descriptor) rest end.
Definition expected_bindings (source : json) := JArray (numbered_bindings 4 (items (bindings (launch_context source)))).
Definition linux_launch (source : json) :=
  let context := launch_context source in let expected := expected_bindings source in
  success (JObject [("prefix",linux_prefix (set context "bindings" expected));("cwd",get context "cwd")]).
Definition seatbelt_source (source : json) :=
  set (set (Seatbelt.seatbelt_input (launch_context source)) "protectedAncestors" (get source "protectedAncestors")) "readAncestors" (get source "readAncestors").
Definition darwin_launch (source : json) :=
  let context := launch_context source in
  let profile := Seatbelt.seatbelt (seatbelt_source source) in
  success (JObject [("prefix",darwin_prefix (JObject [("profile",profile)]));("cwd",get context "cwd")]).
Definition sandbox_prepare (source : json) :=
  next (security_admission source)
    (success (JObject [("bindings",bindings (launch_context source))])).
Definition sandbox_launch (source : json) :=
  if String.eqb (str (get source "options") "platform") "darwin"
  then darwin_launch source else linux_launch source.
Definition unrestricted_launch (source : json) :=
  let cwd := get (get (Workspaces.workspace_bound source) "value") "cwd" in
  success (JObject [("file",JString "/bin/bash");("prefix",JArray [JString "--noprofile";JString "--norc"]);("cwd",cwd)]).
