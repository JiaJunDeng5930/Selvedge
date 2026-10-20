From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Schema Utf8 Numbers.
From Selvedge.Kernel Require Import Domain.
Import ListNotations.
Open Scope string_scope.
Fixpoint contains (needle text : string) :=
 if String.prefix needle text then true else match text with EmptyString => false | String _ rest => contains needle rest end.
Definition valid_path (path : string) :=
 String.prefix "/" path && Nat.leb (String.length path) 4096 && Utf8.no_nul path &&
 negb (contains "/../" (String.append path "/")) && negb (contains "/./" (String.append path "/")) &&
 (String.eqb path "/" || negb (contains "//" (String.append path "/"))).
Definition workspace_schema := [Field "roots" (KArray KText); Field "primary_root" (KOptional KText)].
Definition valid_workspace (value : workspace) :=
 Nat.leb (List.length (workspace_roots value)) 32 &&
 Schema.unique_names (workspace_roots value) && forallb valid_path (workspace_roots value) &&
 match workspace_primary value, workspace_roots value with
 | None, [] => true
 | Some primary, roots => existsb (String.eqb primary) roots
 | _,_ => false end.
Definition root_within (root bound : string) :=
 String.eqb bound "/" || String.eqb root bound || String.prefix (String.append bound "/") root.
Definition workspace_bound (child parent : workspace) :=
 forallb (fun root => existsb (root_within root) (workspace_roots parent)) (workspace_roots child).
Definition sandbox_bound (child parent : sandbox) :=
 (match sandbox_access parent, sandbox_access child with ReadOnly, WorkspaceWrite => false | _,_ => true end) &&
 (negb (sandbox_network child) || sandbox_network parent).
Definition approval_bound (child parent : approval_policy) :=
 match parent, child with
 | FullAccess,_ => true
 | AskForApproval, AskForApproval => true
 | ReviewWith _, AskForApproval => true
 | ReviewWith parent, ReviewWith child => Domain.same_profile child parent
 | _,_ => false end.
Definition settings_bound (child parent : task_settings) :=
 workspace_bound (settings_workspace child) (settings_workspace parent) &&
 sandbox_bound (settings_sandbox child) (settings_sandbox parent) &&
 approval_bound (settings_approval child) (settings_approval parent).
