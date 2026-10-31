From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Schema Utf8 Numbers ArgumentDeclaration.
From Selvedge.Kernel Require Import Domain Numbers.
From Selvedge.Kernel Require WorkspacePath.
Import ListNotations.
Open Scope string_scope.
Definition project_name_declaration := ArgumentDeclaration.Text
 (ArgumentDeclaration.TextConstraints 0 ArgumentDeclaration.maximum_natural 256 false true false None).
Definition valid_project_name (name : string) :=
 ArgumentDeclaration.check project_name_declaration (Json.JString name).
Definition path_constraints := WorkspacePath.constraints.
Definition path_declaration := WorkspacePath.declaration.
Definition canonical_path := WorkspacePath.canonical.
Definition valid_path (path : string) :=
 ArgumentDeclaration.check_text path_constraints path && canonical_path path.
Definition valid_selection (value : workspace) :=
 Schema.unique_names (workspace_roots value) &&
 match workspace_primary value, workspace_roots value with
 | None, [] => true
 | Some primary, roots => existsb (String.eqb primary) roots
 | _,_ => false end.
Definition valid_workspace (value : workspace) :=
 Nat.leb (List.length (workspace_roots value)) 32 &&
 forallb valid_path (workspace_roots value) && valid_selection value.
Definition root_within (root bound : string) :=
 String.eqb bound "/" || String.eqb root bound || String.prefix (String.append bound "/") root.
Definition workspace_bound (child parent : workspace) :=
 forallb (fun root => existsb (root_within root) (workspace_roots parent)) (workspace_roots child).
(* Display metadata does not change the independent reviewer's execution
   configuration, and cannot widen or revoke a delegation by itself. *)
Definition same_reviewer_profile (left right : profile) :=
 String.eqb (profile_key left) (profile_key right) &&
 String.eqb (profile_provider left) (profile_provider right) &&
 String.eqb (profile_model left) (profile_model right) &&
 String.eqb (profile_reasoning left) (profile_reasoning right) &&
 Json.equal (Json.JArray (map Json.JString (profile_reasoning_options left)))
   (Json.JArray (map Json.JString (profile_reasoning_options right))).
Definition approval_bound (child parent : approval_policy) :=
 match parent, child with
 | FullAccess,_ => true
 | AskForApproval, AskForApproval => true
 | ReviewWith _, AskForApproval => true
 | ReviewWith parent, ReviewWith child => same_reviewer_profile child parent
 | _,_ => false end.
Definition same_resource (first second : option N) :=
 match first,second with None,None=>true | Some owner,Some other=>N.eqb owner other | _,_=>false end.
Definition writes_no_broader (child parent : sandbox) (child_space parent_space : workspace) :=
 match sandbox_access child, sandbox_access parent with
 | ReadOnly, _ => true
 | WorkspaceWrite, WorkspaceWrite => workspace_bound child_space parent_space
 | _, _ => false
 end.
(* FullAccess authorizes unrestricted delegation. Otherwise only write roots
   are bounded: selecting another read-only root does not confer write access. *)
Definition may_delegate (child parent : task_settings) :=
 match settings_approval parent with
 | FullAccess => true
 | approval =>
   (negb (sandbox_network (settings_sandbox child)) || sandbox_network (settings_sandbox parent)) &&
   writes_no_broader (settings_sandbox child) (settings_sandbox parent)
     (settings_workspace child) (settings_workspace parent) &&
   approval_bound (settings_approval child) approval
 end.

(* Stable registry positions are identities; the last registry edit controls
   presentation order independently of that identity. *)
Definition next_project_order (projects : list project) :=
 N.succ (fold_right (fun value order => N.max (project_order value) order) 0%N projects).
Fixpoint insert_project (entry : N * project) (entries : list (N * project)) :=
 match entries with
 | [] => [entry]
 | first :: rest => if N.leb (project_order (snd first)) (project_order (snd entry))
   then entry :: entries else first :: insert_project entry rest
 end.
Definition ordered_projects (projects : list project) :=
 fold_right insert_project []
  (filter (fun entry => negb (project_deleted (snd entry))) (Selvedge.Foundation.Registry.indexed pair 0 projects)).
